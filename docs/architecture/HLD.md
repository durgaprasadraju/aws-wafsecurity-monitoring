# High Level Design (HLD)

## 1. Overview

The AWS WAF Security Intelligence & Observability Platform provides centralized monitoring, analytics, reporting, and alerting for AWS WAF-protected applications in a single AWS account.

## 2. Business Objectives

| Objective | Solution Component |
|-----------|-------------------|
| Collect WAF logs | WAF logging → Firehose → S3 |
| Store logs securely | S3 + KMS encryption + lifecycle |
| Analyze attack patterns | Glue + Athena |
| Generate reports | Lambda + EventBridge + SNS |
| Visualize attacks | CloudWatch + Grafana dashboards |
| Monitor infrastructure | Prometheus + Node Exporter |
| Alert security teams | CloudWatch Alarms + Alertmanager + SNS |
| Support multiple environments | Terraform environments (dev/test/prod) |

## 3. Architecture Components

### 3.1 Security Layer
- **AWS WAF Web ACL** attached to Application Load Balancer
- Managed rule groups: Common, SQLi, Known Bad Inputs, IP Reputation, Rate Limiting
- Optional Bot Control (disabled by default in sandbox due to cost)

### 3.2 Data Ingestion Layer
- **Kinesis Data Firehose** delivers WAF logs to S3
- GZIP compression, dynamic partitioning (year/month/day)
- CloudWatch logging for delivery monitoring

### 3.3 Storage & Catalog Layer
- **S3** with versioning, KMS encryption, lifecycle policies
- **AWS Glue** database, table schema, and scheduled crawler

### 3.4 Analytics Layer
- **Amazon Athena** workgroup with encrypted query results
- 11 named queries for threat intelligence

### 3.5 Reporting Layer
- **Lambda** (Python 3.12) triggered by EventBridge schedules
- Generates HTML and CSV reports, delivers via SNS

### 3.6 Observability Layer (EC2-based)
- **Monitoring Server**: Prometheus, Grafana, Alertmanager, CloudWatch Exporter, Blackbox Exporter
- **Agent Nodes** (×3): Node Exporter for infrastructure metrics

### 3.7 Alerting Layer
- CloudWatch metric alarms (block rate, SQLi surge, Firehose failures)
- Prometheus alert rules (security + infrastructure)
- Alertmanager routing by severity (critical/high/medium/low)

## 4. Data Flow

1. Client requests hit ALB
2. WAF evaluates rules, allows or blocks
3. WAF logs stream to Firehose → S3 (partitioned)
4. Glue crawler updates catalog
5. Athena queries analyze logs
6. Lambda generates scheduled reports
7. CloudWatch metrics scraped by CloudWatch Exporter → Prometheus
8. Grafana visualizes metrics; Alertmanager routes alerts

## 5. Environment Strategy

| Environment | Purpose | Bot Control | Instance Size |
|-------------|---------|-------------|---------------|
| dev | Development/testing | Off | t3.medium |
| test | Pre-production validation | Off | t3.medium |
| prod | Production workloads | Optional | t3.large+ |

## 6. Non-Goals (Sandbox)

- Multi-account log aggregation
- AWS Organizations
- Amazon Managed Prometheus/Grafana
- Amazon OpenSearch
- Cross-account IAM roles

## 7. Compliance Alignment

- **AWS Well-Architected**: Security, Reliability, Performance, Cost, Operations
- **CIS AWS Foundations**: Encryption, logging, least privilege IAM
- **NIST 800-53**: AU (audit), SI (system integrity), SC (communications protection)
- **ISO 27001**: A.12 Operations security, A.14 System acquisition
