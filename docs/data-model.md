# Data model — dlp-registrations table

## Registration record
| Field | Type | Notes |
|---|---|---|
| idHash | String (partition key) | SHA-256 hash of national ID, never the raw ID |
| status | String | CONFIRMED or REJECTED |
| reason | String (nullable) | Populated only when status is REJECTED |
| aps | Number | Computed admission point score |
| timestamp | String (ISO 8601) | When the decision was made |
| correlationId | String | Links this record to its log entries |

## Capacity counter record
A single sentinel row in the same table tracks remaining seats.

| Field | Value |
|---|---|
| idHash | "CAPACITY#programme" |
| remaining | Number, starts at 10 |

Seat allocation MUST use a DynamoDB conditional update against this row
(decrement only if remaining > 0) to avoid a race condition when two
applications arrive for the last seat at the same time.

## Status
The capacity counter row was manually initialized on 2026-09-13 with `remaining = 10`, ahead of the function being deployed. Verified with `awslocal dynamodb scan --table-name dlp-registrations`.

## Log entry format

Every registration attempt writes one structured log entry, regardless of outcome.

| Field | Type | Notes |
|---|---|---|
| correlationId | String | Same ID stored on the registration record — links log to record |
| timestamp | String (ISO 8601) | When the attempt was processed |
| outcome | String | CONFIRMED or REJECTED |
| reason | String (nullable) | Populated only when outcome is REJECTED |
| idHashPrefix | String | First 6 characters of idHash only — enough to spot duplicates in logs without exposing the full hash |

**Example log line:**
`{"correlationId": "c-4f1a", "timestamp": "2026-09-13T12:40:00Z", "outcome": "REJECTED", "reason": "SESSION_FULL", "idHashPrefix": "a91f3c"}`