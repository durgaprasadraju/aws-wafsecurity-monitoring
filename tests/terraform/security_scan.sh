#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "=== Security Scans ==="

if command -v tfsec &>/dev/null; then
  echo "Running tfsec..."
  tfsec "$ROOT/terraform" --minimum-severity MEDIUM || true
fi

if command -v checkov &>/dev/null; then
  echo "Running checkov..."
  checkov -d "$ROOT/terraform" --quiet || true
fi

if command -v bandit &>/dev/null; then
  echo "Running bandit..."
  bandit -r "$ROOT/lambda" -ll || true
fi

echo "=== Scans complete ==="
