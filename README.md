# AWS WAF Security Intelligence & Observability Platform

Enterprise-grade AWS WAF monitoring, analytics, reporting, and observability platform optimized for **single-account AWS Sandbox** deployments (Pluralsight / A Cloud Guru).

## Architecture

```
Internet → ALB → AWS WAF ─┬→ CloudWatch Metrics → CloudWatch Exporter → Prometheus ─┐
                           │                                                          ├→ Grafana :3000
                           └→ Kinesis Firehose → S3 → Glue → Athena ─────────────────┘
                                                              ↓
                                                    Lambda Reports → SNS

EC2 Monitoring Server: Prometheus + Grafana (+ Athena plugin) + Alertmanager + Exporters
EC2 Agent Nodes: Node Exporter (×3)
```

Grafana uses two data paths: **Prometheus** for real-time metrics and **Athena** for WAF log forensics. See [Grafana + Athena Guide](docs/guides/grafana-athena-guide.md).

## Quick Start

See **[DEPLOY.md](DEPLOY.md)** for the full copy-paste deployment command reference.

### Prerequisites

- AWS CLI configured with sandbox credentials
- Terraform >= 1.7
- Python >= 3.11
- S3 bucket + DynamoDB table for Terraform remote state (create once)

### Deploy (Dev)

```bash
# 1. Create remote state backend (one-time)
export AWS_REGION=us-west-2
aws s3api create-bucket \
  --bucket waf-security-terraform-state \
  --region $AWS_REGION \
  --create-bucket-configuration LocationConstraint=$AWS_REGION
aws dynamodb create-table \
  --table-name waf-security-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST

# 2. Configure variables
cp terraform/environments/dev/terraform.tfvars.example terraform/environments/dev/terraform.tfvars
# Edit alert_email and other values

# 3. Deploy
cd terraform/environments/dev
terraform init
terraform plan
terraform apply

# 4. Get outputs
terraform output alb_dns_name
terraform output grafana_url
```

### Generate Test Traffic

```bash
ALB_URL=$(cd terraform/environments/dev && terraform output -raw alb_dns_name)
python scripts/attack_simulation/simulate_sqli.py --url "http://$ALB_URL" --count 20
python scripts/attack_simulation/simulate_xss.py --url "http://$ALB_URL" --count 20
```

### Run Tests

```bash
pip install -e ".[dev]"
pytest tests/unit/ -v
bash tests/terraform/validate.sh dev
```

## Repository Structure

| Path | Purpose |
|------|---------|
| `terraform/modules/` | Reusable Terraform modules |
| `terraform/environments/` | dev, test, prod configurations |
| `lambda/report_generator/` | Scheduled WAF report Lambda |
| `observability/` | Prometheus, Grafana, Alertmanager configs |
| `dashboards/` | CloudWatch and Grafana dashboard JSON |
| `athena/queries/` | Standalone Athena SQL queries |
| `scripts/` | Attack simulation, load testing, deployment |
| `tests/` | Unit, integration, e2e, performance tests |
| `docs/` | Architecture, operations, compliance guides |
| `cicd/` | GitHub Actions pipelines |
| `diagrams/` | Mermaid and architecture diagrams |

## Key Features

- **WAF Protection**: Managed rules (Common, SQLi, XSS, IP Reputation, Rate Limiting)
- **Log Pipeline**: WAF → Firehose → S3 (KMS encrypted, partitioned)
- **Analytics**: Glue catalog + Athena workgroup with named queries
- **Reporting**: Lambda generates daily/weekly/monthly HTML + CSV reports via EventBridge
- **Observability**: Self-hosted Prometheus/Grafana/Alertmanager on EC2
- **Grafana Athena**: WAF log analytics dashboard querying S3 logs via Athena — see [Grafana + Athena Guide](docs/guides/grafana-athena-guide.md)
- **Alerting**: CloudWatch alarms + Prometheus alert rules + SNS notifications
- **Security**: KMS encryption, IAM least privilege, public access blocked

## Sandbox Simplifications

This build intentionally excludes multi-account, AWS Organizations, Amazon Managed Prometheus/Grafana, and OpenSearch to ensure reliable deployment in sandbox environments.

## Documentation

- [High Level Design](docs/architecture/HLD.md)
- [Low Level Design](docs/architecture/LLD.md)
- [Architecture Diagrams](diagrams/architecture.md)
- [Security Architecture](docs/architecture/security-architecture.md)
- [Threat Model](docs/architecture/threat-model.md)
- [Deployment Commands (DEPLOY.md)](DEPLOY.md)
- [Deployment Guide](docs/guides/deployment-guide.md)
- [Grafana + Athena Guide](docs/guides/grafana-athena-guide.md)
- [Cost Estimation](docs/guides/cost-estimation.md)
- [SOC Analyst Guide](docs/operations/soc-analyst-guide.md)
- [Incident Response Guide](docs/operations/incident-response-guide.md)
- [Terraform Debugging Guide](docs/guides/terraform-debugging-guide.md)
- [AWS Console UI Guide](docs/guides/aws-console-ui-guide.md)

## License

Internal use — Security Operations Team
