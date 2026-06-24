"""Integration tests for WAF security platform components."""

import json
import os
from pathlib import Path

import pytest
import requests

ROOT = Path(__file__).resolve().parents[2]
SKIP_INTEGRATION = os.environ.get("SKIP_INTEGRATION", "true").lower() == "true"

pytestmark = pytest.mark.skipif(SKIP_INTEGRATION, reason="Set SKIP_INTEGRATION=false to run")


class TestDeployedInfrastructure:
  @pytest.fixture
  def terraform_outputs(self):
    outputs_file = os.environ.get("TF_OUTPUTS_FILE")
    if outputs_file and Path(outputs_file).exists():
      return json.loads(Path(outputs_file).read_text())
    pytest.skip("TF_OUTPUTS_FILE not set")

  def test_alb_responds(self, terraform_outputs):
    url = f"http://{terraform_outputs['alb_dns_name']['value']}"
    resp = requests.get(url, timeout=10)
    assert resp.status_code == 200

  def test_alb_has_waf_protection(self, terraform_outputs):
    assert "waf_web_acl_arn" in terraform_outputs

  def test_s3_bucket_configured(self, terraform_outputs):
    assert terraform_outputs["s3_bucket_name"]["value"]


class TestAthenaQueries:
  def test_query_files_exist(self):
    queries_dir = ROOT / "athena" / "queries"
    sql_files = list(queries_dir.glob("*.sql"))
    assert len(sql_files) >= 2
    for f in sql_files:
      content = f.read_text()
      assert "SELECT" in content.upper()
      assert "waf_logs" in content
