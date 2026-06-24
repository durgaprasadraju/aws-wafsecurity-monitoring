#!/usr/bin/env python3
"""Package Lambda function for deployment."""

import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LAMBDA_SRC = ROOT / "lambda" / "report_generator"
BUILD_DIR = ROOT / "terraform" / "environments" / "dev" / ".build"
OUTPUT_ZIP = BUILD_DIR / "report_generator.zip"


def main() -> int:
    BUILD_DIR.mkdir(parents=True, exist_ok=True)
    staging = BUILD_DIR / "package"
    if staging.exists():
        shutil.rmtree(staging)
    staging.mkdir()

    for py_file in LAMBDA_SRC.glob("*.py"):
        shutil.copy(py_file, staging / py_file.name)

    subprocess.run(
        ["pip", "install", "-r", str(LAMBDA_SRC / "requirements.txt"), "-t", str(staging), "-q"],
        check=True,
    )

    if OUTPUT_ZIP.exists():
        OUTPUT_ZIP.unlink()

    shutil.make_archive(str(OUTPUT_ZIP.with_suffix("")), "zip", staging)
    print(f"Built {OUTPUT_ZIP}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
