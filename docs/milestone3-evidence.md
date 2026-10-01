# Milestone 3 Evidence Plan

Milestone 3 requires one reproducible vertical slice:

Client -> API Gateway -> Lambda -> DynamoDB -> structured logs -> client response.

## Evidence to collect

| Evidence | What to capture |
|---|---|
| E1 Environment | Docker, LocalStack version, setup commands, successful resource creation |
| E2 Valid request | Exact synthetic request, HTTP 201 response and correlation ID |
| E3 Processing trace | Lambda/CloudWatch-compatible structured log containing the same correlation ID |
| E4 Durable result | DynamoDB item containing the registration hash, APS, status, timestamp and correlation ID |
| E5 Invalid request | HTTP 422 response and proof that no invalid item was written |
| E6 Reproduction | Second group member independently repeats setup and the vertical slice |
| E7 Dependency failure | DynamoDB unavailable/misconfigured and HTTP 503 response |
| E8 Security | IAM policy showing only required DynamoDB operations and Lambda log operations |

## Commands

From a clean checkout:

```bash
cp .env.example .env
docker compose up -d
./scripts/setup.sh
./scripts/verify.sh
bash tests/integration/test_milestone3.sh
```

The setup script prints the API Gateway endpoint. Use that endpoint for the valid and invalid request evidence.

For DynamoDB verification:

```bash
aws --endpoint-url=http://localhost:4566 dynamodb scan --table-name dlp-registrations
```

For Lambda log-group verification:

```bash
aws --endpoint-url=http://localhost:4566 logs describe-log-groups
```

Then retrieve the relevant log events and retain the correlation ID as the trace key.

## Reproduction record

Second member: Sanele Ngcobo

Date/time: 1 October 2026, ~15:00 SAST

Machine/OS: Linux (hostname `impunga-yehlathi`), separate machine and user account from the original development environment

Result: PASS

Notes/blockers: Fresh `git clone` of the repository, followed by the exact commands in this document (`cp .env.example .env`, `docker compose up -d`, `./scripts/setup.sh`, `./scripts/verify.sh`, `bash tests/integration/test_milestone3.sh`), with no manual fixes required. `verify.sh` reported 7/7 checks passing. The integration test passed all four cases: normal (`201 CONFIRMED`, correlation ID `40286258-f947-403e-b0b3-41dd3b32169a`), duplicate (`409`), invalid (`422`), and simulated store outage (`503`).

## Important evidence rule

Use synthetic data only. Do not capture real identity numbers, credentials, access keys or populated .env files. Screenshots should retain enough service context to prove what is being demonstrated.

## Data and Observability Evidence (Unam)

### E2 — Valid request

- HTTP status: `201`
- Response status: `CONFIRMED`
- APS: `19`
- Correlation ID: `8ee3ee60-369f-4a37-b925-ecc0aef6afc3`
- Synthetic test data was used.

### E3 — Processing trace

Lambda structured logging recorded the same correlation ID:

```text
{"correlationId":"8ee3ee60-369f-4a37-b925-ecc0aef6afc3","timestamp":"2026-09-30T20:58:38.897743+00:00","outcome":"CONFIRMED","reason":null,"idHashPrefix":"b8da3a"}
```
This confirms trace continuity between the API response and Lambda processing.

### E4 — Durable result

DynamoDB stored the registration record:

- `idHash`: `b8da3a2b07b2e82351eb8b4de9d1866d0be545340ff54a2329be9bd19126bf82`
- `correlationId`: `8ee3ee60-369f-4a37-b925-ecc0aef6afc3`
- `aps`: `19`
- `status`: `CONFIRMED`
- `timestamp`: `2026-09-30T20:58:38.897743+00:00`

The capacity counter showed `remaining=9` after the successful registration.

