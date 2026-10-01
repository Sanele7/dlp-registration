# ADR 002 — Registration service integration architecture

| | |
|---|---|
| **Status** | Accepted |
| **Date** | 1 October 2026 |
| **Author** | Asename Kuphelele Malamule — Architecture and integration lead |
| **Affects** | Milestone 3 and subsequent milestones |

## Context

The Digital Literacy Programme registration service must provide one reproducible
vertical slice from client request through processing and durable storage.

The required integration path is:

**Client → API Gateway → Lambda → DynamoDB**

The service also requires structured observability so that a registration attempt
can be traced using a correlation ID.

## Decision

Use API Gateway as the HTTP entry point, with a `POST /registrations` route
configured with an AWS proxy integration to the registration Lambda.

The Lambda is stateless and is responsible for:

- parsing and validating the request;
- validating the national ID and deriving age;
- calculating APS;
- deriving a SHA-256 `idHash` without storing the raw national ID;
- atomically creating the registration record and reserving programme capacity;
- emitting a structured decision log containing the correlation ID;
- returning the HTTP result and correlation ID to the caller.

DynamoDB is used as the durable state store. Registration records and the
programme capacity sentinel are held in the `dlp-registrations` table.

Registration creation and seat reservation are performed in one DynamoDB
transaction. The registration write uses a conditional expression preventing
an existing `idHash` from being inserted, while the capacity update only
decrements the counter when remaining capacity is greater than zero. This
prevents duplicate submissions from consuming seats and prevents
over-enrolment caused by concurrent requests.

## Integration contract

The external interface is:

`POST /registrations`

The Lambda returns:

- `201` for a successful registration;
- `422` for invalid input;
- `409` for duplicate registration or a full session;
- `503` when storage is unavailable.

Every response contains a correlation ID so the request can be connected to
the corresponding structured log entry.

## Trust boundaries

The applicant/client is outside the trusted service boundary.

API Gateway, Lambda, DynamoDB and the logging destination form the implemented
service boundary. Document verification/intake is explicitly outside the
implemented system and is represented separately in the architecture diagram.

## Consequences

### Benefits

- Clear separation between HTTP ingress, business processing and durable state.
- Stateless Lambda processing supports repeatable local deployment.
- DynamoDB provides durable registration state.
- Atomic seat allocation prevents race-condition over-enrolment.
- The correlation ID provides an end-to-end trace key.
- The design maps directly to the Milestone 3 vertical slice and can be
  reproduced using the LocalStack environment.

### Limitations

- Milestone 3 validates the architecture locally using LocalStack rather than
  a live AWS deployment.
- API Gateway, Lambda and DynamoDB behaviour is therefore not claimed to be
  fully equivalent to production AWS behaviour.
- IAM policy configuration is documented separately; LocalStack verification
  does not demonstrate enforcement equivalent to live AWS IAM.

## Evidence

The implementation is deployed by `scripts/setup.sh`, which creates the
DynamoDB table, deploys the Lambda, configures `POST /registrations` as an
AWS proxy integration, grants API Gateway permission to invoke the Lambda,
and deploys the API stage.

The architecture is represented in `docs/architecture.mermaid`.

Milestone 3 end-to-end behaviour is exercised by
`tests/integration/test_milestone3.sh`.
