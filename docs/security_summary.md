# Security & Access Control Summary

This document describes the security controls, permissions, and network safeguards implemented in the AWS deployment.

---

## 1. Identity & Access Management (IAM) - Least Privilege

The application utilizes an IAM Instance Profile attached directly to the EC2 server, eliminating the need to store static AWS Access Keys (`AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`) on the host. 

### 1.1 Custom S3 Permissions Policy
The EC2 server is restricted to access only its dedicated asset bucket. It has no access to any other S3 buckets in the AWS account:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:ListBucket"],
      "Resource": ["arn:aws:s3:::devops-assignment-assets-xxxxxx"]
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": ["arn:aws:s3:::devops-assignment-assets-xxxxxx/*"]
    }
  ]
}
```

### 1.2 CloudWatch Agent Role
We attach the AWS-managed policy `CloudWatchAgentServerPolicy` to the role. This permits the CloudWatch Agent running on EC2 to:
- Push custom system metrics (Memory, Disk) to the `CWAgent` namespace.
- Stream log files (`/opt/devops-app/app.log`, `/var/log/nginx/access.log`) to CloudWatch Logs.

---

## 2. Network Security & Partitioning

### 2.1 Virtual Private Cloud (VPC)
- We deploy inside a custom VPC (`10.0.0.0/16`) to isolate the environment from the default AWS VPC.
- Network routing is configured via a custom Internet Gateway and Route Table mapping only the public subnet.

### 2.2 Security Group Rules
The EC2 instances are protected by a stateful firewall (Security Group) with strict inbound settings:

| Direction | Port | Protocol | Source | Purpose |
|-----------|------|----------|--------|---------|
| Inbound | 80 | TCP | `0.0.0.0/0` | HTTP Web Traffic (Nginx) |
| Inbound | 443 | TCP | `0.0.0.0/0` | HTTPS Web Traffic (Secure) |
| Inbound | 8000 | TCP | `0.0.0.0/0` | Direct FastAPI API testing |
| Inbound | 22 | TCP | `0.0.0.0/0` | Admin SSH management |
| Outbound | All | All | `0.0.0.0/0` | System patches, AWS APIs |

> [!WARNING]
> Permitting SSH (Port 22) from `0.0.0.0/0` is used for demonstration purposes. In production, this should be locked down to your corporate VPN IP or office CIDR block.

---

## 3. Data Encryption & Protection

### 3.1 Encryption-at-Rest
- **S3 Bucket**: Encrypted using **AES-256 SSE-S3** (Server-Side Encryption with Amazon S3-managed keys) to ensure compliance.
- **EBS Boot Volume**: The EC2 instance's root SSD volume is encrypted at-rest using AWS-managed KMS keys.

### 3.2 S3 Public Access Block
To prevent accidental exposure of sensitive backups or database items, we explicitly set `block_public_acls`, `block_public_policy`, `ignore_public_acls`, and `restrict_public_buckets` to `true` on the S3 bucket.

---

## 4. Production Hardening Recommendations

To scale this infrastructure to a production environment, we recommend:
1. **Remove Public SSH Access**: Disable Port 22 completely. Use **AWS Systems Manager (SSM) Session Manager** to log into instances. Session Manager establishes a secure IAM-controlled CLI channel without exposing ports.
2. **Deploy ALB in Public Subnets / EC2 in Private Subnets**:
   - Move the EC2 instance to a private subnet with no internet route.
   - Deploy an Application Load Balancer (ALB) in the public subnet.
   - Configure the ALB to route HTTP/HTTPS traffic to the EC2 instances.
3. **Automate Certificate Management**: Install Certbot on the server to automatically renew SSL certificates via Let's Encrypt, or use AWS Certificate Manager (ACM) to assign SSL certificates directly to the ALB.
4. **Implement AWS WAF**: Put an AWS Web Application Firewall (WAF) in front of the application to inspect payloads for SQL injections, Cross-Site Scripting (XSS), and rate-limit abusive clients.
