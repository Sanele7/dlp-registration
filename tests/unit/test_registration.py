import json
import sys
from unittest.mock import patch

sys.path.insert(0, "src")

from handlers import registration


def valid_payload():
    return {
        "nationalId": "0303155029083",
        "subjectResults": [
            {"subject": "englishHomeLanguage", "percentage": 50},
            {"subject": "mathematics", "percentage": 40},
            {"subject": "physicalSciences", "percentage": 40},
            {"subject": "lifeSciences", "percentage": 40},
            {"subject": "geography", "percentage": 40},
            {"subject": "isiZulu", "percentage": 40},
            {"subject": "lifeOrientation", "percentage": 70},
        ],
    }


def event(payload=None):
    return {"body": json.dumps(payload or valid_payload())}


def test_invalid_id_returns_422():
    payload = valid_payload()
    payload["nationalId"] = "12345"
    response = registration.handler(event(payload), None)
    assert response["statusCode"] == 422
    assert json.loads(response["body"])["reason"] == "INVALID_NATIONAL_ID"


def test_missing_subjects_returns_422():
    response = registration.handler(
        event({"nationalId": "0303155029083"}), None
    )
    assert response["statusCode"] == 422
    assert json.loads(response["body"])["reason"] == "INVALID_PAYLOAD"


def test_aps_too_high_returns_422_without_storage():
    payload = valid_payload()
    for item in payload["subjectResults"]:
        if item["subject"] != "lifeOrientation":
            item["percentage"] = 80

    with patch.object(registration, "_reserve_seat_and_store") as reserve:
        response = registration.handler(event(payload), None)

    reserve.assert_not_called()
    body = json.loads(response["body"])
    assert response["statusCode"] == 422
    assert body["reason"] == "APS_TOO_HIGH"


def test_successful_registration():
    with patch.object(registration, "_reserve_seat_and_store") as reserve:
        response = registration.handler(event(), None)

    reserve.assert_called_once()
    body = json.loads(response["body"])
    assert response["statusCode"] == 201
    assert body["status"] == "CONFIRMED"
    assert body["aps"] == 19


def test_duplicate_returns_409():
    with patch.object(
        registration,
        "_reserve_seat_and_store",
        side_effect=registration._TransactionRejected(),
    ), patch.object(registration, "_registration_exists", return_value=True):
        response = registration.handler(event(), None)

    assert response["statusCode"] == 409
    assert json.loads(response["body"])["reason"] == "DUPLICATE"


def test_full_session_returns_409():
    with patch.object(
        registration,
        "_reserve_seat_and_store",
        side_effect=registration._TransactionRejected(),
    ), patch.object(
        registration, "_registration_exists", return_value=False
    ), patch.object(registration, "_capacity_remaining", return_value=0):
        response = registration.handler(event(), None)

    assert response["statusCode"] == 409
    assert json.loads(response["body"])["reason"] == "SESSION_FULL"
