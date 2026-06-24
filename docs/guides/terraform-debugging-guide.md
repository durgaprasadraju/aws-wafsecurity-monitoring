# Terraform Debugging Guide

## terraform init Issues

### Symptoms
```
Error: Failed to get existing workspaces
Error: S3 bucket does not exist
```

### Root Cause
Remote state backend S3 bucket or DynamoDB lock table not created.

### Fix
```bash
aws s3 mb s3://waf-security-terraform-state --region us-west-2
aws dynamodb create-table --table-name waf-security-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST
terraform init -reconfigure
```

### Provider conflicts
```
Error: Failed to query available provider packages
```

```bash
rm -rf .terraform .terraform.lock.hcl
terraform init -upgrade
```

---

## terraform plan Failures

### WAF Bot Control not available
```
Error: creating WAFv2 Web ACL: WAFOptimisticLockException
Error: ManagedRuleGroup Bot Control requires subscription
```

**Fix**: Set `enable_bot_control = false` in terraform.tfvars (default for sandbox).

### Circular dependency
```
Error: Cycle: module.monitoring, local.monitoring_user_data
```

**Fix**: Already resolved — monitoring user_data discovers agents via EC2 tags at boot.

### Invalid ALB + WAF association
```
Error: WAFInvalidParameterException
```

**Fix**: Ensure ALB is in the same region as WAF (scope = REGIONAL).

---

## terraform apply Failures

### State locking
```
Error: Error acquiring the state lock
```

```bash
# Check who holds the lock
aws dynamodb get-item --table-name waf-security-terraform-locks \
  --key '{"LockID":{"S":"waf-security-terraform-state/dev/terraform.tfstate-md5"}}'

# Force unlock (use with caution)
terraform force-unlock LOCK_ID
```

### IAM permission denied
```
Error: AccessDenied: User is not authorized to perform: wafv2:CreateWebACL
```

**Fix**: Ensure sandbox role has WAF, Firehose, Glue, Athena, Lambda, EC2, IAM permissions.

### S3 bucket already exists
```
Error: BucketAlreadyExists
```

**Fix**: Bucket names are globally unique. Change `project_name` in locals or delete existing bucket.

---

## Athena Issues

### HIVE_PARTITION_SCHEMA_MISMATCH
**Fix**: Run Glue crawler to update partitions:
```bash
aws glue start-crawler --name waf-security-dev-waf-logs-crawler
```

### Query fails with no data
**Fix**: Verify S3 has logs, crawler completed, and partition values match:
```sql
SELECT * FROM waf_security_dev_waf.waf_logs
WHERE year='2026' AND month='06' AND day='24' LIMIT 10;
```

---

## Lambda Issues

### Timeout during Athena query
**Fix**: Increase Lambda timeout (currently 300s) or optimize queries with partition filters.

### KMS AccessDenied on S3 PutObject
**Fix**: Verify Lambda role has kms:GenerateDataKey on the CMK.

---

## Grafana / Prometheus Issues

### Prometheus targets down
```bash
# SSH to monitoring server
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job, health}'
```

**Fix**: Verify agent security group allows port 9100 from VPC. Re-run EC2 tag discovery in user_data.

### Grafana cannot reach Prometheus
**Fix**: Ensure datasource URL is `http://localhost:9090` or Docker network hostname.

---

## Glue Issues

### Crawler fails with AccessDenied
**Fix**: Verify glue-crawler-role has S3 read permissions on the WAF logs bucket.

---

## General Debugging Commands

```bash
# Terraform debug logging
export TF_LOG=DEBUG
terraform plan 2>&1 | tee plan-debug.log

# Validate all modules
bash tests/terraform/validate.sh dev

# Check WAF logging config
aws wafv2 get-logging-configuration \
  --resource-arn $(terraform output -raw waf_web_acl_arn)

# Check Firehose status
aws firehose describe-delivery-stream \
  --delivery-stream-name $(terraform output -raw firehose_stream_name)
```
