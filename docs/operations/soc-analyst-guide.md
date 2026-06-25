# SOC Analyst Guide

## Daily Operations Checklist

- [ ] Review CloudWatch WAF dashboard for anomalies
- [ ] Check Grafana Security Overview for block rate trends
- [ ] Review overnight SNS report notifications
- [ ] Triage any firing CloudWatch/Prometheus alerts
- [ ] Verify Firehose delivery success > 99%

## Key Dashboards

| Dashboard | Location | Purpose |
|-----------|----------|---------|
| WAF Security (CW) | CloudWatch Dashboards | Real-time block/allow metrics |
| Security Overview | Grafana :3000 | Combined WAF + infrastructure |
| Threat Intelligence | Grafana (Prometheus) | Block trends by rule (SQLi, XSS, Bot) |
| WAF Log Analytics (Athena) | Grafana / Athena | Top attackers, countries, URIs — see [Grafana + Athena Guide](../guides/grafana-athena-guide.md) |

## Investigating a Blocked Request

### Step 1: CloudWatch Metrics
1. Open WAF dashboard
2. Identify spike timeframe and rule name
3. Note which rule group triggered (SQLi, XSS, Rate Limit)

### Step 2: Athena Deep Dive
```sql
SELECT from_unixtime(timestamp/1000) AS event_time,
       httprequest.clientip,
       httprequest.country,
       httprequest.uri,
       httprequest.httpmethod,
       terminatingruleid,
       action
FROM waf_security_dev_waf.waf_logs
WHERE action = 'BLOCK'
  AND year = date_format(current_date, '%Y')
  AND month = date_format(current_date, '%m')
  AND day = date_format(current_date, '%d')
ORDER BY timestamp DESC
LIMIT 100;
```

### Step 3: Identify Attack Pattern
- **SQLi**: Check `terminatingruleid` contains SQLi, review URI parameters
- **XSS**: Check BadInputs rule, review query string payloads
- **Rate Limit**: Single IP with high volume — check `ratebasedrulelist`
- **Bot**: Review User-Agent in httprequest.headers

### Step 4: Determine False Positive
If legitimate traffic blocked:
1. Document the request pattern
2. Create WAF exception rule (count mode first)
3. Monitor for 24h before switching to allow

## Alert Triage

| Alert | Severity | Action |
|-------|----------|--------|
| HighBlockRate | Critical | Check Athena top_attackers, assess DDoS |
| SQLiSurge | High | Run sqli_analysis query, block IPs if needed |
| XSSSurge | High | Run xss_analysis query |
| BotAttackSurge | Medium | Review bot_analysis, consider bot control |
| FirehoseFailures | Critical | Escalate to platform team |
| LambdaErrors | High | Check CloudWatch logs for report failures |

## Report Review

Daily/weekly/monthly reports arrive via SNS with S3 links:
- `s3://bucket/reports/daily/TIMESTAMP/waf_daily_report.html`
- Review executive summary section first
- Drill into top attackers and country breakdown

## IP Blocking (Manual)

For persistent attackers not caught by managed rules:
1. AWS Console → WAF → IP sets → Create IP set
2. Add attacker IP
3. Create blocking rule with higher priority than managed rules

## Escalation

| Condition | Escalate To |
|-----------|-------------|
| Sustained attack > 1 hour | Security Lead |
| Data pipeline down | Platform/SRE |
| False positive affecting production | App team + Security Lead |
| Suspected breach | Incident Response team |
