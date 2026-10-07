# Data model — dlp-registrations table

One DynamoDB table, `dlp-registrations`, partition key `idHash` (String), on-demand billing.
It holds three kinds of item, told apart by the key.

## 1. Registration item (key = SHA-256 hash of the national ID)
| Field | Type | Notes |
|---|---|---|
| idHash | String (partition key) | SHA-256 of the national ID. The raw ID is never stored. |
| status | String | CONFIRMED (rejected attempts are logged, not stored) |
| aps | Number | Admission point score |
| timestamp | String (ISO 8601) | When the decision was made |
| correlationId | String | Links the record to its log entries |
| reference | String | The reference number issued to the applicant |

## 2. Reference lookup item (key = `REF#` + reference)
Lets an applicant check their application with the reference and PIN, without the Lambda ever needing a Scan.

| Field | Type | Notes |
|---|---|---|
| idHash | String (partition key) | `REF#DLP-XXXXXXXX` |
| status, aps, timestamp | | Copy of what the applicant may see |
| salt | String | Random per-reference salt |
| pinHash | String | PBKDF2-HMAC-SHA256 (50,000 iterations) of the PIN. The PIN itself is never stored. |
| failedAttempts | Number | Wrong PIN count; at 5 the reference is locked (HTTP 423) |

## 3. Capacity counter (key = `CAPACITY#programme`)
| Field | Value |
|---|---|
| idHash | `CAPACITY#programme` |
| remaining | Number, starts at `PROGRAMME_CAPACITY` (default 5) |

Registration item, reference item and seat decrement are written in **one
`TransactWriteItems`**: the two puts require `attribute_not_exists(idHash)` and the
seat update requires `remaining > 0`. Either all three happen or none do, so a duplicate
cannot use a seat and two applicants cannot both take the last seat.

## Log entry format
Every attempt writes one structured log entry, whatever the outcome.

| Field | Notes |
|---|---|
| correlationId | Same ID returned to the client and stored on the registration |
| timestamp | ISO 8601, UTC |
| outcome | CONFIRMED, REJECTED, ID_CLEARED or STATUS_VIEWED |
| reason | Set when REJECTED (for example NOT_RESIDENT, DUPLICATE) |
| idHashPrefix | First 6 characters of the hash only; null when no ID was processed |

Example: `{"correlationId":"c-4f1a","timestamp":"2026-10-06T12:40:00+00:00","outcome":"REJECTED","reason":"SESSION_FULL","idHashPrefix":"a91f3c"}`

Logs never contain the national ID, the reference number or the PIN (checked by test T12).
