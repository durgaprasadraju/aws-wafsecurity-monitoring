# Incident Response Guide

## Severity Classification

| Severity | Criteria | Response Time |
|----------|----------|---------------|
| SEV-1 | Active breach, data exfiltration, platform down | 15 minutes |
| SEV-2 | Sustained attack, log pipeline failure | 30 minutes |
| SEV-3 | Elevated blocks, single-vector attack | 2 hours |
| SEV-4 | Informational, isolated blocks | Next business day |

## Incident Response Workflow

```
Detect → Triage → Contain → Eradicate → Recover → Lessons Learned
```

## Playbook: DDoS / High Volume Attack

### Detect
- Alert: `HighBlockRate` or `TopAttackerSpike`
- CloudWatch WAF blocked requests spike

### Triage
```sql
-- Athena: identify top sources
SELECT httprequest.clientip, httprequest.country, COUNT(*) AS blocks
FROM waf_security_dev_waf.waf_logs
WHERE action = 'BLOCK'
  AND from_unixtime(timestamp/1000) > current_timestamp - interval '1' hour
GROUP BY 1, 2 ORDER BY 3 DESC LIMIT 20;
```

### Contain
1. Verify rate limiting rule is active (priority 10)
2. Create WAF IP set to block top attacker IPs
3. Consider lowering `waf_rate_limit` via Terraform (requires apply)

### Eradicate
- Monitor for 1 hour post-containment
- Block additional IPs as they appear

### Recover
- Remove temporary IP blocks after 24h if attack subsided
- Restore original rate limit

### Document
- Record timeline, IPs, rules triggered, actions taken

---

## Playbook: Log Pipeline Failure

### Detect
- Alert: `FirehoseFailures` or `firehose-failures` CloudWatch alarm
- No new objects in S3 `waf-logs/` prefix

### Triage
```bash
aws firehose describe-delivery-stream --delivery-stream-name STREAM_NAME
aws logs filter-log-events \
  --log-group-name /aws/kinesisfirehose/STREAM_NAME \
  --filter-pattern "ERROR"
```

### Contain
- WAF continues blocking; only logging affected
- Enable WAF sampled requests in console for temporary visibility

### Eradicate
Common fixes:
1. S3 bucket policy blocking Firehose role
2. KMS key policy missing Firehose principal
3. IAM role trust policy issue

### Recover
```bash
# Verify delivery resumed
aws s3 ls s3://BUCKET/waf-logs/ --recursive | tail -5
# Run Glue crawler
aws glue start-crawler --name CRAWLER_NAME
```

---

## Playbook: Monitoring Stack Down

### Detect
- Alert: `PrometheusTargetDown`
- Grafana unreachable

### Triage
```bash
ssh ec2-user@MONITORING_IP
sudo docker compose -f /opt/observability/docker-compose.yml ps
curl localhost:9090/-/healthy
```

### Contain
- CloudWatch dashboards remain available as backup
- CloudWatch alarms continue firing to SNS

### Recover
```bash
cd /opt/observability
sudo docker compose restart
# If persistent:
sudo docker compose down && sudo docker compose up -d
```

---

## Communication Templates

### Initial Notification
```
[SEV-X] WAF Security Incident
Time detected: YYYY-MM-DD HH:MM UTC
Alert: {alert_name}
Impact: {description}
Actions: Investigating
Lead: {name}
```

### Resolution Notification
```
[RESOLVED] WAF Security Incident
Duration: X hours
Root cause: {cause}
Actions taken: {actions}
Follow-up: {items}
```

## Post-Incident

1. Complete incident timeline within 48 hours
2. Update runbooks if gaps identified
3. Adjust alert thresholds if false positive
4. Schedule blameless postmortem for SEV-1/SEV-2
