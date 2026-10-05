#!/usr/bin/env bash
# ============================================================
# Milestone 4 final test set (handbook 7.1)
#
#   T1-T3   Normal cases (3 different valid inputs)
#   T4      Repeated user journey (duplicate rejected, no extra seat used)
#   T5-T8   Invalid-input cases (each proves NO durable state was written)
#   T9      Dependency failure (store unavailable -> 503, state untouched)
#   T10     Recovery (same request succeeds once the store is back)
#   T11-T13 Security / control checks (least-privilege IAM, no ID in logs,
#           secret scan)
#   T14     Teardown / rebuild (destroy everything, recreate the slice)
#
# Run from the repository root, on a FRESH environment:
#   ./scripts/teardown.sh && docker compose up -d && ./scripts/setup.sh
#   bash tests/integration/test_milestone4.sh 2>&1 | tee evidence/tests/m4-final-test-run.txt
#
# Set SKIP_TEARDOWN=1 to skip T14 (it destroys and rebuilds the environment).
# All national IDs and marks below are synthetic.
# ============================================================
set -uo pipefail

if [ -f .env ]; then set -a; source .env; set +a; fi

ENDPOINT="${LOCALSTACK_ENDPOINT:-http://localhost:4566}"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
TABLE="${REGISTRATIONS_TABLE:-dlp-registrations}"
FUNCTION="${LAMBDA_FUNCTION_NAME:-dlp-registration-processor}"
API_NAME="${API_GATEWAY_NAME:-dlp-registration-api}"
STAGE="${API_GATEWAY_STAGE:-local}"
CAPACITY="${PROGRAMME_CAPACITY:-10}"

export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-test}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-test}"
export AWS_DEFAULT_REGION="$REGION"

aws_local() { aws --endpoint-url="$ENDPOINT" "$@"; }

PASSN=0; FAILN=0
expect() { # id description expected actual
  if [ "$3" = "$4" ]; then
    echo "PASS $1 $2 (got: $4)"; PASSN=$((PASSN+1))
  else
    echo "FAIL $1 $2 (expected: $3, got: $4)"; FAILN=$((FAILN+1))
  fi
}

resolve_base() {
  API_ID="$(aws_local apigateway get-rest-apis --query "items[?name=='$API_NAME'].id | [0]" --output text)"
  BASE="$ENDPOINT/restapis/$API_ID/$STAGE/_user_request_/registrations"
}

post() { # payload ; sets STATUS and BODY
  local r
  r="$(curl -sS -w '\n%{http_code}' -X POST "$BASE" -H 'Content-Type: application/json' -d "$1")"
  STATUS="$(printf '%s\n' "$r" | tail -n1)"
  BODY="$(printf '%s\n' "$r" | sed '$d')"
}

jget() { python3 -c 'import json,sys; print(json.loads(sys.stdin.read()).get(sys.argv[1],""))' "$1" <<<"$BODY"; }

mk() { # nationalId english maths physsci lifesci geography isizulu lifeorientation
  python3 - "$@" <<'PY'
import json, sys
nid, *v = sys.argv[1:]
names = ["englishHomeLanguage", "mathematics", "physicalSciences", "lifeSciences",
         "geography", "isiZulu", "lifeOrientation"]
print(json.dumps({"nationalId": nid,
                  "subjectResults": [{"subject": n, "percentage": int(x)} for n, x in zip(names, v)]}))
PY
}

item_count() { aws_local dynamodb scan --table-name "$TABLE" --select COUNT --query Count --output text; }
seats_left()  { aws_local dynamodb get-item --table-name "$TABLE" --key '{"idHash":{"S":"CAPACITY#programme"}}' --query 'Item.remaining.N' --output text; }

set_store() { # table name the Lambda should use
  aws_local lambda update-function-configuration --function-name "$FUNCTION" \
    --environment "Variables={REGISTRATIONS_TABLE=$1,PROGRAMME_CAPACITY=$CAPACITY,LOG_LEVEL=${LOG_LEVEL:-INFO}}" >/dev/null
  sleep 2
}
trap 'set_store "$TABLE" >/dev/null 2>&1 || true' EXIT

resolve_base

echo "=== Milestone 4 final test set ==="
echo "API: $BASE"

# ---- Precondition: fresh environment ----------------------
if [ "$(item_count)" != "1" ] || [ "$(seats_left)" != "$CAPACITY" ]; then
  echo "Environment is not fresh (expected only the capacity item, $CAPACITY seats)."
  echo "Run: ./scripts/teardown.sh && docker compose up -d && ./scripts/setup.sh"
  exit 2
fi
echo "Fresh start: items=$(item_count), seats=$(seats_left)"
echo

# ---- Normal cases -----------------------------------------
echo "--- Normal cases ---"
P1="$(mk 0303155029083 50 40 40 40 40 40 70)"        # typical applicant
post "$P1"
expect T1 "normal: typical applicant returns 201" 201 "$STATUS"
expect T1 "normal: APS 19" 19 "$(jget aps)"
CID1="$(jget correlationId)"; echo "     correlationId: $CID1"

post "$(mk 0601205012086 35 32 38 41 33 30 60)"      # low scorer
expect T2 "normal: low-scoring applicant returns 201" 201 "$STATUS"
expect T2 "normal: APS 13" 13 "$(jget aps)"

post "$(mk 0508125123085 50 50 40 40 40 40 55)"      # exactly on the APS ceiling
expect T3 "normal: boundary APS (=20, the ceiling) returns 201" 201 "$STATUS"
expect T3 "normal: APS 20" 20 "$(jget aps)"

expect T3 "3 registrations stored (+ capacity item)" 4 "$(item_count)"
expect T3 "seats left decremented by exactly 3" $((CAPACITY-3)) "$(seats_left)"
echo

echo "--- Repeated user journey ---"
post "$P1"
expect T4 "same applicant again returns 409" 409 "$STATUS"
expect T4 "reason DUPLICATE" DUPLICATE "$(jget reason)"
expect T4 "duplicate consumed no seat" $((CAPACITY-3)) "$(seats_left)"
echo

# ---- Invalid input: each must leave state untouched --------
echo "--- Invalid-input cases (state must not change) ---"
BEFORE_ITEMS="$(item_count)"; BEFORE_SEATS="$(seats_left)"

post "$(mk 1234567890123 50 40 40 40 40 40 70)"
expect T5 "invalid: ID fails checksum -> 422" 422 "$STATUS"
expect T5 "reason INVALID_NATIONAL_ID" INVALID_NATIONAL_ID "$(jget reason)"

post '{"nationalId":"9904276001082","subjectResults":[{"subject":"mathematics","percentage":50}]}'
expect T6 "invalid: missing subjects -> 422" 422 "$STATUS"
expect T6 "reason INVALID_PAYLOAD" INVALID_PAYLOAD "$(jget reason)"

post "$(mk 9904276001082 85 85 85 85 85 85 85)"
expect T7 "invalid: APS above ceiling -> 422" 422 "$STATUS"
expect T7 "reason APS_TOO_HIGH" APS_TOO_HIGH "$(jget reason)"

post '{"nationalId":"9904276001082","subjectResults":[{"subject":"englishHomeLanguage","percentage":50},{"subject":"mathematics","percentage":40},{"subject":"physicalSciences","percentage":40},{"subject":"lifeSciences","percentage":40},{"subject":"geography","percentage":40},{"subject":"isiZulu","percentage":"abc"},{"subject":"lifeOrientation","percentage":70}]}'
expect T8 "invalid: wrong type for a percentage -> 422" 422 "$STATUS"
expect T8 "reason INVALID_PAYLOAD" INVALID_PAYLOAD "$(jget reason)"

expect T5-8 "no item written by any rejected request" "$BEFORE_ITEMS" "$(item_count)"
expect T5-8 "no seat consumed by any rejected request" "$BEFORE_SEATS" "$(seats_left)"
echo

# ---- Dependency failure -----------------------------------
echo "--- Dependency failure ---"
P_OUT="$(mk 0310015150082 50 40 40 40 40 40 70)"
ITEMS_BEFORE="$(item_count)"; SEATS_BEFORE="$(seats_left)"
set_store dlp-registration-store-outage
post "$P_OUT"
expect T9 "store unavailable -> 503" 503 "$STATUS"
expect T9 "reason STORAGE_UNAVAILABLE" STORAGE_UNAVAILABLE "$(jget reason)"
echo "     correlationId: $(jget correlationId)"
set_store "$TABLE"
expect T9 "outage wrote nothing" "$ITEMS_BEFORE" "$(item_count)"
expect T9 "outage consumed no seat" "$SEATS_BEFORE" "$(seats_left)"
echo

# ---- Recovery ---------------------------------------------
echo "--- Recovery ---"
post "$P_OUT"
expect T10 "same request succeeds after the store is restored -> 201" 201 "$STATUS"
expect T10 "not treated as a duplicate (no partial state left by the outage)" CONFIRMED "$(jget status)"
echo

# ---- Security / control checks ----------------------------
echo "--- Security and control checks ---"
POLICY="$(aws_local iam get-role-policy --role-name dlp-lambda-role --policy-name dlp-registration-write --query PolicyDocument --output json)"
IAM_RESULT="$(python3 - "$POLICY" <<'PY'
import json, sys
doc = json.loads(sys.argv[1])
forbidden = {"dynamodb:Scan", "dynamodb:Query", "dynamodb:DeleteItem", "dynamodb:DeleteTable"}
problems = []
for st in doc["Statement"]:
    acts = st["Action"] if isinstance(st["Action"], list) else [st["Action"]]
    res = st["Resource"] if isinstance(st["Resource"], list) else [st["Resource"]]
    if any("*" in a for a in acts): problems.append("wildcard action")
    if any(r == "*" for r in res): problems.append("wildcard resource")
    if forbidden & set(acts): problems.append("forbidden action " + ",".join(sorted(forbidden & set(acts))))
print("OK" if not problems else "; ".join(problems))
PY
)"
expect T11 "live IAM policy: no wildcard actions/resources, no scan/query/delete" OK "$IAM_RESULT"

LOGS="$(aws_local logs filter-log-events --log-group-name "/aws/lambda/$FUNCTION" --query 'events[].message' --output text 2>/dev/null || true)"
LEAKS=0
for id in 0303155029083 0601205012086 0508125123085 0310015150082 9904276001082 1234567890123; do
  if printf '%s' "$LOGS" | grep -q "$id"; then LEAKS=$((LEAKS+1)); fi
done
expect T12 "full national IDs never appear in Lambda logs" 0 "$LEAKS"
expect T12 "logs do contain the correlation/hash-prefix trace" yes "$(printf '%s' "$LOGS" | grep -q idHashPrefix && echo yes || echo no)"

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  FILES="$(git ls-files)"
  TRACKED_ENV="$(git ls-files --error-unmatch .env >/dev/null 2>&1 && echo tracked || echo not-tracked)"
else
  FILES="$(find . -type f -not -path './.git/*' -not -path './volume/*' -not -name '.env')"
  TRACKED_ENV="not-tracked"
fi
SECRET_HITS="$(printf '%s\n' "$FILES" | xargs grep -IlE 'AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----' 2>/dev/null | wc -l | tr -d ' ')"
expect T13 "secret scan: no AWS keys or private keys in repository files" 0 "$SECRET_HITS"
expect T13 ".env (populated config) is not committed" not-tracked "$TRACKED_ENV"
echo

# ---- Teardown / rebuild -----------------------------------
if [ "${SKIP_TEARDOWN:-0}" = "1" ]; then
  echo "--- Teardown/rebuild skipped (SKIP_TEARDOWN=1) ---"
else
  echo "--- Teardown and rebuild ---"
  ./scripts/teardown.sh
  expect T14 "teardown script succeeded" 0 "$?"
  expect T14 "no dlp containers remain" "" "$(docker ps -a --filter name=dlp- --format '{{.Names}}')"
  expect T14 "no local runtime state remains" no "$([ -d ./volume ] && echo yes || echo no)"

  docker compose up -d
  ./scripts/setup.sh
  VERIFY="$(./scripts/verify.sh)"; echo "$VERIFY"
  expect T14 "verify.sh: all checks pass after rebuild" yes "$(printf '%s' "$VERIFY" | grep -q ' 0 failed' && echo yes || echo no)"

  resolve_base
  post "$P1"
  expect T14 "minimum slice works again after rebuild -> 201" 201 "$STATUS"
  echo "     correlationId: $(jget correlationId)"
fi

echo
echo "=== Result: $PASSN passed, $FAILN failed ==="
[ "$FAILN" -eq 0 ]
