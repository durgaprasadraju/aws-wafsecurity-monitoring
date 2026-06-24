# AWS Console UI & Manual Operations Guide

Step-by-step reference for everything Terraform automates in this platform: how each module is created, how to verify it in the **AWS Console**, and how to reproduce **Node Exporter**, **Prometheus**, **Grafana**, **Alertmanager**, and **dashboard JSON** configuration manually if needed.

> **Defaults used below** (dev environment):
> - Region: `us-west-2`
> - Project: `waf-security`
> - Environment: `dev`
> - Replace `ACCOUNT_ID` with your 12-digit AWS account ID.

---

## Table of Contents

1. [Terraform deployment order](#1-terraform-deployment-order)
2. [Module 1 — KMS](#2-module-1--kms)
3. [Module 2 — VPC](#3-module-2--vpc)
4. [Module 3 — S3](#4-module-3--s3)
5. [Module 4 — SNS](#5-module-4--sns)
6. [Module 5 — IAM](#6-module-5--iam)
7. [Module 6 — Kinesis Firehose](#7-module-6--kinesis-firehose)
8. [Module 7 — Application Load Balancer](#8-module-7--application-load-balancer)
9. [Module 8 — AWS WAF](#9-module-8--aws-waf)
10. [Module 9 — AWS Glue](#10-module-9--aws-glue)
11. [Module 10 — Amazon Athena](#11-module-10--amazon-athena)
12. [Module 11 — Lambda Report Generator](#12-module-11--lambda-report-generator)
13. [Module 12 — CloudWatch](#13-module-12--cloudwatch)
14. [Module 13 — Monitoring EC2 (Prometheus/Grafana)](#14-module-13--monitoring-ec2-prometheusgrafana)
15. [Node Exporter on agent nodes](#15-node-exporter-on-agent-nodes)
16. [Prometheus configuration (manual)](#16-prometheus-configuration-manual)
17. [Grafana configuration (manual)](#17-grafana-configuration-manual)
18. [Alertmanager configuration (manual)](#18-alertmanager-configuration-manual)
19. [Grafana dashboard JSON import](#19-grafana-dashboard-json-import)
20. [CloudWatch dashboard JSON](#20-cloudwatch-dashboard-json)
21. [CI/CD pipeline overview](#21-cicd-pipeline-overview)
22. [Quick verification checklist](#22-quick-verification-checklist)

---

## 1. Terraform deployment order

Terraform in `terraform/environments/dev/main.tf` creates modules in dependency order. A single `terraform apply` provisions all of them; this section explains **what happens one module at a time**.

| Order | Module | Depends on | Primary resources |
|-------|--------|------------|-------------------|
| 1 | `kms` | — | Customer-managed KMS key + alias |
| 2 | `vpc` | — | VPC, subnets, IGW, route tables, security groups |
| 3 | `s3` | kms | WAF logs bucket (+ optional access-logs bucket) |
| 4 | `sns` | kms | Security alerts + reports topics, email subscriptions |
| 5 | `iam` | s3, kms, sns | Roles for Firehose, WAF logging, Lambda, Glue, EC2 |
| 6 | `firehose` | s3, iam, kms | Kinesis Data Firehose delivery stream |
| 7 | `alb` | vpc | Application Load Balancer, target group, listener |
| 8 | `waf` | alb, firehose, iam | Regional Web ACL, ALB association, logging |
| 9 | `glue` | s3, iam | Glue database, table schema, crawler |
| 10 | `athena` | glue, s3, kms | Workgroup + 11 named queries |
| 11 | `lambda` | iam, athena, glue, s3, sns, kms | Report generator + EventBridge schedules |
| 12 | `cloudwatch` | waf, firehose, lambda, sns | Dashboard + metric alarms |
| 13 | `monitoring` | vpc, iam, alb | Monitoring EC2, 3 agent EC2s, Elastic IP |

### Deploy with Terraform (automated)

```bash
cd terraform/environments/dev
cp terraform.tfvars.example terraform.tfvars   # set alert_email, region, etc.
terraform init
terraform plan
terraform apply
```

### Get key URLs and names after deploy

```bash
terraform output alb_dns_name
terraform output grafana_url
terraform output prometheus_url
terraform output s3_bucket_name
terraform output -json | jq
```

---

## 2. Module 1 — KMS

**Terraform creates:** `aws_kms_key`, `aws_kms_alias`, `aws_kms_key_policy`

| Resource | Name |
|----------|------|
| KMS key alias | `alias/waf-security-dev` |
| Description | Encryption for S3, SNS, Firehose logs, Athena results |

### Verify in AWS Console

1. Open **AWS Console** → switch region to **US West (Oregon) / us-west-2**
2. Go to **Key Management Service (KMS)** → **Customer managed keys**
3. Click key with alias **`waf-security-dev`**
4. **Key policy** tab: confirm statements for root, CloudWatch Logs, S3, Firehose
5. **General configuration**: Key rotation = Enabled (if `enable_key_rotation = true`)

### Manual equivalent (Console UI)

1. KMS → **Create key** → Symmetric → Next
2. Alias: `waf-security-dev`
3. Key administrators: your IAM user/role
4. Key users: add services (S3, Firehose, SNS) via policy JSON matching `terraform/modules/kms/main.tf`
5. Create key

---

## 3. Module 2 — VPC

**Terraform creates:** VPC, 2 public + 2 private subnets, Internet Gateway, route table, 3 security groups (ALB, monitoring, app)

| Resource | Name / CIDR |
|----------|-------------|
| VPC | `waf-security-dev-vpc` — `10.0.0.0/16` |
| Public subnets | `10.0.0.0/20`, `10.0.16.0/20` (example; auto-calculated) |
| ALB security group | `waf-security-dev-alb-sg` — inbound 80/443 from `0.0.0.0/0` |
| Monitoring security group | `waf-security-dev-monitoring-sg` — 3000, 9090 public; 9100, 9106, 9115, 9093 VPC |
| App security group | `waf-security-dev-app-sg` — port 80 from ALB SG |

### Verify in AWS Console

1. **VPC** → **Your VPCs** → select `waf-security-dev-vpc`
2. **Subnets** → filter by VPC → confirm 4 subnets (2 public, 2 private) across 2 AZs
3. **Internet gateways** → `waf-security-dev-igw` → attached to VPC
4. **Route tables** → public RT has `0.0.0.0/0` → IGW
5. **Security groups** → verify the three groups and inbound rules above

### Manual equivalent (Console UI)

1. VPC → **Create VPC** → name `waf-security-dev-vpc`, CIDR `10.0.0.0/16`
2. Create **Internet Gateway** → attach to VPC
3. Create 2 **public subnets** (auto-assign public IP) + 2 **private subnets**
4. Public route table: add route `0.0.0.0/0` → IGW; associate public subnets
5. Create security groups per `terraform/modules/vpc/main.tf` rules

---

## 4. Module 3 — S3

**Terraform creates:** WAF logs bucket with versioning, SSE-KMS, lifecycle, public access block, bucket policy

| Resource | Name |
|----------|------|
| WAF logs bucket | `waf-security-dev-waf-logs-ACCOUNT_ID` |
| Prefix | `waf-logs/year=YYYY/month=MM/day=DD/` |
| Access logs bucket (optional) | `waf-security-dev-access-logs-ACCOUNT_ID` |

### Verify in AWS Console

1. **S3** → **Buckets** → `waf-security-dev-waf-logs-ACCOUNT_ID`
2. **Objects**: after traffic + WAF blocks, navigate `waf-logs/year=.../month=.../day=.../` → `.gz` files
3. **Properties** → **Default encryption**: SSE-KMS, key `waf-security-dev`
4. **Properties** → **Bucket Versioning**: Enabled
5. **Permissions** → **Block public access**: all four blocks ON
6. **Management** → **Lifecycle rules**: transition to IA/Glacier, expiration per config

### Manual equivalent (Console UI)

1. S3 → **Create bucket** → name `waf-security-dev-waf-logs-ACCOUNT_ID`, region `us-west-2`
2. Block all public access → Enable
3. Default encryption → SSE-KMS → select `alias/waf-security-dev`
4. Enable versioning
5. Create lifecycle rule on prefix `waf-logs/` (IA at 30d, Glacier at 90d, expire at 365d — see module variables)
6. Bucket policy: deny insecure transport (HTTP)

---

## 5. Module 4 — SNS

**Terraform creates:** Two KMS-encrypted topics + email subscriptions (if `alert_email` is set)

| Topic | Purpose |
|-------|---------|
| `waf-security-dev-security-alerts` | CloudWatch alarm notifications |
| `waf-security-dev-reports` | Lambda HTML/CSV report delivery |

### Verify in AWS Console

1. **SNS** → **Topics** → open each topic above
2. **Subscriptions** tab → email endpoint → status must be **Confirmed** (check inbox for AWS confirmation link)
3. **Encryption** → AWS KMS → `alias/waf-security-dev`

### Manual equivalent (Console UI)

1. SNS → **Create topic** → Standard → name `waf-security-dev-security-alerts`
2. Enable encryption → KMS key `waf-security-dev`
3. **Create subscription** → Protocol: Email → enter `alert_email`
4. Repeat for `waf-security-dev-reports`
5. Confirm both subscription emails

---

## 6. Module 5 — IAM

**Terraform creates:** IAM roles + policies + EC2 instance profile (no Console "wizard" — all via API)

| Role | Used by |
|------|---------|
| `waf-security-dev-firehose-role` | Kinesis Firehose → S3 |
| `waf-security-dev-waf-logging-role` | WAF → Firehose |
| `waf-security-dev-lambda-report-role` | Report Lambda (Athena, S3, SNS) |
| `waf-security-dev-glue-crawler-role` | Glue crawler |
| `waf-security-dev-ec2-monitoring-role` | Monitoring + agent EC2 (CloudWatch, EC2 describe) |
| Instance profile | `waf-security-dev-ec2-monitoring-profile` |

### Verify in AWS Console

1. **IAM** → **Roles** → search `waf-security-dev`
2. Open each role → **Trust relationships** (correct service principal)
3. **Permissions** → inline/custom policies match least-privilege needs
4. **IAM** → **Instance profiles** → `waf-security-dev-ec2-monitoring-profile`

### Manual equivalent (Console UI)

For each role above:
1. IAM → **Create role** → Trusted entity: AWS service (Firehose / WAF / Lambda / Glue / EC2)
2. Attach policies per `terraform/modules/iam/main.tf`
3. For EC2: create instance profile and attach `ec2-monitoring-role`

---

## 7. Module 6 — Kinesis Firehose

**Terraform creates:** Delivery stream (name **must** start with `aws-waf-logs-`), CloudWatch log group for delivery errors

| Resource | Name |
|----------|------|
| Delivery stream | `aws-waf-logs-waf-security-dev` |
| Destination | S3 extended with GZIP, 5 MB / 300s buffering |
| Log group | `/aws/kinesisfirehose/aws-waf-logs-waf-security-dev` |

### Verify in AWS Console

1. **Amazon Data Firehose** → **Delivery streams** → `aws-waf-logs-waf-security-dev`
2. **Configuration** tab:
   - Source: Direct PUT
   - Destination: Amazon S3
   - S3 bucket: `waf-security-dev-waf-logs-ACCOUNT_ID`
   - Prefix: `waf-logs/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/`
   - Compression: GZIP
3. **Monitoring** tab: `DeliveryToS3.Success` should be ~1.0 after WAF logging is active
4. **CloudWatch** → **Log groups** → `/aws/kinesisfirehose/...` → check for delivery errors

### Manual equivalent (Console UI)

1. Firehose → **Create Firehose stream**
2. Name: `aws-waf-logs-waf-security-dev` (required prefix for WAF)
3. Source: Direct PUT
4. Destination: Amazon S3 → select WAF logs bucket
5. S3 prefix: `waf-logs/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/`
6. IAM role: `waf-security-dev-firehose-role`
7. Enable CloudWatch error logging
8. Create stream

---

## 8. Module 7 — Application Load Balancer

**Terraform creates:** Internet-facing ALB, HTTP listener (fixed 200 response), target group, ALB access logs bucket

| Resource | Name |
|----------|------|
| ALB | `waf-security-dev-alb` |
| Target group | `waf-security-dev-tg` |
| ALB logs bucket | `waf-security-dev-alb-logs-ACCOUNT_ID` |

### Verify in AWS Console

1. **EC2** → **Load Balancers** → `waf-security-dev-alb`
2. **Listeners** tab: HTTP:80 → fixed response "WAF Security Platform"
3. **Integrations** tab (or WAF): Web ACL association appears after WAF module
4. **Monitoring** tab: request count metrics
5. Copy **DNS name** — used for attack simulation and blackbox probes
6. **S3** → `waf-security-dev-alb-logs-ACCOUNT_ID` → `alb-access-logs/` prefix

### Manual equivalent (Console UI)

1. EC2 → **Load Balancers** → **Create** → Application Load Balancer
2. Internet-facing, select public subnets + `waf-security-dev-alb-sg`
3. Create target group (HTTP:80, health check `/`)
4. Listener: default action **Fixed response** 200 HTML
5. Enable access logs to ALB logs bucket

---

## 9. Module 8 — AWS WAF

**Terraform creates:** Regional Web ACL, rules, ALB association, logging to Firehose

| Resource | Name |
|----------|------|
| Web ACL | `waf-security-dev-web-acl` |
| Scope | Regional (same region as ALB: `us-west-2`) |

**Rules (priorities):**

| Priority | Rule | Action |
|----------|------|--------|
| 1 | AWSManagedRulesCommonRuleSet | Managed |
| 2 | AWSManagedRulesSQLiRuleSet | Managed |
| 3 | AWSManagedRulesKnownBadInputsRuleSet | Managed |
| 4 | AWSManagedRulesAmazonIpReputationList | Managed |
| 5 | AWSManagedRulesBotControlRuleSet | Managed (only if `enable_bot_control = true`) |
| 10 | RateLimitRule | Block (2000 req / 5 min per IP default) |

**Logging:** Firehose stream ARN; filter KEEP for BLOCK and COUNT; redact `authorization` and `cookie` headers.

### Verify in AWS Console

1. **WAF & Shield** → **Web ACLs** → region **us-west-2** (not CloudFront/global)
2. Select `waf-security-dev-web-acl`
3. **Rules** tab: verify 5–6 rules listed
4. **Associated AWS resources** tab: ALB `waf-security-dev-alb` attached
5. **Logging and metrics** tab:
   - Logging enabled → destination = Firehose `aws-waf-logs-waf-security-dev`
   - CloudWatch metrics enabled
6. **Sampled requests** tab: after running attack scripts, filter Action = Block

### Manual equivalent (Console UI)

1. WAF → **Create web ACL** → Regional → name `waf-security-dev-web-acl`
2. Default action: Allow
3. **Add rules** → Rule type: Managed rule groups → add each AWS managed group above
4. Add custom rule: Rate-based → limit 2000 per 5 min → Block
5. **Associate AWS resources** → select ALB
6. **Logging** → Enable → Kinesis Firehose → select `aws-waf-logs-waf-security-dev`
7. Logging filter: keep BLOCK and COUNT actions; redact sensitive headers

### Generate test traffic (to populate logs/metrics)

```bash
ALB_URL=$(cd terraform/environments/dev && terraform output -raw alb_dns_name)
python scripts/attack_simulation/simulate_sqli.py --url "http://$ALB_URL" --count 20
bash scripts/attack_simulation/run_traffic.sh
```

---

## 10. Module 9 — AWS Glue

**Terraform creates:** Glue catalog database, external table with partition projection, scheduled crawler

| Resource | Name |
|----------|------|
| Database | `waf_security_dev_waf` |
| Table | `waf_logs` |
| Crawler | `waf-security-dev-waf-logs-crawler` |
| Schedule | `cron(0 */4 * * ? *)` (every 4 hours) |

### Verify in AWS Console

1. **AWS Glue** → **Data Catalog** → **Databases** → `waf_security_dev_waf`
2. **Tables** → `waf_logs` → **Schema**: columns include `timestamp`, `action`, `httprequest`, etc.
3. **Partition indexes / Partitions**: year/month/day partitions (crawler or projection)
4. **ETL** → **Crawlers** → `waf-security-dev-waf-logs-crawler`
   - S3 target: `s3://waf-security-dev-waf-logs-ACCOUNT_ID/waf-logs/`
   - IAM role: `waf-security-dev-glue-crawler-role`
   - Run crawler manually if partitions are stale

### Manual equivalent (Console UI)

1. Glue → **Databases** → Add `waf_security_dev_waf`
2. **Tables** → Add table `waf_logs` with JSON SerDe, S3 location `waf-logs/`, partition keys year/month/day
3. **Crawlers** → Create crawler → S3 path above → schedule every 4 hours

---

## 11. Module 10 — Amazon Athena

**Terraform creates:** Workgroup with KMS-encrypted results + 11 saved named queries

| Resource | Name |
|----------|------|
| Workgroup | `waf-security-dev-waf-analytics` |
| Results location | `s3://waf-security-dev-waf-logs-ACCOUNT_ID/athena-results/` |
| Engine | Athena engine version 3 |

**Named queries:** top-attackers, top-countries, blocked-requests, sqli-analysis, xss-analysis, bot-analysis, top-uris, hourly/daily/weekly/monthly-trends

### Verify in AWS Console

1. **Athena** → **Workgroups** → `waf-security-dev-waf-analytics`
2. **Query editor** → Workgroup: `waf-security-dev-waf-analytics`, Database: `waf_security_dev_waf`
3. Run:
   ```sql
   SELECT action, COUNT(*) AS cnt
   FROM waf_logs
   WHERE year = '2026' AND month = '06'
   GROUP BY action;
   ```
4. **Saved queries** tab: verify named queries prefixed `waf-security-dev-`

### Manual equivalent (Console UI)

1. Athena → **Workgroups** → Create → name `waf-security-dev-waf-analytics`
2. Query result location: `s3://.../athena-results/`, encryption SSE-KMS
3. Save each SQL from `terraform/modules/athena/main.tf` as named queries

---

## 12. Module 11 — Lambda Report Generator

**Terraform creates:** Python 3.12 Lambda, CloudWatch log group, 3 EventBridge rules (daily/weekly/monthly), error alarm

| Resource | Name |
|----------|------|
| Function | `waf-security-dev-waf-report-generator` |
| Schedules | daily 06:00 UTC, weekly Mon 07:00, monthly 1st 08:00 (defaults) |

**Environment variables:** `ATHENA_WORKGROUP`, `ATHENA_DATABASE`, `S3_BUCKET`, `SNS_TOPIC_ARN`, `ENVIRONMENT`, `PROJECT_NAME`

### Verify in AWS Console

1. **Lambda** → `waf-security-dev-waf-report-generator`
2. **Configuration** → **Environment variables**: verify Athena/S3/SNS values
3. **Configuration** → **Triggers**: 3 EventBridge rules
4. **Test** tab → event `{"report_type": "daily"}` → **Test** → check execution success
5. **Monitor** → CloudWatch metrics (Invocations, Errors, Duration)
6. **S3** bucket → `reports/` prefix for generated HTML/CSV
7. **SNS** `waf-security-dev-reports` → email with report link

### Manual equivalent (Console UI)

1. Package `lambda/report_generator/` as zip
2. Lambda → **Create function** → Python 3.12, role `waf-security-dev-lambda-report-role`
3. Set environment variables and timeout 300s, memory 512 MB
4. **EventBridge** → create 3 rules with cron expressions → target Lambda with JSON input `{"report_type":"daily"}` etc.
5. Add Lambda resource policy allowing `events.amazonaws.com` to invoke

---

## 13. Module 12 — CloudWatch

**Terraform creates:** WAF security dashboard + 3 metric alarms → SNS security-alerts topic

| Resource | Name |
|----------|------|
| Dashboard | `waf-security-dev-waf-security` |
| Alarms | `high-block-rate`, `sqli-surge`, `firehose-failures` |

### Verify in AWS Console

1. **CloudWatch** → **Dashboards** → `waf-security-dev-waf-security`
2. Widgets: Blocked/Allowed requests, SQLi blocks, Firehose delivery, Lambda errors
3. **Alarms** → **All alarms** → filter `waf-security-dev`
4. Alarm actions → SNS topic `waf-security-dev-security-alerts`

### Manual equivalent (Console UI)

1. CloudWatch → **Dashboards** → Create → import JSON from `dashboards/cloudwatch/waf-security-dashboard.json` (or build widgets manually)
2. **Alarms** → Create for `AWS/WAFV2` `BlockedRequests`, threshold 1000 / 5 min → action SNS security-alerts

---

## 14. Module 13 — Monitoring EC2 (Prometheus/Grafana)

**Terraform creates:**

| Resource | Details |
|----------|---------|
| Monitoring EC2 | `waf-security-dev-monitoring-01`, `t3.medium`, public subnet, Elastic IP |
| Agent EC2 × 3 | `waf-security-dev-agent-02` … `04`, `t3.micro`, tag `Role=node-exporter` |
| Bootstrap | `user_data_monitoring.sh` (Docker stack) + `user_data_agent.sh` (node_exporter) |

**Automated on first boot (monitoring server):**

- Docker + Docker Compose
- Node Exporter (systemd, port 9100)
- Prometheus v2.51.0 (port 9090)
- Grafana 10.4.0 (port 3000, admin password `ChangeMe123!`)
- Alertmanager v0.27.0 (port 9093)
- CloudWatch Exporter (host network, port 9106)
- Blackbox Exporter (port 9115)
- Auto-generated `prometheus.yml` with agent private IPs discovered via EC2 API

### Verify in AWS Console

1. **EC2** → **Instances** → 4 instances (1 monitoring + 3 agents)
2. Monitoring instance → **Public IPv4 address** → open `http://<IP>:3000` (Grafana), `http://<IP>:9090` (Prometheus)
3. **Security groups** → `waf-security-dev-monitoring-sg` → inbound 3000, 9090 from your IP (sandbox: `0.0.0.0/0`)
4. **Elastic IPs** → associated with monitoring instance
5. **Systems Manager** (optional): instance has `AmazonSSMManagedInstanceCore` for Session Manager SSH-less access

### Check bootstrap logs on the instance

```bash
# Via SSM Session Manager or SSH
sudo tail -100 /var/log/waf-monitoring-setup.log
sudo tail -100 /var/log/cloud-init-output.log
cd /opt/observability && docker compose ps
```

---

## 15. Node Exporter on agent nodes

**Automated by** `scripts/deployment/user_data_agent.sh` on each agent EC2 at first launch.

### What Terraform/user-data installs

| Setting | Value |
|---------|-------|
| Version | `1.7.0` |
| Binary path | `/usr/local/bin/node_exporter` |
| Listen address | `:9100` |
| Service | `node_exporter.service` (systemd, enabled, restart always) |
| Log file | `/var/log/waf-agent-setup.log` |

### Verify (from monitoring server or laptop via Prometheus)

1. Prometheus → `http://<MONITORING_IP>:9090/targets`
2. Job `node-exporter-agents` → all 3 agent IPs:9100 should be **UP**
3. Query: `node_cpu_seconds_total` or `up{job="node-exporter-agents"}`

### Manual setup on Amazon Linux 2023 (if not using Terraform user-data)

SSH or SSM into each agent instance:

```bash
sudo dnf install -y tar
NODE_EXPORTER_VERSION="1.7.0"
curl -fsSL "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz" | sudo tar xz
sudo mv "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter" /usr/local/bin/

sudo tee /etc/systemd/system/node_exporter.service <<'UNIT'
[Unit]
Description=Node Exporter
After=network.target
[Service]
ExecStart=/usr/local/bin/node_exporter --web.listen-address=:9100
Restart=always
[Install]
WantedBy=multi-user.target
UNIT

sudo systemctl daemon-reload
sudo systemctl enable --now node_exporter
curl -s localhost:9100/metrics | head
```

### Security group (Console UI)

1. EC2 → **Security Groups** → `waf-security-dev-monitoring-sg`
2. **Inbound rules** → Add rule: TCP 9100, source = VPC CIDR `10.0.0.0/16` (so Prometheus can scrape)

### Add agents to Prometheus manually

On monitoring server, edit `/opt/observability/prometheus/prometheus.yml`:

```yaml
  - job_name: node-exporter-agents
    static_configs:
      - targets:
          - 10.0.1.50:9100
          - 10.0.2.51:9100
          - 10.0.1.52:9100
```

Reload: `curl -X POST http://localhost:9090/-/reload` or `docker compose restart prometheus`

---

## 16. Prometheus configuration (manual)

**Automated path:** Generated at boot in `/opt/observability/prometheus/prometheus.yml`  
**Reference template in repo:** `observability/prometheus/prometheus.yml`

### Scrape jobs (automated stack)

| Job name | Target | Purpose |
|----------|--------|---------|
| `prometheus` | `prometheus:9090` | Self-monitoring |
| `node-exporter-agents` | `<agent-private-ip>:9100` (×3) | Agent CPU/memory/disk |
| `node-exporter-local` | `host.docker.internal:9100` | Monitoring server host metrics |
| `cloudwatch-exporter` | `host.docker.internal:9106` | AWS WAF/Firehose/Lambda metrics |
| `blackbox-alb` | ALB DNS via `blackbox-exporter:9115` | ALB HTTP probe |

### Alert rules

**Repo file:** `observability/prometheus/rules/waf-alerts.yml`  
**On server:** `/opt/observability/prometheus/rules/` (mount into container)

Key alerts: `HighBlockRate`, `SQLiSurge`, `XSSSurge`, `HighCPUUsage`, `FirehoseDeliveryFailures`, `PrometheusTargetDown`, `BlackboxProbeFailure`

### Manual Prometheus via Docker Compose (Console/SSH on EC2)

```bash
sudo mkdir -p /opt/observability/{prometheus/rules,grafana/provisioning/datasources,alertmanager,exporters}
cd /opt/observability
# Copy configs from repo observability/ and scripts/deployment/user_data_monitoring.sh
sudo docker compose up -d
```

### Verify in Prometheus UI

1. Open `http://<MONITORING_IP>:9090`
2. **Status** → **Targets**: all jobs UP
3. **Status** → **Configuration**: confirm scrape_configs
4. **Alerts**: rules loaded from `waf-alerts.yml`
5. **Graph** → query `aws_wafv2_blocked_requests_sum{rule="ALL"}`

> **Important:** CloudWatch exporter metrics are **gauges**. Use `aws_wafv2_blocked_requests_sum` directly — do **not** use `rate()` on them.

### CloudWatch exporter config (manual)

**Repo:** `observability/exporters/cloudwatch-exporter-config.yml`  
**On server:** `/opt/observability/exporters/cloudwatch-config.yml`

Metrics exported: WAF BlockedRequests, AllowedRequests, Firehose DeliveryToS3.Success, Lambda Errors, etc.

---

## 17. Grafana configuration (manual)

**Automated at boot:** Docker container with env vars and provisioning directory.

| Setting | Automated value |
|---------|-----------------|
| URL | `http://<MONITORING_EIP>:3000` |
| Admin user | `admin` |
| Admin password | `ChangeMe123!` (change after first login) |
| Sign-up | Disabled (`GF_USERS_ALLOW_SIGN_UP=false`) |

### Datasources (automated provisioning)

File on server: `/opt/observability/grafana/provisioning/datasources/datasources.yml`

| Name | Type | URL / config |
|------|------|--------------|
| Prometheus | prometheus | `http://prometheus:9090` (uid: `prometheus`) |
| CloudWatch | cloudwatch | Default AWS credentials (EC2 instance role), region `us-west-2` |

**Repo reference** (includes Athena datasource for advanced setups): `observability/grafana/provisioning/datasources/datasources.yml`

### Manual datasource setup (Grafana UI)

1. Login → **Connections** → **Data sources** → **Add data source**
2. **Prometheus**:
   - URL: `http://prometheus:9090` (from inside Docker network) or `http://localhost:9090`
   - UID: set to `prometheus` (required for dashboard JSON)
3. **CloudWatch**:
   - Authentication: default (uses EC2 instance profile)
   - Default region: `us-west-2`
4. **Save & test**

### Change admin password (Grafana UI)

1. **Administration** (gear icon) → **Users** → `admin` → **Change password**

### Fix empty dashboards (common issue)

Run on monitoring EC2 (or use repo script):

```bash
sudo bash /path/to/fix_grafana_metrics.sh
# Or from repo: scripts/deployment/fix_grafana_metrics.sh
```

Then re-import dashboard JSON files (see next section).

---

## 18. Alertmanager configuration (manual)

**Automated (minimal):** Default receiver only, no email/Slack in user-data bootstrap.  
**Full template in repo:** `observability/alertmanager/alertmanager.yml` (email, Slack, SNS routes by severity)

### Automated bootstrap file (on server)

`/opt/observability/alertmanager/alertmanager.yml`:

```yaml
global:
  resolve_timeout: 5m
route:
  receiver: default
  group_by: ['alertname']
  group_wait: 30s
  repeat_interval: 4h
receivers:
  - name: default
```

### Manual Alertmanager with email (edit on server)

1. SSH to monitoring EC2
2. Edit `/opt/observability/alertmanager/alertmanager.yml` using repo template (set `ALERT_EMAIL_TO`, SMTP, optional Slack webhook, SNS topic ARN)
3. `cd /opt/observability && docker compose restart alertmanager`
4. Verify: `http://<MONITORING_IP>:9093/#/status`

### Verify routing (UI)

1. Open `http://<MONITORING_IP>:9093`
2. **Status** → confirm config loaded
3. Trigger test alert in Prometheus → **Alerts** tab shows firing → Alertmanager receives notification

---

## 19. Grafana dashboard JSON import

Dashboards are **not** auto-imported at Terraform apply time — import once per environment via Grafana UI.

### Dashboard files (repo)

| File | Purpose |
|------|---------|
| `dashboards/grafana/security-overview.json` | WAF blocks/allows, SQLi, rate limit |
| `dashboards/grafana/threat-intelligence.json` | Attack patterns, top rules |
| `dashboards/grafana/executive-dashboard.json` | High-level KPIs |
| `dashboards/grafana/infrastructure-monitoring.json` | Node CPU, memory, disk from node_exporter |
| `dashboards/cloudwatch/waf-security-dashboard.json` | Native CloudWatch dashboard (not Grafana) |

All Grafana dashboards use datasource UID **`prometheus`** for PromQL panels.

### Import steps (Grafana UI)

1. Open `http://<MONITORING_IP>:3000` → login `admin` / `ChangeMe123!`
2. **Dashboards** → **New** → **Import**
3. Click **Upload JSON file** → select each file from `dashboards/grafana/`
4. When prompted for datasource, choose **Prometheus**
5. Click **Import**
6. Set time range: **Last 6 hours** (metrics need scrape time + CloudWatch delay ~2 min)
7. Repeat for all four Grafana JSON files

### Verify panels show data

1. **Explore** → datasource Prometheus → run:
   ```promql
   aws_wafv2_blocked_requests_sum{rule="ALL"}
   node_cpu_seconds_total
   probe_success{job="blackbox-alb"}
   ```
2. If empty: generate WAF traffic (Section 9), wait 2–5 minutes, refresh dashboard

### Re-import after datasource UID fix

If panels show "Datasource not found":
1. **Connections** → **Data sources** → Prometheus → ensure **UID** = `prometheus`
2. Re-import JSON files

---

## 20. CloudWatch dashboard JSON

**Automated by Terraform** when `cloudwatch_dashboard_json_path` is empty (built-in widgets) or when set to `dashboards/cloudwatch/waf-security-dashboard.json`.

### Verify in AWS Console

1. **CloudWatch** → **Dashboards** → `waf-security-dev-waf-security`
2. Confirm widgets for WAF, Firehose, Lambda

### Manual import (Console UI)

1. CloudWatch → **Dashboards** → **Create dashboard**
2. Name: `waf-security-dev-waf-security`
3. **Actions** → **View/edit source** → paste JSON from `dashboards/cloudwatch/waf-security-dashboard.json`
4. Save

---

## 21. CI/CD pipeline overview

**File:** `cicd/github-actions/ci.yml` (copy to `.github/workflows/ci.yml` in your fork to activate)

| Job | When | What it does |
|-----|------|--------------|
| `terraform-validate` | Every push/PR | `terraform fmt -check`, validate all modules + dev env |
| `security-scan` | Every push/PR | tfsec, Checkov on Terraform; bandit/semgrep on Lambda |
| `unit-tests` | Every push/PR | pytest with coverage on `lambda/` |
| `integration-tests` | PRs only | Dashboard JSON + Prometheus config validation |
| `terraform-plan` | Push to `main` only | OIDC AWS auth → `terraform plan` → upload `tfplan` artifact |

**Note:** The pipeline **plans** but does **not** auto-apply. Review the `tfplan` artifact and run `terraform apply` manually or extend the workflow.

### Required GitHub secret

| Secret | Value |
|--------|-------|
| `AWS_ROLE_ARN` | IAM role ARN trusted by GitHub OIDC for read-only plan |

---

## 22. Quick verification checklist

Use this after `terraform apply` or manual setup:

| # | Component | Console / URL | Pass criteria |
|---|-----------|---------------|---------------|
| 1 | KMS | KMS → `alias/waf-security-dev` | Key active, rotation on |
| 2 | VPC | VPC → `waf-security-dev-vpc` | 4 subnets, IGW attached |
| 3 | ALB | EC2 → Load Balancers | DNS resolves, HTTP 200 |
| 4 | WAF | WAF → Web ACLs (us-west-2) | 5+ rules, ALB associated, logging ON |
| 5 | Firehose | Data Firehose | DeliveryToS3.Success ≈ 1 |
| 6 | S3 | S3 → waf-logs bucket | `.gz` under `waf-logs/year=.../` |
| 7 | Glue | Glue → `waf_logs` table | Schema + partitions |
| 8 | Athena | Query editor | `SELECT COUNT(*) FROM waf_logs` works |
| 9 | Lambda | Lambda → Test daily report | Success + S3 report object |
| 10 | SNS | Subscriptions | Email **Confirmed** |
| 11 | CloudWatch | Dashboard + Alarms | Widgets show data, alarms OK |
| 12 | Agents | Prometheus targets | 3× node-exporter-agents UP |
| 13 | Prometheus | `:9090/targets` | All targets UP |
| 14 | Grafana | `:3000` | Login works, imported dashboards show data |
| 15 | Alertmanager | `:9093` | Config loaded, receives alerts |

### Useful CLI commands

```bash
export AWS_REGION=us-west-2
cd terraform/environments/dev

terraform output grafana_url
bash ../../../scripts/deployment/verify_waf_logging.sh
bash ../../../scripts/attack_simulation/run_traffic.sh

aws s3 ls "s3://$(terraform output -raw s3_bucket_name)/waf-logs/" --recursive | head
aws glue start-crawler --name waf-security-dev-waf-logs-crawler --region us-west-2

curl -s "http://$(terraform output -raw monitoring_server_ip):9090/api/v1/targets" | jq '.data.activeTargets[] | {job: .labels.job, health: .health}'
```

---

## Related documentation

| Path | Description |
|------|-------------|
| [DEPLOY.md](../DEPLOY.md) | Copy-paste deploy commands |
| [docs/guides/deployment-guide.md](../docs/guides/deployment-guide.md) | Deployment walkthrough |
| [docs/guides/aws-console-ui-guide.md](../docs/guides/aws-console-ui-guide.md) | Shorter console navigation guide |
| [debug/README.md](../debug/README.md) | Troubleshooting Grafana/Prometheus/WAF logging |
| [cicd/github-actions/ci.yml](../cicd/github-actions/ci.yml) | Commented CI/CD pipeline |
| [observability/](../observability/) | Reference Prometheus/Grafana/Alertmanager configs |
| [dashboards/](../dashboards/) | Grafana + CloudWatch dashboard JSON |

---

*Internal use — Security Operations Team*
