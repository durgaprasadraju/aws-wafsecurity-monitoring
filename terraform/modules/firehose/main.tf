resource "aws_kinesis_firehose_delivery_stream" "waf_logs" {
  # WAF requires delivery stream names to start with aws-waf-logs-
  # https://docs.aws.amazon.com/waf/latest/developerguide/logging-kinesis.html
  name        = "aws-waf-logs-${var.project_name}-${var.environment}"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn            = var.firehose_role_arn
    bucket_arn          = var.s3_bucket_arn
    prefix              = "waf-logs/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/"
    error_output_prefix = "waf-logs-errors/!{firehose:error-output-type}/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/"
    buffering_size      = 5
    buffering_interval  = 300
    compression_format  = "GZIP"

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = aws_cloudwatch_log_group.firehose.name
      log_stream_name = aws_cloudwatch_log_stream.firehose_s3.name
    }

    processing_configuration {
      enabled = false
    }

    s3_backup_mode = "Disabled"
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-waf-firehose"
  })
}

resource "aws_cloudwatch_log_group" "firehose" {
  name              = "/aws/kinesisfirehose/aws-waf-logs-${var.project_name}-${var.environment}"
  retention_in_days = 30
  kms_key_id        = var.kms_key_arn

  tags = var.tags
}

resource "aws_cloudwatch_log_stream" "firehose_s3" {
  name           = "S3Delivery"
  log_group_name = aws_cloudwatch_log_group.firehose.name
}
