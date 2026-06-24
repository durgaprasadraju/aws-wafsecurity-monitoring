"""Shared utilities for WAF report generation."""

import logging
import os
import time
from typing import Any

import boto3

LOG_LEVEL = os.environ.get("LOG_LEVEL", "INFO")
logging.basicConfig(level=LOG_LEVEL)
logger = logging.getLogger(__name__)


def get_athena_client():
    return boto3.client("athena")


def get_s3_client():
    return boto3.client("s3")


def get_sns_client():
    return boto3.client("sns")


def wait_for_query(athena_client, query_execution_id: str, max_wait: int = 120) -> dict[str, Any]:
    """Poll Athena until query completes or times out."""
    elapsed = 0
    while elapsed < max_wait:
        response = athena_client.get_query_execution(QueryExecutionId=query_execution_id)
        state = response["QueryExecution"]["Status"]["State"]
        if state == "SUCCEEDED":
            return response
        if state in ("FAILED", "CANCELLED"):
            reason = response["QueryExecution"]["Status"].get("StateChangeReason", "Unknown")
            raise RuntimeError(f"Athena query {state}: {reason}")
        time.sleep(2)
        elapsed += 2
    raise TimeoutError(f"Athena query timed out after {max_wait}s")


def fetch_query_results(athena_client, query_execution_id: str) -> list[list[str]]:
    """Fetch all result rows from a completed Athena query."""
    rows: list[list[str]] = []
    paginator = athena_client.get_paginator("get_query_results")
    for page in paginator.paginate(QueryExecutionId=query_execution_id):
        for row in page["ResultSet"]["Rows"]:
            rows.append([col.get("VarCharValue", "") for col in row["Data"]])
    return rows


def execute_athena_query(
    athena_client,
    query: str,
    database: str,
    workgroup: str,
    output_location: str,
) -> tuple[str, list[list[str]]]:
    """Execute Athena query and return execution ID and results."""
    response = athena_client.start_query_execution(
        QueryString=query,
        QueryExecutionContext={"Database": database},
        WorkGroup=workgroup,
        ResultConfiguration={"OutputLocation": output_location},
    )
    execution_id = response["QueryExecutionId"]
    logger.info("Started Athena query: %s", execution_id)
    wait_for_query(athena_client, execution_id)
    results = fetch_query_results(athena_client, execution_id)
    return execution_id, results
