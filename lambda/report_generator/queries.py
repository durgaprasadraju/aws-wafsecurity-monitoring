"""WAF security report queries."""

REPORT_QUERIES = {
    "top_attackers": """
        SELECT httprequest.clientip AS client_ip,
               httprequest.country AS country,
               COUNT(*) AS blocked_count
        FROM {database}.waf_logs
        WHERE action = 'BLOCK'
          AND from_unixtime(timestamp/1000) >= date_add('day', -{days}, current_timestamp)
        GROUP BY httprequest.clientip, httprequest.country
        ORDER BY blocked_count DESC
        LIMIT 25
    """,
    "top_countries": """
        SELECT httprequest.country AS country,
               COUNT(*) AS total_requests,
               SUM(CASE WHEN action = 'BLOCK' THEN 1 ELSE 0 END) AS blocked
        FROM {database}.waf_logs
        WHERE from_unixtime(timestamp/1000) >= date_add('day', -{days}, current_timestamp)
        GROUP BY httprequest.country
        ORDER BY blocked DESC
        LIMIT 20
    """,
    "sqli_attempts": """
        SELECT httprequest.clientip AS client_ip,
               httprequest.uri AS uri,
               COUNT(*) AS attempts
        FROM {database}.waf_logs
        WHERE action = 'BLOCK'
          AND (terminatingruleid LIKE '%SQLi%' OR terminatingruleid LIKE '%SQL%')
          AND from_unixtime(timestamp/1000) >= date_add('day', -{days}, current_timestamp)
        GROUP BY httprequest.clientip, httprequest.uri
        ORDER BY attempts DESC
        LIMIT 20
    """,
    "xss_attempts": """
        SELECT httprequest.clientip AS client_ip,
               httprequest.uri AS uri,
               COUNT(*) AS attempts
        FROM {database}.waf_logs
        WHERE action = 'BLOCK'
          AND (terminatingruleid LIKE '%XSS%' OR terminatingruleid LIKE '%BadInputs%')
          AND from_unixtime(timestamp/1000) >= date_add('day', -{days}, current_timestamp)
        GROUP BY httprequest.clientip, httprequest.uri
        ORDER BY attempts DESC
        LIMIT 20
    """,
    "bot_attacks": """
        SELECT httprequest.clientip AS client_ip,
               COUNT(*) AS bot_blocks
        FROM {database}.waf_logs
        WHERE action = 'BLOCK'
          AND terminatingruleid LIKE '%Bot%'
          AND from_unixtime(timestamp/1000) >= date_add('day', -{days}, current_timestamp)
        GROUP BY httprequest.clientip
        ORDER BY bot_blocks DESC
        LIMIT 20
    """,
    "traffic_summary": """
        SELECT
          COUNT(*) AS total_requests,
          SUM(CASE WHEN action = 'BLOCK' THEN 1 ELSE 0 END) AS blocked,
          SUM(CASE WHEN action = 'ALLOW' THEN 1 ELSE 0 END) AS allowed,
          ROUND(100.0 * SUM(CASE WHEN action = 'BLOCK' THEN 1 ELSE 0 END) / COUNT(*), 2) AS block_rate_pct
        FROM {database}.waf_logs
        WHERE from_unixtime(timestamp/1000) >= date_add('day', -{days}, current_timestamp)
    """,
}

REPORT_DAYS = {
    "daily": 1,
    "weekly": 7,
    "monthly": 30,
}
