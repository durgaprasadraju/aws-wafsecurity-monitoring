"""AWS Lambda handler for WAF security report generation."""

import json
import logging
import os
from datetime import datetime, timezone

from athena_utils import execute_athena_query, get_athena_client, get_s3_client, get_sns_client
from queries import REPORT_DAYS, REPORT_QUERIES
from report_builder import generate_csv, generate_html

logger = logging.getLogger()
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO"))

ATHENA_WORKGROUP = os.environ["ATHENA_WORKGROUP"]
ATHENA_DATABASE = os.environ["ATHENA_DATABASE"]
S3_BUCKET = os.environ["S3_BUCKET"]
SNS_TOPIC_ARN = os.environ["SNS_TOPIC_ARN"]
ENVIRONMENT = os.environ.get("ENVIRONMENT", "dev")
PROJECT_NAME = os.environ.get("PROJECT_NAME", "waf-security")


def lambda_handler(event, context):
    """Generate and deliver WAF security report."""
    report_type = event.get("report_type", "daily")
    days = REPORT_DAYS.get(report_type, 1)
    logger.info("Generating %s report for %s environment (%d days)", report_type, ENVIRONMENT, days)

    athena = get_athena_client()
    s3 = get_s3_client()
    sns = get_sns_client()
    output_location = f"s3://{S3_BUCKET}/athena-results/"
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    prefix = f"reports/{report_type}/{timestamp}"

    sections = {}
    for name, query_template in REPORT_QUERIES.items():
        query = query_template.format(database=ATHENA_DATABASE, days=days)
        try:
            _, results = execute_athena_query(athena, query, ATHENA_DATABASE, ATHENA_WORKGROUP, output_location)
            sections[name.replace("_", " ").title()] = results
        except Exception as exc:
            logger.error("Query %s failed: %s", name, exc)
            sections[name.replace("_", " ").title()] = [["error"], [str(exc)]]

    summary = {}
    traffic = sections.get("Traffic Summary", [])
    if len(traffic) >= 2:
        headers = traffic[0]
        values = traffic[1]
        summary = dict(zip(headers, values))

    html_content = generate_html(report_type, ENVIRONMENT, PROJECT_NAME, sections, summary)
    csv_content = generate_csv(sections)

    html_key = f"{prefix}/waf_{report_type}_report.html"
    csv_key = f"{prefix}/waf_{report_type}_report.csv"

    s3.put_object(
        Bucket=S3_BUCKET,
        Key=html_key,
        Body=html_content.encode("utf-8"),
        ContentType="text/html",
        ServerSideEncryption="aws:kms",
    )
    s3.put_object(
        Bucket=S3_BUCKET,
        Key=csv_key,
        Body=csv_content.encode("utf-8"),
        ContentType="text/csv",
        ServerSideEncryption="aws:kms",
    )

    message = {
        "report_type": report_type,
        "environment": ENVIRONMENT,
        "html_report": f"s3://{S3_BUCKET}/{html_key}",
        "csv_report": f"s3://{S3_BUCKET}/{csv_key}",
        "summary": summary,
        "generated_at": timestamp,
    }

    sns.publish(
        TopicArn=SNS_TOPIC_ARN,
        Subject=f"[{ENVIRONMENT.upper()}] WAF {report_type.title()} Security Report",
        Message=json.dumps(message, indent=2),
    )

    logger.info("Report delivered: %s", json.dumps(message))
    return {"statusCode": 200, "body": json.dumps(message)}
