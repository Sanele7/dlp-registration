"""Lambda handler for POST /registrations.

Implements the registration contract in docs/interfaces.md.
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import logging
import os
import secrets
import uuid
from datetime import datetime, timezone

import boto3
from botocore.exceptions import BotoCoreError, ClientError

from validation.aps import calculate_aps
from validation.national_id import (
    _extract_birth_date,
    _passes_luhn_checksum,
    validate_and_derive_age,
)

LOG = logging.getLogger()
LOG.setLevel(os.getenv("LOG_LEVEL", "INFO"))

TABLE_NAME = os.getenv("REGISTRATIONS_TABLE", "dlp-registrations")
CAPACITY_KEY = "CAPACITY#programme"
PROGRAMME_CAPACITY = int(os.getenv("PROGRAMME_CAPACITY", "5"))
REF_PREFIX = "REF#"
REF_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  # no 0/O/1/I to avoid misreading
MAX_PIN_ATTEMPTS = 5
NEXT_STEPS = (
    "Please bring the required documents listed on the programme post, including "
    "your proof of residence, to the branch helpdesk. Keep your reference number "
    "and PIN safe: you need both to check your application."
)
MIN_AGE = int(os.getenv("MIN_AGE", "18"))
MAX_AGE = int(os.getenv("MAX_AGE", "25"))

DYNAMODB_ENDPOINT = os.getenv("DYNAMODB_ENDPOINT")
_dynamodb = boto3.resource("dynamodb", endpoint_url=DYNAMODB_ENDPOINT) if DYNAMODB_ENDPOINT else boto3.resource("dynamodb")
_table = _dynamodb.Table(TABLE_NAME)


def handler(event, context):
    route = str((event or {}).get("resource") or (event or {}).get("path") or "") if isinstance(event, dict) else ""
    if route.rstrip("/").endswith("/status"):
        return _status_handler(event)
    if route.rstrip("/").endswith("/check"):
        return _check_handler(event)
    return _register_handler(event)


def _register_handler(event):
    correlation_id = str(uuid.uuid4())
    timestamp = datetime.now(timezone.utc).isoformat()

    try:
        payload = _parse_payload(event)
    except ValueError:
        return _failure(
            422, correlation_id, timestamp, "INVALID_PAYLOAD",
            detail="The request is not valid JSON.",
        )

    resident = payload.get("fromKwaDlangezwa")
    if not isinstance(resident, bool):
        return _failure(
            422, correlation_id, timestamp, "INVALID_PAYLOAD",
            detail="Please answer whether you are from KwaDlangezwa (yes or no).",
        )
    if not resident:
        return _failure(
            422, correlation_id, timestamp, "NOT_RESIDENT",
            detail=(
                "This programme is only open to residents of KwaDlangezwa. "
                "Your application cannot continue."
            ),
        )

    national_id = payload.get("nationalId")
    subject_results = payload.get("subjectResults")

    if not isinstance(national_id, str) or not isinstance(subject_results, list):
        return _failure(422, correlation_id, timestamp, "INVALID_PAYLOAD")

    if len(subject_results) != 7:
        return _failure(
            422, correlation_id, timestamp, "INVALID_PAYLOAD",
            detail="Exactly 7 subjects are required (6 counted subjects plus Life Orientation).",
        )

    subjects = _subject_array_to_dict(subject_results)
    if subjects is None:
        return _failure(422, correlation_id, timestamp, "INVALID_PAYLOAD")

    id_result = validate_and_derive_age(national_id)
    if not id_result["valid"]:
        return _failure(
            422, correlation_id, timestamp, "INVALID_NATIONAL_ID",
            detail=_id_problem(national_id),
        )

    age = id_result["age"]
    if age < MIN_AGE or age > MAX_AGE:
        return _failure(
            422, correlation_id, timestamp, "AGE_NOT_ELIGIBLE",
            detail=(
                f"Applicants must be between {MIN_AGE} and {MAX_AGE} years old "
                f"(age is worked out from the national ID). Your age is {age}."
            ),
        )

    aps_result = calculate_aps(subjects)
    if not aps_result["valid"]:
        if aps_result.get("reason") == "APS_ABOVE_CEILING":
            return _failure(
                422, correlation_id, timestamp, "APS_TOO_HIGH",
                detail=(
                    f"Your APS is {aps_result['aps_total']}, but the programme "
                    "accepts a maximum of 20 (best 6 subjects, excluding Life Orientation)."
                ),
            )
        return _failure(
            422, correlation_id, timestamp, "INVALID_PAYLOAD",
            detail="Each of the 6 counted subjects needs a percentage between 0 and 100, and subject names must not repeat.",
        )

    id_hash = hashlib.sha256(national_id.encode("utf-8")).hexdigest()
    id_hash_prefix = id_hash[:6]

    reference = _new_reference()
    pin = _new_pin()
    salt = secrets.token_hex(8)

    item = {
        "idHash": id_hash,
        "status": "CONFIRMED",
        "aps": aps_result["aps_total"],
        "timestamp": timestamp,
        "correlationId": correlation_id,
        "reference": reference,
    }
    ref_item = {
        "idHash": REF_PREFIX + reference,
        "status": "CONFIRMED",
        "aps": aps_result["aps_total"],
        "timestamp": timestamp,
        "salt": salt,
        "pinHash": _hash_pin(pin, salt),
    }

    try:
        _reserve_seat_and_store(item, ref_item)
    except _TransactionRejected:
        if _registration_exists(id_hash):
            return _failure(
                409, correlation_id, timestamp, "DUPLICATE", id_hash_prefix,
                detail="This national ID is already registered. Use your reference number and PIN to check your application.",
            )

        if _capacity_remaining() <= 0:
            return _failure(
                409, correlation_id, timestamp, "SESSION_FULL", id_hash_prefix,
                detail="All seats in this programme session are taken.",
            )

        return _failure(
            503, correlation_id, timestamp, "STORAGE_UNAVAILABLE", id_hash_prefix,
            detail="The registration store is temporarily unavailable. Please try again shortly.",
        )
    except (BotoCoreError, ClientError, Exception):
        LOG.exception("Registration storage failure")
        return _failure(
            503, correlation_id, timestamp, "STORAGE_UNAVAILABLE", id_hash_prefix,
            detail="The registration store is temporarily unavailable. Please try again shortly.",
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
            "reference": reference,
            "pin": pin,
            "nextSteps": NEXT_STEPS,
        },
    )


class _TransactionRejected(Exception):
    """The transaction was cancelled by a business-condition check."""


def _reserve_seat_and_store(item: dict, ref_item: dict) -> None:
    """Atomically reserve one seat and create the registration record.

    The two writes are atomic: either both happen or neither happens.
    This prevents over-enrolment and prevents a duplicate from consuming
    a seat.
    """
    try:
        boto3.client("dynamodb", endpoint_url=DYNAMODB_ENDPOINT).transact_write_items(
            TransactItems=[
                {
                    "Put": {
                        "TableName": TABLE_NAME,
                        "Item": _serialize_item(item),
                        "ConditionExpression": "attribute_not_exists(idHash)",
                    }
                },
                {
                    "Put": {
                        "TableName": TABLE_NAME,
                        "Item": _serialize_ref_item(ref_item),
                        "ConditionExpression": "attribute_not_exists(idHash)",
                    }
                },
                {
                    "Update": {
                        "TableName": TABLE_NAME,
                        "Key": {"idHash": {"S": CAPACITY_KEY}},
                        "UpdateExpression": "ADD #remaining :one",
                        "ConditionExpression": "#remaining > :zero",
                        "ExpressionAttributeNames": {"#remaining": "remaining"},
                        "ExpressionAttributeValues": {
                            ":one": {"N": "-1"},
                            ":zero": {"N": "0"},
                        },
                    }
                },
            ]
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
        "reference": {"S": item["reference"]},
    }


def _serialize_ref_item(item: dict) -> dict:
    return {
        "idHash": {"S": item["idHash"]},
        "status": {"S": item["status"]},
        "aps": {"N": str(item["aps"])},
        "timestamp": {"S": item["timestamp"]},
        "salt": {"S": item["salt"]},
        "pinHash": {"S": item["pinHash"]},
        "failedAttempts": {"N": "0"},
    }


def _new_reference() -> str:
    return "DLP-" + "".join(secrets.choice(REF_ALPHABET) for _ in range(8))


def _new_pin() -> str:
    return f"{secrets.randbelow(10**6):06d}"


def _hash_pin(pin: str, salt: str) -> str:
    return hashlib.pbkdf2_hmac("sha256", pin.encode(), salt.encode(), 50_000).hex()


def _check_handler(event):
    """POST /registrations/check: early screening used right after the national
    ID is entered, so the applicant is stopped before typing their marks.

    Read-only. The registration itself still re-checks everything atomically.
    """
    correlation_id = str(uuid.uuid4())
    timestamp = datetime.now(timezone.utc).isoformat()

    try:
        payload = _parse_payload(event)
    except ValueError:
        payload = {}
    national_id = payload.get("nationalId") if isinstance(payload, dict) else None
    if not isinstance(national_id, str):
        return _failure(
            422, correlation_id, timestamp, "INVALID_PAYLOAD",
            detail="Please provide your national ID.",
        )

    id_result = validate_and_derive_age(national_id)
    if not id_result["valid"]:
        return _failure(
            422, correlation_id, timestamp, "INVALID_NATIONAL_ID",
            detail=_id_problem(national_id),
        )

    age = id_result["age"]
    if age < MIN_AGE or age > MAX_AGE:
        return _failure(
            422, correlation_id, timestamp, "AGE_NOT_ELIGIBLE",
            detail=(
                f"Applicants must be between {MIN_AGE} and {MAX_AGE} years old "
                f"(age is worked out from the national ID). Your age is {age}."
            ),
        )

    id_hash = hashlib.sha256(national_id.encode("utf-8")).hexdigest()
    id_hash_prefix = id_hash[:6]
    try:
        if _registration_exists(id_hash):
            return _failure(
                409, correlation_id, timestamp, "DUPLICATE", id_hash_prefix,
                detail="This national ID is already registered. Use your reference number and PIN to check your application.",
            )
        if _capacity_remaining() <= 0:
            return _failure(
                409, correlation_id, timestamp, "SESSION_FULL", id_hash_prefix,
                detail="All seats in this programme session are taken.",
            )
    except (BotoCoreError, ClientError, Exception):
        LOG.exception("ID check storage failure")
        return _failure(
            503, correlation_id, timestamp, "STORAGE_UNAVAILABLE", id_hash_prefix,
            detail="The registration store is temporarily unavailable. Please try again shortly.",
        )

    _log_decision(correlation_id, timestamp, "ID_CLEARED", None, id_hash_prefix)
    return _response(200, {"correlationId": correlation_id, "status": "OK"})


def _status_handler(event):
    """POST /registrations/status: an applicant checks their application
    with the reference number and PIN issued at registration."""
    correlation_id = str(uuid.uuid4())
    timestamp = datetime.now(timezone.utc).isoformat()

    try:
        payload = _parse_payload(event)
    except ValueError:
        payload = {}
    reference = payload.get("reference") if isinstance(payload, dict) else None
    pin = payload.get("pin") if isinstance(payload, dict) else None
    if not isinstance(reference, str) or not isinstance(pin, str) or not reference or not pin:
        return _failure(
            422, correlation_id, timestamp, "INVALID_PAYLOAD",
            detail="Please provide your reference number and PIN.",
        )
    reference = reference.strip().upper()
    not_found = (
        404, correlation_id, timestamp, "NOT_FOUND"
    )
    not_found_detail = "No application matches that reference number and PIN."

    try:
        response = _table.get_item(Key={"idHash": REF_PREFIX + reference}, ConsistentRead=True)
    except (BotoCoreError, ClientError, Exception):
        LOG.exception("Status lookup storage failure")
        return _failure(
            503, correlation_id, timestamp, "STORAGE_UNAVAILABLE",
            detail="The registration store is temporarily unavailable. Please try again shortly.",
        )
    record = response.get("Item")
    if not record:
        return _failure(*not_found, detail=not_found_detail)

    if int(record.get("failedAttempts", 0)) >= MAX_PIN_ATTEMPTS:
        return _failure(
            423, correlation_id, timestamp, "TOO_MANY_ATTEMPTS",
            detail="Too many wrong PIN attempts. Please contact the branch helpdesk.",
        )

    if not hmac.compare_digest(_hash_pin(pin, record["salt"]), record["pinHash"]):
        try:
            _table.update_item(
                Key={"idHash": REF_PREFIX + reference},
                UpdateExpression="ADD failedAttempts :one",
                ExpressionAttributeValues={":one": 1},
            )
        except Exception:
            LOG.exception("Could not record failed PIN attempt")
        return _failure(*not_found, detail=not_found_detail)

    _log_decision(correlation_id, timestamp, "STATUS_VIEWED", None, None)
    return _response(
        200,
        {
            "correlationId": correlation_id,
            "reference": reference,
            "status": record["status"],
            "aps": int(record["aps"]),
            "registeredAt": record["timestamp"],
            "nextSteps": NEXT_STEPS,
        },
    )


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
    detail: str | None = None,
):
    _log_decision(
        correlation_id,
        timestamp,
        "REJECTED",
        reason,
        id_hash_prefix,
    )

    body = {
        "correlationId": correlation_id,
        "status": "REJECTED",
        "reason": reason,
    }
    if detail:
        body["detail"] = detail
    return _response(status_code, body)


def _id_problem(national_id: str) -> str:
    """Plain-language explanation of why a national ID was rejected.

    Never echoes the ID itself.
    """
    if not national_id.isdigit():
        return "The national ID must contain digits only."
    if len(national_id) != 13:
        return f"The national ID must be exactly 13 digits (you entered {len(national_id)})."
    if _extract_birth_date(national_id) is None:
        return "The first 6 digits are not a valid birth date (YYMMDD)."
    if not _passes_luhn_checksum(national_id):
        return "The ID number is not valid: its last digit (checksum) does not match the other digits. Please check for a typing mistake."
    return "The national ID is not valid."


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
