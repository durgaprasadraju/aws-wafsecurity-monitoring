resource "aws_cloudwatch_dashboard" "waf_security" {
  dashboard_name = "${var.project_name}-${var.environment}-waf-security"

  dashboard_body = var.dashboard_json_path != "" ? file(var.dashboard_json_path) : jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "Blocked Requests"
          region = data.aws_region.current.region
          metrics = [
            ["AWS/WAFV2", "BlockedRequests", "WebACL", var.web_acl_name, "Region", data.aws_region.current.region, "Rule", "ALL"],
            [".", "AllowedRequests", ".", ".", ".", ".", ".", "."]
          ]
          period = 300
          stat   = "Sum"
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "Rate Limit Rule"
          region = data.aws_region.current.region
          metrics = [
            ["AWS/WAFV2", "BlockedRequests", "WebACL", var.web_acl_name, "Region", data.aws_region.current.region, "Rule", "RateLimitRule"]
          ]
          period = 300
          stat   = "Sum"
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "SQLi Rule Blocks"
          region = data.aws_region.current.region
          metrics = [
            ["AWS/WAFV2", "BlockedRequests", "WebACL", var.web_acl_name, "Region", data.aws_region.current.region, "Rule", "AWSManagedRulesSQLiRuleSet"]
          ]
          period = 300
          stat   = "Sum"
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Bot Control Blocks"
          region = data.aws_region.current.region
          metrics = [
            ["AWS/WAFV2", "BlockedRequests", "WebACL", var.web_acl_name, "Region", data.aws_region.current.region, "Rule", "AWSManagedRulesBotControlRuleSet"]
          ]
          period = 300
          stat   = "Sum"
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 12
        height = 6
        properties = {
          title  = "Firehose Delivery"
          region = data.aws_region.current.region
          metrics = [
            ["AWS/Firehose", "DeliveryToS3.Success", "DeliveryStreamName", var.firehose_name],
            [".", "DeliveryToS3.DataFreshness", ".", "."]
          ]
          period = 300
          stat   = "Average"
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 12
        width  = 12
        height = 6
        properties = {
          title  = "Lambda Report Errors"
          region = data.aws_region.current.region
          metrics = [
            ["AWS/Lambda", "Errors", "FunctionName", var.lambda_function_name],
            [".", "Duration", ".", "."]
          ]
          period = 300
          stat   = "Sum"
          view   = "timeSeries"
        }
      }
    ]
  })
}

resource "aws_cloudwatch_metric_alarm" "high_block_rate" {
  alarm_name          = "${var.project_name}-${var.environment}-high-block-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "BlockedRequests"
  namespace           = "AWS/WAFV2"
  period              = 300
  statistic           = "Sum"
  threshold           = 1000
  alarm_description   = "High WAF block rate detected"
  treat_missing_data  = "notBreaching"

  dimensions = {
    WebACL = var.web_acl_name
    Region = data.aws_region.current.region
    Rule   = "ALL"
  }

  alarm_actions = [var.sns_topic_arn]

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "sqli_surge" {
  alarm_name          = "${var.project_name}-${var.environment}-sqli-surge"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "BlockedRequests"
  namespace           = "AWS/WAFV2"
  period              = 300
  statistic           = "Sum"
  threshold           = 100
  alarm_description   = "SQL injection attack surge detected"
  treat_missing_data  = "notBreaching"

  dimensions = {
    WebACL = var.web_acl_name
    Region = data.aws_region.current.region
    Rule   = "AWSManagedRulesSQLiRuleSet"
  }

  alarm_actions = [var.sns_topic_arn]

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "firehose_failures" {
  alarm_name          = "${var.project_name}-${var.environment}-firehose-failures"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "DeliveryToS3.Success"
  namespace           = "AWS/Firehose"
  period              = 300
  statistic           = "Average"
  threshold           = 0.95
  alarm_description   = "Firehose delivery success rate below 95%"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DeliveryStreamName = var.firehose_name
  }

  alarm_actions = [var.sns_topic_arn]

  tags = var.tags
}

data "aws_region" "current" {}
