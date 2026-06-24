#!/usr/bin/env bash
# Verify WAF logging is wired to the correct Firehose stream.
set -euo pipefail

REGION="${AWS_REGION:-us-west-2}"
PROJECT="${PROJECT_NAME:-waf-security}"
ENV="${ENVIRONMENT:-dev}"
WEB_ACL_NAME="${PROJECT}-${ENV}-web-acl"
EXPECTED_STREAM="aws-waf-logs-${PROJECT}-${ENV}"

echo "Region:          $REGION"
echo "Expected stream: $EXPECTED_STREAM"
echo

WEB_ACL_ARN=$(aws wafv2 list-web-acls --scope REGIONAL --region "$REGION" \
  --query "WebACLs[?Name=='${WEB_ACL_NAME}'].ARN | [0]" --output text)

if [[ -z "$WEB_ACL_ARN" || "$WEB_ACL_ARN" == "None" ]]; then
  echo "ERROR: Web ACL '$WEB_ACL_NAME' not found"
  exit 1
fi

echo "Web ACL ARN: $WEB_ACL_ARN"

LOGGING=$(aws wafv2 get-logging-configuration --resource-arn "$WEB_ACL_ARN" --region "$REGION" 2>/dev/null || true)
if [[ -z "$LOGGING" ]]; then
  echo "ERROR: WAF logging is NOT enabled. Run: cd terraform/environments/dev && terraform apply"
  exit 1
fi

DEST=$(echo "$LOGGING" | jq -r '.LoggingConfiguration.LogDestinationConfigs[0]')
echo "WAF log destination: $DEST"

if [[ "$DEST" != *"deliverystream/${EXPECTED_STREAM}" ]]; then
  echo "ERROR: WAF points to wrong stream. Expected *deliverystream/${EXPECTED_STREAM}"
  exit 1
fi

STREAM_STATUS=$(aws firehose describe-delivery-stream \
  --delivery-stream-name "$EXPECTED_STREAM" --region "$REGION" \
  --query 'DeliveryStreamDescription.DeliveryStreamStatus' --output text 2>/dev/null || echo "NOT_FOUND")

echo "Firehose status: $STREAM_STATUS"

if [[ "$STREAM_STATUS" != "ACTIVE" ]]; then
  echo "ERROR: Firehose stream '$EXPECTED_STREAM' is not ACTIVE"
  exit 1
fi

echo
echo "OK: WAF logging is correctly configured to Firehose stream '$EXPECTED_STREAM'"
