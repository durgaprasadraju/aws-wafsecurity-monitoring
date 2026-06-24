# AWS Console UI Guide

Step-by-step navigation for verifying and managing platform components.

> Screenshot placeholders: `[Screenshot: description]` — capture after deployment.

## 1. AWS WAF

**Navigation**: AWS Console → WAF & Shield → Web ACLs → `waf-security-dev-web-acl`

### Verify Web ACL
1. Click **Web ACLs** in left sidebar
2. Select region: **US East (N. Virginia)**
3. Click `waf-security-dev-web-acl`
4. **Rules** tab: Verify 5-6 rules listed
5. **Logging and metrics** tab: Confirm logging destination shows Firehose stream

`[Screenshot: WAF Web ACL rules list]`

### Test a Rule
1. Go to **Sampled requests** tab
2. Set time range to last 1 hour
3. Filter by Action = Block
4. Verify blocked requests appear after attack simulation

---

## 2. Kinesis Data Firehose

**Navigation**: AWS Console → Amazon Data Firehose → Delivery streams → `aws-waf-logs-waf-security-dev`

1. Click delivery stream name
2. **Monitoring** tab: Check DeliveryToS3.Success metric
3. **Configuration** tab: Verify S3 bucket destination and prefix `waf-logs/year=...`
4. **Error logs** tab: Check CloudWatch log group for errors

`[Screenshot: Firehose monitoring dashboard]`

---

## 3. Amazon S3

**Navigation**: AWS Console → S3 → `waf-security-dev-waf-logs-ACCOUNT_ID`

1. Click bucket name
2. **Objects** tab: Navigate to `waf-logs/year=YYYY/month=MM/day=DD/`
3. Verify `.gz` files present
4. **Properties** tab:
   - Default encryption: SSE-KMS
   - Versioning: Enabled
   - Server access logging: Enabled

`[Screenshot: S3 WAF logs partition structure]`

---

## 4. AWS Glue

**Navigation**: AWS Console → AWS Glue → Data Catalog → Databases → `waf_security_dev_waf`

1. Click database name
2. Click table `waf_logs`
3. **Schema** tab: Verify columns (timestamp, action, httprequest, etc.)
4. **Partitions** tab: Verify year/month/day partitions
5. **Crawlers**: Click `waf-security-dev-waf-logs-crawler` → Run crawler

`[Screenshot: Glue table schema]`

---

## 5. Amazon Athena

**Navigation**: AWS Console → Athena → Query editor

1. Workgroup: Select `waf-security-dev-waf-analytics`
2. Database: Select `waf_security_dev_waf`
3. Run query:
   ```sql
   SELECT action, COUNT(*) as cnt
   FROM waf_logs
   WHERE year = '2026' AND month = '06'
   GROUP BY action;
   ```
4. **Saved queries** tab: View named queries

`[Screenshot: Athena query results]`

---

## 6. AWS Lambda

**Navigation**: AWS Console → Lambda → `waf-security-dev-waf-report-generator`

1. **Configuration** tab → Environment variables: Verify ATHENA_WORKGROUP, S3_BUCKET, SNS_TOPIC_ARN
2. **Test** tab: Create test event `{"report_type": "daily"}` → Click **Test**
3. **Monitor** tab → View CloudWatch metrics
4. **Configuration** → Triggers: Verify 3 EventBridge rules

`[Screenshot: Lambda test execution]`

---

## 7. Amazon CloudWatch

**Navigation**: AWS Console → CloudWatch → Dashboards → `waf-security-dev-waf-security`

1. View blocked/allowed request graphs
2. **Alarms** → All alarms: Verify high-block-rate, sqli-surge alarms
3. **Log groups**: Check `/aws/lambda/...` and `/aws/kinesisfirehose/...`

`[Screenshot: CloudWatch WAF dashboard]`

---

## 8. Amazon SNS

**Navigation**: AWS Console → SNS → Topics

1. `waf-security-dev-security-alerts` — security alarm notifications
2. `waf-security-dev-reports` — report delivery
3. Click topic → **Subscriptions**: Confirm email status = Confirmed

`[Screenshot: SNS subscription confirmed]`

---

## 9. Grafana (EC2)

**URL**: `http://MONITORING_IP:3000`

1. Login: admin / ChangeMe123!
2. **Dashboards** → WAF Security Overview
3. **Connections** → Data sources: Verify Prometheus, CloudWatch
4. **Alerting** → Alert rules: Review configured rules

`[Screenshot: Grafana security overview dashboard]`

---

## 10. Prometheus (EC2)

**URL**: `http://MONITORING_IP:9090`

1. **Status** → Targets: All targets should show UP
2. **Alerts**: View firing/pending alerts
3. **Graph**: Query `aws_wafv2_blocked_requests_sum`

`[Screenshot: Prometheus targets page]`
