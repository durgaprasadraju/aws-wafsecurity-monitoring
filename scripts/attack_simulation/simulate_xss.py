#!/usr/bin/env python3
"""Simulate XSS attacks against WAF-protected endpoint."""

import argparse
import random
import time
import urllib.parse
import urllib.request

XSS_PAYLOADS = [
    "<script>alert('XSS')</script>",
    "<img src=x onerror=alert(1)>",
    "javascript:alert(document.cookie)",
    "<svg onload=alert(1)>",
    "<body onload=alert('XSS')>",
    "'\"><script>alert(String.fromCharCode(88,83,83))</script>",
    "<iframe src=javascript:alert(1)>",
    "<input onfocus=alert(1) autofocus>",
    "<marquee onstart=alert(1)>",
    "<details open ontoggle=alert(1)>",
]

PATHS = ["/comment", "/search", "/profile", "/feedback", "/api/render"]


def send_request(base_url: str, path: str, payload: str) -> int:
    params = urllib.parse.urlencode({"comment": payload, "name": payload, "q": payload})
    url = f"{base_url.rstrip('/')}{path}?{params}"
    req = urllib.request.Request(url, headers={"User-Agent": "WAF-Simulator/XSS"})
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            return resp.status
    except urllib.error.HTTPError as e:
        return e.code
    except Exception:
        return 0


def main():
    parser = argparse.ArgumentParser(description="Simulate XSS attacks for WAF log generation")
    parser.add_argument("--url", required=True, help="Target ALB URL")
    parser.add_argument("--count", type=int, default=50)
    parser.add_argument("--delay", type=float, default=0.5)
    args = parser.parse_args()

    print(f"Starting XSS simulation: {args.count} requests to {args.url}")
    blocked = 0
    for i in range(args.count):
        status = send_request(args.url, random.choice(PATHS), random.choice(XSS_PAYLOADS))
        if status in (403, 0):
            blocked += 1
        print(f"[{i+1}/{args.count}] HTTP {status}")
        time.sleep(args.delay)
    print(f"\nComplete: {blocked}/{args.count} likely blocked")


if __name__ == "__main__":
    main()
