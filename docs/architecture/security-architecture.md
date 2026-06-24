# Security Architecture

## 1. Defense in Depth

```
Layer 1: Perimeter     → WAF Web ACL (managed rules + rate limiting)
Layer 2: Transport     → HTTPS-ready ALB, TLS termination
Layer 3: Data          → KMS encryption at rest (S3, SNS, CloudWatch Logs)
Layer 4: Access        → IAM least privilege, no public S3 access
Layer 5: Monitoring    → CloudTrail, CloudWatch, Prometheus alerting
Layer 6: Audit         → S3 access logging, WAF full request logging
```

## 2. Encryption

| Resource | Method | Key |
|----------|--------|-----|
| S3 WAF logs | SSE-KMS | Customer-managed CMK |
| S3 ALB logs | Default SSE-S3 | AWS managed |
| SNS topics | SSE-KMS | Customer-managed CMK |
| CloudWatch Logs | SSE-KMS | Customer-managed CMK |
| Athena results | SSE-KMS | Customer-managed CMK |
| EC2 volumes | EBS encryption | AWS managed |

## 3. IAM Least Privilege

- Each service has a dedicated IAM role
- No wildcard actions except where required (Athena query execution)
- EC2 instance profile limited to CloudWatch read + EC2 describe
- S3 bucket policy denies insecure transport and unencrypted uploads

## 4. Network Security

- S3 public access blocked on all buckets
- Monitoring services accessible only within VPC CIDR
- ALB is the only internet-facing component
- IMDSv2 required on all EC2 instances

## 5. Logging & Audit

| Source | Destination | Retention |
|--------|-------------|-----------|
| WAF | Firehose → S3 | 90 days (lifecycle) |
| ALB | S3 access logs | Per bucket policy |
| S3 access | S3 access logs bucket | 90 days |
| Lambda | CloudWatch Logs | 30 days |
| Firehose | CloudWatch Logs | 30 days |
| KMS | CloudTrail | Account default |

## 6. Compliance Mapping

### CIS AWS Foundations Benchmark
| Control | Implementation |
|---------|---------------|
| 2.1.1 Deny S3 public access | S3 public access block |
| 3.7 KMS CMK rotation | enable_key_rotation = true |
| 4.1 IAM roles for services | Dedicated service roles |
| 4.4 Ensure IAM access keys rotated | No access keys; use roles |

### NIST 800-53
| Control | Implementation |
|---------|---------------|
| AU-2 Audit events | WAF logging, CloudTrail |
| AU-9 Protection of audit info | KMS encryption, S3 versioning |
| SI-4 System monitoring | CloudWatch, Prometheus, Grafana |
| SC-8 Transmission confidentiality | TLS, KMS |
| SC-13 Cryptographic protection | KMS CMK |

### ISO 27001
| Control | Implementation |
|---------|---------------|
| A.12.4.1 Event logging | WAF + ALB + application logs |
| A.10.1.1 Cryptographic controls | KMS encryption |
| A.9.2.3 Privileged access | IAM roles, no long-term keys |

## 7. Security Controls Checklist

- [x] WAF enabled with managed rules
- [x] Rate limiting configured
- [x] Log redaction (auth headers)
- [x] Encryption at rest (KMS)
- [x] Encryption in transit (HTTPS/TLS ready)
- [x] S3 public access blocked
- [x] IAM least privilege
- [x] CloudWatch alarms for security events
- [x] Automated security reporting
- [x] IMDSv2 on EC2
