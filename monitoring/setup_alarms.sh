#!/bin/bash
# DevOps Technical Assignment - Setup CloudWatch Monitoring
# This script automates CloudWatch Alarms and Dashboard creation.
# Requirements: AWS CLI installed and configured.

set -eo pipefail

# Default settings (can be overridden by environment variables)
AWS_REGION=${AWS_REGION:-"us-east-1"}
INSTANCE_ID=$1
EMAIL_ADDRESS=$2

if [ -z "$INSTANCE_ID" ] || [ -z "$EMAIL_ADDRESS" ]; then
    echo "Usage: $0 <EC2_INSTANCE_ID> <NOTIFICATION_EMAIL>"
    echo "Example: $0 i-0123456789abcdef0 devops-alerts@mycompany.com"
    exit 1
fi

echo "=========================================================="
echo "      Deploying CloudWatch Alarms and Dashboards"
echo "=========================================================="
echo "AWS Region:  $AWS_REGION"
echo "EC2 Instance ID: $INSTANCE_ID"
echo "Alerts Email:    $EMAIL_ADDRESS"
echo "=========================================================="

# 1. Create SNS Topic for Alerts
echo "--> Creating SNS Alert Topic..."
TOPIC_ARN=$(aws sns create-topic \
    --name devops-app-alerts \
    --region "$AWS_REGION" \
    --query "TopicArn" \
    --output text)

echo "Created SNS Topic: $TOPIC_ARN"

# 2. Subscribe Email to SNS Topic
echo "--> Subscribing email $EMAIL_ADDRESS to SNS topic..."
aws sns subscribe \
    --topic-arn "$TOPIC_ARN" \
    --protocol email \
    --notification-endpoint "$EMAIL_ADDRESS" \
    --region "$AWS_REGION"

echo "Check your email inbox to confirm the subscription subscription link."

# 3. Create CPU Alarm (>80%)
echo "--> Creating CPU Utilization Alarm (>80% average for 10 minutes)..."
aws cloudwatch put-metric-alarm \
    --alarm-name "EC2-CPU-High-80Percent-${INSTANCE_ID}" \
    --alarm-description "Triggers if CPU exceeds 80% for 2 consecutive evaluation periods of 5 minutes" \
    --actions-enabled \
    --alarm-actions "$TOPIC_ARN" \
    --ok-actions "$TOPIC_ARN" \
    --metric-name CPUUtilization \
    --namespace AWS/EC2 \
    --statistic Average \
    --dimensions Name=InstanceId,Value="$INSTANCE_ID" \
    --period 300 \
    --evaluation-periods 2 \
    --threshold 80.0 \
    --comparison-operator GreaterThanOrEqualToThreshold \
    --region "$AWS_REGION"

# 4. Create Memory Alarm (>80% from CWAgent)
echo "--> Creating Memory Utilization Alarm (>80% average for 10 minutes)..."
aws cloudwatch put-metric-alarm \
    --alarm-name "EC2-Mem-High-80Percent-${INSTANCE_ID}" \
    --alarm-description "Triggers if custom memory metric mem_used_percent exceeds 80% for 2 consecutive evaluation periods of 5 minutes" \
    --actions-enabled \
    --alarm-actions "$TOPIC_ARN" \
    --ok-actions "$TOPIC_ARN" \
    --metric-name mem_used_percent \
    --namespace CWAgent \
    --statistic Average \
    --dimensions Name=InstanceId,Value="$INSTANCE_ID" \
    --period 300 \
    --evaluation-periods 2 \
    --threshold 80.0 \
    --comparison-operator GreaterThanOrEqualToThreshold \
    --region "$AWS_REGION"

# 5. Build CloudWatch Dashboard
echo "--> Constructing CloudWatch Dashboard..."
DASHBOARD_FILE="dashboard_processed.json"

# Replace variables in the template JSON using envsubst or sed
if command -v envsubst &> /dev/null; then
    export INSTANCE_ID
    export AWS_REGION
    envsubst < dashboard.json > "$DASHBOARD_FILE"
else
    # Simple sed replacement fallback
    sed -e "s/\${INSTANCE_ID}/$INSTANCE_ID/g" \
        -e "s/\${AWS_REGION}/$AWS_REGION/g" \
        dashboard.json > "$DASHBOARD_FILE"
fi

aws cloudwatch put-dashboard \
    --dashboard-name "DevOps-System-Control-${INSTANCE_ID}" \
    --dashboard-body file://"$DASHBOARD_FILE" \
    --region "$AWS_REGION"

rm -f "$DASHBOARD_FILE"

echo "=========================================================="
echo "Dashboard Created: DevOps-System-Control-${INSTANCE_ID}"
echo "Alarms Created:    EC2-CPU-High-80Percent-${INSTANCE_ID}"
echo "                   EC2-Mem-High-80Percent-${INSTANCE_ID}"
echo "CloudWatch Configuration Complete!"
echo "=========================================================="
