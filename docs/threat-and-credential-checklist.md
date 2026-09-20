# Threat and Credential Checklist

**Module:** 4CPS501B Cloud Computing
**Milestone:** 2 — Architecture and Risk
**Owner:** Sanele Ngcobo — Cloud platform and security lead
**Date:** September 2026

---

## Purpose

This checklist records specific, identified risks to the registration system and the environment it runs in, together with the mitigation in place for each. Entries are drawn from actual review of the codebase and configuration, and from real incidents encountered during development — not from hypothetical scenarios alone.

---

## 1. Least-privilege access

**Finding:** the Lambda execution policy (`infra/lambda-policy.json`) originally granted `dynamodb:Query` alongside `PutItem`, `GetItem` and `UpdateItem`. Review against the actual data access pattern in `docs/data-model.md` showed every operation in the system is a direct lookup by a known key — a specific `idHash`, or the fixed sentinel key for the capacity counter. No part of the system searches across a range of records.

**Risk:** `Query` allows searching across table contents without knowing an exact key in advance. If the function's credentials were ever compromised, this permission would let an attacker enumerate registration records — potentially revealing how many people registered and when — beyond what the function's own logic requires or uses.

**Mitigation:** `dynamodb:Query` was removed from the policy. The corrected policy was verified directly against the running LocalStack instance (`aws iam get-role-policy`), confirming only `PutItem`, `GetItem` and `UpdateItem` remain, scoped to the single named table `dlp-registrations`.

**Residual risk:** the policy has not been tested under IAM *enforcement* — LocalStack approximates IAM behaviour rather than strictly enforcing it in the same way real AWS does. The policy's correctness has been verified by inspection of its contents, not by attempting a denied operation and observing the denial.

---

## 2. Docker socket privilege

**Finding:** `docker-compose.yml` mounts `/var/run/docker.sock` into the LocalStack container.

**Risk:** LocalStack requires this mount to start Lambda function containers on invocation — it needs the ability to instruct Docker to launch new containers. This grants the LocalStack container effective control over Docker on the host machine, not limited to its own containers.

**Mitigation:** accepted as a necessary trade-off for local Lambda emulation. This environment is never exposed to a network — bound to `127.0.0.1` only — runs solely on personal development machines, and handles exclusively synthetic data. The privilege is real but the exposure is limited to the developer's own machine.

**Residual risk:** not mitigated further. This is inherent to running Lambda emulation locally with the current LocalStack architecture, and is out of scope to change within this project.

---

## 3. Credential handling — recorded incidents

**Finding:** during Milestone 1 development, a personal access token was inadvertently exposed on two separate occasions — once captured in a screenshot shared for troubleshooting, and once typed into the wrong terminal prompt where it was echoed to the visible output.

**Response:** in both cases the exposure was identified and the affected token was revoked and regenerated before any further use. No unauthorised access to the repository resulted from either incident, as far as can be determined from repository activity.

**Significance:** this is recorded not to minimise the incidents but because they demonstrate the credential-handling process functioning as intended — detecting exposure and responding by revocation, rather than continuing to use a compromised credential.

**Mitigation adopted going forward:** the team has agreed that any screenshot or shared terminal output showing a credential prompt mid-entry is treated as a compromised credential by default, with immediate revocation, regardless of whether exposure is confirmed.

---

## 4. Secrets in version control

**Finding:** `.env` (containing local, non-production credentials) is excluded via `.gitignore`. `.env.example` contains placeholder values only.

**Risk:** a member could commit `.env` directly, or hardcode a value into a script, bypassing the gitignore protection.

**Mitigation:** `git status` is checked before every commit as standing practice. A repository-wide secret scan is planned before final submission (Milestone 4) to check both current files and commit history, since a value removed in a later commit remains recoverable from history unless the whole repository is rewritten.

**Residual risk:** this relies on manual discipline rather than an automated pre-commit hook. Adding a pre-commit secret-scanning hook is a candidate improvement for Milestone 3 if time allows.

---

## 5. Malformed or malicious input

**Finding:** the registration processor accepts JSON from any caller with no authentication layer in front of it, per the scope defined in Milestone 1.

**Risk:** a malformed payload, or a deliberately crafted one, could cause unexpected behaviour if validation does not run before any business logic executes.

**Mitigation:** validation is designed to run first, in a fixed order, before any database access — structural checks (types, required fields) precede business-rule checks (ID checksum, age, APS), which precede any read or write to the data store. A malformed payload is rejected at the earliest possible point.

**Residual risk:** this ordering must be verified in the assembled Lambda handler once written, not assumed from the design alone. This is a required check before Milestone 3.

---

## 6. Data minimisation

**Finding:** the data model stores a SHA-256 hash of the national ID (`idHash`) rather than the ID itself. Log entries store only the first six characters of that hash (`idHashPrefix`), not the full hash.

**Risk:** minimal — the hash is not reversible to the original ID, and the truncated log prefix is insufficient on its own to identify an individual with certainty.

**Mitigation:** already designed in from the outset by the data and observability lead. No further action needed.

**Residual risk:** the hash is unsalted. For this project's synthetic-data-only scope this is accepted; it would not be acceptable if the system ever handled real personal data.

---

## Summary

| # | Area | Status |
|---|---|---|
| 1 | Least-privilege IAM policy | Fixed and verified |
| 2 | Docker socket privilege | Accepted trade-off, documented |
| 3 | Credential exposure incidents | Resolved, process improved |
| 4 | Secrets in version control | Manual discipline in place, automation planned |
| 5 | Malformed input handling | Designed, verification pending in Milestone 3 |
| 6 | Data minimisation | Already sound by design |
