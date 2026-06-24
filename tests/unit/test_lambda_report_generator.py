"""Unit tests for WAF report generator Lambda."""

import json
import os
import sys
from unittest.mock import MagicMock, patch

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "../../lambda/report_generator"))

from report_builder import generate_csv, generate_html
from queries import REPORT_DAYS, REPORT_QUERIES


class TestReportBuilder:
    def test_generate_csv_multiple_sections(self):
        sections = {
            "Top Attackers": [["ip", "count"], ["1.2.3.4", "10"]],
            "Countries": [["country", "blocks"], ["US", "5"]],
        }
        csv_output = generate_csv(sections)
        assert "Top Attackers" in csv_output
        assert "1.2.3.4" in csv_output

    def test_generate_html_contains_summary(self):
        sections = {"Traffic": [["total", "blocked"], ["100", "10"]]}
        summary = {"total_requests": 100, "blocked": 10}
        html = generate_html("daily", "dev", "waf-security", sections, summary)
        assert "Daily WAF Security Report" in html
        assert "total_requests" in html or "Total Requests" in html
        assert "<table>" in html


class TestQueries:
    def test_report_days_mapping(self):
        assert REPORT_DAYS["daily"] == 1
        assert REPORT_DAYS["weekly"] == 7
        assert REPORT_DAYS["monthly"] == 30

    def test_all_queries_have_database_placeholder(self):
        for name, query in REPORT_QUERIES.items():
            assert "{database}" in query, f"{name} missing database placeholder"
            assert "{days}" in query, f"{name} missing days placeholder"


class TestLambdaHandler:
    @patch("handler.get_sns_client")
    @patch("handler.get_s3_client")
    @patch("handler.get_athena_client")
    @patch("handler.execute_athena_query")
    def test_lambda_handler_daily_report(self, mock_athena, mock_athena_client, mock_s3_client, mock_sns_client):
        os.environ.setdefault("ATHENA_WORKGROUP", "test-wg")
        os.environ.setdefault("ATHENA_DATABASE", "test_db")
        os.environ.setdefault("S3_BUCKET", "test-bucket")
        os.environ.setdefault("SNS_TOPIC_ARN", "arn:aws:sns:us-east-1:123456789012:test")
        os.environ.setdefault("ENVIRONMENT", "dev")
        os.environ.setdefault("PROJECT_NAME", "waf-security")

        mock_athena.return_value = ("exec-id", [["total", "blocked"], ["100", "10"]])
        mock_s3 = MagicMock()
        mock_sns = MagicMock()
        mock_s3_client.return_value = mock_s3
        mock_sns_client.return_value = mock_sns

        from handler import lambda_handler

        result = lambda_handler({"report_type": "daily"}, None)
        body = json.loads(result["body"])
        assert result["statusCode"] == 200
        assert body["report_type"] == "daily"
        mock_s3.put_object.assert_called()
        mock_sns.publish.assert_called_once()
