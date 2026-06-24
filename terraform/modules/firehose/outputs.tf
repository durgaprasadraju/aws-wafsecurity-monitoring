output "delivery_stream_arn" {
  value = aws_kinesis_firehose_delivery_stream.waf_logs.arn
}

output "delivery_stream_name" {
  value = aws_kinesis_firehose_delivery_stream.waf_logs.name
}

output "log_group_name" {
  value = aws_cloudwatch_log_group.firehose.name
}
