import sys
sys.path.insert(0, 'src')
from validation.national_id import validate_and_derive_age

test_id = "0303155029083"

result = validate_and_derive_age(test_id)
print("Test ID:", test_id)
print("Result:", result)

bad_result = validate_and_derive_age("12345")
print("Bad result:", bad_result)
