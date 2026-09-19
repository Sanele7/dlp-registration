import sys
sys.path.insert(0, 'src')
from validation.aps import calculate_aps

# From Milestone 1's example payload
subjects = {
    "englishHomeLanguage": 62,
    "mathematics": 48,
    "physicalSciences": 51,
    "lifeSciences": 55,
    "geography": 49,
    "isiZulu": 58,
    "lifeOrientation": 70
}

result = calculate_aps(subjects)
print("Example payload result:", result)

# A high-achieving applicant who should be rejected
high_scores = {
    "englishHomeLanguage": 85,
    "mathematics": 90,
    "physicalSciences": 88,
    "lifeSciences": 82,
    "geography": 91,
    "isiZulu": 87,
    "lifeOrientation": 95
}

high_result = calculate_aps(high_scores)
print("High achiever result:", high_result)

# A low scorer who should be within the ceiling
low_scores = {
    "englishHomeLanguage": 35,
    "mathematics": 32,
    "physicalSciences": 38,
    "lifeSciences": 41,
    "geography": 33,
    "isiZulu": 30,
    "lifeOrientation": 60
}

low_result = calculate_aps(low_scores)
print("Low scorer result:", low_result)
