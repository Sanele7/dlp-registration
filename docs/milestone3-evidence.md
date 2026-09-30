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

Second member: ____________________

Date/time: ____________________

Machine/OS: ____________________

Result: PASS / FAIL

Notes/blockers: ____________________

## Important evidence rule

Use synthetic data only. Do not capture real identity numbers, credentials, access keys or populated .env files. Screenshots should retain enough service context to prove what is being demonstrated.
