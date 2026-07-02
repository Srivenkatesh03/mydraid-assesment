# Infrastructure & Application Deployment Guide

This guide describes how to provision the AWS cloud infrastructure using Terraform and deploy the FastAPI web application.

---

## 1. Credentials & Prerequisites Configuration

Before running the deployment, you must set up authentication credentials in three different environments:

### 1.1 Local AWS Credentials (For Terraform)
To authorize Terraform to provision network and compute resources, configure your AWS CLI credentials on your local machine:
- **Option A (AWS CLI - Recommended)**: Install the AWS CLI and run:
  ```bash
  aws configure
  ```
  Provide your `AWS Access Key ID`, `AWS Secret Access Key`, and default region (`us-east-1`). This saves credentials securely in `~/.aws/credentials`.
- **Option B (Environment Variables)**: Export credentials directly in your shell:
  ```bash
  export AWS_ACCESS_KEY_ID="your_access_key"
  export AWS_SECRET_ACCESS_KEY="your_secret_key"
  export AWS_DEFAULT_REGION="us-east-1"
  ```

### 1.2 EC2 SSH Key Pair
- Create an SSH Key Pair in your AWS Console (EC2 -> Key Pairs).
- Download the private key file (e.g., `my-aws-ssh-key.pem`).
- Place it in a secure folder and restrict permissions (critical for SSH to work):
  ```bash
  chmod 400 /path/to/my-aws-ssh-key.pem
  ```

### 1.3 GitHub Actions Secrets (For CI/CD Automation)
To allow the GitHub Actions runner to deploy updates directly to your EC2 instance, navigate to your GitHub Repository -> **Settings** -> **Secrets and variables** -> **Actions**, and add the following repository secrets:
- `EC2_SSH_KEY`: Copy and paste the entire text content of your private key file (`my-aws-ssh-key.pem`).
- `EC2_HOST`: The Public IP Address of your EC2 instance (printed as output by Terraform after deployment).
- `EC2_USERNAME`: Set this to `ubuntu` (the default login user for Ubuntu AMIs).

### 1.4 Application S3 Storage Authentication
- **Important**: You do **not** need to generate or configure any AWS keys inside the FastAPI application code or configuration.
- The EC2 instance runs with a custom **IAM Instance Profile** (`aws_iam_instance_profile.ec2_profile`) created by Terraform. 
- The AWS SDK (`boto3`) inside FastAPI automatically queries the EC2 Instance Metadata Service (IMDS) at runtime to obtain temporary credentials, ensuring secure, keyless storage access.

---

## 2. Software Prerequisites
Ensure you have the following installed on your administration machine:
- **Terraform CLI** (v1.0.0+)
- **Git** CLI


---

## 2. Infrastructure Setup (Terraform)

### Step 2.1: Initialize Terraform
Navigate to the `terraform/` directory and initialize the backend and provider plugins:
```bash
cd terraform/
terraform init
```

### Step 2.2: Customize Configuration Variables
Create a `terraform.tfvars` file from the example:
```bash
cp terraform.tfvars.example terraform.tfvars
```
Edit `terraform.tfvars` in your text editor and specify your AWS SSH key pair name and desired region:
```hcl
aws_region   = "us-east-1"
project_name = "devops-app"
environment  = "production"
key_name     = "my-aws-ssh-key" # Must exist in us-east-1
```

### Step 2.3: Dry Run / Plan
Generate a plan to verify the resources that Terraform will create:
```bash
terraform plan
```
Review the output to ensure:
- VPC CIDR is `10.0.0.0/16`.
- S3 Bucket is locked from public access.
- IAM Instance profile and permissions are correct.

### Step 2.4: Deploy the Infrastructure
Apply the changes. This will deploy the network, storage, IAM profiles, and launch the EC2 server:
```bash
terraform apply -auto-approve
```
*Note: Provisioning takes approximately 2-3 minutes. Once complete, the output will display the EC2 Public IP and S3 bucket name.*

---

## 3. Verifying EC2 Bootstrapping
Our EC2 instance uses User Data to bootstrap Nginx, the Python environment, FastAPI, and CloudWatch Agent on boot.

To verify the boot status:
1. **SSH into the EC2 instance**:
   ```bash
   ssh -i /path/to/my-aws-ssh-key.pem ubuntu@<EC2_PUBLIC_IP>
   ```
2. **Tail the user-data log** to ensure installation succeeded without errors:
   ```bash
   tail -f /var/log/cloud-init-output.log
   ```
3. **Verify running services**:
   - Check FastAPI systemd status: `sudo systemctl status fastapi`
   - Check Nginx status: `sudo systemctl status nginx`
   - Check CloudWatch Agent status:
     ```bash
     sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a status
     ```

---

## 4. Accessing the Dashboard & API
Once the deployment finishes:
- Open your browser and navigate to: `http://<EC2_PUBLIC_IP>/`
- The system metrics, S3 uploader, and items database manager should be fully operational.
- You can test API endpoints directly:
  - Health check: `curl http://<EC2_PUBLIC_IP>/api/v1/health`
  - Fetch items list: `curl http://<EC2_PUBLIC_IP>/api/v1/items`
  - Trigger a 30-second CPU spike:
    ```bash
    curl -X POST "http://<EC2_PUBLIC_IP>/api/v1/cpu-spike?duration=30"
    ```

---

## 5. Teardown / Cleanup
To avoid ongoing AWS charges, destroy all provisioned resources when you are done testing:
```bash
cd terraform/
terraform destroy -auto-approve
```
This command deletes the EC2 instance, the versioned S3 bucket, IAM profiles, security groups, and the custom VPC, returning your AWS account to its original state.
