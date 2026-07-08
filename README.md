# AWS DevOps Technical Assignment Solution

This repository contains the complete implementation for the **DevOps Engineer Technical Assignment**. It includes network infrastructure, storage configuration, identity configuration, deployment automation, monitoring, and load testing suites for a production-like FastAPI application.

---

## 🏗️ Repository Architecture

Our solution builds a secure cloud architecture that complies with AWS Free Tier constraints:

- **Virtual Private Cloud (VPC)**: Customized `10.0.0.0/16` network.
- **Compute (EC2)**: Single `t2.micro` Ubuntu 22.04 LTS instance serving FastAPI backend behind an Nginx reverse proxy.
- **Storage (S3)**: AES-256 encrypted, private S3 bucket for assets and database backups.
- **Identity (IAM)**: EC2 Instance Profile with restricted read/write permissions mapped only to our target S3 bucket.
- **Monitoring (CloudWatch)**: CloudWatch Agent configured to track RAM, Disk, and CPU, and stream application/system logs to CloudWatch Logs.
- **Load Testing (k6)**: Ramping multi-stage virtual user simulation targeting HTTP dashboard and API workloads.

---

## 📂 Directory Structure

The project files are organized as follows:

```
devops-technical-assignment/
├── app/                      # FastAPI Web Application & UI Dashboard
│   ├── templates/            # Glassmorphic dashboard templates
│   │   └── index.html
│   ├── main.py               # Main API routes, metrics & S3 mock fallback
│   ├── test_main.py          # automated pytest unit tests
│   ├── requirements.txt      # Application dependencies
│   └── Dockerfile            # Container configuration
├── terraform/                # Infrastructure as Code (IaC)
│   ├── main.tf               # VPC, Security Groups, S3, IAM, EC2 definition
│   ├── variables.tf          # Configurable variables
│   ├── outputs.tf            # Output parameters (EC2 IP, S3 Bucket)
│   └── terraform.tfvars.example
├── .github/
│   └── workflows/
│       └── deploy.yml        # CI/CD deployment pipeline configuration
├── monitoring/               # CloudWatch Agent & Alarms
│   ├── amazon-cloudwatch-agent.json # Metrics & Logs collection rules
│   ├── dashboard.json        # CloudWatch dashboard grid schema
│   └── setup_alarms.sh       # Automated CLI alarm provisioner
├── load-testing/             # Performance testing suite
│   ├── load_test.js          # k6 load testing schema
│   └── run_load_tests.py     # Automated multi-threaded execution runner
├── docs/                     # Documentation assets
│   ├── aws_architecture_diagram.png
│   ├── deployment_guide.md   # Setup instructions
│   ├── security_summary.md   # IAM & firewall rules summary
│   └── load_test_report.md   # k6/benchmark performance results
├── README.md                 # Project entry point
└── final_report.md           # Assignment final report (PDF equivalent)
```

---

## 🚀 Quick Start Guides

To inspect and run individual parts of this assignment, click the links below:

1. **Infrastructure & Credentials Setup**: Read the [Deployment Guide](docs/deployment_guide.md#1-credentials--prerequisites-configuration) to configure credentials and initialize/apply the Terraform scripts.
2. **Security Controls**: Read the [Security & Access Control Summary](docs/security_summary.md) to inspect network segregation and IAM profiles.
3. **Load Testing**: Read the [Load Testing & Performance Report](docs/load_test_report.md) or run `python load-testing/run_load_tests.py` to trigger local load simulation.
4. **Final Deliverable**: Review the complete technical document in the [Final Report](final_report.md).

**demo video**:https://drive.google.com/file/d/1If1n9xhZaKbqQ-D-OaLafd1hIi4rlbin/view?usp=drive_link
