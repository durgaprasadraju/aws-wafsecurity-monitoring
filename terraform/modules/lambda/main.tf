resource "aws_lambda_function" "report_generator" {
  function_name = "${var.project_name}-${var.environment}-waf-report-generator"
  role          = var.lambda_role_arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.12"
  timeout       = 300
  memory_size   = 512

  filename         = var.lambda_zip_path
  source_code_hash = filebase64sha256(var.lambda_zip_path)

  environment {
    variables = {
      ATHENA_WORKGROUP  = var.athena_workgroup
      ATHENA_DATABASE   = var.athena_database
      S3_BUCKET         = var.s3_bucket_name
      SNS_TOPIC_ARN     = var.sns_topic_arn
      ENVIRONMENT       = var.environment
      PROJECT_NAME      = var.project_name
      LOG_LEVEL         = "INFO"
    }
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-report-generator"
  })
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${aws_lambda_function.report_generator.function_name}"
  retention_in_days = 30
  kms_key_id        = var.kms_key_arn

  tags = var.tags
}

resource "aws_cloudwatch_event_rule" "daily_report" {
  name                = "${var.project_name}-${var.environment}-daily-report"
  description         = "Trigger daily WAF security report"
  schedule_expression = var.report_schedule_daily

  tags = var.tags
}

resource "aws_cloudwatch_event_rule" "weekly_report" {
  name                = "${var.project_name}-${var.environment}-weekly-report"
  description         = "Trigger weekly WAF security report"
  schedule_expression = var.report_schedule_weekly

  tags = var.tags
}

resource "aws_cloudwatch_event_rule" "monthly_report" {
  name                = "${var.project_name}-${var.environment}-monthly-report"
  description         = "Trigger monthly WAF security report"
  schedule_expression = var.report_schedule_monthly

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "daily_report" {
  rule      = aws_cloudwatch_event_rule.daily_report.name
  target_id = "daily-report-lambda"
  arn       = aws_lambda_function.report_generator.arn

  input = jsonencode({ report_type = "daily" })
}

resource "aws_cloudwatch_event_target" "weekly_report" {
  rule      = aws_cloudwatch_event_rule.weekly_report.name
  target_id = "weekly-report-lambda"
  arn       = aws_lambda_function.report_generator.arn

  input = jsonencode({ report_type = "weekly" })
}

resource "aws_cloudwatch_event_target" "monthly_report" {
  rule      = aws_cloudwatch_event_rule.monthly_report.name
  target_id = "monthly-report-lambda"
  arn       = aws_lambda_function.report_generator.arn

  input = jsonencode({ report_type = "monthly" })
}

resource "aws_lambda_permission" "eventbridge_daily" {
  statement_id  = "AllowEventBridgeDaily"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.report_generator.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.daily_report.arn
}

resource "aws_lambda_permission" "eventbridge_weekly" {
  statement_id  = "AllowEventBridgeWeekly"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.report_generator.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.weekly_report.arn
}

resource "aws_lambda_permission" "eventbridge_monthly" {
  statement_id  = "AllowEventBridgeMonthly"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.report_generator.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.monthly_report.arn
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${var.project_name}-${var.environment}-lambda-report-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "WAF report Lambda function errors"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.report_generator.function_name
  }

  tags = var.tags
}
