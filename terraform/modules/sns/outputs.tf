output "security_alerts_topic_arn" {
  value = aws_sns_topic.security_alerts.arn
}

output "reports_topic_arn" {
  value = aws_sns_topic.reports.arn
}
