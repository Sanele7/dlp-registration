import json
import sys
from unittest.mock import patch

sys.path.insert(0, "src")

from handlers import registration


def valid_payload():
    return {
        "fromKwaDlangezwa": True,
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
        event({"fromKwaDlangezwa": True, "nationalId": "0303155029083"}), None
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
    assert body["reference"].startswith("DLP-") and len(body["reference"]) == 12
    assert len(body["pin"]) == 6 and body["pin"].isdigit()
    assert "proof of residence" in body["nextSteps"]
    # the PIN is never stored in clear: only salt + hash go to the store
    ref_item = reserve.call_args[0][1]
    assert body["pin"] not in json.dumps(ref_item)


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


def test_rejection_includes_plain_language_detail():
    payload = valid_payload()
    payload["nationalId"] = "9911211111088"
    response = registration.handler(event(payload), None)
    body = json.loads(response["body"])
    assert body["reason"] == "INVALID_NATIONAL_ID"
    assert "checksum" in body["detail"]
    assert "9911211111088" not in response["body"]


def test_aps_too_high_detail_states_the_score():
    payload = valid_payload()
    for s in payload["subjectResults"]:
        s["percentage"] = 90
    response = registration.handler(event(payload), None)
    body = json.loads(response["body"])
    assert body["reason"] == "APS_TOO_HIGH"
    assert "42" in body["detail"]


def test_applicant_over_age_limit_is_rejected_with_age_reason():
    payload = valid_payload()
    payload["nationalId"] = "9911211111082"
    response = registration.handler(event(payload), None)
    body = json.loads(response["body"])
    assert response["statusCode"] == 422
    assert body["reason"] == "AGE_NOT_ELIGIBLE"
    assert "between 18 and 25" in body["detail"]
    assert "9911211111082" not in response["body"]


def test_applicant_under_age_limit_is_rejected_with_age_reason():
    payload = valid_payload()
    payload["nationalId"] = "1206105001087"
    body = json.loads(registration.handler(event(payload), None)["body"])
    assert body["reason"] == "AGE_NOT_ELIGIBLE"


def test_non_resident_is_rejected_before_anything_else():
    with patch.object(registration, "_reserve_seat_and_store") as reserve:
        response = registration.handler(
            event({"fromKwaDlangezwa": False}), None
        )
    reserve.assert_not_called()
    body = json.loads(response["body"])
    assert response["statusCode"] == 422
    assert body["reason"] == "NOT_RESIDENT"
    assert "KwaDlangezwa" in body["detail"]


def test_missing_residence_answer_is_rejected():
    payload = valid_payload()
    del payload["fromKwaDlangezwa"]
    response = registration.handler(event(payload), None)
    assert response["statusCode"] == 422
    assert json.loads(response["body"])["reason"] == "INVALID_PAYLOAD"


def _status_event(reference, pin):
    return {"resource": "/registrations/status",
            "body": json.dumps({"reference": reference, "pin": pin})}


def _stored_ref(pin="123456"):
    salt = "abcd1234abcd1234"
    return {"idHash": "REF#DLP-ABCD2345", "status": "CONFIRMED", "aps": 19,
            "timestamp": "2026-10-06T12:00:00+00:00", "salt": salt,
            "pinHash": registration._hash_pin(pin, salt), "failedAttempts": 0}


def test_status_check_with_correct_reference_and_pin():
    with patch.object(registration._table, "get_item", return_value={"Item": _stored_ref()}):
        response = registration.handler(_status_event("dlp-abcd2345", "123456"), None)
    body = json.loads(response["body"])
    assert response["statusCode"] == 200
    assert body["status"] == "CONFIRMED" and body["aps"] == 19
    assert "nationalId" not in body and "idHash" not in body


def test_status_check_wrong_pin_is_not_found_and_counted():
    with patch.object(registration._table, "get_item", return_value={"Item": _stored_ref()}), \
         patch.object(registration._table, "update_item") as upd:
        response = registration.handler(_status_event("DLP-ABCD2345", "000000"), None)
    assert response["statusCode"] == 404
    assert json.loads(response["body"])["reason"] == "NOT_FOUND"
    upd.assert_called_once()


def test_status_check_unknown_reference_looks_the_same_as_wrong_pin():
    with patch.object(registration._table, "get_item", return_value={}):
        response = registration.handler(_status_event("DLP-NOPE0000", "123456"), None)
    assert response["statusCode"] == 404
    assert json.loads(response["body"])["reason"] == "NOT_FOUND"


def test_status_check_locks_after_too_many_wrong_pins():
    locked = _stored_ref(); locked["failedAttempts"] = 5
    with patch.object(registration._table, "get_item", return_value={"Item": locked}):
        response = registration.handler(_status_event("DLP-ABCD2345", "123456"), None)
    assert response["statusCode"] == 423
    assert json.loads(response["body"])["reason"] == "TOO_MANY_ATTEMPTS"


def _check_event(nid):
    return {"resource": "/registrations/check", "body": json.dumps({"nationalId": nid})}


def test_check_clears_a_new_eligible_id():
    with patch.object(registration, "_registration_exists", return_value=False), \
         patch.object(registration, "_capacity_remaining", return_value=3):
        response = registration.handler(_check_event("0303155029083"), None)
    assert response["statusCode"] == 200


def test_check_stops_a_duplicate_before_marks_are_entered():
    with patch.object(registration, "_registration_exists", return_value=True):
        response = registration.handler(_check_event("0303155029083"), None)
    body = json.loads(response["body"])
    assert response["statusCode"] == 409 and body["reason"] == "DUPLICATE"


def test_check_stops_bad_checksum_and_age_and_full_session():
    assert json.loads(registration.handler(_check_event("9911211111088"), None)["body"])["reason"] == "INVALID_NATIONAL_ID"
    assert json.loads(registration.handler(_check_event("9911211111082"), None)["body"])["reason"] == "AGE_NOT_ELIGIBLE"
    with patch.object(registration, "_registration_exists", return_value=False), \
         patch.object(registration, "_capacity_remaining", return_value=0):
        assert json.loads(registration.handler(_check_event("0303155029083"), None)["body"])["reason"] == "SESSION_FULL"
