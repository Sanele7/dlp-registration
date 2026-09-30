import json
import sys
from unittest.mock import Mock, patch

sys.path.insert(0, "src")

from handlers import registration


def valid_event():
    return {
        "body": json.dumps(
            {
                "nationalId": "0303155029083",
                "subjectResults": [
                    {"subject": "englishHomeLanguage", "percentage": 62},
                    {"subject": "mathematics", "percentage": 48},
                    {"subject": "physicalSciences", "percentage": 51},
                    {"subject": "lifeSciences", "percentage": 55},
                    {"subject": "geography", "percentage": 49},
                    {"subject": "isiZulu", "percentage": 58},
                    {"subject": "lifeOrientation", "percentage": 70},
                ]
            }
        )
    }


def test_invalid_id_returns_422():
    response = registration.handler(
        {
            "body": json.dumps(
                {
                    "nationalId": "12345",
                    "subjectResults": valid_event_payload()["subjectResults"],
                }
            )
        },
        None,
    )
    assert response["statusCode"] == 422
    assert json.loads(response["body"])["reason"] == "INVALID_NATIONAL_ID"


def test_missing_subjects_returns_422():
    response = registration.handler(
        {"body": json.dumps({"nationalId": "0303155029083"})},
        None,
    )
    assert response["statusCode"] == 422
    assert json.loads(response["body"])["reason"] == "INVALID_PAYLOAD"


def test_successful_registration():
    with patch.object(registration, "_reserve_seat_and_store") as reserve:
        response = registration.handler(valid_event(), None)

    reserve.assert_called_once()
    body = json.loads(response["body"])
    assert response["statusCode"] == 201
    assert body["status"] == "CONFIRMED"
    assert body["aps"] == 20


def test_duplicate_returns_409():
    with patch.object(
        registration, "_reserve_seat_and_store",
        side_effect=registration._TransactionRejected(),
    ), patch.object(registration, "_registration_exists", return_value=True):
        response = registration.handler(valid_event(), None)

    assert response["statusCode"] == 409
    assert json.loads(response["body"])["reason"] == "DUPLICATE"


def test_full_session_returns_409():
    with patch.object(
        registration, "_reserve_seat_and_store",
        side_effect=registration._TransactionRejected(),
    ), patch.object(registration, "_registration_exists", return_value=False), patch.object(
        registration, "_capacity_remaining", return_value=0
    ):
        response = registration.handler(valid_event(), None)

    assert response["statusCode"] == 409
    assert json.loads(response["body"])["reason"] == "SESSION_FULL"


def valid_event_payload():
    return json.loads(valid_event()["body"])
