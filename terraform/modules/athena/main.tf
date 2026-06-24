resource "aws_athena_workgroup" "waf" {
  name = "${var.project_name}-${var.environment}-waf-analytics"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    result_configuration {
      output_location = "s3://${var.s3_results_bucket}/athena-results/"

      encryption_configuration {
        encryption_option = "SSE_KMS"
        kms_key_arn       = var.kms_key_arn
      }
    }

    engine_version {
      selected_engine_version = "Athena engine version 3"
    }
  }

  tags = var.tags
}

locals {
  queries = {
    top_attackers = <<-SQL
      SELECT httprequest.clientip AS client_ip,
             httprequest.country AS country,
             COUNT(*) AS blocked_count
      FROM ${var.database_name}.waf_logs
      WHERE action = 'BLOCK'
        AND year = date_format(current_date, '%Y')
        AND month = date_format(current_date, '%m')
      GROUP BY httprequest.clientip, httprequest.country
      ORDER BY blocked_count DESC
      LIMIT 50
    SQL

    top_countries = <<-SQL
      SELECT httprequest.country AS country,
             COUNT(*) AS request_count,
             SUM(CASE WHEN action = 'BLOCK' THEN 1 ELSE 0 END) AS blocked_count
      FROM ${var.database_name}.waf_logs
      WHERE year = date_format(current_date, '%Y')
        AND month = date_format(current_date, '%m')
      GROUP BY httprequest.country
      ORDER BY blocked_count DESC
      LIMIT 30
    SQL

    blocked_requests = <<-SQL
      SELECT date_format(from_unixtime(timestamp/1000), '%Y-%m-%d %H:%i') AS event_time,
             httprequest.clientip AS client_ip,
             httprequest.uri AS uri,
             terminatingruleid AS rule_id,
             action
      FROM ${var.database_name}.waf_logs
      WHERE action = 'BLOCK'
        AND year = date_format(current_date, '%Y')
        AND month = date_format(current_date, '%m')
        AND day = date_format(current_date, '%d')
      ORDER BY timestamp DESC
      LIMIT 1000
    SQL

    sqli_analysis = <<-SQL
      SELECT httprequest.clientip AS client_ip,
             httprequest.uri AS uri,
             terminatingruleid AS rule_id,
             COUNT(*) AS sqli_attempts
      FROM ${var.database_name}.waf_logs
      WHERE action = 'BLOCK'
        AND (terminatingruleid LIKE '%SQLi%' OR terminatingruleid LIKE '%SQL%')
        AND year = date_format(current_date, '%Y')
        AND month = date_format(current_date, '%m')
      GROUP BY httprequest.clientip, httprequest.uri, terminatingruleid
      ORDER BY sqli_attempts DESC
      LIMIT 100
    SQL

    xss_analysis = <<-SQL
      SELECT httprequest.clientip AS client_ip,
             httprequest.uri AS uri,
             terminatingruleid AS rule_id,
             COUNT(*) AS xss_attempts
      FROM ${var.database_name}.waf_logs
      WHERE action = 'BLOCK'
        AND (terminatingruleid LIKE '%XSS%' OR terminatingruleid LIKE '%BadInputs%')
        AND year = date_format(current_date, '%Y')
        AND month = date_format(current_date, '%m')
      GROUP BY httprequest.clientip, httprequest.uri, terminatingruleid
      ORDER BY xss_attempts DESC
      LIMIT 100
    SQL

    bot_analysis = <<-SQL
      SELECT httprequest.clientip AS client_ip,
             httprequest.httpmethod AS method,
             COUNT(*) AS bot_requests
      FROM ${var.database_name}.waf_logs
      WHERE action = 'BLOCK'
        AND terminatingruleid LIKE '%Bot%'
        AND year = date_format(current_date, '%Y')
        AND month = date_format(current_date, '%m')
      GROUP BY httprequest.clientip, httprequest.httpmethod
      ORDER BY bot_requests DESC
      LIMIT 100
    SQL

    top_uris = <<-SQL
      SELECT httprequest.uri AS uri,
             COUNT(*) AS total_requests,
             SUM(CASE WHEN action = 'BLOCK' THEN 1 ELSE 0 END) AS blocked
      FROM ${var.database_name}.waf_logs
      WHERE year = date_format(current_date, '%Y')
        AND month = date_format(current_date, '%m')
      GROUP BY httprequest.uri
      ORDER BY blocked DESC
      LIMIT 50
    SQL

    hourly_trends = <<-SQL
      SELECT date_format(from_unixtime(timestamp/1000), '%Y-%m-%d %H:00') AS hour,
             COUNT(*) AS total,
             SUM(CASE WHEN action = 'BLOCK' THEN 1 ELSE 0 END) AS blocked
      FROM ${var.database_name}.waf_logs
      WHERE year = date_format(current_date, '%Y')
        AND month = date_format(current_date, '%m')
        AND day = date_format(current_date, '%d')
      GROUP BY 1
      ORDER BY 1
    SQL

    daily_trends = <<-SQL
      SELECT date_format(from_unixtime(timestamp/1000), '%Y-%m-%d') AS day,
             COUNT(*) AS total,
             SUM(CASE WHEN action = 'BLOCK' THEN 1 ELSE 0 END) AS blocked
      FROM ${var.database_name}.waf_logs
      WHERE year = date_format(current_date, '%Y')
        AND month = date_format(current_date, '%m')
      GROUP BY 1
      ORDER BY 1
    SQL

    weekly_trends = <<-SQL
      SELECT date_format(date_trunc('week', from_unixtime(timestamp/1000)), '%Y-%m-%d') AS week_start,
             COUNT(*) AS total,
             SUM(CASE WHEN action = 'BLOCK' THEN 1 ELSE 0 END) AS blocked
      FROM ${var.database_name}.waf_logs
      WHERE from_unixtime(timestamp/1000) >= date_add('day', -90, current_date)
      GROUP BY 1
      ORDER BY 1
    SQL

    monthly_trends = <<-SQL
      SELECT date_format(from_unixtime(timestamp/1000), '%Y-%m') AS month,
             COUNT(*) AS total,
             SUM(CASE WHEN action = 'BLOCK' THEN 1 ELSE 0 END) AS blocked
      FROM ${var.database_name}.waf_logs
      WHERE from_unixtime(timestamp/1000) >= date_add('month', -12, current_date)
      GROUP BY 1
      ORDER BY 1
    SQL
  }
}

resource "aws_athena_named_query" "queries" {
  for_each = local.queries

  name        = "${var.project_name}-${var.environment}-${replace(each.key, "_", "-")}"
  database    = var.database_name
  workgroup   = aws_athena_workgroup.waf.name
  description = "WAF analytics: ${each.key}"
  query       = each.value
}
