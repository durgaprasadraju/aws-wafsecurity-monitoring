#!/usr/bin/env python3
"""Simulate rate limit abuse against WAF-protected endpoint."""

import argparse
import concurrent.futures
import urllib.request


def fetch(url: str) -> int:
    req = urllib.request.Request(url, headers={"User-Agent": "WAF-Simulator/RateLimit"})
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            return resp.status
    except urllib.error.HTTPError as e:
        return e.code
    except Exception:
        return 0


def main():
    parser = argparse.ArgumentParser(description="Simulate rate limit abuse")
    parser.add_argument("--url", required=True)
    parser.add_argument("--count", type=int, default=500)
    parser.add_argument("--workers", type=int, default=50)
    args = parser.parse_args()

    print(f"Rate limit simulation: {args.count} rapid requests from single IP pattern")
    results = {"403": 0, "200": 0, "other": 0}
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
        statuses = list(pool.map(fetch, [args.url] * args.count))
    for s in statuses:
        if s == 403:
            results["403"] += 1
        elif s == 200:
            results["200"] += 1
        else:
            results["other"] += 1
    print(f"Results: {results}")


if __name__ == "__main__":
    main()
