# Validation rules — registration eligibility

## 0. Residence (asked first)
- The applicant must answer "Are you from KwaDlangezwa?" (`fromKwaDlangezwa`, true/false). It is required.
- *No* → rejected immediately with reason `NOT_RESIDENT` (HTTP 422): the programme is only open to residents of KwaDlangezwa.
- *Yes* → the remaining rules apply. The applicant must later bring proof of residence to the branch helpdesk; the service does not verify it online.

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

## 2. Age eligibility
- Age is derived from the first 6 digits of the national ID (never self-declared).
- Applicants must be between **18 and 25 years old, inclusive** (configurable with `MIN_AGE` / `MAX_AGE`).
- Outside that range the request is rejected with reason `AGE_NOT_ELIGIBLE` (HTTP 422), before APS is calculated.
- Checked after the ID is validated, so an invalid ID is still reported as `INVALID_NATIONAL_ID`.

## 3. APS (Admission Point Score)
- Applicants take 7 subjects.
- APS is calculated from the **best 6 subjects, excluding Life Orientation**.
- Maximum allowed APS for this programme: **20**.
- An applicant with APS above 20 is rejected with reason `APS_TOO_HIGH`.

**Example:** an applicant with 6 qualifying subjects summing to 22 → rejected, reason `APS_TOO_HIGH`.