# Architecture Diagrams

This folder contains visual architecture diagrams for the AWS WAF Security Intelligence & Observability Platform.

## Diagram files

| File | Format | Description |
|------|--------|-------------|
| [aws-architecture.drawio](aws-architecture.drawio) | draw.io / diagrams.net | **Primary AWS architecture diagram** with official AWS service icons |
| [waf-platform.drawio](waf-platform.drawio) | draw.io / diagrams.net | Simplified legacy overview (text boxes) |
| [architecture.md](architecture.md) | Mermaid | Text-based diagrams (system, sequence, network, threat model) |

## How to open the AWS diagram

### Option 1: diagrams.net (recommended)

1. Go to [https://app.diagrams.net/](https://app.diagrams.net/)
2. **File → Open from → Device**
3. Select `diagrams/aws-architecture.drawio`
4. AWS icons render automatically from the built-in **AWS 2024** shape library

### Option 2: VS Code / Cursor

1. Install the **Draw.io Integration** extension
2. Open `diagrams/aws-architecture.drawio` in the editor

### Option 3: Desktop app

Download [diagrams.net desktop](https://github.com/jgraph/drawio-desktop/releases) and open the `.drawio` file.

## AWS services shown

| Category | AWS Services |
|----------|--------------|
| **Networking** | VPC, Internet Gateway, Application Load Balancer |
| **Security** | AWS WAF, IAM, KMS |
| **Compute** | EC2 (monitoring server + 3 agent nodes), Lambda |
| **Storage** | S3 (WAF logs + Athena query results) |
| **Analytics** | Kinesis Data Firehose, AWS Glue, Amazon Athena |
| **Observability** | Amazon CloudWatch (metrics, alarms, dashboards) |
| **Integration** | Amazon EventBridge, Amazon SNS |

### On EC2 (not separate AWS icons)

These run as containers/processes on the monitoring EC2 instance:

- Prometheus, Grafana (+ Athena plugin), Alertmanager
- CloudWatch Exporter, Blackbox Exporter, Node Exporter

## Data flows (numbered on diagram)

1. **HTTP traffic** — Users → WAF → ALB
2. **Log pipeline** — WAF → Firehose → S3 → Glue → Athena
3. **Scheduled reports** — EventBridge → Lambda → Athena → SNS
4. **Metrics path** — WAF → CloudWatch → EC2 Prometheus → Grafana
5. **Log analytics** — Athena → Grafana (Athena data source / WAF Log Analytics dashboard)

## Related documentation

- [High Level Design (HLD)](../docs/architecture/HLD.md)
- [Low Level Design (LLD)](../docs/architecture/LLD.md)
- [Grafana + Athena Guide](../docs/guides/grafana-athena-guide.md)
- [Mermaid diagrams](architecture.md)

## Exporting

From diagrams.net:

- **File → Export as → PNG / SVG / PDF** for presentations or documentation
- Recommended export: PNG at 200% scale for crisp icons

## Project PDF documentation

A consolidated PDF covering architecture, services, data/metrics flows, Prometheus monitoring, tests, and deployment is available at:

**[docs/AWS-WAF-Security-Platform-Documentation.pdf](../docs/AWS-WAF-Security-Platform-Documentation.pdf)**

Regenerate after doc changes:

```bash
python3 scripts/generate_project_pdf.py
```

## Icon reference

Icons use the draw.io `mxgraph.aws4` library (`shape=mxgraph.aws4.resourceIcon`). Official AWS Architecture Icons: [https://aws.amazon.com/architecture/icons/](https://aws.amazon.com/architecture/icons/)
