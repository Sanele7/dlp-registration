# ADR 001 — Development platform and LocalStack version

| | |
|---|---|
| **Status** | Accepted |
| **Date** | 30 August 2026 |
| **Author** | Sanele Ngcobo — Cloud platform and security lead |
| **Affects** | Milestones 1–4. All development and evidence collection. |

---

## Context

The practical must demonstrate event-driven processing, durable state, observability, least-privilege access and cost reasoning within an eight-week window. All five members must be able to run the system, and the module handbook penalises a system that works only on one member's machine.

The handbook offers five platform options. Two of them — AWS native serverless and Google Cloud — require creating chargeable resources, which the handbook permits only with the lecturer's explicit authorisation. That authorisation had not been obtained when Milestone 1 planning began, and Milestone 1 closes on 6 September 2026.

---

## Decision

**Develop on LocalStack, pinned to version 4.14.0.**

Fall back to a provider-neutral Docker Compose stack if the team cannot run LocalStack reliably.

---

## Options considered

### Option A — AWS native serverless

The strongest option on learning value. Real Lambda, real IAM enforcement, real managed services, and no emulator caveat required in the report. It aligns directly with the Week 4 course content and Test 2 preparation.

**Not selected as the primary route because** the authorisation gate had not been passed and the milestone deadline did not permit waiting. This remains the preferred route if access is granted, and the team has an open action to ask whether AWS Educate lab access is available to the class.

### Option C — LocalStack (selected)

Emulates Lambda, DynamoDB, API Gateway and CloudWatch Logs locally in Docker. The team writes genuine AWS SDK code, so the work maps onto the module content without requiring a real account. No billing exposure and no approval delay.

It also permits safe dependency-failure testing: stopping the container produces a genuine store outage, which satisfies the required failure case without breaking anything real.

### Option D — Docker Compose (fallback)

A container service with PostgreSQL. Most robust and simplest to run, but loses the AWS alignment and requires an explicit mapping table in the report showing which local component stands in for which cloud service.

---

## The version problem, and why 4.14.0

The initial configuration pinned LocalStack `2026.05.0`, chosen as a recent stable release. It failed to start.

**Observed behaviour:** the container exited with code 55 and the message `License activation failed`, stating that no credentials were found in the environment and that a `LOCALSTACK_AUTH_TOKEN` was required.

**Cause:** LocalStack consolidated its previously separate free Community image and commercial Pro image into a single distribution in March 2026, and moved from semantic to calendar versioning at the same time. From version 2026.03.0 onward, an auth token is mandatory to start the product. A grace-period environment variable existed briefly and expired on 6 April 2026.

**Options at that point:**

1. **Register for a free account per member and set an auth token.** LocalStack retained a free tier for non-commercial use, and offers student verification. Viable, but it makes the environment depend on five separate registrations and introduces a genuine per-member secret that must never reach the repository.

2. **Pin to the last release predating the consolidation.** Version 4.14.0, built 26 February 2026, is the final Community-image release and starts without any token.

3. **Abandon LocalStack for Option D.**

**Selected: option 2.** Version 4.14.0 was pulled and started successfully, printing a warning banner that it is the Community image and that consolidation was coming — which is itself evidence that the version was chosen deliberately rather than by accident.

The version is pinned in three places so that no member can silently run a different build: `docker-compose.yml` (as the default), `.env.example` (which members copy), and `.env` (which is gitignored).

---

## Consequences

**Accepted**

- Version 4.14.0 receives no further security patches or bug fixes. This is accepted because the emulator runs only on local development machines, is bound to `127.0.0.1` rather than the network, and handles synthetic data exclusively. It is not exposed to any untrusted input.
- The `LAMBDA_EXECUTOR` setting was removed from the Compose file after 4.14.0 reported it deprecated. The Docker socket mount, which the newer Lambda provider requires, is retained.

**Required in the report**

- Each emulated component must be mapped to its cloud equivalent, with a statement of what was not validated against real AWS.
- IAM is approximated rather than enforced by LocalStack. The least-privilege policy in `infra/lambda-policy.json` grants four named DynamoDB actions on one named table, plus log writes to one named log group — no wildcards. **This was verified by inspection, not by an observed denial.** The report must say so rather than implying the policy was tested under enforcement.
- The cost worksheet uses mapped public-cloud rates, with actual local charge recorded as zero.

**Security note**

The Compose file mounts `/var/run/docker.sock` into the container, which LocalStack requires in order to start Lambda containers. This grants the container substantial privilege on the host. Acceptable for local development on personal machines; it must be carried into the Milestone 2 threat checklist rather than left unstated.

---

## Verification

Confirmed on 30 August 2026 on Ubuntu with Docker 29.7.2 and Compose v5.5.0:

```
PASS  Docker is running
PASS  LocalStack container is up
PASS  LocalStack is healthy
PASS  DynamoDB table exists
PASS  IAM role exists
5 passed, 0 failed
```

Evidence: `evidence/platform/`

---

## Review trigger

Revisit this decision if any of the following occur:

- AWS Educate lab access is confirmed available — in which case Option A becomes the primary route and LocalStack is retained for local development only
- Two or more members cannot run the environment by **13 September 2026**, the midpoint of Milestone 2 — in which case the team switches to Option D
- LocalStack 4.14.0 becomes unavailable on Docker Hub

---

## References

- Module handbook §2.3, §2.6 (platform options and the authorisation gate)
- LocalStack image consolidation announcement, March 2026
- Container startup log, 30 August 2026 — `evidence/platform/`
