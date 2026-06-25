#!/usr/bin/env python3
"""Generate project documentation PDF using only Python stdlib."""

from __future__ import annotations

import textwrap
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "docs" / "AWS-WAF-Security-Platform-Documentation.pdf"

PAGE_WIDTH = 612
PAGE_HEIGHT = 792
MARGIN_LEFT = 50
MARGIN_RIGHT = 50
MARGIN_TOP = 50
MARGIN_BOTTOM = 50
LINE_HEIGHT = 14
TITLE_SIZE = 18
H1_SIZE = 14
H2_SIZE = 12
BODY_SIZE = 10
CODE_SIZE = 8.5
MAX_CHARS = 92


class PdfWriter:
    def __init__(self) -> None:
        self.pages: list[list[str]] = [[]]
        self.y = PAGE_HEIGHT - MARGIN_TOP
        self.font = "Helvetica"
        self.size = BODY_SIZE

    def _new_page(self) -> None:
        self.pages.append([])
        self.y = PAGE_HEIGHT - MARGIN_TOP

    def _ensure_space(self, lines: int = 1) -> None:
        if self.y - lines * LINE_HEIGHT < MARGIN_BOTTOM:
            self._new_page()

    def _escape(self, text: str) -> str:
        return text.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")

    def _add_line(self, text: str, size: float | None = None, font: str | None = None) -> None:
        self._ensure_space()
        size = size or self.size
        font = font or self.font
        x = MARGIN_LEFT
        self.pages[-1].append(
            f"BT /{font} {size} Tf {x:.2f} {self.y:.2f} Td ({self._escape(text)}) Tj ET"
        )
        self.y -= LINE_HEIGHT

    def blank(self, count: int = 1) -> None:
        for _ in range(count):
            self._ensure_space()
            self.y -= LINE_HEIGHT

    def title(self, text: str) -> None:
        self._add_line(text, TITLE_SIZE, "Helvetica-Bold")
        self.blank()

    def h1(self, text: str) -> None:
        self.blank()
        self._add_line(text, H1_SIZE, "Helvetica-Bold")

    def h2(self, text: str) -> None:
        self.blank()
        self._add_line(text, H2_SIZE, "Helvetica-Bold")

    def paragraph(self, text: str) -> None:
        for line in textwrap.wrap(text, width=MAX_CHARS):
            self._add_line(line, BODY_SIZE)

    def bullet(self, text: str) -> None:
        wrapped = textwrap.wrap(text, width=MAX_CHARS - 4)
        for i, line in enumerate(wrapped):
            prefix = "- " if i == 0 else "  "
            self._add_line(prefix + line, BODY_SIZE)

    def code_block(self, text: str) -> None:
        for line in text.splitlines():
            if not line:
                self.blank()
                continue
            chunks = textwrap.wrap(line, width=105) or [""]
            for chunk in chunks:
                self._add_line(chunk, CODE_SIZE, "Courier")

    def table_row(self, cols: list[str], widths: list[int] | None = None) -> None:
        widths = widths or [30, 62]
        left, right = cols[0][: widths[0]], cols[1][: widths[1]]
        self._add_line(f"{left:<{widths[0]}} {right}", BODY_SIZE)

    def build(self, path: Path) -> None:
        font_regular = 5
        font_bold = 6
        font_courier = 7

        objects: list[bytes] = [
            b"1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n",
            b"2 0 obj\n<< /Type /Pages /Kids [] /Count 0 >>\nendobj\n",
            b"3 0 obj\n<< >>\nendobj\n",
            b"4 0 obj\n<< >>\nendobj\n",
            b"5 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>\nendobj\n",
            b"6 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold >>\nendobj\n",
            b"7 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Courier >>\nendobj\n",
        ]
        page_obj_nums: list[int] = []
        next_num = 8

        for page_cmds in self.pages:
            content = "\n".join(page_cmds).encode("latin-1", errors="replace")
            content_obj = (
                f"{next_num} 0 obj\n<< /Length {len(content)} >>\nstream\n".encode()
                + content
                + b"\nendstream\nendobj\n"
            )
            objects.append(content_obj)
            content_num = next_num
            next_num += 1

            page_obj = (
                f"{next_num} 0 obj\n"
                f"<< /Type /Page /Parent 2 0 R "
                f"/MediaBox [0 0 {PAGE_WIDTH} {PAGE_HEIGHT}] "
                f"/Contents {content_num} 0 R "
                f"/Resources << /Font << "
                f"/Helvetica {font_regular} 0 R "
                f"/Helvetica-Bold {font_bold} 0 R "
                f"/Courier {font_courier} 0 R "
                f">> >> >>\nendobj\n"
            ).encode()
            objects.append(page_obj)
            page_obj_nums.append(next_num)
            next_num += 1

        kids = " ".join(f"{n} 0 R" for n in page_obj_nums)
        objects[1] = (
            f"2 0 obj\n<< /Type /Pages /Kids [{kids}] /Count {len(page_obj_nums)} >>\nendobj\n"
        ).encode()

        pdf = bytearray(b"%PDF-1.4\n")
        offsets = [0]
        for obj in objects:
            offsets.append(len(pdf))
            pdf.extend(obj)

        xref_pos = len(pdf)
        pdf.extend(f"xref\n0 {len(objects) + 1}\n".encode())
        pdf.extend(b"0000000000 65535 f \n")
        for off in offsets[1:]:
            pdf.extend(f"{off:010d} 00000 n \n".encode())
        pdf.extend(
            f"trailer\n<< /Size {len(objects) + 1} /Root 1 0 R >>\n"
            f"startxref\n{xref_pos}\n%%EOF\n".encode()
        )
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(pdf)


def build_document() -> PdfWriter:
    doc = PdfWriter()
    today = date.today().isoformat()

    doc.title("AWS WAF Security Intelligence & Observability Platform")
    doc.paragraph(f"Project Documentation | Generated {today}")
    doc.paragraph(
        "Enterprise-grade AWS WAF monitoring, analytics, reporting, and observability "
        "for single-account sandbox deployments. This document covers architecture, "
        "AWS services, data flows, Prometheus monitoring, Grafana dashboards, and tests."
    )

    doc.h1("1. Executive Summary")
    doc.paragraph(
        "The platform protects web applications with AWS WAF, streams security logs to S3, "
        "analyzes threats with Glue and Athena, delivers scheduled reports via Lambda and SNS, "
        "and provides real-time observability through Prometheus, Grafana, and Alertmanager on EC2."
    )

    doc.h1("2. AWS Architecture Overview")
    doc.paragraph(
        "Open diagrams/aws-architecture.drawio in diagrams.net for the full visual diagram "
        "with official AWS service icons. The ASCII overview below matches that layout."
    )
    doc.code_block(
        """
                         [ Users / Internet ]
                                  |
                           [ AWS WAF Web ACL ]
                            /               \\
                    [ ALB + VPC ]      [ CloudWatch Metrics ]
                           |                    |
              [ EC2 Monitoring Server ]   [ CloudWatch Exporter :9106 ]
              Prometheus / Grafana              |
              Alertmanager / Exporters     [ Prometheus :9090 ]
                           |                    |
                           +---------> [ Grafana :3000 ]
                           |
                    [ Kinesis Firehose ]
                           |
                    [ Amazon S3 - WAF Logs ]
                           |
                    [ AWS Glue Catalog ]
                           |
                    [ Amazon Athena ]
                      /         \\
            [ Lambda Reports ]   [ Grafana Athena DS ]
                    |                 (log analytics)
               [ Amazon SNS ]
        [ EventBridge schedules Lambda ]
        [ KMS encrypts S3/SNS | IAM roles for all services ]
        """
    )

    doc.h1("3. AWS Services and Importance")
    services = [
        ("AWS WAF", "First line of defense. Blocks SQLi, XSS, bad inputs, bots, rate abuse."),
        ("Application Load Balancer", "Distributes HTTP traffic; WAF is associated with the ALB."),
        ("Amazon VPC", "Network isolation. Public subnets host ALB and monitoring EC2 instances."),
        ("Kinesis Firehose", "Reliable, buffered delivery of WAF logs to S3 with partitioning."),
        ("Amazon S3", "Durable log storage (waf-logs/), reports, and Athena query results."),
        ("AWS Glue", "Catalog and crawler for waf_logs table used by Athena and Grafana."),
        ("Amazon Athena", "Serverless SQL on logs for reports, forensics, and Grafana panels."),
        ("AWS Lambda", "Scheduled report generator (HTML/CSV) triggered by EventBridge."),
        ("Amazon EventBridge", "Cron schedules for daily, weekly, and monthly reports."),
        ("Amazon SNS", "Email notifications for reports and security/platform alerts."),
        ("Amazon CloudWatch", "WAF/Firehose/Lambda/ALB metrics, alarms, and dashboards."),
        ("Amazon EC2", "Hosts Prometheus, Grafana, Alertmanager, and exporters (4 instances)."),
        ("AWS KMS", "Encrypts S3 objects, SNS topics, Firehose logs, and Athena results."),
        ("AWS IAM", "Least-privilege roles for Firehose, Lambda, Glue, WAF logging, and EC2."),
    ]
    for name, importance in services:
        doc.bullet(f"{name}: {importance}")

    doc.h1("4. Data Flow (Log Pipeline)")
    doc.code_block(
        """
  Client Request
       |
       v
  [ ALB ] <--- associated --- [ AWS WAF Web ACL ]
       |                              |
       |                              | logs (BLOCK/COUNT)
       v                              v
  Application response         [ Kinesis Firehose ]
                                      |
                                      v GZIP, year/month/day partitions
                               [ S3: waf-logs/ ]
                                      |
                                      v Glue crawler
                               [ Glue: waf_logs table ]
                                      |
                    +-----------------+------------------+
                    v                 v                  v
             [ Athena queries ]  [ Lambda reports ]  [ Grafana Athena ]
                    |                 |                  |
                    v                 v                  v
             [ S3: athena-results ] [ SNS email ]   [ Log dashboards ]
        """
    )
    doc.paragraph(
        "Log pipeline steps: (1) WAF evaluates request, (2) log record sent to Firehose, "
        "(3) Firehose writes to S3, (4) Glue crawler updates partitions, (5) Athena/Grafana/Lambda query logs."
    )

    doc.h1("5. Metrics Flow (Prometheus-Centric)")
    doc.paragraph(
        "Prometheus is the central metrics store on the monitoring EC2. CloudWatch Exporter "
        "pulls AWS metrics; Node Exporter and Blackbox Exporter provide infra and ALB health data."
    )
    doc.code_block(
        """
  [ AWS WAF ] ---------> [ CloudWatch Metrics: BlockedRequests, AllowedRequests ]
  [ Firehose ] --------> [ CloudWatch: DeliveryToS3.Success, DataFreshness ]
  [ Lambda ] -----------> [ CloudWatch: Errors, Duration ]
  [ ALB ] --------------> [ CloudWatch: RequestCount, 5XX ]
  [ Athena ] -----------> [ CloudWatch: ProcessedBytes ]
                              |
                              v
                    [ CloudWatch Exporter :9106 ]
                              |
                              v scrape every 15s
                    [ Prometheus :9090 ] <----- [ Node Exporter :9100 x4 EC2 ]
                              ^              [ Blackbox Exporter :9115 -> ALB ]
                              |
                    +---------+---------+
                    v                   v
             [ Grafana :3000 ]   [ Alertmanager :9093 ]
             Prometheus DS            |
             (Security Overview,       v
              Threat Intel,         [ SNS / on-call ]
              Executive,
              Infrastructure)
        """
    )

    doc.h1("6. Prometheus Monitoring (Detailed)")
    doc.h2("6.1 Scrape Targets")
    scrape_jobs = [
        ("prometheus", "localhost:9090", "Self-monitoring"),
        ("node-exporter", "agent EC2s :9100", "CPU, memory, disk, network"),
        ("node-exporter-monitoring", "localhost:9100", "Monitoring server health"),
        ("cloudwatch-exporter", "localhost:9106", "AWS WAF, Firehose, Lambda, ALB, Athena metrics"),
        ("blackbox-exporter", "ALB DNS via :9115", "HTTP probe_success for ALB health"),
        ("aws-waf-cloudwatch", "filtered aws_wafv2_*", "WAF-specific metric relabeling"),
        ("aws-firehose-cloudwatch", "filtered aws_firehose_*", "Delivery pipeline health"),
        ("aws-lambda-cloudwatch", "filtered aws_lambda_*", "Report generator errors"),
        ("aws-athena-cloudwatch", "filtered aws_athena_*", "Query volume monitoring"),
    ]
    doc.table_row(["Job", "Target / Purpose"])
    for job, target, purpose in scrape_jobs:
        doc.table_row([job, f"{target} - {purpose}"])

    doc.h2("6.2 Key Prometheus Metrics")
    metrics = [
        "aws_wafv2_blocked_requests_sum - blocked requests by rule",
        "aws_wafv2_allowed_requests_sum - allowed requests by rule",
        "aws_firehose_delivery_to_s3_success_average - log delivery health",
        "aws_lambda_errors_sum - report Lambda failures",
        "node_cpu_seconds_total - infrastructure CPU",
        "node_memory_MemAvailable_bytes - memory pressure",
        "probe_success{job=blackbox-alb} - ALB reachability",
        "up - scrape target availability",
    ]
    for m in metrics:
        doc.bullet(m)

    doc.h2("6.3 Alert Rules (waf-alerts.yml)")
    alerts = [
        ("HighBlockRate", "critical", "Block rate > 10/s for 5m"),
        ("SQLiSurge", "high", "SQLi blocks elevated"),
        ("XSSSurge", "high", "XSS/BadInputs blocks elevated"),
        ("BotAttackSurge", "medium", "Bot control blocks elevated"),
        ("TopAttackerSpike", "high", "Sudden coordinated attack pattern"),
        ("HighCPUUsage", "medium", "Node CPU > 85% for 10m"),
        ("HighMemoryUsage", "medium", "Memory > 90% for 10m"),
        ("DiskSpaceLow", "high", "Disk < 15% free"),
        ("LambdaErrors", "high", "Report generator failing"),
        ("FirehoseDeliveryFailures", "critical", "S3 delivery < 95%"),
        ("PrometheusTargetDown", "critical", "Scrape target unreachable"),
        ("BlackboxProbeFailure", "high", "ALB health probe failed"),
    ]
    doc.table_row(["Alert", "Severity / Condition"])
    for name, sev, cond in alerts:
        doc.table_row([name, f"{sev}: {cond}"])

    doc.h2("6.4 Storage and Retention")
    doc.bullet("TSDB retention: 30 days (prometheus.yml)")
    doc.bullet("Scrape interval: 15 seconds")
    doc.bullet("Rule evaluation interval: 15 seconds")

    doc.h1("7. Grafana Dashboards")
    dashboards = [
        ("WAF Security Overview", "Prometheus", "Block/allow rates, SQLi/XSS/Bot, node CPU, ALB probe"),
        ("Threat Intelligence", "Prometheus", "Attack trends by rule type"),
        ("Executive Dashboard", "Prometheus", "Block rate %, platform health summary"),
        ("Infrastructure Monitoring", "Prometheus", "CPU, memory, disk, Firehose, scrape targets"),
        ("WAF Log Analytics (Athena)", "Athena", "Top attackers, countries, URIs, recent blocks"),
    ]
    doc.table_row(["Dashboard", "Datasource / Purpose"])
    for name, ds, purpose in dashboards:
        doc.table_row([name, f"{ds}: {purpose}"])

    doc.h1("8. Reporting and Alerting Flow")
    doc.code_block(
        """
  [ EventBridge cron ]
     |  daily 06:00 UTC | weekly Mon 07:00 | monthly 1st 08:00
     v
  [ Lambda Report Generator ]
     |-- runs 6 Athena queries (top_attackers, countries, sqli, xss, bot, summary)
     |-- builds HTML + CSV
     v
  [ S3: reports/ ]  +  [ SNS notification email ]

  [ Prometheus alert fires ]
     v
  [ Alertmanager :9093 ] --> route by severity --> [ SNS / receivers ]
        """
    )

    doc.h1("9. Test Suite")
    doc.paragraph(
        "Run: pip install -e '.[dev]' && pytest tests/unit/ -v && bash tests/terraform/validate.sh dev"
    )
    doc.h2("9.1 Unit Tests")
    unit_tests = [
        ("test_prometheus_alertmanager.py", "Prometheus YAML, 30d retention, alert rules, Alertmanager routing"),
        ("test_grafana_dashboards.py", "Grafana JSON validity, gridPos, Athena dashboard SQL panels"),
        ("test_dashboard_validation.py", "CloudWatch + Grafana dashboard structure validation"),
        ("test_lambda_report_generator.py", "CSV/HTML reports, Athena query placeholders, handler mocks"),
        ("test_terraform_structure.py", "Module files, env configs, no hardcoded secrets"),
    ]
    for file, scope in unit_tests:
        doc.bullet(f"{file}: {scope}")

    doc.h2("9.2 Integration and E2E Tests")
    doc.bullet("test_infrastructure.py: ALB response, WAF protection, S3 config, Athena query files")
    doc.bullet("tests/e2e/run_e2e.py: End-to-end validation after deployment")
    doc.bullet("tests/terraform/validate.sh: terraform fmt, validate, plan for each environment")
    doc.bullet("tests/terraform/security_scan.sh: Static security checks on Terraform")

    doc.h2("9.3 Expected Test Coverage Areas")
    doc.bullet("Prometheus scrape config and 12 alert rules across security + infrastructure")
    doc.bullet("5 Grafana dashboards including Athena log analytics with 13 SQL targets")
    doc.bullet("Lambda report generator with 6 Athena query templates")
    doc.bullet("Terraform modules: vpc, alb, waf, firehose, s3, glue, athena, lambda, monitoring, iam, kms, sns, cloudwatch")

    doc.h1("10. Deployment Quick Reference")
    doc.code_block(
        """
  cd terraform/environments/dev
  terraform init && terraform apply
  terraform output grafana_url
  terraform output alb_dns_name

  # Generate test traffic
  python scripts/attack_simulation/simulate_sqli.py --url http://$ALB --count 20

  # Verify Prometheus
  curl http://<monitoring-ip>:9090/api/v1/query?query=up
  curl http://<monitoring-ip>:9090/api/v1/query?query=aws_wafv2_blocked_requests_sum
        """
    )

    doc.h1("11. Related Documentation")
    doc.bullet("docs/architecture/HLD.md - High Level Design")
    doc.bullet("docs/architecture/LLD.md - Low Level Design")
    doc.bullet("diagrams/aws-architecture.drawio - AWS icon architecture diagram")
    doc.bullet("docs/guides/grafana-athena-guide.md - Grafana Athena setup")
    doc.bullet("DEPLOY.md - Copy-paste deployment commands")

    doc.blank(2)
    doc.paragraph("Internal use - Security Operations Team")
    return doc


def main() -> None:
    doc = build_document()
    doc.build(OUTPUT)
    print(f"Generated: {OUTPUT} ({OUTPUT.stat().st_size:,} bytes, {len(doc.pages)} pages)")


if __name__ == "__main__":
    main()
