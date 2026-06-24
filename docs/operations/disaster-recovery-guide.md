# Disaster Recovery Guide

## Recovery Objectives

| Tier | Components | RTO | RPO |
|------|-----------|-----|-----|
| Tier 1 | WAF, ALB | 15 min | 0 |
| Tier 2 | Firehose, S3 logs | 1 hour | 5 min |
| Tier 3 | Athena, Glue, Lambda | 2 hours | 1 hour |
| Tier 4 | EC2 Observability | 4 hours | 24 hours |

## Scenario 1: Complete Region Failure

**Impact**: All resources unavailable.

**Recovery**:
1. Deploy to alternate region (requires Terraform variable changes)
2. Update `aws_region` in environment tfvars
3. `terraform apply` in new region
4. Update DNS/ALB endpoint for applications
5. S3 cross-region replication (future enhancement)

## Scenario 2: S3 Bucket Deletion

**Impact**: Loss of WAF logs and reports.

**Recovery**:
1. Restore from S3 versioning:
   ```bash
   aws s3api list-object-versions --bucket BUCKET --prefix waf-logs/
   aws s3api restore-object --bucket BUCKET --key KEY --version-id VERSION
   ```
2. If versioning insufficient, restore from Glacier lifecycle copies
3. Re-run Glue crawler
4. Re-generate reports via Lambda

## Scenario 3: Terraform State Corruption

**Impact**: Cannot manage infrastructure.

**Recovery**:
1. Restore state from S3 versioning:
   ```bash
   aws s3api list-object-versions --bucket waf-security-terraform-state --prefix dev/
   aws s3 cp s3://waf-security-terraform-state/dev/terraform.tfstate \
     s3://waf-security-terraform-state/dev/terraform.tfstate \
     --version-id VERSION_ID
   ```
2. `terraform refresh` to reconcile
3. If state lost entirely: `terraform import` for each resource

## Scenario 4: KMS Key Deletion

**Impact**: Cannot decrypt S3 objects, logs, SNS.

**Recovery**:
1. If within deletion window (30 days): cancel deletion
   ```bash
   aws kms cancel-key-deletion --key-id KEY_ID
   ```
2. If key permanently deleted: data is unrecoverable — redeploy with new key

## Scenario 5: Monitoring Server Failure

**Impact**: No Prometheus/Grafana/Alertmanager.

**Recovery**:
1. CloudWatch dashboards and alarms remain operational
2. Terminate failed EC2 instance
3. `terraform apply` to recreate monitoring server
4. User data script auto-configures observability stack
5. Restore Grafana dashboards from Git repo

## DR Testing Schedule

| Test | Frequency | Last Tested |
|------|-----------|-------------|
| State restore | Quarterly | — |
| Lambda report recovery | Monthly | — |
| Monitoring server rebuild | Quarterly | — |
| Full e2e DR drill | Annually | — |

## DR Runbook Checklist

- [ ] Identify failure scope
- [ ] Notify stakeholders
- [ ] Activate backup monitoring (CloudWatch)
- [ ] Execute recovery procedure
- [ ] Validate log pipeline
- [ ] Validate reporting
- [ ] Validate observability
- [ ] Post-incident review
