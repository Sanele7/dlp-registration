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
