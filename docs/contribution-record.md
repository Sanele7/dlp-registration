# Contribution record

Documented contributions come from the repository (ADR authors, evidence owners, role assignments in the README).
Each member completes the last column in their own words before submission.

| Member | Role | Documented in the repository | Additional contribution (member to complete) |
|---|---|---|---|
| Asename Kuphelele Malamule | Architecture and integration | ADR 002; architecture diagram; interface design sign-off | [to complete] |
| Sanele Ngcobo | Platform and security | ADR 001; threat and credential checklist; repository setup | [to complete] |
| Bandile Shezi | Function development | Registration Lambda implementation; interface contract | [to complete] |
| Unam Mkhomanzi | Data and observability | Data model; logging and correlation evidence; Milestone 4 scripts, tests and report | [to complete] |
| Siphokazi Zothile Mongisa Majozi | QA, cost and documentation | Cost estimate; clean-clone reproduction checks; documentation | [to complete] |

Commit counts are not a reliable measure of contribution here: some commits were made through one member's account while the work was done with AI assistance (see below).

## Statement on AI assistance

The group used Claude (an AI assistant from Anthropic) during Milestones 3 and 4 as a development and writing aid. It helped draft and debug the helper scripts (`start.sh`, `register.sh`, `check-status.sh`, `admin.sh`, preflight and teardown fixes), the Milestone 4 additions to the registration handler (residence, age, reference and PIN, status lookup, early screening), the unit and integration tests, and first drafts of documents including the final report. Group members reviewed the output, ran it on their own computers and made the design decisions recorded in `docs/decision-log.md`.

[Confirm this wording against the module's policy on AI use before submitting.]

## Peer review

Peer review evidence goes in `evidence/peer-review/` (see the README there).
