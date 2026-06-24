#!/usr/bin/env bash
# Run ON the monitoring EC2 (as root) to fix empty Grafana dashboards.
# Fixes: datasource UID, CloudWatch exporter, agent scrape ports.
set -euo pipefail

cd /opt/observability

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
cat > grafana/provisioning/datasources/datasources.yml <<'EOF'
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
      defaultRegion: us-west-2
EOF

echo "=== Fixing CloudWatch exporter scrape target ==="
sed -i "s|cloudwatch-exporter:9106|host.docker.internal:9106|g" prometheus/prometheus.yml

echo "=== Restarting stack ==="
docker compose up -d
curl -sf -X POST http://localhost:9090/-/reload || docker compose restart prometheus
docker compose restart grafana cloudwatch-exporter

echo "=== Done. Wait 2 min, then re-import dashboards in Grafana UI ==="
echo "Verify: curl -s http://localhost:9090/api/v1/query?query=aws_wafv2_blocked_requests_sum"
