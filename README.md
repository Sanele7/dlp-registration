# Digital Literacy Programme — Registration Service

Cloud-based registration service for a community skills programme at the
University of Zululand. Applicants submit a registration; the service
validates eligibility and remaining capacity and returns a provisional
acceptance or a reasoned rejection.

**Module:** 4CPS501B Cloud Computing
**Group:** 5

---

## Quick start (one command)

```bash
git clone https://github.com/Sanele7/dlp-registration.git
cd dlp-registration
./scripts/start.sh
```

`start.sh` checks the tools, picks the right Docker engine, removes a stale LocalStack container, creates `.env` with 5 seats, starts LocalStack, runs `setup.sh` and `verify.sh`. Use `./scripts/start.sh --reset` for a clean slate (no registrations, 5 seats) at any time. Then run `./scripts/register.sh`.

## Prerequisites

| Requirement | Check with |
|---|---|
| Docker Engine + Compose plugin | `docker --version` and `docker compose version` |
| AWS CLI v2 | `aws --version` |
| Python 3.11+ | `python3 --version` |
| `zip` and `curl` | `zip -v` and `curl --version` |

`./scripts/setup.sh` checks all of these first and tells you what is missing.

See `docs/docker-setup.md` if Docker is not installed.

---

## Setup

Run these four commands from the repository root.

```bash
cp .env.example .env
docker compose up -d
./scripts/setup.sh
./scripts/verify.sh
```

`verify.sh` should report all checks passing. If any fail, see
Troubleshooting below.

---

## Daily use

| Task | Command |
|---|---|
| Start | `docker compose up -d` |
| Check health | `./scripts/verify.sh` |
| View logs | `docker compose logs -f localstack` |
| Stop (keep data) | `docker compose down` |
| Stop and wipe | `./scripts/teardown.sh` |

---

## Repository layout

```
src/handlers/       Lambda entry point (register, check and status routes)
src/validation/     National ID and APS rules
infra/              IAM policies
scripts/            start, setup, verify, teardown, register, check-status, admin, slice, awslocal, preflight
tests/unit/         rule and handler tests (30)
tests/integration/  end-to-end tests (Milestone 3 and the Milestone 4 final set)
docs/               architecture and event-flow diagrams, data model, interfaces, validation rules,
                    decision log, ADRs, cost worksheet, threat checklist, contribution record
evidence/           indexed evidence pack: tests, platform checks, screenshots, peer review
```

---

## Architecture summary

`Applicant (scripts) -> API Gateway -> Lambda -> DynamoDB`, with structured logs for every attempt.
One stateless Lambda serves three POST routes: `/registrations` (register), `/registrations/check`
(read-only early screening) and `/registrations/status` (reference + PIN lookup). Rules run in a fixed
order before any write: residence, national ID and checksum, age 18-25, APS at most 20. The registration
item, a reference lookup item and the seat decrement are written in **one DynamoDB transaction**, so a
duplicate cannot use a seat and the programme cannot be over-enrolled. See `docs/architecture.png`,
`docs/event-flow.png`, `docs/data-model.md`, `docs/interfaces.md` and `docs/decision-log.md`.

| Local component | AWS equivalent |
|---|---|
| LocalStack REST API | Amazon API Gateway |
| Lambda, python3.11, 128 MB | AWS Lambda |
| DynamoDB table `dlp-registrations` | Amazon DynamoDB |
| Lambda log group | Amazon CloudWatch Logs |
| IAM role `dlp-lambda-role` | AWS IAM (policy inspected, not enforced by LocalStack) |

## Configuration variables

Copy `.env.example` to `.env` (`start.sh` does this). `.env` is gitignored. Values are placeholders or fake local values only.

| Variable | Default | Meaning |
|---|---|---|
| `LOCALSTACK_VERSION` | `4.14.0` | Pinned LocalStack image (see ADR 001) |
| `LOCALSTACK_ENDPOINT` | `http://localhost:4566` | Where the AWS CLI and scripts connect |
| `LOCALSTACK_DEBUG` | `0` | LocalStack debug logging |
| `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` | `test`, `test` | Fake credentials required by the SDK. Never use real keys |
| `AWS_DEFAULT_REGION` | `us-east-1` | Region used by the CLI and the table ARN |
| `REGISTRATIONS_TABLE` | `dlp-registrations` | DynamoDB table name |
| `COUNTER_TABLE` | `dlp-capacity` | Reserved; the seat counter lives in the registrations table |
| `LAMBDA_FUNCTION_NAME` | `dlp-registration-processor` | Lambda name |
| `PROGRAMME_CAPACITY` | `5` | Seats available (read by `setup.sh` and the Lambda) |
| `LOG_LEVEL` | `INFO` | Lambda log level |
| `API_GATEWAY_NAME`, `API_GATEWAY_STAGE` | `dlp-registration-api`, `local` | API name and stage |
| `MIN_AGE`, `MAX_AGE` | `18`, `25` | Lambda environment variables (code defaults; not in `.env.example`) |

## Version pins

| What | Pin | Where |
|---|---|---|
| LocalStack image | `4.14.0` | `docker-compose.yml`, `.env.example` |
| Lambda runtime | `python3.11` | `scripts/setup.sh` |
| Test tools (local only) | `pytest>=8`, `boto3>=1.34` | `requirements-dev.txt` |

## Testing

| Layer | Command | Expected |
|---|---|---|
| Unit (30 tests, no Docker needed) | `pip install -r requirements-dev.txt` then `AWS_DEFAULT_REGION=us-east-1 AWS_ACCESS_KEY_ID=x AWS_SECRET_ACCESS_KEY=x python3 -m pytest tests/unit -q` | `30 passed` |
| Environment check | `./scripts/verify.sh` | `7 passed, 0 failed` |
| Milestone 3 integration | `bash tests/integration/test_milestone3.sh` | `All Milestone 3 integration checks passed.` |
| Milestone 4 final test set | `./scripts/start.sh --reset` then `bash tests/integration/test_milestone4.sh 2>&1 \| tee evidence/tests/m4-final-test-run.txt` | `=== Result: N passed, 0 failed ===` |

The Milestone 4 set needs a fresh environment, covers normal, invalid, dependency-failure, recovery,
security/control and teardown/rebuild cases (T1-T17), and ends by tearing the environment down and
rebuilding it. `SKIP_TEARDOWN=1` skips the last step. The Milestone 3 test leaves one registration behind,
so reset (`./scripts/start.sh --reset`) before running the Milestone 4 set. The evidence is indexed in `evidence/INDEX.md`.

## Teardown

```bash
./scripts/teardown.sh
```

Stops and removes the container and network, deletes `./volume` (falling back to a throwaway container if
files are root-owned), and verifies that no `dlp-` container and no local state remain. Rebuild with
`./scripts/start.sh`.

## Release

The version used for the demonstration is the git tag recorded here: **[INSERT TAG, e.g. v1.0.0, and commit hash]**.
Check it out with `git checkout <tag>`.

## AI assistance

AI assistance (Claude, by Anthropic) was used for scripts, tests and documentation drafts. See
`docs/contribution-record.md` for the full statement.

---

## Security rules — non-negotiable

- **Never commit `.env`.** It is gitignored. Confirm before every push.
- **Never commit real AWS keys.** LocalStack uses the fake values `test`/`test`.
- **Never commit real personal data.** Test identity numbers are synthetic.
- Check every screenshot before adding it to `evidence/`.

The module handbook treats submissions containing live credentials as a
serious professional error, not a minor deduction.

---

### Register a student and check an application

```bash
./scripts/register.sh
```

It first asks **"Are you from KwaDlangezwa?"**. Answering *no* ends the application with the reason. Answering *yes* it asks for the 13-digit national ID and the seven subject percentages (English, Mathematics, Physical Sciences, Life Sciences, Geography, isiZulu, Life Orientation). On success it prints a **reference number** and a **6-digit PIN** (shown once) and reminds the student to bring the required documents, including proof of residence, to the branch helpdesk.

Non-interactive: `./scripts/register.sh yes 0303155029083 60 50 50 50 50 50 70` or `./scripts/register.sh no`.

To check an application later, with the reference and PIN:

```bash
./scripts/check-status.sh
```

`register.sh` stops right after the national ID is entered if the ID is invalid, over/under age, **already registered** (`NOT REGISTERED (DUPLICATE)`) or the programme is full, so the student never has to type their marks.

Admin view of the seats and the accepted applicants (reference, APS, time; no national IDs or PINs):

```bash
./scripts/admin.sh
```

The programme has **5 seats** by default (`PROGRAMME_CAPACITY` in `.env`; the demo uses 5).

## Troubleshooting

**`bash: api-id: No such file or directory` (or similar with `<...>`)**
A placeholder such as `<api-id>` was pasted literally. Never type angle
brackets; use `./scripts/slice.sh`, or the `API_ID=$(...)` lookup above.

**`aws: [ERROR]: An error occurred (NoRegion)` or credential errors**
Your terminal has no AWS settings (only the scripts read `.env`). Use
`./scripts/awslocal.sh ...` instead of calling `aws` directly, or run
`set -a; source .env; set +a` first.

**`aws: command not found` or `zip: command not found`**
Install the missing tool; `./scripts/preflight.sh` lists what is missing.

**`rm: cannot remove './volume/...': Permission denied` during teardown**
LocalStack creates `./volume` as root. `teardown.sh` now removes it through
a throwaway container; pull the latest `scripts/teardown.sh`.

**`permission denied ... docker.sock`**
You are not in the `docker` group, or have not logged out since being added.
Log out and back in, or reboot.

**`Cannot connect to the Docker daemon`**
```bash
sudo systemctl start docker
```

**`docker-compose: command not found`**
Use `docker compose` with a space. The hyphenated form is the old v1 syntax.

**LocalStack unhealthy or setup.sh times out**
```bash
docker compose logs localstack
```
If it is stuck, wipe and rebuild:
```bash
./scripts/teardown.sh && docker compose up -d && ./scripts/setup.sh
```

**Scripts fail with `\r: command not found`**
Line endings were converted to CRLF. `.gitattributes` should prevent this.
Fix an affected file with:
```bash
sed -i 's/\r$//' scripts/*.sh
```

---

## Roles

| Area | Owner |
|---|---|
| Architecture and integration | Asename Kuphelele Malamule |
| Platform and security | Sanele Ngcobo |
| Function development | Bandile Shezi |
| Data and observability | Unam Mkhomanzi |
| QA, cost and documentation | Siphokazi Zothile Mongisa Majozi |

## Milestone 3 — working vertical slice

The integrated path is:

`Client → API Gateway → Lambda → DynamoDB`

Lambda emits structured CloudWatch-compatible logs containing a correlation ID, outcome and reason. The same correlation ID is returned to the client and can be used to trace the request.

### Local API

The easiest way to exercise the whole slice (valid request, log trace,
stored record, rejected request) is one command, with nothing to copy or
fill in:

```bash
./scripts/slice.sh
```

To run the AWS CLI by hand, use the wrapper. It sets the endpoint, region
and fake credentials for you, so it works in any new terminal:

```bash
./scripts/awslocal.sh dynamodb scan --table-name dlp-registrations
./scripts/awslocal.sh logs describe-log-groups
```

To send a request yourself, look up the API id automatically (do **not**
type `<api-id>` literally; the shell treats `<` as redirection):

```bash
API_ID=$(./scripts/awslocal.sh apigateway get-rest-apis \
  --query "items[?name=='dlp-registration-api'].id | [0]" --output text)

curl -s -i -X POST "http://localhost:4566/restapis/$API_ID/local/_user_request_/registrations" \
  -H 'Content-Type: application/json' \
  -d '{
    "nationalId": "0303155029083",
    "subjectResults": [
      {"subject":"englishHomeLanguage","percentage":50},
      {"subject":"mathematics","percentage":40},
      {"subject":"physicalSciences","percentage":40},
      {"subject":"lifeSciences","percentage":40},
      {"subject":"geography","percentage":40},
      {"subject":"isiZulu","percentage":40},
      {"subject":"lifeOrientation","percentage":70}
    ]
  }'
```

Expected normal response: HTTP `201`, `status: CONFIRMED`, an APS value and a `correlationId`.

To trace a correlation ID through the Lambda logs (replace the value with
the one you received):

```bash
CID=40286258-f947-403e-b0b3-41dd3b32169a   # example; use your own
./scripts/awslocal.sh logs filter-log-events \
  --log-group-name /aws/lambda/dlp-registration-processor --filter-pattern "$CID"
```

A second registration with the same national ID returns `409`; for a clean
run use `./scripts/teardown.sh && docker compose up -d && ./scripts/setup.sh`.

### Milestone 3 integration test

After setup, run:

```bash
bash tests/integration/test_milestone3.sh
```

The test covers:
- normal registration;
- duplicate registration;
- invalid input;
- simulated DynamoDB store outage returning HTTP `503`.

The test uses synthetic data only.

### Reproduction by a second member

A second member should clone the repository and independently execute:

```bash
cp .env.example .env
docker compose up -d
./scripts/setup.sh
./scripts/verify.sh
bash tests/integration/test_milestone3.sh
```

Record the member, machine/date, commands used and result in the Milestone 3 evidence pack.
