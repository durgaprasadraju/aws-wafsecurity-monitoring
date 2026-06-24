# Deployment Commands

Step-by-step commands to deploy the **AWS WAF Security Intelligence & Observability Platform** in a single AWS account (sandbox-friendly).

**Default region:** `us-west-2`

---

## Prerequisites

```bash
# Verify tools
terraform version    # >= 1.7
aws --version
python3 --version    # >= 3.11 (optional, for traffic simulation)

# Verify AWS credentials
aws sts get-caller-identity

# Set region for this session
export AWS_REGION=us-west-2
export AWS_DEFAULT_REGION=us-west-2
```

Required IAM permissions: WAF, S3, Firehose, Glue, Athena, Lambda, EC2, IAM, KMS, SNS, EventBridge, CloudWatch.

---

## Step 1 — Create Terraform remote state (one-time)

```bash
export AWS_REGION=us-west-2

# S3 bucket for Terraform state
aws s3api create-bucket \
  --bucket waf-security-terraform-state \
  --region $AWS_REGION \
  --create-bucket-configuration LocationConstraint=$AWS_REGION

aws s3api put-bucket-versioning \
  --bucket waf-security-terraform-state \
  --versioning-configuration Status=Enabled

# DynamoDB table for state locking
aws dynamodb create-table \
  --table-name waf-security-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region $AWS_REGION
```

> **us-east-1 only:** omit `--create-bucket-configuration LocationConstraint=...` when creating the S3 bucket.

---

## Step 2 — Configure environment variables

```bash
cd terraform/environments/dev

cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
aws_region               = "us-west-2"
alert_email              = "your-email@example.com"
waf_rate_limit           = 2000
enable_bot_control       = false
monitoring_instance_type = "t3.medium"
agent_count              = 3
key_name                 = ""   # optional: EC2 SSH key pair name
```

---

## Step 3 — Initialize and deploy

```bash
cd terraform/environments/dev

terraform init
terraform fmt -recursive
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
```

Apply takes ~10–15 minutes. Creates VPC, ALB, WAF, S3, Firehose, Glue, Athena, Lambda, SNS, CloudWatch, and 4 EC2 instances.

---

## Step 4 — View outputs

```bash
terraform output

terraform output -raw firehose_stream_name      # must be: aws-waf-logs-waf-security-dev
terraform output -raw waf_logging_destination   # WAF → Firehose ARN
terraform output -raw alb_dns_name
terraform output -raw grafana_url
terraform output -raw s3_bucket_name
```

Verify WAF logging is wired correctly:

```bash
bash ../../../scripts/deployment/verify_waf_logging.sh
```

Expected Firehose stream name: **`aws-waf-logs-waf-security-dev`** (must start with `aws-waf-logs-`).

---

## Step 5 — Confirm SNS subscriptions

Check your email inbox and **confirm** both SNS topic subscriptions (security alerts + reports).

```bash
aws sns list-subscriptions --region us-west-2 \
  --query "Subscriptions[?contains(TopicArn,'waf-security-dev')].[TopicArn,Protocol,Endpoint,SubscriptionArn]" \
  --output table
```

---

## Step 6 — Verify ALB and WAF

```bash
ALB_DNS=$(terraform output -raw alb_dns_name)

# Expect HTTP 200
curl -s -o /dev/null -w "HTTP %{http_code}\n" "http://${ALB_DNS}"

# WAF Web ACL
aws wafv2 list-web-acls --scope REGIONAL --region us-west-2

# Firehose stream
aws firehose describe-delivery-stream \
  --delivery-stream-name "$(terraform output -raw firehose_stream_name)" \
  --region us-west-2 \
  --query 'DeliveryStreamDescription.DeliveryStreamStatus'
```

---

## Step 7 — Generate test traffic

```bash
# All scenarios in one command (auto-detects ALB from terraform)
bash ../../../scripts/attack_simulation/run_traffic.sh

# Or run individually:
ALB_URL="http://$(terraform output -raw alb_dns_name)"
python3 ../../../scripts/attack_simulation/simulate_sqli.py --url "$ALB_URL" --count 20
python3 ../../../scripts/attack_simulation/simulate_xss.py --url "$ALB_URL" --count 20
python3 ../../../scripts/attack_simulation/simulate_bot_attack.py --url "$ALB_URL" --count 50
python3 ../../../scripts/attack_simulation/simulate_rate_limit_attack.py --url "$ALB_URL" --count 100
```

Wait **5–10 minutes** for Firehose to deliver logs:

```bash
aws s3 ls "s3://$(terraform output -raw s3_bucket_name)/waf-logs/" --recursive | head
```

---

## Step 8 — Run Glue crawler

```bash
aws glue start-crawler \
  --name waf-security-dev-waf-logs-crawler \
  --region us-west-2

# Poll until READY
aws glue get-crawler \
  --name waf-security-dev-waf-logs-crawler \
  --region us-west-2 \
  --query 'Crawler.State' \
  --output text
```

---

## Step 9 — Query Athena

```bash
BUCKET=$(terraform output -raw s3_bucket_name)

aws athena start-query-execution \
  --region us-west-2 \
  --query-string "SELECT action, COUNT(*) AS cnt FROM waf_security_dev_waf.waf_logs GROUP BY action" \
  --work-group waf-security-dev-waf-analytics \
  --query-execution-context Database=waf_security_dev_waf \
  --result-configuration "OutputLocation=s3://${BUCKET}/athena-results/"
```

---

## Step 10 — Access Grafana and Prometheus

```bash
echo "Grafana:    $(terraform output -raw grafana_url)"
echo "Prometheus: $(terraform output -raw prometheus_url)"
```

| Service    | Default login        |
|-----------|----------------------|
| Grafana   | `admin` / `ChangeMe123!` |
| Prometheus| No auth (VPC access) |

Change the Grafana password on first login. Allow **3–5 minutes** after EC2 launch for Docker services to start.

---

## Step 11 — Test Lambda report

```bash
aws lambda invoke \
  --region us-west-2 \
  --function-name "$(terraform output -raw lambda_function_name)" \
  --cli-binary-format raw-in-base64-out \
  --payload '{"report_type":"daily"}' \
  /tmp/waf-report-output.json

cat /tmp/waf-report-output.json
```

---

## Deploy other environments

```bash
# Test
cd terraform/environments/test
cp terraform.tfvars.example terraform.tfvars
terraform init && terraform apply

# Prod
cd terraform/environments/prod
cp terraform.tfvars.example terraform.tfvars
terraform init && terraform apply
```

---

## Teardown

```bash
cd terraform/environments/dev

# Empty log bucket first (required before destroy)
aws s3 rm "s3://$(terraform output -raw s3_bucket_name)" --recursive

terraform destroy
```

---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| `Backend initialization required` | Run `terraform init` in the environment directory |
| `BucketAlreadyExists` | S3 bucket names are global — change `project_name` or use a unique suffix |
| No WAF logs in S3 | Wait 5–10 min; check Firehose CloudWatch logs |
| WAF logging fails: invalid LOG_DESTINATION ARN | Firehose stream name must start with `aws-waf-logs-` |
| Athena returns 0 rows | Run Glue crawler; use partition filters (`year`, `month`, `day`) |
| Grafana unreachable | Wait for EC2 user-data; check security group allows port 3000 from your IP/VPC |

More detail: [docs/guides/deployment-guide.md](docs/guides/deployment-guide.md) · [docs/guides/terraform-debugging-guide.md](docs/guides/terraform-debugging-guide.md)

---

## Quick reference (copy-paste)

```bash
export AWS_REGION=us-west-2
export AWS_DEFAULT_REGION=us-west-2

cd terraform/environments/dev
cp terraform.tfvars.example terraform.tfvars   # edit alert_email
terraform init
terraform plan -out=tfplan
terraform apply tfplan
terraform output grafana_url
```
