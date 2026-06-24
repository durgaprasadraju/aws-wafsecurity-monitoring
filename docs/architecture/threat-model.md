# Threat Model

## 1. Scope

**In scope**: WAF-protected ALB, log pipeline, analytics, reporting, observability stack.
**Out of scope**: Application code, database layer, end-user devices.

## 2. Assets

| Asset | Classification | Impact if Compromised |
|-------|---------------|----------------------|
| WAF logs (S3) | Confidential | Attack pattern exposure |
| Athena query results | Confidential | Security intelligence leak |
| Grafana/Prometheus | Internal | Monitoring blind spot |
| KMS keys | Critical | Data decryption |
| IAM roles | Critical | Lateral movement |

## 3. Threat Actors

| Actor | Motivation | Capability |
|-------|-----------|------------|
| External attacker | Data theft, disruption | Low–High |
| Automated bot | Scraping, credential stuffing | Medium |
| Insider threat | Data exfiltration | Medium–High |
| Misconfiguration | Accidental exposure | Low |

## 4. STRIDE Analysis

| Threat | Category | Mitigation |
|--------|----------|------------|
| SQLi/XSS bypass | Tampering | WAF managed rules, logging |
| Log tampering | Tampering | S3 versioning, KMS, IAM |
| Credential theft from logs | Information Disclosure | Header redaction |
| S3 bucket exposure | Information Disclosure | Public access block, bucket policy |
| DDoS/rate abuse | Denial of Service | WAF rate limiting, ALB scaling |
| Privilege escalation | Elevation of Privilege | IAM least privilege |
| Alert fatigue | Denial of Service | Alertmanager routing, severity tiers |

## 5. Attack Scenarios

### Scenario 1: SQL Injection Campaign
1. Attacker sends SQLi payloads to `/login`
2. WAF SQLi rule set blocks requests
3. Logs delivered to S3 via Firehose
4. CloudWatch alarm triggers on SQLi surge
5. SOC reviews Athena query + Grafana dashboard

### Scenario 2: Rate Limit Evasion
1. Attacker distributes requests across IPs
2. Per-IP rate limit may not catch distributed attack
3. Mitigation: Monitor aggregate block rate alarm
4. Future: Enable AWS WAF rate-based rules with custom keys

### Scenario 3: Log Pipeline Failure
1. Firehose delivery fails
2. CloudWatch alarm: firehose-failures
3. Runbook: Check IAM, S3 permissions, KMS key
4. Recovery: Fix permissions, replay from WAF sampling

## 6. Risk Matrix

| Risk | Likelihood | Impact | Residual Risk |
|------|-----------|--------|---------------|
| SQLi attack | High | Medium | Low (WAF blocks) |
| Log pipeline outage | Low | High | Medium (alarms) |
| S3 misconfiguration | Low | Critical | Low (policies) |
| Monitoring blind spot | Medium | Medium | Low (redundant CW+Prom) |

## 7. Security Testing

- Attack simulation scripts (`scripts/attack_simulation/`)
- Locust load testing with attack scenarios
- Terraform security scans (tfsec, checkov)
- Python security scans (bandit, semgrep)
