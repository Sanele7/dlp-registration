#!/usr/bin/env bash
set -euo pipefail
export AWS_PAGER=""

if [ -f .env ]; then set -a; source .env; set +a; fi

ENDPOINT="${LOCALSTACK_ENDPOINT:-http://localhost:4566}"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
TABLE="${REGISTRATIONS_TABLE:-dlp-registrations}"
FUNCTION="${LAMBDA_FUNCTION_NAME:-dlp-registration-processor}"
API_NAME="${API_GATEWAY_NAME:-dlp-registration-api}"
STAGE="${API_GATEWAY_STAGE:-local}"

export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-test}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-test}"
export AWS_DEFAULT_REGION="$REGION"

API_ID="$(aws --endpoint-url="$ENDPOINT" apigateway get-rest-apis --query "items[?name=='$API_NAME'].id | [0]" --output text)"
BASE="$ENDPOINT/restapis/$API_ID/$STAGE/_user_request_/registrations"

PAYLOAD='{"fromKwaDlangezwa":true,"nationalId":"0303155029083","subjectResults":[{"subject":"englishHomeLanguage","percentage":50},{"subject":"mathematics","percentage":40},{"subject":"physicalSciences","percentage":40},{"subject":"lifeSciences","percentage":40},{"subject":"geography","percentage":40},{"subject":"isiZulu","percentage":40},{"subject":"lifeOrientation","percentage":70}]}'

echo "E2E test: POST $BASE"

response="$(curl -sS -w '\n%{http_code}' -X POST "$BASE" -H 'Content-Type: application/json' -d "$PAYLOAD")"
status="$(printf '%s\n' "$response" | tail -n1)"
body="$(printf '%s\n' "$response" | sed '$d')"
[ "$status" = "201" ] || { echo "FAIL normal case: $status $body"; exit 1; }
echo "PASS normal case: $status $body"

correlation_id="$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["correlationId"])' <<<"$body")"
[ -n "$correlation_id" ] || { echo "FAIL: missing correlationId"; exit 1; }
echo "Correlation ID: $correlation_id"

response="$(curl -sS -w '\n%{http_code}' -X POST "$BASE" -H 'Content-Type: application/json' -d "$PAYLOAD")"
status="$(printf '%s\n' "$response" | tail -n1)"
[ "$status" = "409" ] || { echo "FAIL duplicate case: $status"; exit 1; }
echo "PASS duplicate case: $status"

response="$(curl -sS -w '\n%{http_code}' -X POST "$BASE" -H 'Content-Type: application/json' -d '{"fromKwaDlangezwa":true,"nationalId":"12345","subjectResults":[]}' )"
status="$(printf '%s\n' "$response" | tail -n1)"
[ "$status" = "422" ] || { echo "FAIL invalid case: $status"; exit 1; }
echo "PASS invalid case: $status"

echo "Simulating store outage with an unavailable DynamoDB table..."
restore() {
  aws --endpoint-url="$ENDPOINT" lambda update-function-configuration --function-name "$FUNCTION" --environment "Variables={REGISTRATIONS_TABLE=$TABLE,PROGRAMME_CAPACITY=${PROGRAMME_CAPACITY:-5},LOG_LEVEL=${LOG_LEVEL:-INFO}}" >/dev/null || true
  sleep 1
}
trap restore EXIT

aws --endpoint-url="$ENDPOINT" lambda update-function-configuration --function-name "$FUNCTION" --environment "Variables={REGISTRATIONS_TABLE=dlp-registration-store-outage,PROGRAMME_CAPACITY=${PROGRAMME_CAPACITY:-5},LOG_LEVEL=${LOG_LEVEL:-INFO}}" >/dev/null
sleep 1

response="$(curl -sS -w '\n%{http_code}' -X POST "$BASE" -H 'Content-Type: application/json' -d "$PAYLOAD")"
status="$(printf '%s\n' "$response" | tail -n1)"
[ "$status" = "503" ] || { echo "FAIL store-outage case: $status"; exit 1; }
echo "PASS store-outage case: $status"

echo "All Milestone 3 integration checks passed."
