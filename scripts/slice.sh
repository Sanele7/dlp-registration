#!/usr/bin/env bash
# ============================================================
# Runs the whole vertical slice with ONE command and no
# placeholders: valid request -> trace the correlation ID through the
# Lambda logs -> show the DynamoDB record -> invalid request -> show
# that nothing new was stored.
#
# Usage: ./scripts/slice.sh
# Optional: NATIONAL_ID=<synthetic 13-digit id> ./scripts/slice.sh
# (A second run with the same ID returns 409 DUPLICATE; reset with
#  ./scripts/teardown.sh && docker compose up -d && ./scripts/setup.sh)
# ============================================================
set -uo pipefail
cd "$(dirname "$0")/.."

if [ -f .env ]; then set -a; source .env; set +a; fi

ENDPOINT="${LOCALSTACK_ENDPOINT:-http://localhost:4566}"
TABLE="${REGISTRATIONS_TABLE:-dlp-registrations}"
FUNCTION="${LAMBDA_FUNCTION_NAME:-dlp-registration-processor}"
API_NAME="${API_GATEWAY_NAME:-dlp-registration-api}"
STAGE="${API_GATEWAY_STAGE:-local}"
NATIONAL_ID="${NATIONAL_ID:-0303155029083}"

export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-test}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-test}"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"

aws_local() { aws --endpoint-url="$ENDPOINT" "$@"; }

API_ID="$(aws_local apigateway get-rest-apis --query "items[?name=='$API_NAME'].id | [0]" --output text 2>/dev/null || true)"
if [ -z "$API_ID" ] || [ "$API_ID" = "None" ]; then
  echo "API not found. Run ./scripts/setup.sh first (and ./scripts/verify.sh to check)." >&2
  exit 1
fi
BASE="$ENDPOINT/restapis/$API_ID/$STAGE/_user_request_/registrations"

payload() { # nationalId
  cat <<JSON
{"nationalId":"$1","subjectResults":[{"subject":"englishHomeLanguage","percentage":50},{"subject":"mathematics","percentage":40},{"subject":"physicalSciences","percentage":40},{"subject":"lifeSciences","percentage":40},{"subject":"geography","percentage":40},{"subject":"isiZulu","percentage":40},{"subject":"lifeOrientation","percentage":70}]}
JSON
}

field() { python3 -c 'import json,sys
try: print(json.loads(sys.stdin.read()).get(sys.argv[1],""))
except Exception: print("")' "$1"; }

echo "=== Step 1 - E2 valid request ==="
echo "POST $BASE"
RESP="$(curl -s -i -X POST "$BASE" -H 'Content-Type: application/json' -d "$(payload "$NATIONAL_ID")")"
echo "$RESP"
BODY="$(printf '%s' "$RESP" | tail -n1)"
CID="$(printf '%s' "$BODY" | field correlationId)"
REASON="$(printf '%s' "$BODY" | field reason)"
echo
if [ "$REASON" = "DUPLICATE" ]; then
  echo "That national ID is already registered (409 DUPLICATE)."
  echo "For a clean run: ./scripts/teardown.sh && docker compose up -d && ./scripts/setup.sh"
  exit 0
fi
if [ -z "$CID" ]; then
  echo "No correlationId in the response - the request did not reach the Lambda." >&2
  exit 1
fi
echo "Correlation ID: $CID"
echo

echo "=== Step 2 - E3 processing trace (Lambda logs filtered by that ID) ==="
EVENTS=0
for _ in 1 2 3 4 5 6; do
  EVENTS="$(aws_local logs filter-log-events --log-group-name "/aws/lambda/$FUNCTION" --filter-pattern "$CID" --query 'length(events)' --output text 2>/dev/null || echo 0)"
  [ "$EVENTS" != "0" ] && [ "$EVENTS" != "None" ] && break
  sleep 2
done
aws_local logs filter-log-events --log-group-name "/aws/lambda/$FUNCTION" --filter-pattern "$CID" --query 'events[].message' --output text
echo
echo "Log events carrying this correlation ID: $EVENTS"
echo

echo "=== Step 3 - E4 durable result (DynamoDB) ==="
aws_local dynamodb scan --table-name "$TABLE"
ITEMS_BEFORE="$(aws_local dynamodb scan --table-name "$TABLE" --select COUNT --query Count --output text)"
echo

echo "=== Step 4 - E5 invalid request (ID fails the checksum) ==="
curl -s -i -X POST "$BASE" -H 'Content-Type: application/json' -d "$(payload 1234567890123)"
echo
ITEMS_AFTER="$(aws_local dynamodb scan --table-name "$TABLE" --select COUNT --query Count --output text)"
echo
echo "Items in table before invalid request: $ITEMS_BEFORE, after: $ITEMS_AFTER"
if [ "$ITEMS_BEFORE" = "$ITEMS_AFTER" ]; then
  echo "PASS: the rejected request wrote nothing."
else
  echo "FAIL: the table changed after a rejected request." >&2
  exit 1
fi
