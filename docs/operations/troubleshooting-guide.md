# Troubleshooting Guide

## WAF Logs Not Appearing in S3

| Check | Command |
|-------|---------|
| WAF logging enabled? | `aws wafv2 get-logging-configuration --resource-arn ACL_ARN` |
| Firehose active? | `aws firehose describe-delivery-stream --delivery-stream-name NAME` |
| Firehose errors? | Check `/aws/kinesisfirehose/` CloudWatch log group |
| S3 permissions? | Verify Firehose IAM role has s3:PutObject |
| KMS? | Verify Firehose role has kms:GenerateDataKey |
| Time delay? | Firehose buffers up to 5 MB or 300 seconds |

## Athena Returns Zero Rows

1. Confirm S3 has data: `aws s3 ls s3://BUCKET/waf-logs/ --recursive | head`
2. Run Glue crawler: `aws glue start-crawler --name CRAWLER`
3. Check partitions: Glue console → table → Partitions tab
4. Use correct partition values in WHERE clause
5. WAF logs are JSON — ensure Glue table uses JsonSerDe

## Lambda Report Fails

```bash
aws logs tail /aws/lambda/FUNCTION_NAME --since 1h
```

Common causes:
- Athena timeout → increase Lambda timeout
- Missing Glue table → run crawler
- SNS not confirmed → check email subscription
- KMS permissions → verify Lambda role policy

## Grafana Shows No Data

1. Check Prometheus targets: `http://IP:9090/targets`
2. Verify CloudWatch exporter running: `curl localhost:9106/metrics`
3. CloudWatch metrics have 2-3 minute delay
4. Check datasource configuration in Grafana

## High Costs

1. Review Athena data scanned per query in CloudWatch
2. Add partition filters to all queries
3. Reduce Glue crawler frequency
4. Check S3 lifecycle transitions are active
5. Review EC2 instance sizes

## EC2 Monitoring Server Not Starting

```bash
# Check user data execution
sudo cat /var/log/cloud-init-output.log
# Check Docker
sudo systemctl status docker
sudo docker compose -f /opt/observability/docker-compose.yml logs
```

## WAF Blocking Legitimate Traffic

1. Identify rule in sampled requests
2. Switch rule to count mode (override action)
3. Create scope-down statement to exclude specific paths
4. Deploy via Terraform WAF module update
