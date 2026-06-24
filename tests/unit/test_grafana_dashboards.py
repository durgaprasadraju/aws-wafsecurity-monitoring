"""Grafana dashboard validation tests."""

import json
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
DASHBOARD_DIR = ROOT / "dashboards" / "grafana"


class TestGrafanaDashboards:
    @pytest.fixture
    def dashboard_files(self):
        return list(DASHBOARD_DIR.glob("*.json"))

    def test_dashboard_files_exist(self, dashboard_files):
        assert len(dashboard_files) >= 1

    @pytest.mark.parametrize("dashboard_file", list(DASHBOARD_DIR.glob("*.json")), ids=lambda p: p.name)
    def test_dashboard_json_valid(self, dashboard_file):
        data = json.loads(dashboard_file.read_text())
        assert "title" in data
        assert "panels" in data

    @pytest.mark.parametrize("dashboard_file", list(DASHBOARD_DIR.glob("*.json")), ids=lambda p: p.name)
    def test_panels_have_gridpos(self, dashboard_file):
        data = json.loads(dashboard_file.read_text())
        for panel in data.get("panels", []):
            assert "gridPos" in panel, f"Panel {panel.get('title')} missing gridPos"

    def test_security_overview_has_variables(self):
        data = json.loads((DASHBOARD_DIR / "security-overview.json").read_text())
        variables = data.get("templating", {}).get("list", [])
        var_names = [v["name"] for v in variables]
        assert "environment" in var_names

    def test_datasource_references(self):
        data = json.loads((DASHBOARD_DIR / "security-overview.json").read_text())
        for panel in data["panels"]:
            if "datasource" in panel:
                assert panel["datasource"]["type"] == "prometheus"
