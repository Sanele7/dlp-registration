import sys

sys.path.insert(0, "src")

from validation.national_id import validate_and_derive_age


def test_valid_id_passes_checksum_and_derives_age():
    result = validate_and_derive_age("0303155029083")
    assert result["valid"] is True
    assert isinstance(result["age"], int)
    assert result["age"] >= 0


def test_wrong_length_is_invalid():
    result = validate_and_derive_age("12345")
    assert result == {"valid": False, "reason": "INVALID_NATIONAL_ID"}


def test_non_digit_characters_are_invalid():
    result = validate_and_derive_age("030315502908A")
    assert result == {"valid": False, "reason": "INVALID_NATIONAL_ID"}


def test_fails_checksum_is_invalid():
    # Same digits as the valid ID above but with the check digit altered,
    # so it fails the Luhn checksum while still being 13 numeric digits.
    result = validate_and_derive_age("0303155029084")
    assert result == {"valid": False, "reason": "INVALID_NATIONAL_ID"}


def test_impossible_calendar_date_is_invalid():
    # Month 13 cannot be a real birth date.
    result = validate_and_derive_age("0313155029083")
    assert result == {"valid": False, "reason": "INVALID_NATIONAL_ID"}
