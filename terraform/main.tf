terraform {
  required_version = ">= 1.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Generate unique suffix for S3 Bucket
resource "random_string" "bucket_suffix" {
  length  = 6
  special = false
  upper   = false
}

# 1. Custom VPC Network
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "${var.project_name}-vpc"
    Environment = var.environment
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name        = "${var.project_name}-public-subnet"
    Environment = var.environment
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "${var.project_name}-igw"
    Environment = var.environment
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name        = "${var.project_name}-public-rt"
    Environment = var.environment
  }
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# 2. Security Groups
resource "aws_security_group" "web_sg" {
  name        = "${var.project_name}-web-sg"
  description = "Allow inbound web traffic and SSH"
  vpc_id      = aws_vpc.main.id

  # HTTP
  ingress {
    description = "Allow HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS
  ingress {
    description = "Allow HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Direct FastAPI Access (optional / debugging)
  ingress {
    description = "Allow FastAPI Port"
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH (For demo purposes allowed globally, in prod restrict to bastion/office IP)
  ingress {
    description = "Allow SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound rules (Allow everything)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-web-sg"
    Environment = var.environment
  }
}

# 3. S3 Bucket with Security Blocks and Encryption
resource "aws_s3_bucket" "assets" {
  bucket        = "${var.s3_bucket_name}-${random_string.bucket_suffix.result}"
  force_destroy = true

  tags = {
    Name        = "${var.project_name}-assets"
    Environment = var.environment
  }
}

# Encrypt S3 bucket at rest
resource "aws_s3_bucket_server_side_encryption_configuration" "assets_encryption" {
  bucket = aws_s3_bucket.assets.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block all public S3 access
resource "aws_s3_bucket_public_access_block" "assets_block_public" {
  bucket = aws_s3_bucket.assets.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 4. IAM Roles & EC2 Instance Profile (Least Privilege for S3)
resource "aws_iam_role" "ec2_role" {
  name = "${var.project_name}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# Custom IAM Policy for specific S3 Bucket read/write access
resource "aws_iam_policy" "s3_access_policy" {
  name        = "${var.project_name}-s3-access-policy"
  description = "Allows EC2 instance to perform CRUD actions on the project S3 bucket"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.assets.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          "${aws_s3_bucket.assets.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "s3_attach" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.s3_access_policy.arn
}

# Standard policy for CloudWatch Agent access on EC2
resource "aws_iam_role_policy_attachment" "cw_agent_attach" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.project_name}-ec2-instance-profile"
  role = aws_iam_role.ec2_role.name
}

# 5. Get Latest Ubuntu AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  owners = ["099720109477"] # Canonical
}

# 6. EC2 Application Server
resource "aws_instance" "app_server" {
  ami                  = data.aws_ami.ubuntu.id
  instance_type        = var.instance_type
  user_data_replace_on_change = true
  subnet_id            = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  iam_instance_profile = aws_iam_instance_profile.ec2_profile.name
  key_name             = var.key_name != "" ? var.key_name : null

  # Root block volume encryption
  root_block_device {
    volume_size           = 8
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  } 

  # User data to bootstrap EC2 Server
  user_data = <<-EOF
              #!/bin/bash
              # Update package list and upgrade packages
              apt-get update -y
              apt-get upgrade -y

              # Install required packages
              apt-get install -y git python3-pip python3-venv nginx awscli wget

              # Download and install Amazon CloudWatch Agent manually (not in default apt repos)
              wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
              dpkg -i -E ./amazon-cloudwatch-agent.deb
              rm -f amazon-cloudwatch-agent.deb

              # Create app directory
              mkdir -p /opt/devops-app
              cd /opt/devops-app

              # Clone app repository or pull files
              # For bootstrapping we can write app files directly from User Data or pull them from S3/Git
              # Here we write a systemd service file to run FastAPI and configure Nginx proxying
              
              # Write environment variables
              echo "AWS_S3_BUCKET=${aws_s3_bucket.assets.id}" >> /etc/environment
              echo "AWS_REGION=${var.aws_region}" >> /etc/environment

              # Setup application files (simulating deployment pull)
              # Note: In actual production, the CI/CD pipeline runs this step, this is for initial boot
              mkdir -p app/templates
              
              # Write temporary placeholder main.py & requirements
              cat << 'APP' > app/requirements.txt
              fastapi>=0.100.0
              uvicorn>=0.22.0
              jinja2>=3.1.2
              python-multipart>=0.0.6
              psutil>=5.9.5
              boto3>=1.28.0
              pytest>=7.4.0
              requests>=2.31.0
              httpx>=0.24.1
              APP

              # Create Virtual Environment and Install deps
              python3 -m venv venv
              ./venv/bin/pip install -r app/requirements.txt

              # Nginx Configuration
              cat << 'NGINX' > /etc/nginx/sites-available/default
              server {
                  listen 80 default_server;
                  listen [::]:80 default_server;

                  server_name _;

                  location / {
                      proxy_pass http://127.0.0.1:8000;
                      proxy_http_version 1.1;
                      proxy_set_header Upgrade $http_upgrade;
                      proxy_set_header Connection 'upgrade';
                      proxy_set_header Host $host;
                      proxy_cache_bypass $http_upgrade;
                      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                      proxy_set_header X-Forwarded-Proto $scheme;
                  }
              }
              NGINX

              # Restart Nginx
              systemctl restart nginx

              # Config CloudWatch Agent
              cat << 'CWA' > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
              {
                "agent": {
                  "metrics_collection_interval": 60,
                  "run_as_user": "root"
                },
                "metrics": {
                  "metrics_collected": {
                    "cpu": {
                      "measurement": [
                        "usage_active",
                        "usage_idle"
                      ],
                      "metrics_collection_interval": 60,
                      "totalcpu": true
                    },
                    "mem": {
                      "measurement": [
                        "mem_used_percent"
                      ],
                      "metrics_collection_interval": 60
                    },
                    "disk": {
                      "measurement": [
                        "used_percent"
                      ],
                      "metrics_collection_interval": 60,
                      "resources": [
                        "/"
                      ]
                    }
                  }
                },
                "logs": {
                  "logs_collected": {
                    "files": {
                      "collect_list": [
                        {
                          "file_path": "/opt/devops-app/app.log",
                          "log_group_name": "DevOps-App-Logs",
                          "log_stream_name": "{hostname}-app",
                          "retention_in_days": 7
                        },
                        {
                          "file_path": "/var/log/nginx/access.log",
                          "log_group_name": "DevOps-Nginx-Access",
                          "log_stream_name": "{hostname}-nginx",
                          "retention_in_days": 7
                        }
                      ]
                    }
                  }
                }
              }
              CWA

              # Start CloudWatch Agent
              /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
                -a fetch-config \
                -m ec2 \
                -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
                -s

              # Change ownership of the app directory to ubuntu so CI/CD rsync deployments do not fail with Permission Denied
              chown -R ubuntu:ubuntu /opt/devops-app

              EOF

  tags = {
    Name        = "${var.project_name}-app-server"
    Environment = var.environment
  }
}
