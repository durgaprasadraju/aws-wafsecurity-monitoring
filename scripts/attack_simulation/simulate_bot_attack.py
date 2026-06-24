#!/usr/bin/env python3
"""Simulate bot attack traffic against WAF-protected endpoint."""

import argparse
import concurrent.futures
import time
import urllib.request

BOT_USER_AGENTS = [
    "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)",
    "Mozilla/5.0 (compatible; bingbot/2.0; +http://www.bing.com/bingbot.htm)",
    "python-requests/2.31.0",
    "curl/8.4.0",
    "Scrapy/2.11.0 (+https://scrapy.org)",
    "Mozilla/5.0 (compatible; AhrefsBot/7.0; +http://ahrefs.com/robot/)",
    "SemrushBot/7~bl",
    "MJ12bot/v1.4.8",
]


def fetch(url: str, ua: str) -> int:
    req = urllib.request.Request(url, headers={"User-Agent": ua})
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            return resp.status
    except urllib.error.HTTPError as e:
        return e.code
    except Exception:
        return 0


def main():
    parser = argparse.ArgumentParser(description="Simulate bot attacks")
    parser.add_argument("--url", required=True)
    parser.add_argument("--count", type=int, default=100)
    parser.add_argument("--workers", type=int, default=10)
    args = parser.parse_args()

    print(f"Bot simulation: {args.count} requests, {args.workers} workers")
    blocked = 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
        futures = []
        for i in range(args.count):
            ua = BOT_USER_AGENTS[i % len(BOT_USER_AGENTS)]
            futures.append(pool.submit(fetch, args.url, ua))
        for i, f in enumerate(concurrent.futures.as_completed(futures)):
            status = f.result()
            if status in (403, 0):
                blocked += 1
            if (i + 1) % 20 == 0:
                print(f"Progress: {i+1}/{args.count}")
    print(f"Complete: {blocked}/{args.count} likely blocked")


if __name__ == "__main__":
    main()
