# Digital Literacy Programme — Registration Service

Cloud-based registration service for a community skills programme at the
University of Zululand. Applicants submit a registration; the service
validates eligibility and remaining capacity and returns a provisional
acceptance or a reasoned rejection.

**Module:** 4CPS501B Cloud Computing
**Group:** 5

---

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
src/handlers/       Lambda entry point
src/validation/     ID, APS and eligibility rules
infra/              IAM policies
scripts/            setup, verify, teardown, slice (run the slice), awslocal (AWS CLI wrapper), preflight
tests/unit/         rule-level tests
tests/integration/  end-to-end tests
docs/decisions/     architecture decision records
evidence/           screenshots, logs, test output
```

---

## Security rules — non-negotiable

- **Never commit `.env`.** It is gitignored. Confirm before every push.
- **Never commit real AWS keys.** LocalStack uses the fake values `test`/`test`.
- **Never commit real personal data.** Test identity numbers are synthetic.
- Check every screenshot before adding it to `evidence/`.

The module handbook treats submissions containing live credentials as a
serious professional error, not a minor deduction.

---

### Register a student from the command line

```bash
./scripts/register.sh
```

It asks for the 13-digit national ID and the seven subject percentages (English, Mathematics, Physical Sciences, Life Sciences, Geography, isiZulu, Life Orientation), then prints the result. Non-interactive form: `./scripts/register.sh 0303155029083 60 50 50 50 50 50 70`.

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
