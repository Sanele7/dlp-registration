# Evidence index

Maps each requirement and each handbook item to the code, the test and the evidence file.
Screenshots are numbered as the figures in the final report; save them in `evidence/screenshots/`
(suggested names in the last table). Items marked **TO ADD** are produced by running the commands shown.

## Requirements to tests to evidence

| Req | Requirement | Where implemented | Tests | Evidence |
|---|---|---|---|---|
| FR1 | Residence question; "no" ends with NOT_RESIDENT | `src/handlers/registration.py` | T8d; unit `test_non_resident_...` | Fig 4 |
| FR2 | ID: 13 digits, real date, Luhn checksum | `src/validation/national_id.py` | T5; unit `test_national_id.py` | Fig 4 |
| FR3 | Age 18-25 from the ID | `registration.py` | T8b, T8c; unit `test_applicant_over/under_age...` | Fig 4 |
| FR4 | APS (best 6 excluding Life Orientation) at most 20 | `src/validation/aps.py` | T1-T3, T7; unit `test_aps.py` | Fig 7 |
| FR5 | One registration per ID | transaction condition | T4; early screening T17 | Fig 4 |
| FR6 | Five seats, never over-enrolled | transaction condition on `CAPACITY#programme` | T3 (seats), T16 | Fig 6, Fig 10 |
| FR7 | Reference and one-time PIN; status check; lockout | `registration.py` | T1, T15; unit `test_status_check_...` | Fig 3, Fig 5 |
| FR8 | Plain-language reason on every rejection | `registration.py` (`detail`) | T4, T8d; unit `test_rejection_includes_...` | Fig 4 |
| FR9 | Traceable by correlation ID | structured log in `registration.py` | T12; `slice.sh` step 2 | Fig 9 |
| FR10 | Reproducible build, test, teardown | `scripts/start.sh`, `teardown.sh` | T14 | Fig 2, Fig 12 |
| NFR | No raw ID, PIN or reference in logs; least privilege; secret scan; safe failure | `infra/lambda-policy.json`, `.gitignore` | T9-T13 | Fig 10, Fig 11 |

## Handbook 7.1 test set to test IDs

| Class | Minimum | Tests |
|---|---|---|
| Normal cases | 3 | T1, T2, T3 (boundary APS 20), T4 (repeated journey) |
| Invalid input | 2 | T5 (checksum), T6 (missing field), T7 (out of range), T8 (wrong type), T8b-T8d |
| Dependency failure | 1 | T9 (store unavailable, 503) |
| Recovery | 1 | T10 (same request succeeds after restore) |
| Security / control | 1 | T11 (least-privilege IAM), T12 (no IDs in logs), T13 (secret scan), T15 (PIN lockout) |
| Teardown / rebuild | 1 | T14 |

## Handbook 7.2 repository contents to location

| Item | Location |
|---|---|
| README: prerequisites, architecture summary, configuration, run, test, teardown | `README.md` |
| Architecture and event-flow diagrams | `docs/architecture.mermaid` / `.png`, `docs/event-flow.mermaid` / `.png` |
| Source code | `src/handlers/`, `src/validation/` |
| Compose / infrastructure and version pins | `docker-compose.yml`, `infra/`, `.env.example`, `requirements-dev.txt` |
| Automated tests and results | `tests/unit/`, `tests/integration/`, `evidence/tests/` |
| Safe example configuration | `.env.example` |
| Evidence pack | this folder |
| Decision log, contribution record, peer review | `docs/decision-log.md`, `docs/decisions/`, `docs/contribution-record.md`, `evidence/peer-review/` |
| Release tag / commit used for the demonstration | recorded in the final report and in `README.md` (section "Release") |

## Evidence files

| File | Produced by | Status |
|---|---|---|
| `evidence/tests/m4-final-test-run.txt` | `bash tests/integration/test_milestone4.sh 2>&1 \| tee evidence/tests/m4-final-test-run.txt` | **TO ADD** |
| `evidence/tests/unit-test-results.txt` | `python3 -m pytest tests/unit -v` | present (30 passed) |
| `evidence/tests/clean-rerun-confirmation.txt` | Milestone 3 clean-clone run | present |
| `evidence/platform/` | Milestone 1-2 platform and security checks | present |
| `evidence/screenshots/fig02-start.png` ... `fig14-peer-review.png` | figures 2-14 of the final report | **TO ADD** |
| `evidence/peer-review/` | peer-review forms | **TO ADD** |
