"""Locust load testing scenarios for WAF security platform."""

import random
from locust import HttpUser, between, task

SQLI_PAYLOADS = ["' OR 1=1--", "admin'--", "1; DROP TABLE users--"]
XSS_PAYLOADS = ["<script>alert(1)</script>", "<img src=x onerror=alert(1)>"]


class NormalUser(HttpUser):
    wait_time = between(1, 3)
    weight = 5

    @task(3)
    def browse_home(self):
        self.client.get("/", name="home")

    @task(2)
    def browse_search(self):
        self.client.get("/search", params={"q": "laptop"}, name="search")

    @task(1)
    def browse_products(self):
        self.client.get(f"/products/{random.randint(1, 100)}", name="product")


class HeavyUser(HttpUser):
    wait_time = between(0.1, 0.5)
    weight = 2

    @task
    def rapid_requests(self):
        for _ in range(5):
            self.client.get("/", name="heavy-home")


class BotUser(HttpUser):
    wait_time = between(0.05, 0.2)
    weight = 1

    def on_start(self):
        self.client.headers.update({
            "User-Agent": random.choice([
                "python-requests/2.31.0",
                "Scrapy/2.11.0",
                "curl/8.4.0",
            ])
        })

    @task
    def crawl(self):
        self.client.get("/", name="bot-crawl")


class SQLiAttackUser(HttpUser):
    wait_time = between(0.5, 1)
    weight = 1

    @task
    def sqli_attack(self):
        payload = random.choice(SQLI_PAYLOADS)
        self.client.get("/login", params={"user": payload, "pass": payload}, name="sqli-attack")


class XSSAttackUser(HttpUser):
    wait_time = between(0.5, 1)
    weight = 1

    @task
    def xss_attack(self):
        payload = random.choice(XSS_PAYLOADS)
        self.client.get("/comment", params={"text": payload}, name="xss-attack")


class RateLimitAbuseUser(HttpUser):
    wait_time = between(0, 0.01)
    weight = 1

    @task
    def flood(self):
        self.client.get("/", name="rate-flood")
