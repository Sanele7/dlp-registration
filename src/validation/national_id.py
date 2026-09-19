"""
National ID validation for the Digital Literacy Programme.

Validates a 13-digit South African national ID number and derives
the applicant's age from it. Age is derived, never self-declared,
per Milestone 1 section 3.2.
"""

from datetime import date


def validate_and_derive_age(national_id: str) -> dict:
    if not isinstance(national_id, str) or len(national_id) != 13 or not national_id.isdigit():
        return {"valid": False, "reason": "INVALID_NATIONAL_ID"}

    if not _passes_luhn_checksum(national_id):
        return {"valid": False, "reason": "INVALID_NATIONAL_ID"}

    birth_date = _extract_birth_date(national_id)
    if birth_date is None:
        return {"valid": False, "reason": "INVALID_NATIONAL_ID"}

    age = _calculate_age(birth_date)
    return {"valid": True, "age": age}


def _extract_birth_date(national_id: str) -> date | None:
    yy = int(national_id[0:2])
    mm = int(national_id[2:4])
    dd = int(national_id[4:6])
    current_year_short = date.today().year % 100
    century = 2000 if yy <= current_year_short else 1900
    year = century + yy
    try:
        return date(year, mm, dd)
    except ValueError:
        return None


def _calculate_age(birth_date: date) -> int:
    today = date.today()
    age = today.year - birth_date.year
    if (today.month, today.day) < (birth_date.month, birth_date.day):
        age -= 1
    return age


def _passes_luhn_checksum(national_id: str) -> bool:
    """
    Standard Luhn: process all 13 digits right to left.
    Starting from the rightmost digit (the check digit itself),
    double every second digit going leftwards.
    Valid if total mod 10 == 0.
    """
    digits = [int(d) for d in national_id]
    total = 0
    for i, digit in enumerate(reversed(digits)):
        if i % 2 == 1:
            doubled = digit * 2
            total += doubled - 9 if doubled > 9 else doubled
        else:
            total += digit
    return total % 10 == 0
