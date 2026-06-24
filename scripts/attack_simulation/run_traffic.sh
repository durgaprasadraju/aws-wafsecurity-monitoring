#!/usr/bin/env bash
# Generate WAF test traffic against the deployed ALB.
# Usage: ./run_traffic.sh [ALB_URL]
#   ALB_URL optional — auto-detected from terraform output if omitted.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENV_DIR="$ROOT/terraform/environments/dev"

if [[ $# -ge 1 ]]; then
  ALB_URL="$1"
else
  if [[ ! -d "$ENV_DIR/.terraform" ]]; then
    echo "Usage: $0 http://your-alb-dns-name"
    echo "   or: cd terraform/environments/dev && terraform apply, then re-run"
    exit 1
  fi
  ALB_DNS=$(terraform -chdir="$ENV_DIR" output -raw alb_dns_name)
  ALB_URL="http://${ALB_DNS}"
fi

# Strip trailing slash for consistency
ALB_URL="${ALB_URL%/}"

echo "=============================================="
echo " WAF Traffic Generator"
echo " Target: $ALB_URL"
echo "=============================================="
echo

echo "--- Normal traffic (curl) ---"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$ALB_URL/" || true)
echo "GET / -> HTTP $HTTP_CODE (expect 200)"
echo

echo "--- SQLi simulation (20 requests) ---"
python3 "$SCRIPT_DIR/simulate_sqli.py" --url "$ALB_URL" --count 20 --delay 0.3
echo

echo "--- XSS simulation (20 requests) ---"
python3 "$SCRIPT_DIR/simulate_xss.py" --url "$ALB_URL" --count 20 --delay 0.3
echo

echo "--- Bot simulation (50 requests) ---"
python3 "$SCRIPT_DIR/simulate_bot_attack.py" --url "$ALB_URL" --count 50 --workers 10
echo

echo "--- Rate limit simulation (100 requests) ---"
python3 "$SCRIPT_DIR/simulate_rate_limit_attack.py" --url "$ALB_URL" --count 100 --workers 50
echo

echo "=============================================="
echo " Done. WAF logs arrive in S3 after 5-10 min."
echo " Check: aws s3 ls s3://BUCKET/waf-logs/ --recursive"
echo "=============================================="
