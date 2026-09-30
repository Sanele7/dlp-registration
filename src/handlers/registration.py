"""Lambda handler for POST /registrations.

Implements the registration contract in docs/interfaces.md.
"""

from __future__ import annotations

import base64
import hashlib
import json
import logging
import os
import uuid
from datetime import datetime, timezone

import boto3
from botocore.exceptions import BotoCoreError, ClientError

from validation.aps import calculate_aps
from validation.national_id import validate_and_derive_age

LOG = logging.getLogger()
LOG.setLevel(os.getenv("LOG_LEVEL", "INFO"))

TABLE_NAME = os.getenv("REGISTRATIONS_TABLE", "dlp-registrations")
CAPACITY_KEY = "CAPACITY#programme"
PROGRAMME_CAPACITY = int(os.getenv("PROGRAMME_CAPACITY", "10"))

_dynamodb = boto3.resource("dynamodb")
_table = _dynamodb.Table(TABLE_NAME)


def handler(event, context):
    correlation_id = str(uuid.uuid4())
    timestamp = datetime.now(timezone.utc).isoformat()

    try:
        payload = _parse_payload(event)
    except ValueError:
        return _failure(422, correlation_id, timestamp, "INVALID_PAYLOAD")

    national_id = payload.get("nationalId")
    subject_results = payload.get("subjectResults")

    if not isinstance(national_id, str) or not isinstance(subject_results, list):
        return _failure(422, correlation_id, timestamp, "INVALID_PAYLOAD")

    if len(subject_results) != 7:
        return _failure(422, correlation_id, timestamp, "INVALID_PAYLOAD")

    subjects = _subject_array_to_dict(subject_results)
    if subjects is None:
        return _failure(422, correlation_id, timestamp, "INVALID_PAYLOAD")

    id_result = validate_and_derive_age(national_id)
    if not id_result["valid"]:
        return _failure(422, correlation_id, timestamp, "INVALID_NATIONAL_ID")

    aps_result = calculate_aps(subjects)
    if not aps_result["valid"]:
        reason = (
            "APS_TOO_HIGH"
            if aps_result.get("reason") == "APS_ABOVE_CEILING"
            else "INVALID_PAYLOAD"
        )
        return _failure(422, correlation_id, timestamp, reason)

    id_hash = hashlib.sha256(national_id.encode("utf-8")).hexdigest()
    id_hash_prefix = id_hash[:6]

    item = {
        "idHash": id_hash,
        "status": "CONFIRMED",
        "aps": aps_result["aps_total"],
        "timestamp": timestamp,
        "correlationId": correlation_id,
    }

    try:
        _reserve_seat_and_store(item)
    except _TransactionRejected:
        if _registration_exists(id_hash):
            return _failure(
                409, correlation_id, timestamp, "DUPLICATE", id_hash_prefix
            )

        if _capacity_remaining() <= 0:
            return _failure(
                409, correlation_id, timestamp, "SESSION_FULL", id_hash_prefix
            )

        return _failure(
            503, correlation_id, timestamp, "STORAGE_UNAVAILABLE", id_hash_prefix
        )
    except (BotoCoreError, ClientError, Exception):
        LOG.exception("Registration storage failure")
        return _failure(
            503, correlation_id, timestamp, "STORAGE_UNAVAILABLE", id_hash_prefix
        )

    _log_decision(
        correlation_id,
        timestamp,
        "CONFIRMED",
        None,
        id_hash_prefix,
    )

    return _response(
        201,
        {
            "correlationId": correlation_id,
            "status": "CONFIRMED",
            "aps": aps_result["aps_total"],
        },
    )


class _TransactionRejected(Exception):
    """The transaction was cancelled by a business-condition check."""


def _reserve_seat_and_store(item: dict) -> None:
    """Atomically reserve one seat and create the registration record.

    The two writes are atomic: either both happen or neither happens.
    This prevents over-enrolment and prevents a duplicate from consuming
    a seat.
    """
    try:
        _dynamodb.meta.client.transact_write_items(
            TransactItems=[
                {
                    "Put": {
                        "TableName": TABLE_NAME,
                        "Item": _serialize_item(item),
                        "ConditionExpression": "attribute_not_exists(idHash)",
                    }
                },
                {
                    "Update": {
                        "TableName": TABLE_NAME,
                        "Key": {"idHash": {"S": CAPACITY_KEY}},
                        "UpdateExpression": "SET #remaining = #remaining - :one",
                        "ConditionExpression": "#remaining > :zero",
                        "ExpressionAttributeNames": {"#remaining": "remaining"},
                        "ExpressionAttributeValues": {
                            ":one": {"N": "1"},
                            ":zero": {"N": "0"},
                        },
                    }
                },
            ],
            ClientRequestToken=item["correlationId"],
        )
    except _dynamodb.meta.client.exceptions.TransactionCanceledException as exc:
        raise _TransactionRejected() from exc


def _serialize_item(item: dict) -> dict:
    return {
        "idHash": {"S": item["idHash"]},
        "status": {"S": item["status"]},
        "aps": {"N": str(item["aps"])},
        "timestamp": {"S": item["timestamp"]},
        "correlationId": {"S": item["correlationId"]},
    }


def _registration_exists(id_hash: str) -> bool:
    response = _table.get_item(Key={"idHash": id_hash}, ConsistentRead=True)
    return "Item" in response


def _capacity_remaining() -> int:
    response = _table.get_item(Key={"idHash": CAPACITY_KEY}, ConsistentRead=True)
    item = response.get("Item")
    if not item:
        return 0
    return int(item.get("remaining", 0))


def _subject_array_to_dict(subject_results: list) -> dict | None:
    subjects = {}
    for entry in subject_results:
        if not isinstance(entry, dict):
            return None

        name = entry.get("subject")
        percentage = entry.get("percentage")

        if not isinstance(name, str) or not name.strip():
            return None

        if name in subjects:
            return None

        subjects[name] = percentage

    return subjects


def _parse_payload(event) -> dict:
    if not isinstance(event, dict):
        raise ValueError("event must be an object")

    body = event.get("body", event)
    if isinstance(body, str):
        if event.get("isBase64Encoded"):
            body = base64.b64decode(body).decode("utf-8")
        body = json.loads(body)

    if not isinstance(body, dict):
        raise ValueError("body must be a JSON object")

    return body


def _failure(
    status_code: int,
    correlation_id: str,
    timestamp: str,
    reason: str,
    id_hash_prefix: str | None = None,
):
    _log_decision(
        correlation_id,
        timestamp,
        "REJECTED",
        reason,
        id_hash_prefix,
    )

    return _response(
        status_code,
        {
            "correlationId": correlation_id,
            "status": "REJECTED",
            "reason": reason,
        },
    )


def _log_decision(
    correlation_id: str,
    timestamp: str,
    outcome: str,
    reason: str | None,
    id_hash_prefix: str | None,
):
    entry = {
        "correlationId": correlation_id,
        "timestamp": timestamp,
        "outcome": outcome,
        "reason": reason,
        "idHashPrefix": id_hash_prefix,
    }
    LOG.info(json.dumps(entry, separators=(",", ":")))


def _response(status_code: int, body: dict):
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }
