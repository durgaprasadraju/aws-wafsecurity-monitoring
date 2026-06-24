# Security Compliance Mapping

## AWS Well-Architected Framework

### Security Pillar
| Best Practice | Control | Implementation |
|--------------|---------|----------------|
| SEC 1: Identity | IAM roles per service | `terraform/modules/iam/` |
| SEC 4: Network protection | WAF on ALB | `terraform/modules/waf/` |
| SEC 5: Data protection | KMS encryption | `terraform/modules/kms/` |
| SEC 6: Incident response | Alerting + runbooks | Prometheus, CloudWatch, docs/operations/ |
| SEC 8: Protect compute | IMDSv2, encrypted EBS | `terraform/modules/monitoring/` |
| SEC 9: Application security | WAF managed rules | SQLi, XSS, IP reputation, rate limit |
| SEC 10: Data classification | Log redaction | WAF redacts auth/cookie headers |
| SEC 11: Encryption in transit | TLS-ready ALB | HTTPS listener can be added |

### Reliability Pillar
| Best Practice | Implementation |
|--------------|----------------|
| Multi-AZ subnets | VPC module with 2 AZs |
| Monitoring | Prometheus + CloudWatch |
| Backup | S3 versioning, Terraform state versioning |

### Operational Excellence
| Best Practice | Implementation |
|--------------|----------------|
| IaC | Full Terraform deployment |
| Runbooks | docs/operations/ |
| CI/CD | cicd/github-actions/ci.yml |

### Cost Optimization
| Best Practice | Implementation |
|--------------|----------------|
| Lifecycle policies | S3 IA/Glacier transitions |
| Partitioned queries | Athena year/month/day |
| Right-sizing | t3 instances for sandbox |

## CIS AWS Foundations Benchmark v1.5

| CIS ID | Control | Status | Evidence |
|--------|---------|--------|----------|
| 2.1.1 | S3 Block Public Access | ✅ | s3 module public_access_block |
| 2.1.2 | S3 encryption | ✅ | SSE-KMS on WAF logs bucket |
| 3.1 | CloudTrail | ⚠️ | Account-level (enable separately) |
| 3.7 | KMS key rotation | ✅ | enable_key_rotation = true |
| 4.1 | IAM roles for services | ✅ | Dedicated roles per service |
| 4.3 | No root access keys | ✅ | No keys in Terraform |

## NIST 800-53 Rev 5

| Family | Control | Implementation |
|--------|---------|----------------|
| AU-2 | Audit events | WAF logging, CloudWatch, CloudTrail |
| AU-6 | Audit review | SOC analyst guide, dashboards |
| AU-9 | Audit protection | KMS encryption, S3 policies |
| SI-4 | System monitoring | Prometheus, CloudWatch alarms |
| SC-7 | Boundary protection | WAF Web ACL |
| SC-8 | Transmission confidentiality | TLS, KMS |
| SC-13 | Cryptographic protection | Customer-managed KMS |
| IR-4 | Incident handling | Incident response guide |
| IR-5 | Incident monitoring | Alertmanager, SNS |

## ISO 27001:2022

| Annex A | Control | Implementation |
|---------|---------|----------------|
| A.8.15 | Logging | WAF, ALB, Lambda, Firehose logs |
| A.8.16 | Monitoring | Grafana, Prometheus, CloudWatch |
| A.8.24 | Cryptography | KMS CMK |
| A.5.15 | Access control | IAM least privilege |
| A.5.24 | Incident management | IR guide, playbooks |
| A.8.9 | Configuration management | Terraform IaC |
