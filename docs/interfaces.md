# Interface contracts

## SubmitRegistration

| Field | Detail |
|---|---|
| Name | SubmitRegistration |
| Trigger/endpoint | POST /registrations |
| Input | `nationalId` (string, 13 digits, required), `subjectResults` (array of 7 subject/percentage pairs, required) |
| Validation | National ID must be 13 digits, valid calendar date, pass checksum (see validation-rules.md). APS computed from best 6 of 7 subjects (excluding Life Orientation) must be ≤ 20 |
| Success output | 201, body includes `correlationId`, `status: CONFIRMED` |
| Failure output | 422 (invalid ID or APS too high, not retryable without correcting input); 409 (duplicate or session full, not retryable); 503 (storage unavailable, retryable after delay). Every failure logged with `correlationId` and `reason` |
| Idempotency | Duplicate detected via SHA-256 hash of national ID (`idHash`) as the table's partition key. A second submission with the same ID is rejected as 409 DUPLICATE, never processed twice |
| Owner | Bandile (implementation), Asename (interface design sign-off) |