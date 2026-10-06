#!/usr/bin/env bash
# ============================================================
# Admin view: seats and the list of accepted applicants.
#
# Runs with the operator's own (local) credentials, NOT the Lambda role,
# so the service itself keeps its least-privilege policy (no Scan).
# Shows reference numbers, APS and time only. Never national IDs or PINs.
#
# Usage: ./scripts/admin.sh
# ============================================================
set -uo pipefail
export AWS_PAGER=""
cd "$(dirname "$0")/.."
if [ -f .env ]; then set -a; source .env; set +a; fi

ENDPOINT="${LOCALSTACK_ENDPOINT:-http://localhost:4566}"
TABLE="${REGISTRATIONS_TABLE:-dlp-registrations}"
export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-test}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-test}"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"

JSON="$(aws --endpoint-url="$ENDPOINT" dynamodb scan --table-name "$TABLE" --output json 2>/dev/null)" || {
  echo "Cannot read the table. Is LocalStack running and ./scripts/setup.sh done?" >&2; exit 1; }

python3 - "$JSON" <<'PY'
import json, sys
items = json.loads(sys.argv[1])["Items"]
g = lambda it, k, t="S": it.get(k, {}).get(t, "")
cap = next((int(g(i, "remaining", "N")) for i in items if g(i, "idHash") == "CAPACITY#programme"), None)
refs = sorted((i for i in items if g(i, "idHash").startswith("REF#")), key=lambda i: g(i, "timestamp"))
print("=== Digital Literacy Programme - admin view ===")
print(f"Accepted applicants : {len(refs)}")
print(f"Seats remaining     : {cap if cap is not None else 'unknown'}")
if cap is not None:
    print(f"Seats in total      : {len(refs) + cap}")
print()
print(f"{'#':<3} {'REFERENCE':<14} {'APS':<4} {'STATUS':<10} {'REGISTERED AT (UTC)':<27} LOCKED")
for n, i in enumerate(refs, 1):
    locked = "yes" if int(g(i, "failedAttempts", "N") or 0) >= 5 else "no"
    print(f"{n:<3} {g(i, 'idHash')[4:]:<14} {g(i, 'aps', 'N'):<4} {g(i, 'status'):<10} {g(i, 'timestamp')[:26]:<27} {locked}")
if not refs:
    print("(no accepted applicants yet)")
PY
