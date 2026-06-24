# Deployment Guide

## Prerequisites

1. AWS account with permissions for WAF, S3, Firehose, Glue, Athena, Lambda, EC2, IAM, KMS, SNS, EventBridge, CloudWatch
2. Terraform >= 1.7 installed
3. AWS CLI v2 configured
4. Python 3.11+ (for tests and attack simulation)

## Step 1: Create Terraform Backend

```bash
export AWS_REGION=us-west-2

aws s3api create-bucket \
  --bucket waf-security-terraform-state \
  --region $AWS_REGION \
  --create-bucket-configuration LocationConstraint=$AWS_REGION

aws s3api put-bucket-versioning \
  --bucket waf-security-terraform-state \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket waf-security-terraform-state \
  --server-side-encryption-configuration '{
    "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]
  }'

aws dynamodb create-table \
  --table-name waf-security-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region $AWS_REGION
```

## Step 2: Configure Environment

```bash
cd terraform/environments/dev
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:
- Set `alert_email` to your email (confirm SNS subscription after deploy)
- Adjust `waf_rate_limit` if needed
- Set `key_name` if SSH access to EC2 is required

## Step 3: Deploy Infrastructure

```bash
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

Expected resources: ~40-50 (VPC, ALB, WAF, S3, Firehose, Glue, Athena, Lambda, SNS, EC2×4, IAM, KMS, CloudWatch)

## Step 4: Verify Deployment

```bash
# ALB reachable
curl -s -o /dev/null -w "%{http_code}" http://$(terraform output -raw alb_dns_name)

# WAF Web ACL exists
aws wafv2 list-web-acls --scope REGIONAL --region $AWS_REGION

# Firehose active
aws firehose describe-delivery-stream \
  --delivery-stream-name $(terraform output -raw firehose_stream_name)

# Confirm SNS email subscription (check inbox)
```

## Step 5: Generate Traffic & Validate Logs

```bash
ALB_URL="http://$(terraform output -raw alb_dns_name)"

# Normal + attack traffic
python ../../../scripts/attack_simulation/simulate_sqli.py --url $ALB_URL --count 30
python ../../../scripts/attack_simulation/simulate_xss.py --url $ALB_URL --count 30
python ../../../scripts/attack_simulation/simulate_rate_limit_attack.py --url $ALB_URL --count 200

# Wait 5-10 minutes for Firehose delivery
aws s3 ls s3://$(terraform output -raw s3_bucket_name)/waf-logs/ --recursive | head
```

## Step 6: Run Glue Crawler

```bash
aws glue start-crawler --name waf-security-dev-waf-logs-crawler
# Wait for completion
aws glue get-crawler --name waf-security-dev-waf-logs-crawler \
  --query 'Crawler.State' --output text
```

## Step 7: Query Athena

```bash
aws athena start-query-execution \
  --query-string "SELECT COUNT(*) FROM waf_security_dev_waf.waf_logs" \
  --work-group waf-security-dev-waf-analytics \
  --query-execution-context Database=waf_security_dev_waf \
  --result-configuration OutputLocation=s3://$(terraform output -raw s3_bucket_name)/athena-results/
```

## Step 8: Access Grafana

```bash
echo "Grafana: $(terraform output -raw grafana_url)"
echo "Default credentials: admin / ChangeMe123!"
```

Change the Grafana admin password immediately after first login.

## Step 9: Test Lambda Report

```bash
aws lambda invoke \
  --function-name $(terraform output -raw lambda_function_name) \
  --payload '{"report_type":"daily"}' \
  /tmp/report-output.json

cat /tmp/report-output.json
```

## Environment Promotion

| From | To | Steps |
|------|-----|-------|
| dev | test | Update tfvars, `terraform apply` in test/ |
| test | prod | Enable bot control, increase instance sizes, enable deletion protection |

## Teardown

```bash
# Empty S3 buckets first
aws s3 rm s3://BUCKET_NAME --recursive
terraform destroy
```

## Troubleshooting

See [Terraform Debugging Guide](terraform-debugging-guide.md) and [Troubleshooting Guide](../operations/troubleshooting-guide.md).
