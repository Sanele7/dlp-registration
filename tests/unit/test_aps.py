import sys

sys.path.insert(0, "src")

from validation.aps import calculate_aps


def test_example_payload_is_above_ceiling():
    # From Milestone 1's example payload.
    subjects = {
        "englishHomeLanguage": 62,
        "mathematics": 48,
        "physicalSciences": 51,
        "lifeSciences": 55,
        "geography": 49,
        "isiZulu": 58,
        "lifeOrientation": 70,
    }
    result = calculate_aps(subjects)
    assert result == {"valid": False, "reason": "APS_ABOVE_CEILING", "aps_total": 23}


def test_high_achiever_is_above_ceiling():
    subjects = {
        "englishHomeLanguage": 85,
        "mathematics": 90,
        "physicalSciences": 88,
        "lifeSciences": 82,
        "geography": 91,
        "isiZulu": 87,
        "lifeOrientation": 95,
    }
    result = calculate_aps(subjects)
    assert result == {"valid": False, "reason": "APS_ABOVE_CEILING", "aps_total": 42}


def test_low_scorer_is_within_ceiling():
    subjects = {
        "englishHomeLanguage": 35,
        "mathematics": 32,
        "physicalSciences": 38,
        "lifeSciences": 41,
        "geography": 33,
        "isiZulu": 30,
        "lifeOrientation": 60,
    }
    result = calculate_aps(subjects)
    assert result == {"valid": True, "aps_total": 13}


def test_life_orientation_is_excluded_from_the_total():
    # Life Orientation at 0% must not change the total if every other
    # subject is unchanged, because it is excluded from the calculation.
    base = {
        "englishHomeLanguage": 35,
        "mathematics": 32,
        "physicalSciences": 38,
        "lifeSciences": 41,
        "geography": 33,
        "isiZulu": 30,
    }
    low_lo = calculate_aps({**base, "lifeOrientation": 0})
    high_lo = calculate_aps({**base, "lifeOrientation": 100})
    assert low_lo["aps_total"] == high_lo["aps_total"] == 13


def test_wrong_subject_count_is_invalid():
    result = calculate_aps({"mathematics": 50})
    assert result == {"valid": False, "reason": "INVALID_PAYLOAD"}


def test_out_of_range_percentage_is_invalid():
    subjects = {
        "englishHomeLanguage": 35,
        "mathematics": 32,
        "physicalSciences": 38,
        "lifeSciences": 41,
        "geography": 33,
        "isiZulu": 150,
        "lifeOrientation": 60,
    }
    result = calculate_aps(subjects)
    assert result == {"valid": False, "reason": "INVALID_PAYLOAD"}
