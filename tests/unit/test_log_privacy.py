import json
import logging
import sys
from unittest.mock import patch

sys.path.insert(0, "src")

from handlers import registration
from test_registration import event, valid_payload

NATIONAL_ID = "0303155029083"


def _logged_text(caplog):
    return " ".join(record.getMessage() for record in caplog.records)


def test_successful_registration_logs_no_id_pin_or_reference(caplog):
    caplog.set_level(logging.INFO)
    with patch.object(registration, "_reserve_seat_and_store"):
        response = registration.handler(event(), None)
    body = json.loads(response["body"])
    logged = _logged_text(caplog)
    assert logged, "a decision must be logged"
    assert NATIONAL_ID not in logged
    assert body["pin"] not in logged
    assert body["reference"] not in logged


def test_successful_registration_log_carries_the_correlation_id(caplog):
    caplog.set_level(logging.INFO)
    with patch.object(registration, "_reserve_seat_and_store"):
        response = registration.handler(event(), None)
    body = json.loads(response["body"])
    assert body["correlationId"] in _logged_text(caplog)


def test_rejection_is_logged_with_reason_but_without_the_id(caplog):
    caplog.set_level(logging.INFO)
    payload = valid_payload()
    payload["nationalId"] = "9911211111082"
    registration.handler(event(payload), None)
    logged = _logged_text(caplog)
    assert "AGE_NOT_ELIGIBLE" in logged
    assert "9911211111082" not in logged


def test_duplicate_is_logged_without_the_id(caplog):
    caplog.set_level(logging.INFO)
    with patch.object(
        registration, "_reserve_seat_and_store",
        side_effect=registration._TransactionRejected(),
    ), patch.object(registration, "_registration_exists", return_value=True):
        registration.handler(event(), None)
    logged = _logged_text(caplog)
    assert "DUPLICATE" in logged
    assert NATIONAL_ID not in logged
