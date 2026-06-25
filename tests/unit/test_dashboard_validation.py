"""Validate dashboard JSON files."""

import json
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]


class TestCloudWatchDashboard:
    def test_dashboard_json_valid(self):
        path = ROOT / "dashboards/cloudwatch/waf-security-dashboard.json"
        data = json.loads(path.read_text())
        assert "widgets" in data
        assert len(data["widgets"]) >= 5

    def test_all_widgets_have_type(self):
        path = ROOT / "dashboards/cloudwatch/waf-security-dashboard.json"
        data = json.loads(path.read_text())
        for widget in data["widgets"]:
            assert "type" in widget
            assert "properties" in widget


class TestGrafanaDashboard:
    def test_security_overview_valid(self):
        path = ROOT / "dashboards/grafana/security-overview.json"
        data = json.loads(path.read_text())
        assert data["title"] == "WAF Security Overview"
        assert "panels" in data
        assert len(data["panels"]) >= 3

    def test_panels_have_targets(self):
        path = ROOT / "dashboards/grafana/security-overview.json"
        data = json.loads(path.read_text())
        for panel in data["panels"]:
            if panel.get("type") != "row":
                assert "targets" in panel or panel.get("type") == "text"

    def test_has_templating_variables(self):
        path = ROOT / "dashboards/grafana/security-overview.json"
        data = json.loads(path.read_text())
        assert "templating" in data
        assert len(data["templating"]["list"]) >= 1

    def test_athena_dashboard_has_sql_panels(self):
        path = ROOT / "dashboards/grafana/athena-log-analytics.json"
        data = json.loads(path.read_text())
        sql_panels = [
            p for p in data["panels"]
            if any("rawSQL" in t for t in p.get("targets", []))
        ]
        assert len(sql_panels) >= 5
