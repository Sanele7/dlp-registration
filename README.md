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
scripts/            setup, verify, teardown
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

## Troubleshooting

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
