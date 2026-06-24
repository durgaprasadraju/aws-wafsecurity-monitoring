# Cost Estimation

Estimated monthly costs for US East (N. Virginia). Actual costs vary by traffic volume.

## Development Environment (~$150-250/month)

| Service | Configuration | Est. Monthly Cost |
|---------|--------------|-------------------|
| AWS WAF | Web ACL + 5 rule groups | $10 + $1/rule + $0.60/M requests |
| WAF Requests | ~1M requests/month | $5 |
| ALB | 1 ALB, low traffic | $20 |
| S3 | 50 GB logs, IA transition | $5 |
| Firehose | 10 GB/month | $3 |
| Glue Crawler | 4 runs/day | $5 |
| Athena | 50 GB scanned/month | $25 |
| Lambda | 90 invocations/month | $1 |
| SNS | 100 notifications | $1 |
| KMS | 1 CMK + API calls | $2 |
| EC2 Monitoring | t3.medium × 1 | $30 |
| EC2 Agents | t3.micro × 3 | $25 |
| CloudWatch | Dashboards + alarms + logs | $15 |
| Data Transfer | Minimal | $5 |
| **Total** | | **~$150-200** |

## Test Environment (~$200-300/month)

Same as dev with increased Athena scanning and traffic simulation.

## Production Environment (~$500-1500/month)

| Service | Configuration | Est. Monthly Cost |
|---------|--------------|-------------------|
| AWS WAF | + Bot Control | $10 + $10/bot rule + requests |
| WAF Requests | ~10M requests/month | $50 |
| ALB | Higher traffic | $50 |
| S3 | 500 GB logs | $15 |
| Firehose | 100 GB/month | $30 |
| Athena | 500 GB scanned | $250 |
| EC2 Monitoring | t3.large | $60 |
| EC2 Agents | t3.small × 3 | $45 |
| CloudWatch | Enhanced monitoring | $50 |
| **Total** | | **~$600-1200** |

## Cost Optimization Recommendations

1. **Athena**: Use partition filters (year/month/day) in all queries — already implemented
2. **S3 Lifecycle**: Transition to IA at 30 days, Glacier at 60 days — configured
3. **Glue Crawler**: Reduce frequency in dev (every 12h instead of 4h)
4. **Bot Control**: Keep disabled in dev/test (saves ~$10/month + per-request fees)
5. **EC2**: Use Savings Plans or Reserved Instances for prod monitoring server
6. **CloudWatch Logs**: 30-day retention limits log storage costs
7. **Athena Workgroup**: Set bytes scanned cutoff per query in workgroup settings
8. **Firehose**: 5 MB / 300s buffering reduces S3 PUT costs
9. **Grafana**: Self-hosted on EC2 vs AMG saves ~$9+/user/month
10. **Prometheus**: Self-hosted vs AMP saves ~$0.90/10M samples

## Cost Monitoring

```bash
# Enable AWS Cost Explorer tags
# Tag key: Project = waf-security, Environment = dev|test|prod

aws ce get-cost-and-usage \
  --time-period Start=2026-06-01,End=2026-06-30 \
  --granularity MONTHLY \
  --filter '{"Tags":{"Key":"Project","Values":["waf-security"]}}' \
  --metrics BlendedCost \
  --group-by Type=DIMENSION,Key=SERVICE
```
