# Decision log

Full records for D1 and D2 are the ADRs in `docs/decisions/`. Later decisions are recorded here.

| ID | Date | Decision | Reason / alternatives rejected | Owner |
|---|---|---|---|---|
| D1 | 30 Aug 2026 | Develop on LocalStack pinned to 4.14.0 (ADR 001) | Newer images need an auth token; AWS native needs lecturer authorisation; Docker Compose fallback kept | Sanele Ngcobo |
| D2 | 1 Oct 2026 | API Gateway to one stateless Lambda to DynamoDB; registration and seat reservation in one transaction (ADR 002) | Separate writes could leave a seat used by a duplicate or allow over-enrolment | Asename Malamule |
| D3 | 6 Oct 2026 | Ask the residence question first; "no" ends with `NOT_RESIDENT` | Programme is for KwaDlangezwa residents; checking first saves the applicant's effort | Group 5 |
| D4 | 6 Oct 2026 | Age 18 to 25 inclusive, derived from the ID, own reason `AGE_NOT_ELIGIBLE`; limits configurable (`MIN_AGE`, `MAX_AGE`) | Age was derived before but not used as a rule. **Confirm the limits against the brief.** | Group 5 |
| D5 | 6 Oct 2026 | Issue a reference and one-time PIN; store the PIN only as a salted hash; lock after 5 wrong attempts | Applicants need to check their application. Storing a clear PIN or allowing unlimited guesses was rejected | Group 5 |
| D6 | 6 Oct 2026 | Keep the Luhn checksum instead of accepting any 13 digits with a valid date | Required by `docs/validation-rules.md`; real IDs always pass; relaxing it would accept mistyped numbers | Group 5 |
| D7 | 6 Oct 2026 | Add a read-only early-screening route (`/registrations/check`) | Stops duplicates and bad IDs before marks are entered. Accepted trade-off: it reveals whether an ID is registered | Group 5 |
| D8 | 6 Oct 2026 | Admin view is an operator script using local credentials, not an API route or a Lambda permission | Keeps the Lambda policy free of Scan; no unauthenticated admin endpoint | Group 5 |
| D9 | 6 Oct 2026 | Reduce capacity from 10 to 5 seats | Shorter demonstration that still shows a full programme | Group 5 |
| D10 | 6-7 Oct 2026 | Provide `start.sh [--reset]` and fix reproducibility problems in scripts rather than in instructions | Clean-clone runs failed for different members; one command removes the variation | Group 5 |
