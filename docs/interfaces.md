# Interface contracts

## SubmitRegistration

| Field | Detail |
|---|---|
| Name | SubmitRegistration |
| Trigger/endpoint | POST /registrations |
| Input | `nationalId` (string, 13 digits, required), `subjectResults` (array of 7 subject/percentage pairs, required) |
| Validation | National ID must be 13 digits, valid calendar date, pass checksum (see validation-rules.md). APS computed from best 6 of 7 subjects (excluding Life Orientation) must be ≤ 20 |
| Success output | 201, body includes `correlationId`, `status: CONFIRMED` |
| Failure output | 422 (invalid ID, age outside 18–25 `AGE_NOT_ELIGIBLE`, or APS too high, not retryable without correcting input); 409 (duplicate or session full, not retryable); 503 (storage unavailable, retryable after delay). Every failure logged with `correlationId` and `reason` |
| Idempotency | Duplicate detected via SHA-256 hash of national ID (`idHash`) as the table's partition key. A second submission with the same ID is rejected as 409 DUPLICATE, never processed twice |
| Owner | Bandile (implementation), Asename (interface design sign-off) |
## Rejection detail (added in Milestone 4)

Every rejection response may include an optional `detail` field: a plain-language explanation for the applicant (for example, which part of the national ID failed, or the applicant's APS against the ceiling of 20). The `reason` codes and status codes are unchanged, so existing clients are unaffected. `detail` never contains the national ID.


## Residence, reference number and PIN (added in Milestone 4)

- Request field `fromKwaDlangezwa` (boolean, required). `false` → 422 `NOT_RESIDENT`.
- A successful registration (201) also returns `reference` (`DLP-` + 8 characters), a one-time 6-digit `pin`, and `nextSteps` (bring the required documents, including proof of residence, to the branch helpdesk).
- The PIN is stored only as a salted PBKDF2 hash. The reference lookup item is `REF#<reference>` in the same table.
- `POST /registrations/status` with `{"reference", "pin"}` returns 200 with `status`, `aps`, `registeredAt`, `nextSteps`. A wrong PIN and an unknown reference both return 404 `NOT_FOUND` (no enumeration). After 5 wrong PINs the reference is locked: 423 `TOO_MANY_ATTEMPTS`.
- New reasons: `NOT_RESIDENT`, `AGE_NOT_ELIGIBLE`, `NOT_FOUND`, `TOO_MANY_ATTEMPTS`.
- Programme capacity is 5 seats (`PROGRAMME_CAPACITY`).
