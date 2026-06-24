# KMS Module

## Purpose

Creates a customer-managed KMS key with rotation enabled for encrypting WAF logs, S3 buckets, CloudWatch Logs, and Firehose delivery streams.

## Architecture

Single CMK per environment with key policy allowing S3, Firehose, CloudWatch Logs, and account root access.

## Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| project_name | Project name | string | required |
| environment | Environment name | string | required |
| tags | Resource tags | map(string) | {} |
| deletion_window_in_days | Key deletion window | number | 30 |
| enable_key_rotation | Enable rotation | bool | true |

## Outputs

| Name | Description |
|------|-------------|
| key_id | KMS key ID |
| key_arn | KMS key ARN |
| alias_name | KMS alias |

## Dependencies

None.

## Security Controls

- CMK with automatic rotation (CIS 3.7)
- Least-privilege key policy
- 30-day deletion window

## Failure Scenarios

| Scenario | Recovery |
|----------|----------|
| Key disabled | Re-enable via console/CLI |
| Policy misconfiguration | Apply corrected Terraform |

## Monitoring

CloudTrail logs all KMS API calls.

## Testing

```bash
terraform validate
aws kms describe-key --key-id alias/<project>-<env>
```

## Runbook

See `docs/operations/runbooks/kms-key-rotation.md`.
