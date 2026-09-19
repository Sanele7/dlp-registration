"""
APS calculation for the Digital Literacy Programme.

Converts seven subject percentages into an APS total, excluding
Life Orientation, per Milestone 1 section 3.2. Ceiling is 20.
"""

REQUIRED_SUBJECT_COUNT = 6
APS_CEILING = 20

def calculate_aps(subject_results: dict) -> dict:
    """
    Takes a dict of subject_name -> percentage.
    Life Orientation is accepted in the input but excluded from the total.

    Returns:
        {"valid": True, "aps_total": int} if within ceiling
        {"valid": False, "reason": "APS_ABOVE_CEILING", "aps_total": int} if over
        {"valid": False, "reason": "INVALID_PAYLOAD"} if the input is malformed
    """
    if not isinstance(subject_results, dict):
        return {"valid": False, "reason": "INVALID_PAYLOAD"}

    # Exclude Life Orientation from the count and the total.
    counted = {
        name: pct for name, pct in subject_results.items()
        if name.lower().replace(" ", "") != "lifeorientation"
    }

    if len(counted) != REQUIRED_SUBJECT_COUNT:
        return {"valid": False, "reason": "INVALID_PAYLOAD"}

    total = 0
    for name, pct in counted.items():
        if not isinstance(pct, (int, float)) or pct < 0 or pct > 100:
            return {"valid": False, "reason": "INVALID_PAYLOAD"}
        total += _percentage_to_level(pct)

    if total > APS_CEILING:
        return {"valid": False, "reason": "APS_ABOVE_CEILING", "aps_total": total}

    return {"valid": True, "aps_total": total}


def _percentage_to_level(pct: float) -> int:
    if pct >= 80:
        return 7
    if pct >= 70:
        return 6
    if pct >= 60:
        return 5
    if pct >= 50:
        return 4
    if pct >= 40:
        return 3
    if pct >= 30:
        return 2
    return 1
