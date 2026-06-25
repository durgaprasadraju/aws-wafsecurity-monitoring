# Architecture Diagrams

## System Architecture

```mermaid
flowchart TB
    Internet([Internet])
    ALB[Application Load Balancer]
    WAF[AWS WAF Web ACL]
    CW[CloudWatch Metrics]
    FH[Kinesis Firehose]
    S3[(S3 WAF Logs)]
    S3R[(S3 Athena Results)]
    Glue[AWS Glue Catalog]
    Athena[Amazon Athena]
    Lambda[Lambda Report Generator]
    EB[EventBridge Schedules]
    SNS[SNS Topics]
    CW_Dash[CloudWatch Dashboard]

    subgraph Observability["EC2 Observability Stack"]
        Prom[Prometheus]
        Graf[Grafana]
        AM[Alertmanager]
        CWE[CloudWatch Exporter]
        BBE[Blackbox Exporter]
        NE1[Node Exporter EC2-02]
        NE2[Node Exporter EC2-03]
        NE3[Node Exporter EC2-04]
    end

    Internet --> ALB
    ALB --> WAF
    WAF --> CW
    WAF --> FH
    FH --> S3
    S3 --> Glue
    Glue --> Athena
    EB --> Lambda
    Lambda --> Athena
    Lambda --> S3
    Lambda --> SNS
    Athena --> S3R
    Athena -->|grafana-athena-datasource| Graf
    CW --> CWE
    CWE --> Prom
    Prom --> Graf
    Prom --> AM
    AM --> SNS
    NE1 --> Prom
    NE2 --> Prom
    NE3 --> Prom
    BBE --> Prom
    CW --> CW_Dash
```

## Grafana Dual-Path Visualization

Grafana consumes **metrics** (Prometheus) and **logs** (Athena) through separate data sources.

```mermaid
flowchart TB
    subgraph MetricsPath["Metrics Path — real-time aggregates"]
        WAF1[AWS WAF] --> CW[CloudWatch]
        CW --> CWX[CloudWatch Exporter :9106]
        CWX --> Prom[Prometheus :9090]
        FH1[Firehose] --> CW
        Prom --> G1[Grafana Panels]
    end

    subgraph LogsPath["Logs Path — forensic detail"]
        WAF2[AWS WAF] --> FH2[Firehose]
        FH2 --> S3[(S3 waf-logs/)]
        S3 --> Glue[Glue waf_logs]
        Glue --> Athena[Athena Workgroup]
        Athena --> G2[Grafana Athena DS]
        G2 --> G3[Grafana Panels]
        Athena --> S3R[(S3 athena-results/)]
    end

    subgraph Dashboards["Grafana Dashboards :3000"]
        G1 --> D1[Security Overview]
        G1 --> D2[Threat Intelligence]
        G1 --> D3[Executive / Infrastructure]
        G3 --> D4[WAF Log Analytics Athena]
    end
```

## Data Flow Sequence

```mermaid
sequenceDiagram
    participant C as Client
    participant ALB as ALB
    participant WAF as AWS WAF
    participant FH as Firehose
    participant S3 as S3
    participant G as Glue
    participant A as Athena
    participant L as Lambda
    participant Gf as Grafana

    C->>ALB: HTTP Request
    ALB->>WAF: Evaluate Rules
    alt Blocked
        WAF-->>C: 403 Forbidden
    else Allowed
        WAF-->>C: 200 OK
    end
    WAF->>FH: Log Record
    FH->>S3: GZIP JSON (partitioned)
    G->>G: Crawler updates schema
    L->>A: Scheduled Query
    A->>S3: Read logs
    A-->>L: Query results
    L->>S3: HTML/CSV report
    L->>SNS: Notification
    Gf->>A: Interactive SQL (dashboard refresh)
    A->>S3: Read logs
    A-->>Gf: Table / time-series results
```

## Athena → Grafana Query Flow

```mermaid
sequenceDiagram
    participant User as SOC Analyst
    participant Graf as Grafana
    participant EC2 as Monitoring EC2 IAM Role
    participant A as Athena
    participant Glue as Glue Catalog
    participant S3L as S3 waf-logs/
    participant S3R as S3 athena-results/

    User->>Graf: Open WAF Log Analytics dashboard
    Graf->>A: StartQueryExecution (via Athena plugin)
    Note over Graf,A: Workgroup: waf-security-{env}-waf-analytics
    A->>Glue: Resolve waf_logs schema / partitions
    A->>S3L: Scan partitioned log files
    A->>S3R: Write query results
    A-->>Graf: Return result set
    Graf-->>User: Render tables / charts
```

## Network Diagram

```mermaid
flowchart LR
    subgraph VPC["VPC 10.0.0.0/16"]
        subgraph Public["Public Subnets"]
            ALB[ALB]
            MON[EC2-01 Monitoring]
            AG1[EC2-02 Agent]
            AG2[EC2-03 Agent]
            AG3[EC2-04 Agent]
        end
        IGW[Internet Gateway]
    end

    subgraph AWSManaged["AWS Managed Services"]
        S3[(S3 Logs)]
        Athena[Athena]
        Glue[Glue]
    end

    Internet([Internet]) --> IGW
    IGW --> ALB
    IGW --> MON
    ALB --- WAF[WAF Web ACL]
    MON --- Graf[Grafana :3000]
    MON --- Prom[Prometheus :9090]
    Graf -->|Athena API| Athena
    Athena --> S3
    Athena --> Glue
    AG1 --- NE[Node Exporter]
    AG2 --- NE
    AG3 --- NE
    Prom --- NE
```

## Threat Model Diagram

```mermaid
flowchart TD
    subgraph External["External Threats"]
        SQLi[SQL Injection]
        XSS[Cross-Site Scripting]
        Bot[Bot Traffic]
        DDoS[Rate Abuse]
        Reputation[Bad IP Reputation]
    end

    subgraph Controls["Security Controls"]
        WAF_R[SQLi Rule Set]
        WAF_X[XSS Rule Set]
        WAF_B[Bot Control]
        WAF_RL[Rate Limiting]
        WAF_IP[IP Reputation]
    end

    subgraph Detection["Detection & Response"]
        Logs[WAF Logs S3]
        Metrics[CloudWatch Metrics]
        AthenaQ[Athena Analytics]
        GrafM[Grafana Metrics Dashboards]
        GrafA[Grafana Athena Dashboard]
        Alerts[Prometheus Alerts]
        Reports[Lambda Reports]
    end

    SQLi --> WAF_R
    XSS --> WAF_X
    Bot --> WAF_B
    DDoS --> WAF_RL
    Reputation --> WAF_IP
    WAF_R --> Logs
    WAF_X --> Logs
    WAF_B --> Logs
    WAF_RL --> Logs
    WAF_IP --> Logs
    Logs --> AthenaQ
    Logs --> Reports
    AthenaQ --> GrafA
    Metrics --> GrafM
    Metrics --> Alerts
```

## Deployment Topology

```mermaid
flowchart TB
    subgraph AWS["Single AWS Account"]
        subgraph Region["us-west-2"]
            TF[Terraform State S3 + DynamoDB]
            subgraph Stack["waf-security-dev"]
                All[All Platform Resources]
            end
        end
    end

    GH[GitHub Actions] -->|terraform plan/apply| TF
    TF --> Stack
    Dev[Developer] -->|terraform apply| TF
```

## Related Documentation

- [High Level Design (HLD)](../docs/architecture/HLD.md)
- [Low Level Design (LLD)](../docs/architecture/LLD.md)
- [AWS Architecture Diagram (draw.io)](aws-architecture.drawio)
- [Grafana + Athena Guide](../docs/guides/grafana-athena-guide.md)
