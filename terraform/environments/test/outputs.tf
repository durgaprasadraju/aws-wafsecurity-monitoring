output "alb_dns_name" {
  description = "ALB DNS name for testing WAF"
  value       = module.alb.alb_dns_name
}

output "waf_web_acl_arn" {
  description = "WAF Web ACL ARN"
  value       = module.waf.web_acl_arn
}

output "s3_bucket_name" {
  description = "WAF logs S3 bucket"
  value       = module.s3.bucket_name
}

output "athena_workgroup" {
  description = "Athena workgroup name"
  value       = module.athena.workgroup_name
}

output "glue_database" {
  description = "Glue database name"
  value       = module.glue.database_name
}

output "monitoring_server_ip" {
  description = "Monitoring server public IP"
  value       = module.monitoring.monitoring_server_public_ip
}

output "grafana_url" {
  description = "Grafana URL"
  value       = "http://${module.monitoring.monitoring_server_public_ip}:3000"
}

output "prometheus_url" {
  description = "Prometheus URL"
  value       = "http://${module.monitoring.monitoring_server_public_ip}:9090"
}

output "lambda_function_name" {
  description = "Report generator Lambda function"
  value       = module.lambda.function_name
}

output "firehose_stream_name" {
  description = "Firehose delivery stream"
  value       = module.firehose.delivery_stream_name
}
