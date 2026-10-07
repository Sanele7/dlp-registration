# Cost worksheet, resource inventory and teardown (Milestone 4)

Updates `docs/cost-estimate.md` (Milestone 2) for the final system: three routes, a reference lookup item per registration, 5 seats.
Actual cost is **$0**: everything ran on LocalStack with no cloud account or payment method.

## Assumptions
List prices, US East (N. Virginia), as in `docs/cost-estimate.md` (checked September 2026). Re-confirm on the AWS pricing pages before any real deployment.

- Per **accepted** applicant: 3 Lambda invocations (early check, registration, one status check); 6 write request units (a transaction of 3 items costs 2 units each); 3 consistent read units.
- Per **rejected** attempt: 1 invocation and up to 2 read units.
- Lambda 128 MB, 50 ms average billed duration (observed: 65 ms for an accepted registration, 1 ms for an invalid payload).
- About 1.5 KB of log data per invocation, including platform lines.

## Worksheet

| Line item | Rate | A: this intake (5 accepted + 20 rejected attempts) | B: 500 accepted + 500 rejected per month |
|---|---|---|---|
| Lambda requests | $0.20 per million | 35 calls = $0.000007 | 2,000 calls = $0.0004 |
| Lambda duration | $0.0000166667 per GB-second | $0.000004 | $0.0002 |
| DynamoDB writes | $0.625 per million WRU | 30 WRU = $0.000019 | 3,000 WRU = $0.0019 |
| DynamoDB reads | $0.125 per million RRU | 55 RRU = $0.000007 | 2,500 RRU = $0.0003 |
| CloudWatch Logs | $0.50 per GB ingested | 0.05 MB = $0.000026 | 3 MB = $0.0015 |
| API Gateway (REST) | $3.50 per million calls | 35 calls = $0.00012 | 2,000 calls = $0.0070 |
| **Total at list price** | | **about $0.0002** | **about $0.011 per month** |
| After free tiers | | $0 | $0 for Lambda, DynamoDB and logs; API Gateway free tier is time-limited |
| **Actual cost (LocalStack)** | | **$0** | |

Cost drivers: API Gateway requests, then DynamoDB writes. DynamoDB writes would reach $1 only at roughly 270,000 registrations a month. The early-check call is about a third of requests; dropping it, or using an HTTP API, would lower the largest line.

## Resource inventory

| Resource | Name / setting | Created by | Removed by |
|---|---|---|---|
| Docker container | `dlp-localstack` (`localstack/localstack:4.14.0`), bound to 127.0.0.1:4566 | `docker compose up` | `teardown.sh` |
| Docker network | `dlp-registration_default` | `docker compose up` | `docker compose down` |
| DynamoDB table | `dlp-registrations`, key `idHash`, on-demand | `setup.sh` | container removal |
| Lambda function | `dlp-registration-processor`, python3.11, 128 MB, `handlers.registration.handler` | `setup.sh` | container removal |
| IAM role and policy | `dlp-lambda-role`, inline policy `dlp-registration-write` | `setup.sh` | container removal |
| API Gateway REST API | `dlp-registration-api`, stage `local`, routes `/registrations`, `/check`, `/status` | `setup.sh` | container removal |
| Log group | `/aws/lambda/dlp-registration-processor` | first invocation | container removal |
| Local files | `./volume` (LocalStack state), `.env` | LocalStack / `start.sh` | `teardown.sh` removes `./volume` |

## Teardown evidence

`./scripts/teardown.sh` stops the container, removes the volumes and `./volume`, then checks that no `dlp-` container and no local state remain. Its output is evidence figure 12 (`evidence/screenshots/fig12-teardown.png`), and test T14 in `evidence/tests/m4-final-test-run.txt` repeats the check and rebuilds the minimum slice.
