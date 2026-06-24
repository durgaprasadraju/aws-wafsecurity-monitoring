# Platform Debug & Operations Guide

End-to-end reference: **Terraform apply → WAF logging → S3/Athena → Prometheus/Grafana**, including issues we hit in this project, how they were fixed, and where to look when something breaks.

**Default region:** `us-west-2`  
**Project prefix:** `waf-security-dev`

---

## Table of contents

1. [Architecture at a glance](#1-architecture-at-a-glance)
2. [Terraform apply — what gets created](#2-terraform-apply--what-gets-created)
3. [Issue history & fixes (this deployment)](#3-issue-history--fixes-this-deployment)
4. [WAF logs → Firehose → S3 → Athena (end-to-end)](#4-waf-logs--firehose--s3--athena-end-to-end)
5. [Observability stack — how it is installed](#5-observability-stack--how-it-is-installed)
6. [Why `user_data_monitoring.sh` exists](#6-why-user_data_monitoringsh-exists)
7. [Grafana dashboards — import & common “no data” causes](#7-grafana-dashboards--import--common-no-data-causes)
8. [Troubleshooting matrix](#8-troubleshooting-matrix)
9. [Useful commands (copy-paste)](#9-useful-commands-copy-paste)

---

## 1. Architecture at a glance

```
Internet → ALB (+ WAF Web ACL) → backend targets
                │
                ├─ WAF logs ──► Kinesis Firehose ──► S3 (waf-logs/year=…/)
                │                                      │
                │                                      ├─ Glue Crawler → Glue Catalog
                │                                      └─ Athena queries
                │
                └─ CloudWatch metrics (AWS/WAFV2) ──► CloudWatch Exporter ──► Prometheus ──► Grafana

Lambda (report generator) ──► Athena + S3 ──► HTML/CSV report ──► SNS email

EC2 monitoring server: Prometheus, Grafana, Alertmanager, exporters (user-data bootstrap)
EC2 agent nodes (×3): node_exporter on :9100
```

| Layer | Purpose |
|-------|---------|
| **WAF** | Block SQLi, XSS, bad inputs, rate limits |
| **Firehose** | Stream WAF logs to S3 (buffered, compressed) |
| **S3** | Durable log storage, partitioned by date |
| **Glue + Athena** | SQL analytics on logs |
| **Prometheus + Grafana** | Metrics & dashboards (WAF CW metrics, node CPU, ALB probe) |
| **SNS** | Email alerts and daily/weekly report notifications |
| **Lambda** | Scheduled report generation |

---

## 2. Terraform apply — what gets created

```bash
cd terraform/environments/dev
cp terraform.tfvars.example terraform.tfvars   # set alert_email
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

**Apply time:** ~10–15 minutes.

### AWS services created (heads-up)

| Service | Resource name (dev) | What it does |
|---------|---------------------|--------------|
| **VPC** | `waf-security-dev` VPC, public subnets | Network for ALB + EC2 |
| **ALB** | `waf-security-dev-alb` | Public HTTP entry point |
| **WAFv2** | `waf-security-dev-web-acl` | Regional Web ACL on ALB |
| **S3** | `waf-security-dev-waf-logs-<account_id>` | WAF log destination |
| **Kinesis Firehose** | `aws-waf-logs-waf-security-dev` | **Name must start with `aws-waf-logs-`** for WAF logging |
| **Glue** | DB `waf_security_dev_waf`, table `waf_logs`, crawler | Catalog for Athena |
| **Athena** | Workgroup `waf-security-dev-waf-analytics` | SQL on S3 logs |
| **Lambda** | `waf-security-dev-waf-report-generator` | Daily/weekly reports |
| **SNS** | `waf-security-dev-reports` | Email subscription |
| **CloudWatch** | Alarms, log groups for Firehose | Ops monitoring |
| **EC2** | 1× monitoring (`t3.medium`) + 3× agents | Prometheus/Grafana stack |
| **IAM** | Roles for Firehose, WAF logging, Glue, Lambda, EC2 | Least-privilege access |
| **KMS** | CMK for encryption | S3, SNS, etc. |

### Key outputs

```bash
terraform output -raw alb_dns_name
terraform output -raw s3_bucket_name
terraform output -raw firehose_stream_name    # aws-waf-logs-waf-security-dev
terraform output -raw grafana_url               # http://<eip>:3000
terraform output -raw prometheus_url
terraform output -raw athena_workgroup
```

---

## 3. Issue history & fixes (this deployment)

Chronological list of problems encountered and resolutions.

### 3.1 Terraform / config

| Issue | Symptom | Root cause | Fix |
|-------|---------|------------|-----|
| `terraform validate` fails | Syntax errors in `variables.tf` | Semicolons instead of HCL blocks | Multi-line variable blocks |
| Circular dependency | Plan fails on monitoring module | `user_data` referenced module outputs | Move `templatefile()` into monitoring module; discover agents via EC2 tags at boot |

### 3.2 WAF → Firehose logging

| Issue | Symptom | Root cause | Fix |
|-------|---------|------------|-----|
| `WAFInvalidParameterException: LOG_DESTINATION` | WAF logging enable fails | Firehose stream name must start with `aws-waf-logs-` | Renamed stream in `terraform/modules/firehose/main.tf` |
| Firehose receives records, S3 empty | `DeliveryToS3.Records = 0` | S3 bucket policy `DenyUnencryptedObjectUploads` blocked Firehose PutObject | Removed deny rule; default bucket KMS encryption remains |

**Files:** `terraform/modules/firehose/main.tf`, `terraform/modules/s3/main.tf`, `terraform/modules/waf/main.tf`

### 3.3 Monitoring EC2 / Grafana unreachable

| Issue | Symptom | Root cause | Fix |
|-------|---------|------------|-----|
| HTTP 000 on port 3000 | SG open but no response | `cloud-init` failed; Grafana never started | See user-data fixes below |
| `docker compose` not found | cloud-init fails ~130s | Amazon Linux 2023 has `docker` only, not Compose plugin | Install Compose binary to `/usr/local/lib/docker/cli-plugins/` |
| cloud-init fails ~27s | Immediate script failure | `dnf install curl` conflicts with preinstalled `curl-minimal` | Removed `curl` from `dnf install` line |
| cloud-init fails ~27s (attempt 2) | `exec > >(tee …)` | Process substitution fails under cloud-init | Use simple `exec > /var/log/waf-monitoring-setup.log 2>&1` |
| Terraform “no changes” but instance broken | Old instance still running | `user_data` only runs at **first boot**; in-place update does not re-run | `terraform taint module.monitoring.aws_instance.monitoring_server` then `apply` |

**Log on instance:** `/var/log/waf-monitoring-setup.log`  
**Console:** EC2 → Instance → Actions → Monitor and troubleshoot → Get system log

### 3.4 Grafana dashboards empty

| Issue | Symptom | Root cause | Fix |
|-------|---------|------------|-----|
| All panels “No data” | Explore also empty for panel queries | Dashboards use datasource UID `prometheus`; Grafana provisioned random UID | Set `uid: prometheus` in `grafana/provisioning/datasources/datasources.yml` |
| Security/Threat/Executive empty | `rate()` / `increase()` return nothing | CloudWatch exporter exposes **gauges**, not Prometheus counters | Dashboard JSON updated: use `aws_wafv2_blocked_requests_sum{rule="ALL"}` not `rate(...)` |
| XSS panel empty | No `BadInputs` rule series | XSS blocks appear under `AWSManagedRulesCommonRuleSet` | Query `rule=~".*CommonRuleSet.*"` |
| Bot panel empty | Always zero | `enable_bot_control = false` in tfvars | Expected; enable bot control or ignore panel |
| Rate limit panel empty | Always zero | Rate limit is 2000 req/5min; test traffic too low | Run more requests or lower `waf_rate_limit` |
| Infrastructure CPU — only 1 host | 3 agent targets DOWN | Agent `node_exporter` not listening on :9100; wrong scrape port `:80` | Fixed `user_data_agent.sh`; prometheus targets `IP:9100` |
| CloudWatch exporter — no WAF metrics | `aws_wafv2_*` missing | Docker cannot reach IMDS (hop limit 1) | `http_put_response_hop_limit = 2` + cloudwatch-exporter `network_mode: host` |
| Agent metrics missing after agent replace | Old IPs in prometheus.yml | Agent IPs baked at monitoring boot | Re-taint monitoring server or reload prometheus config |

**Re-import dashboards** after JSON fixes: Grafana → Dashboards → Import → upload files from `dashboards/grafana/`.

---

## 4. WAF logs → Firehose → S3 → Athena (end-to-end)

### 4.1 Data flow

```
WAF Web ACL (regional)
    │  logging configuration → Firehose delivery stream ARN
    ▼
Kinesis Data Firehose (aws-waf-logs-waf-security-dev)
    │  buffer (e.g. 5 MB / 300s) → gzip → S3 PutObject
    ▼
S3: s3://waf-security-dev-waf-logs-<account>/waf-logs/year=YYYY/month=MM/day=DD/*.gz
    │  JSON lines (one WAF log record per line)
    ▼
Glue Crawler (or partition projection on table)
    ▼
Athena: SELECT … FROM waf_security_dev_waf.waf_logs
```

### 4.2 Step-by-step verification

#### Step A — WAF logging enabled

```bash
cd terraform/environments/dev
bash ../../../scripts/deployment/verify_waf_logging.sh
```

Or manually:

```bash
aws wafv2 get-logging-configuration \
  --resource-arn "$(terraform output -raw waf_web_acl_arn)" \
  --region us-west-2
```

Expect destination containing `deliverystream/aws-waf-logs-waf-security-dev`.

#### Step B — Generate traffic

```bash
bash scripts/attack_simulation/run_traffic.sh
# Expect: SQLi/XSS → HTTP 403
```

#### Step C — Firehose healthy

```bash
aws firehose describe-delivery-stream \
  --delivery-stream-name "$(terraform output -raw firehose_stream_name)" \
  --region us-west-2 \
  --query 'DeliveryStreamDescription.DeliveryStreamStatus'
# ACTIVE

# CloudWatch metrics (AWS Console or CLI)
aws cloudwatch get-metric-statistics \
  --namespace AWS/Firehose \
  --metric-name DeliveryToS3.Success \
  --dimensions Name=DeliveryStreamName,Value=aws-waf-logs-waf-security-dev \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 300 --statistics Average --region us-west-2
```

#### Step D — S3 objects (wait 5–10 min after traffic)

```bash
BUCKET=$(terraform output -raw s3_bucket_name)
aws s3 ls "s3://${BUCKET}/waf-logs/" --recursive | head
```

Inspect one file:

```bash
KEY=$(aws s3 ls "s3://${BUCKET}/waf-logs/" --recursive | head -1 | awk '{print $4}')
aws s3 cp "s3://${BUCKET}/${KEY}" - | gunzip | head -1 | jq .
```

#### Step E — Glue crawler

```bash
aws glue start-crawler --name waf-security-dev-waf-logs-crawler --region us-west-2

aws glue get-crawler --name waf-security-dev-waf-logs-crawler --region us-west-2 \
  --query 'Crawler.{State:State,LastCrawl:LastCrawl.Status}'
# State: READY, LastCrawl: SUCCEEDED
```

#### Step F — Athena query

```bash
BUCKET=$(terraform output -raw s3_bucket_name)

aws athena start-query-execution \
  --region us-west-2 \
  --query-string "SELECT action, COUNT(*) AS cnt FROM waf_security_dev_waf.waf_logs WHERE year='2026' AND month='06' AND day='24' GROUP BY action" \
  --work-group waf-security-dev-waf-analytics \
  --query-execution-context Database=waf_security_dev_waf \
  --result-configuration "OutputLocation=s3://${BUCKET}/athena-results/"
```

Or use SQL files: `athena/queries/blocked_requests.sql`, `athena/queries/top_attackers.sql`.

**Always filter partitions:** `year`, `month`, `day`.

### 4.3 Where to look when logs pipeline fails

| Symptom | Check | Likely fix |
|---------|-------|------------|
| No logging config | `aws wafv2 get-logging-configuration` | `terraform apply` WAF module |
| Invalid LOG_DESTINATION | Stream name | Must start with `aws-waf-logs-` |
| Firehose errors | CloudWatch log group `/aws/kinesisfirehose/...` | IAM, S3 permissions, KMS |
| Records in Firehose, not S3 | Firehose `DeliveryToS3` metrics | S3 bucket policy / KMS header |
| S3 has files, Athena 0 rows | Glue crawler / partitions | Run crawler; use partition filters |
| Athena query fails | Workgroup, output location | Check `s3://.../athena-results/` exists |

---

## 5. Observability stack — how it is installed

Nothing is installed via Grafana/Prometheus packages on the host OS. **Everything runs in Docker** on the monitoring EC2, bootstrapped by **user-data**.

### 5.1 Components on monitoring EC2

| Component | How installed | Port | Role |
|-----------|-----------------|------|------|
| **Docker + Compose** | `dnf install docker`; Compose binary from GitHub releases | — | Run observability containers |
| **node_exporter** | systemd on host (`/usr/local/bin/node_exporter`) | 9100 | Host metrics (CPU, memory, disk) |
| **Prometheus** | `prom/prometheus` container | 9090 | Scrape & store metrics |
| **Grafana** | `grafana/grafana` container | 3000 | Dashboards (default `admin` / `ChangeMe123!`) |
| **Alertmanager** | `prom/alertmanager` container | 9093 | Alert routing |
| **CloudWatch exporter** | `prom/cloudwatch-exporter` (host network) | 9106 | Pull `AWS/WAFV2`, `AWS/Firehose` → Prometheus format |
| **Blackbox exporter** | `prom/blackbox-exporter` container | 9115 | HTTP probe of ALB |

### 5.2 Agent EC2 nodes (×3)

| Component | How installed | Port |
|-----------|----------------|------|
| **node_exporter** | `user_data_agent.sh` via cloud-init | 9100 |

Prometheus on the monitoring server discovers agent private IPs via **EC2 API** at boot (`tag:Role=node-exporter`).

### 5.3 SNS & Lambda (not on EC2)

| Component | Provisioned by | Purpose |
|-----------|----------------|---------|
| **SNS topic** | Terraform `module.sns` | Report emails to `alert_email` in tfvars |
| **Lambda** | Terraform `module.lambda` | Runs Athena queries, builds HTML/CSV, publishes to SNS |
| **EventBridge** | Terraform | Schedules daily/weekly/monthly reports |

SNS is **not** installed on the monitoring server; it is a managed AWS service subscribed to your email.

---

## 6. Why `user_data_monitoring.sh` exists

**Location:** `scripts/deployment/user_data_monitoring.sh`  
**Used by:** `terraform/modules/monitoring/main.tf` → `templatefile(...)` on monitoring EC2

### Why not bake an AMI or use Ansible?

- **Sandbox-friendly:** Single `terraform apply` brings up the full stack.
- **No manual steps:** EC2 boots → cloud-init runs script → Docker stack is live.
- **Environment injection:** Terraform passes `project_name`, `alb_dns_name`, `aws_region`, `account_id` into the script.

### What the script does (order)

1. Install Docker, git, jq, awscli, tar (not `curl` — conflicts on AL2023).
2. Install Docker Compose CLI plugin (binary).
3. Install **node_exporter** on the host (systemd).
4. Wait 90s for agent instances to register in EC2.
5. Query agent private IPs via AWS CLI.
6. Write `/opt/observability/prometheus/prometheus.yml` (scrape targets).
7. Write CloudWatch exporter config (WAF + Firehose metrics).
8. Write Grafana datasource provisioning (`uid: prometheus`).
9. Write `docker-compose.yml` and run `docker compose up -d`.
10. Health-check Grafana on `localhost:3000`.

### Important logs

| Log | Path |
|-----|------|
| Bootstrap log | `/var/log/waf-monitoring-setup.log` |
| cloud-init | `/var/log/cloud-init-output.log` |
| Docker | `docker compose -f /opt/observability/docker-compose.yml logs` |

### When you must replace the instance

`user_data` runs **only on first launch**. Changing the script requires:

```bash
terraform taint module.monitoring.aws_instance.monitoring_server
terraform apply -target=module.monitoring
```

---

## 7. Grafana dashboards — import & common “no data” causes

### Import (one-time per environment)

1. Open `http://<monitoring-ip>:3000` → login `admin` / `ChangeMe123!`
2. **Dashboards** → **New** → **Import**
3. Upload each file from `dashboards/grafana/`:
   - `security-overview.json`
   - `threat-intelligence.json`
   - `executive-dashboard.json`
   - `infrastructure-monitoring.json`
4. Select **Prometheus** as datasource when prompted.
5. Time range: **Last 6 hours** (Prometheus may not have 7 days of history yet).

### Metrics vs logs

| Source | Used for | Tool |
|--------|----------|------|
| CloudWatch `AWS/WAFV2` | Grafana WAF panels | Prometheus + CloudWatch exporter |
| S3 WAF JSON logs | SQLi details, top IPs, forensics | Athena |
| node_exporter | CPU, memory, disk | Grafana Infrastructure dashboard |

### PromQL tips (CloudWatch exporter)

- **Do use:** `aws_wafv2_blocked_requests_sum{rule="ALL"}`
- **Do not use:** `rate(aws_wafv2_blocked_requests_sum[5m])` — returns empty (gauge, not counter).
- **SQLi:** `rule=~".*SQLi.*"`
- **XSS / common rules:** `rule=~".*CommonRuleSet.*"`
- **IP reputation:** `rule=~".*IpReputation.*"`

### Verify in Explore before blaming dashboards

```promql
aws_wafv2_blocked_requests_sum{rule="ALL"}
node_cpu_seconds_total
probe_success{job="blackbox-alb"}
```

---

## 8. Troubleshooting matrix

### Grafana

| Symptom | Where to check | How to fix |
|---------|----------------|------------|
| Site won’t load | EC2 state, SG port 3000, `curl :3000/login` | Wait for user-data; check `/var/log/waf-monitoring-setup.log` |
| Login works, all panels empty | Grafana → Connections → Data sources → UID | Re-import dashboards; ensure datasource `uid: prometheus` |
| Some panels empty | Explore → run panel query | See PromQL tips; generate traffic; check rule names |
| Bot / rate limit empty | tfvars `enable_bot_control`, `waf_rate_limit` | Expected with current config |

### Prometheus

| Symptom | Where to check | How to fix |
|---------|----------------|------------|
| No WAF metrics | `http://<ip>:9090/targets` → cloudwatch-exporter | IMDS hop limit 2; host network for exporter |
| Agents DOWN | Targets → `node-exporter-agents` | Fix agent user-data; ensure `:9100` in prometheus.yml |
| Stale agent IPs | prometheus.yml on server | Re-taint monitoring EC2 or reload config |

### WAF logging pipeline

| Symptom | Where to check | How to fix |
|---------|----------------|------------|
| No S3 files | Firehose CW metrics, S3 policy | See §3.2 and §4.3 |
| Athena empty | Crawler state, partition filters | Run crawler; filter `year/month/day` |

### EC2 user-data

| Symptom | Where to check | How to fix |
|---------|----------------|------------|
| cloud-init failed | EC2 system log | Fix script; **taint** instance; re-apply |
| Docker not running | `docker compose ps` on instance | Re-run compose or replace instance |

---

## 9. Useful commands (copy-paste)

```bash
export AWS_REGION=us-west-2
cd terraform/environments/dev

# --- Deploy ---
terraform apply

# --- Outputs ---
terraform output grafana_url
terraform output -raw s3_bucket_name

# --- WAF logging ---
bash ../../../scripts/deployment/verify_waf_logging.sh

# --- Traffic ---
bash ../../../scripts/attack_simulation/run_traffic.sh

# --- S3 logs ---
aws s3 ls "s3://$(terraform output -raw s3_bucket_name)/waf-logs/" --recursive | head

# --- Glue ---
aws glue start-crawler --name waf-security-dev-waf-logs-crawler --region us-west-2

# --- Prometheus (from laptop) ---
curl -s 'http://54.245.38.193:9090/api/v1/query?query=aws_wafv2_blocked_requests_sum' | jq '.data.result | length'
curl -s 'http://54.245.38.193:9090/api/v1/targets' | jq '.data.activeTargets[] | {job: .labels.job, health: .health}'

# --- Replace monitoring (after user_data change) ---
terraform taint module.monitoring.aws_instance.monitoring_server
terraform apply -target=module.monitoring

# --- Lambda report test ---
aws lambda invoke --region us-west-2 \
  --function-name "$(terraform output -raw lambda_function_name)" \
  --cli-binary-format raw-in-base64-out \
  --payload '{"report_type":"daily"}' /tmp/report.json && cat /tmp/report.json
```

---

## Related files in this repo

| Path | Purpose |
|------|---------|
| `DEPLOY.md` | Official deployment steps |
| `scripts/deployment/user_data_monitoring.sh` | Monitoring EC2 bootstrap |
| `scripts/deployment/user_data_agent.sh` | Agent node_exporter bootstrap |
| `scripts/deployment/verify_waf_logging.sh` | WAF → Firehose wiring check |
| `scripts/deployment/fix_grafana_metrics.sh` | On-instance Grafana/Prometheus fix helper |
| `dashboards/grafana/*.json` | Import into Grafana UI |
| `athena/queries/*.sql` | Sample Athena analytics |
| `docs/guides/terraform-debugging-guide.md` | Additional Terraform notes |

---

## Quick “start here” when something breaks

1. **Grafana down?** → EC2 system log + `/var/log/waf-monitoring-setup.log`
2. **Dashboards empty?** → Prometheus Explore → datasource UID → re-import JSON
3. **No WAF metrics in Grafana?** → Prometheus targets → CloudWatch exporter
4. **No WAF logs in S3?** → `verify_waf_logging.sh` → Firehose → S3 policy
5. **Athena empty?** → S3 files exist? → Glue crawler → partition filters

For full deploy from scratch, start with [DEPLOY.md](../DEPLOY.md).
