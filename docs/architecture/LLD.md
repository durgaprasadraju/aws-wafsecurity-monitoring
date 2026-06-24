# Low Level Design (LLD)

## 1. Network Design

### VPC: 10.0.0.0/16
| Subnet | CIDR | AZ | Purpose |
|--------|------|-----|---------|
| public-0 | 10.0.0.0/20 | az-a | ALB, Monitoring EC2 |
| public-1 | 10.0.16.0/20 | az-b | ALB, Agent EC2 |
| private-0 | 10.0.32.0/20 | az-a | Future expansion |
| private-1 | 10.0.48.0/20 | az-b | Future expansion |

### Security Groups
| SG | Inbound | Outbound |
|----|---------|----------|
| alb-sg | 80, 443 from 0.0.0.0/0 | All |
| monitoring-sg | 9090, 3000, 9093, 9100, 9106, 9115 from VPC | All |
| app-sg | 80 from alb-sg | All |

## 2. WAF Web ACL Rules

| Priority | Rule | Action |
|----------|------|--------|
| 1 | AWSManagedRulesCommonRuleSet | Block (default) |
| 2 | AWSManagedRulesSQLiRuleSet | Block |
| 3 | AWSManagedRulesKnownBadInputsRuleSet | Block |
| 4 | AWSManagedRulesAmazonIpReputationList | Block |
| 5 | AWSManagedRulesBotControlRuleSet | Block (optional) |
| 10 | RateLimitRule (2000/5min/IP) | Block |

### Logging Configuration
- Destination: Firehose delivery stream ARN
- Filter: KEEP BLOCK and COUNT actions
- Redacted fields: authorization, cookie headers

## 3. S3 Bucket Design

**Bucket**: `{project}-{env}-waf-logs-{account_id}`

```
waf-logs/
  year=2026/month=06/day=24/
    firehose-output-files.gz
reports/
  daily/{timestamp}/
    waf_daily_report.html
    waf_daily_report.csv
athena-results/
  query-output-files
```

### Lifecycle
- Day 30: Transition to STANDARD_IA
- Day 60: Transition to GLACIER
- Day 90: Expiration

## 4. Glue Schema

**Database**: `waf_security_{env}_waf`
**Table**: `waf_logs` (partitioned by year, month, day)

Key columns: timestamp, action, terminatingruleid, httprequest (struct with clientip, country, uri, httpmethod)

## 5. Athena Workgroup

- Name: `waf-security-{env}-waf-analytics`
- Engine: Athena engine version 3
- Results: `s3://{bucket}/athena-results/` (SSE-KMS)
- CloudWatch metrics enabled

## 6. Lambda Report Generator

| Schedule | Cron | Report Type | Lookback |
|----------|------|-------------|----------|
| Daily | `cron(0 6 * * ? *)` | daily | 1 day |
| Weekly | `cron(0 7 ? * MON *)` | weekly | 7 days |
| Monthly | `cron(0 8 1 * ? *)` | monthly | 30 days |

### Queries Executed
1. top_attackers
2. top_countries
3. sqli_attempts
4. xss_attempts
5. bot_attacks
6. traffic_summary

## 7. EC2 Monitoring Stack

### Monitoring Server (EC2-01)
| Service | Port | Container/Image |
|---------|------|-----------------|
| Prometheus | 9090 | prom/prometheus:v2.51.0 |
| Grafana | 3000 | grafana/grafana:10.4.0 |
| Alertmanager | 9093 | prom/alertmanager:v0.27.0 |
| CloudWatch Exporter | 9106 | prom/cloudwatch-exporter |
| Blackbox Exporter | 9115 | prom/blackbox-exporter |
| Node Exporter | 9100 | systemd native |

### Agent Nodes (EC2-02, 03, 04)
- Node Exporter on port 9100

## 8. IAM Roles

| Role | Service | Key Permissions |
|------|---------|-----------------|
| firehose-role | firehose.amazonaws.com | S3 PutObject, KMS |
| lambda-report-role | lambda.amazonaws.com | Athena, S3, SNS, Glue read |
| glue-crawler-role | glue.amazonaws.com | S3 read, Glue service |
| ec2-monitoring-role | ec2.amazonaws.com | CloudWatch read, EC2 describe |

## 9. KMS Key Policy

Allows: account root, CloudWatch Logs, S3, Firehose

## 10. Terraform State

- Backend: S3 `waf-security-terraform-state`
- Locking: DynamoDB `waf-security-terraform-locks`
- Keys: `dev/`, `test/`, `prod/` terraform.tfstate
