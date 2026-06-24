-- Blocked Requests: Recent blocks with details
SELECT date_format(from_unixtime(timestamp/1000), '%Y-%m-%d %H:%i:%s') AS event_time,
       httprequest.clientip AS client_ip,
       httprequest.country AS country,
       httprequest.uri AS uri,
       httprequest.httpmethod AS method,
       terminatingruleid AS rule_id,
       action
FROM waf_security_dev_waf.waf_logs
WHERE action = 'BLOCK'
  AND year = date_format(current_date, '%Y')
  AND month = date_format(current_date, '%m')
  AND day = date_format(current_date, '%d')
ORDER BY timestamp DESC
LIMIT 1000;
