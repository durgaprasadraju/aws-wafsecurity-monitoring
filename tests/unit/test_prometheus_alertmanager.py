"""Validate Prometheus and Alertmanager configuration."""

import yaml
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]


class TestPrometheusConfig:
    def test_prometheus_yml_valid(self):
        path = ROOT / "observability/prometheus/prometheus.yml"
        data = yaml.safe_load(path.read_text())
        assert data["global"]["scrape_interval"] == "15s"
        assert "scrape_configs" in data

    def test_retention_30d(self):
        path = ROOT / "observability/prometheus/prometheus.yml"
        data = yaml.safe_load(path.read_text())
        assert data["storage"]["tsdb"]["retention.time"] == "30d"

    def test_alert_rules_exist(self):
        path = ROOT / "observability/prometheus/rules/waf-alerts.yml"
        data = yaml.safe_load(path.read_text())
        assert "groups" in data
        rules = [r for g in data["groups"] for r in g["rules"]]
        rule_names = [r["alert"] for r in rules]
        assert "HighBlockRate" in rule_names
        assert "SQLiSurge" in rule_names


class TestAlertmanagerConfig:
    def test_alertmanager_yml_valid(self):
        path = ROOT / "observability/alertmanager/alertmanager.yml"
        data = yaml.safe_load(path.read_text())
        assert "route" in data
        assert "receivers" in data

    def test_severity_routing(self):
        path = ROOT / "observability/alertmanager/alertmanager.yml"
        data = yaml.safe_load(path.read_text())
        routes = data["route"]["routes"]
        severities = [r["match"]["severity"] for r in routes]
        assert "critical" in severities
        assert "high" in severities
