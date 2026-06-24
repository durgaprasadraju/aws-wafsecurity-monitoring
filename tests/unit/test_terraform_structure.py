"""Validate Terraform configuration structure."""

import os
import re
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
TERRAFORM_ROOT = ROOT / "terraform"
MODULES = TERRAFORM_ROOT / "modules"
ENVIRONMENTS = ["dev", "test", "prod"]

REQUIRED_MODULE_FILES = ["main.tf", "variables.tf", "outputs.tf"]
REQUIRED_MODULES = [
    "waf", "firehose", "s3", "glue", "athena", "lambda",
    "cloudwatch", "sns", "kms", "iam", "monitoring", "vpc", "alb",
]


class TestTerraformStructure:
    @pytest.mark.parametrize("module_name", REQUIRED_MODULES)
    def test_module_exists_with_required_files(self, module_name):
        module_dir = MODULES / module_name
        assert module_dir.is_dir(), f"Module {module_name} not found"
        for fname in REQUIRED_MODULE_FILES:
            assert (module_dir / fname).exists(), f"{module_name}/{fname} missing"

    @pytest.mark.parametrize("env", ENVIRONMENTS)
    def test_environment_has_core_files(self, env):
        env_dir = TERRAFORM_ROOT / "environments" / env
        for fname in ["main.tf", "variables.tf", "outputs.tf"]:
            assert (env_dir / fname).exists(), f"{env}/{fname} missing"

    def test_dev_main_references_all_modules(self):
        content = (TERRAFORM_ROOT / "environments/dev/main.tf").read_text()
        for module in REQUIRED_MODULES:
            assert f'module "{module}"' in content, f"dev main.tf missing module {module}"

    def test_version_constraints(self):
        content = (TERRAFORM_ROOT / "environments/dev/main.tf").read_text()
        assert 'required_version = ">= 1.7"' in content
        assert 'version = ">= 5.0"' in content

    @pytest.mark.parametrize("module_name", REQUIRED_MODULES)
    def test_no_hardcoded_secrets(self, module_name):
        module_dir = MODULES / module_name
        for tf_file in module_dir.glob("*.tf"):
            content = tf_file.read_text()
            assert "AKIA" not in content
            assert not re.search(r'password\s*=\s*"[^$]', content, re.IGNORECASE)
