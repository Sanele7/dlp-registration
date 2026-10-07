import sys

import pytest

sys.path.insert(0, "src")

from validation.aps import _percentage_to_level, calculate_aps

SUBJECTS = ["englishHomeLanguage", "mathematics", "physicalSciences",
            "lifeSciences", "geography", "isiZulu"]


def marks(values):
    result = dict(zip(SUBJECTS, values))
    result["lifeOrientation"] = 90
    return result


@pytest.mark.parametrize("pct,level", [
    (100, 7), (80, 7), (79, 6), (70, 6), (69, 5), (60, 5), (59, 4),
    (50, 4), (49, 3), (40, 3), (39, 2), (30, 2), (29, 1), (0, 1),
])
def test_percentage_boundaries_map_to_the_right_level(pct, level):
    assert _percentage_to_level(pct) == level


def test_ceiling_of_exactly_20_is_accepted():
    result = calculate_aps(marks([50, 50, 40, 40, 40, 40]))
    assert result == {"valid": True, "aps_total": 20}


def test_one_point_above_the_ceiling_is_rejected():
    result = calculate_aps(marks([50, 50, 50, 40, 40, 40]))
    assert result["valid"] is False
    assert result["reason"] == "APS_ABOVE_CEILING"
    assert result["aps_total"] == 21


def test_percentage_above_100_is_invalid():
    assert calculate_aps(marks([101, 40, 40, 40, 40, 40]))["reason"] == "INVALID_PAYLOAD"


def test_negative_percentage_is_invalid():
    assert calculate_aps(marks([-1, 40, 40, 40, 40, 40]))["reason"] == "INVALID_PAYLOAD"
