#!/usr/bin/env bash
# Run ON the monitoring EC2 (as root) to fix empty Grafana dashboards.
# Fixes: datasource UID, CloudWatch exporter, agent scrape ports, Athena datasource.
set -euo pipefail

cd /opt/observability

AWS_REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
PROJECT_NAME=$(aws ec2 describe-tags --region "$AWS_REGION" --filters "Name=resource-id,Values=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)" "Name=key,Values=Project" --query 'Tags[0].Value' --output text)
ENVIRONMENT=$(aws ec2 describe-tags --region "$AWS_REGION" --filters "Name=resource-id,Values=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)" "Name=key,Values=Environment" --query 'Tags[0].Value' --output text)
ATHENA_DATABASE="${PROJECT_NAME//-/_}_${ENVIRONMENT}_waf"
ATHENA_WORKGROUP="${PROJECT_NAME}-${ENVIRONMENT}-waf-analytics"
S3_BUCKET="${PROJECT_NAME}-${ENVIRONMENT}-waf-logs-${ACCOUNT_ID}"

echo "=== Fixing Prometheus agent scrape targets (port 9100) ==="
sed -i 's/- 10\./- /' prometheus/prometheus.yml 2>/dev/null || true
# Ensure agent IPs use :9100
python3 - <<'PY'
from pathlib import Path
import re
p = Path("prometheus/prometheus.yml")
text = p.read_text()
lines = []
in_agents = False
for line in text.splitlines():
    if "node-exporter-agents" in line and "job_name" in line:
        in_agents = True
    elif in_agents and line.strip().startswith("- job_name:"):
        in_agents = False
    if in_agents and re.match(r"\s+- 10\.\d+\.\d+\.\d+$", line):
        line = line.rstrip() + ":9100"
    lines.append(line)
p.write_text("\n".join(lines) + "\n")
PY

echo "=== Fixing Grafana datasource UID ==="
mkdir -p grafana/provisioning/dashboards/json
cat > grafana/provisioning/datasources/datasources.yml <<EOF
apiVersion: 1
datasources:
  - name: Prometheus
    uid: prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: true
  - name: CloudWatch
    uid: cloudwatch
    type: cloudwatch
    access: proxy
    jsonData:
      authType: default
      defaultRegion: ${AWS_REGION}
  - name: Athena
    uid: athena
    type: grafana-athena-datasource
    access: proxy
    jsonData:
      authType: default
      defaultRegion: ${AWS_REGION}
      catalog: AwsDataCatalog
      database: ${ATHENA_DATABASE}
      workgroup: ${ATHENA_WORKGROUP}
      outputLocation: s3://${S3_BUCKET}/athena-results/
EOF

cat > grafana/provisioning/dashboards/dashboards.yml <<'EOF'
apiVersion: 1
providers:
  - name: waf-dashboards
    orgId: 1
    folder: WAF Security
    type: file
    disableDeletion: false
    editable: true
    updateIntervalSeconds: 30
    allowUiUpdates: true
    options:
      path: /etc/grafana/provisioning/dashboards/json
EOF

echo "=== Fixing CloudWatch exporter scrape target ==="
sed -i "s|cloudwatch-exporter:9106|host.docker.internal:9106|g" prometheus/prometheus.yml

echo "=== Restarting stack ==="
docker compose up -d
curl -sf -X POST http://localhost:9090/-/reload || docker compose restart prometheus
docker compose restart grafana cloudwatch-exporter

echo "=== Done. Wait 2 min for Athena plugin + dashboards to load ==="
echo "Dashboard: WAF Log Analytics (Athena) in folder WAF Security"
echo "Verify Athena: Grafana -> Connections -> Data sources -> Athena -> Save & test"
echo "Verify Prometheus: curl -s http://localhost:9090/api/v1/query?query=aws_wafv2_blocked_requests_sum"
