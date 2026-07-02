output "vpc_id" {
  description = "The ID of the custom VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_id" {
  description = "The ID of the public subnet"
  value       = aws_subnet.public.id
}

output "s3_bucket_name" {
  description = "The globally unique name of the S3 bucket"
  value       = aws_s3_bucket.assets.id
}

output "s3_bucket_arn" {
  description = "The ARN of the S3 bucket"
  value       = aws_s3_bucket.assets.arn
}

output "ec2_public_ip" {
  description = "The public IP address of the EC2 application server"
  value       = aws_instance.app_server.public_ip
}

output "ec2_public_dns" {
  description = "The public DNS name of the EC2 application server"
  value       = aws_instance.app_server.public_dns
}

output "deployment_instructions" {
  description = "Simple guidance on accessing the web dashboard"
  value       = "FastAPI web interface is accessible at http://${aws_instance.app_server.public_ip}/ or http://${aws_instance.app_server.public_dns}/"
}
