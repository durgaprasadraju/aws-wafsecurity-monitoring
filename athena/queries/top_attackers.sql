-- Top Attackers: IPs with most blocked requests
SELECT httprequest.clientip AS client_ip,
       httprequest.country AS country,
       COUNT(*) AS blocked_count
FROM waf_security_dev_waf.waf_logs
WHERE action = 'BLOCK'
  AND year = date_format(current_date, '%Y')
  AND month = date_format(current_date, '%m')
GROUP BY httprequest.clientip, httprequest.country
ORDER BY blocked_count DESC
LIMIT 50;
