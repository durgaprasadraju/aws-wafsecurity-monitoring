#!/bin/bash
# EC2 user-data: install Prometheus, Grafana, Alertmanager on monitoring server.
set -eo pipefail

PROJECT_NAME="${project_name}"
ALB_DNS="${alb_dns_name}"
ENVIRONMENT="${environment}"
AWS_REGION="${aws_region}"
ACCOUNT_ID="${account_id}"

exec > /var/log/waf-monitoring-setup.log 2>&1
echo "=== WAF Monitoring setup started at $(date) ==="

dnf install -y docker git jq awscli tar
systemctl enable --now docker

COMPOSE_VERSION="2.24.6"
mkdir -p /usr/local/lib/docker/cli-plugins
curl -fsSL "https://github.com/docker/compose/releases/download/v$${COMPOSE_VERSION}/docker-compose-linux-x86_64" \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
docker compose version

NODE_EXPORTER_VERSION="1.7.0"
curl -fsSL "https://github.com/prometheus/node_exporter/releases/download/v$${NODE_EXPORTER_VERSION}/node_exporter-$${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz" | tar xz
mv "node_exporter-$${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter" /usr/local/bin/
cat > /etc/systemd/system/node_exporter.service <<'UNIT'
[Unit]
Description=Node Exporter
After=network.target
[Service]
ExecStart=/usr/local/bin/node_exporter
Restart=always
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now node_exporter

mkdir -p /opt/observability/{prometheus/rules,grafana/provisioning/datasources,alertmanager,exporters}
cd /opt/observability

# Wait for agent nodes to register
sleep 90
AGENT_IPS=$(aws ec2 describe-instances \
  --region "$AWS_REGION" \
  --filters "Name=tag:Project,Values=$PROJECT_NAME" "Name=tag:Role,Values=node-exporter" "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].PrivateIpAddress' \
  --output text | tr '\t' '\n' | sed 's/^/        - /' | sed 's/$/:9100/')

cat > prometheus/prometheus.yml <<PROM
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    environment: '$ENVIRONMENT'
    project: '$PROJECT_NAME'

rule_files:
  - /etc/prometheus/rules/*.yml

alerting:
  alertmanagers:
    - static_configs:
        - targets: ['alertmanager:9093']

scrape_configs:
  - job_name: prometheus
    static_configs:
      - targets: ['prometheus:9090']

  - job_name: node-exporter-agents
    static_configs:
      - targets:
$AGENT_IPS

  - job_name: node-exporter-local
    static_configs:
      - targets: ['host.docker.internal:9100']

  - job_name: cloudwatch-exporter
    static_configs:
      - targets: ['host.docker.internal:9106']

  - job_name: blackbox-alb
    metrics_path: /probe
    params:
      module: [http_2xx]
    static_configs:
      - targets: ['http://$ALB_DNS']
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: blackbox-exporter:9115
PROM

cat > exporters/cloudwatch-config.yml <<CW
region: $AWS_REGION
use_get_metric_data: true
metrics:
  - aws_namespace: AWS/WAFV2
    aws_metric_name: BlockedRequests
    aws_dimensions: [Region, Rule, WebACL]
    aws_dimension_select:
      WebACL: ["${project_name}-${environment}-web-acl"]
      Region: ["$AWS_REGION"]
    aws_statistics: [Sum]
    range_seconds: 300
    period_seconds: 60
    delay_seconds: 120
  - aws_namespace: AWS/WAFV2
    aws_metric_name: AllowedRequests
    aws_dimensions: [Region, Rule, WebACL]
    aws_dimension_select:
      WebACL: ["${project_name}-${environment}-web-acl"]
      Region: ["$AWS_REGION"]
    aws_statistics: [Sum]
    range_seconds: 300
    period_seconds: 60
    delay_seconds: 120
  - aws_namespace: AWS/Firehose
    aws_metric_name: DeliveryToS3.Success
    aws_dimensions: [DeliveryStreamName]
    aws_dimension_select:
      DeliveryStreamName: ["aws-waf-logs-${project_name}-${environment}"]
    aws_statistics: [Average]
    range_seconds: 300
    period_seconds: 60
CW

cat > grafana/provisioning/datasources/datasources.yml <<GRAFANA
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
      defaultRegion: $AWS_REGION
GRAFANA

cat > alertmanager/alertmanager.yml <<'AM'
global:
  resolve_timeout: 5m
route:
  receiver: default
  group_by: ['alertname']
  group_wait: 30s
  repeat_interval: 4h
receivers:
  - name: default
AM

cat > docker-compose.yml <<'COMPOSE'
services:
  prometheus:
    image: prom/prometheus:v2.51.0
    ports: ["9090:9090"]
    extra_hosts:
      - "host.docker.internal:host-gateway"
    volumes:
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml
      - ./prometheus/rules:/etc/prometheus/rules
      - prometheus-data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.retention.time=30d'
      - '--web.enable-lifecycle'
    restart: always

  grafana:
    image: grafana/grafana:10.4.0
    ports: ["3000:3000"]
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=ChangeMe123!
      - GF_USERS_ALLOW_SIGN_UP=false
      - GF_SERVER_HTTP_ADDR=0.0.0.0
    volumes:
      - grafana-data:/var/lib/grafana
      - ./grafana/provisioning:/etc/grafana/provisioning
    restart: always
    depends_on:
      - prometheus

  alertmanager:
    image: prom/alertmanager:v0.27.0
    ports: ["9093:9093"]
    volumes:
      - ./alertmanager/alertmanager.yml:/etc/alertmanager/alertmanager.yml
    restart: always

  cloudwatch-exporter:
    image: prom/cloudwatch-exporter:latest
    network_mode: host
    volumes:
      - ./exporters/cloudwatch-config.yml:/config/config.yml
    restart: always

  blackbox-exporter:
    image: prom/blackbox-exporter:v0.25.0
    ports: ["9115:9115"]
    restart: always

volumes:
  prometheus-data:
  grafana-data:
COMPOSE

docker compose version
docker compose up -d

echo "=== Waiting for Grafana to start ==="
for i in $(seq 1 30); do
  if curl -sf http://localhost:3000/login >/dev/null 2>&1; then
    echo "Grafana is up after $${i}0 seconds"
    exit 0
  fi
  sleep 10
done

echo "ERROR: Grafana did not start within 5 minutes"
docker compose ps
docker compose logs grafana --tail 50
exit 1
