# Operational Handbook

## Platform Overview

Single-account AWS WAF security monitoring platform with log analytics and EC2-based observability.

## Daily Operations

| Time | Task | Owner |
|------|------|-------|
| 06:00 UTC | Daily report generated (Lambda) | Automated |
| 08:00 UTC | Review overnight alerts | SOC Analyst |
| 09:00 UTC | Check Firehose delivery metrics | SRE |
| Weekly Mon | Review weekly report | Security Lead |
| Monthly 1st | Review monthly report + costs | Security Lead |

## Service Management

### Restart Observability Stack
```bash
ssh ec2-user@MONITORING_IP
cd /opt/observability
sudo docker compose restart
```

### Run Glue Crawler Manually
```bash
aws glue start-crawler --name waf-security-{env}-waf-logs-crawler
```

### Trigger Manual Report
```bash
aws lambda invoke \
  --function-name waf-security-{env}-waf-report-generator \
  --payload '{"report_type":"daily"}' output.json
```

## Change Management

1. All infrastructure changes via Terraform
2. PR required with `terraform plan` output
3. Apply to dev → test → prod
4. No manual console changes in production

## Backup & Recovery

| Component | Backup Method | RTO | RPO |
|-----------|--------------|-----|-----|
| Terraform state | S3 versioning | 1h | 0 |
| WAF logs | S3 versioning + lifecycle | 4h | 5min |
| Prometheus data | EBS snapshots | 2h | 24h |
| Grafana dashboards | Git repository | 1h | 0 |

## Escalation Matrix

| Level | Contact | When |
|-------|---------|------|
| L1 | SOC Analyst | Alert triage |
| L2 | Security Engineer | Sustained attacks |
| L3 | Platform SRE | Infrastructure failures |
| L4 | Security Lead | SEV-1 incidents |

## Maintenance Windows

- **Dev**: Anytime
- **Test**: Tuesday 02:00-04:00 UTC
- **Prod**: Sunday 02:00-06:00 UTC

## Key URLs

| Service | URL Pattern |
|---------|-------------|
| ALB | `http://{alb_dns_name}` |
| Grafana | `http://{monitoring_ip}:3000` |
| Prometheus | `http://{monitoring_ip}:9090` |
| Alertmanager | `http://{monitoring_ip}:9093` |
| CloudWatch Dashboard | AWS Console → CloudWatch → Dashboards |
