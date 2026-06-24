#!/bin/bash
# Agent EC2: install node_exporter for Prometheus scraping.
set -eo pipefail

exec > /var/log/waf-agent-setup.log 2>&1
echo "=== Agent node_exporter setup started at $(date) ==="

dnf install -y tar
NODE_EXPORTER_VERSION="1.7.0"
curl -fsSL "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz" | tar xz
mv "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter" /usr/local/bin/

cat > /etc/systemd/system/node_exporter.service <<'UNIT'
[Unit]
Description=Node Exporter
After=network.target
[Service]
ExecStart=/usr/local/bin/node_exporter --web.listen-address=:9100
Restart=always
[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now node_exporter
echo "=== Agent setup complete ==="
