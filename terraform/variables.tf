variable "aws_region" {
  description = "AWS region to deploy the infrastructure"
  type        = string
  default     = "ap-south-1" # Mumbai region
}

variable "project_name" {
  description = "Name of the project to prefix resource names"
  type        = string
  default     = "devops-app"
}

variable "environment" {
  description = "Target deployment environment"
  type        = string
  default     = "production"
}

variable "instance_type" {
  description = "EC2 instance size for the application server"
  type        = string
  default     = "t3.micro" # Free Tier eligible
}

variable "key_name" {
  description = "SSH key pair name for EC2 access (optional)"
  type        = string
  default     = "myraid"
}

variable "s3_bucket_name" {
  description = "Base name for the S3 bucket (will append random suffix for uniqueness)"
  type        = string
  default     = "devops-assignment-assets"
}
