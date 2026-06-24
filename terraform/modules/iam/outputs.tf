output "firehose_role_arn" {
  value = aws_iam_role.firehose.arn
}

output "waf_logging_role_arn" {
  value = aws_iam_role.waf_logging.arn
}

output "lambda_report_role_arn" {
  value = aws_iam_role.lambda_report.arn
}

output "glue_crawler_role_arn" {
  value = aws_iam_role.glue_crawler.arn
}

output "ec2_monitoring_instance_profile_name" {
  value = aws_iam_instance_profile.ec2_monitoring.name
}

output "ec2_monitoring_role_arn" {
  value = aws_iam_role.ec2_monitoring.arn
}
