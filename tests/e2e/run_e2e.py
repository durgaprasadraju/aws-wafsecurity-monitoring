"""End-to-end test workflow automation."""

import json
import os
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def run_cmd(cmd: list[str], cwd: str | None = None) -> int:
    print(f"  $ {' '.join(cmd)}")
    return subprocess.call(cmd, cwd=cwd)


def main() -> int:
    env = os.environ.get("E2E_ENV", "dev")
    env_dir = ROOT / "terraform" / "environments" / env

    print("=== E2E Test Workflow ===\n")

    print("[1/8] Terraform Validate")
    if run_cmd(["bash", str(ROOT / "tests/terraform/validate.sh"), env]) != 0:
        return 1

    if os.environ.get("E2E_DEPLOY", "false") != "true":
        print("\nSkipping deploy steps (set E2E_DEPLOY=true to run full e2e)")
        print("[2/8] Unit Tests")
        return run_cmd([sys.executable, "-m", "pytest", "tests/unit/", "-v"], cwd=str(ROOT))

    print("\n[2/8] Terraform Apply")
    if run_cmd(["terraform", "apply", "-auto-approve"], cwd=str(env_dir)) != 0:
        return 1

    print("\n[3/8] Get Outputs")
    result = subprocess.run(
        ["terraform", "output", "-json"],
        cwd=str(env_dir),
        capture_output=True,
        text=True,
    )
    outputs = json.loads(result.stdout)
    alb_dns = outputs["alb_dns_name"]["value"]
    alb_url = f"http://{alb_dns}"

    print(f"\n[4/8] Generate Traffic → {alb_url}")
    scripts = [
        ["python", str(ROOT / "scripts/attack_simulation/simulate_sqli.py"), "--url", alb_url, "--count", "10"],
        ["python", str(ROOT / "scripts/attack_simulation/simulate_xss.py"), "--url", alb_url, "--count", "10"],
    ]
    for cmd in scripts:
        run_cmd(cmd)

    print("\n[5/8] Wait for log pipeline (5 min)")
    time.sleep(300)

    print("\n[6/8] Verify S3 logs")
    bucket = outputs["s3_bucket_name"]["value"]
    if run_cmd(["aws", "s3", "ls", f"s3://{bucket}/waf-logs/", "--recursive"]) != 0:
        print("WARNING: No S3 logs found yet")

    print("\n[7/8] Run Glue Crawler")
    run_cmd(["aws", "glue", "start-crawler", "--name", "waf-security-dev-waf-logs-crawler"])

    print("\n[8/8] Unit + Integration Tests")
    os.environ["SKIP_INTEGRATION"] = "false"
    os.environ["TF_OUTPUTS_FILE"] = "/tmp/tf-outputs.json"
    Path(os.environ["TF_OUTPUTS_FILE"]).write_text(result.stdout)
    return run_cmd([sys.executable, "-m", "pytest", "tests/", "-v", "-m", "not slow"], cwd=str(ROOT))


if __name__ == "__main__":
    sys.exit(main())
