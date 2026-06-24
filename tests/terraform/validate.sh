#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENV="${1:-dev}"
ENV_DIR="$ROOT/terraform/environments/$ENV"

echo "=== Terraform Validation: $ENV ==="

for module in "$ROOT/terraform/modules"/*/; do
  echo "Validating module: $(basename "$module")"
  terraform -chdir="$module" init -backend=false -input=false >/dev/null
  terraform -chdir="$module" validate
done

echo "Validating environment: $ENV"
terraform -chdir="$ENV_DIR" init -backend=false -input=false >/dev/null
terraform -chdir="$ENV_DIR" validate
terraform -chdir="$ENV_DIR" fmt -check -recursive

echo "=== All validations passed ==="
