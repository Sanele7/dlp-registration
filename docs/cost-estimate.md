# Cost Estimate

**Module:** 4CPS501B Cloud Computing
**Milestone:** 2 — Architecture and Risk
**Owner:** Siphokazi Zothile Mongisa Majozi — QA, cost and documentation lead
**Date:** September 2026

---

## Purpose

This estimate maps the Digital Literacy Programme registration service onto current, published AWS pricing, so that its running cost can be assessed even though it is developed and demonstrated entirely on LocalStack at zero charge. Per Milestone 1 §6, no chargeable AWS resource has been provisioned; the figures below are for comparison and understanding only.

---

## Pricing used

Current AWS on-demand pricing, US East (N. Virginia), as published by AWS and cross-checked against third-party pricing summaries in September 2026.

| Service | Metered rate | Free tier (recurring, no expiry) |
|---|---|---|
| Lambda | $0.20 per million requests, plus a duration charge per GB-second | 1,000,000 requests/month |
| DynamoDB (on-demand) | $0.625 per million write request units, $0.125 per million read request units | 25 GB storage; 25 WCU/25 RCU equivalent throughput/month |
| CloudWatch Logs | $0.50 per GB ingested (Standard class) | First 5 GB ingested/month |

---

## Usage modelled

Each registration attempt is assumed to generate:

- 1 Lambda invocation
- 2 DynamoDB writes (the registration record itself, plus the atomic update to the capacity counter)
- 1 DynamoDB read (the duplicate check against the applicant's ID hash)
- 1 structured log entry, approximately 250–300 bytes

### Scenario A — Actual scale (this intake)

10 registrations, once.

| Metric | Volume | % of free tier |
|---|---|---|
| Lambda invocations | 10 | 0.001% |
| DynamoDB writes | 20 | negligible |
| DynamoDB reads | 10 | negligible |
| Log data ingested | ~3 KB | negligible |

**Cost: $0.** Every figure sits entirely within the free tier for its service.

### Scenario B — Projected scale (university-wide, multiple programmes)

500 registrations per month, modelling the same system supporting several community programmes running concurrently.

| Metric | Volume | % of free tier |
|---|---|---|
| Lambda invocations | 500 | 0.05% |
| DynamoDB writes | 1,000 | negligible |
| DynamoDB reads | 500 | negligible |
| Log data ingested | ~150 KB | negligible |

**Cost: $0.** Still entirely within the free tier for every service.

---

## Why cost stays at zero, and where that changes

Both scenarios return the same figure not because local execution is free — it is, but that is a separate fact — but because AWS's own free tier absorbs this workload's volume by a wide margin under real AWS pricing.

The tightest constraint among the three services is DynamoDB's write throughput. At $0.625 per million write request units, a monthly bill of roughly $1 in DynamoDB write charges alone would require approximately 1.6 million writes. At 2 writes per registration, that is roughly **800,000 registrations in a single month** before this architecture begins to cost anything measurable.

This is well beyond any realistic volume for a single community skills programme, and serves as the practical ceiling of this architecture's genuinely free operating range: the system would need to scale roughly 1,600 times beyond the projected scenario above before incurring any DynamoDB charge, and Lambda's request free tier alone would absorb over 3,000 times the projected monthly volume before its own charges began.

---

## Local execution cost

**$0**, confirmed. No AWS account, billing profile, or payment method is used at any point in this project. All figures above are calculated from published AWS list pricing purely for comparison, per the platform decision recorded in Milestone 1 §6 and ADR 001.

---

## Sources

- AWS Lambda pricing (request and duration rates, free tier), accessed September 2026
- AWS DynamoDB on-demand pricing (WRU/RRU rates, free tier), accessed September 2026
- AWS CloudWatch Logs pricing (ingestion rate, free tier), accessed September 2026

Rates are US East (N. Virginia) list prices and may vary by region. AWS pricing is subject to change; figures here reflect rates published at the time of writing and should be reconfirmed against the official AWS pricing pages before any real deployment decision.
