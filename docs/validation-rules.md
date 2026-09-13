# Validation rules — registration eligibility

## 1. National ID number
- Must be exactly 13 digits, numeric only.
- First 6 digits must form a valid calendar date (YYMMDD).
- Must pass the standard South African ID checksum (Luhn-style algorithm).

**Examples:**
| ID number | Result | Reason |
|---|---|---|
| 9001015013088 | Valid | Correct checksum, valid date |
| 9001015013089 | Invalid | Checksum fails |
| 900101501308 | Invalid | Only 12 digits |
| 9013015013088 | Invalid | Month "13" is not a valid calendar month |

## 2. APS (Admission Point Score)
- Applicants take 7 subjects.
- APS is calculated from the **best 6 subjects, excluding Life Orientation**.
- Maximum allowed APS for this programme: **20**.
- An applicant with APS above 20 is rejected with reason `APS_TOO_HIGH`.

**Example:** an applicant with 6 qualifying subjects summing to 22 → rejected, reason `APS_TOO_HIGH`.