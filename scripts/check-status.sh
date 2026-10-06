#!/usr/bin/env bash
# ============================================================
# Check a registration with the reference number and PIN issued at
# registration.
#
# Interactive:  ./scripts/check-status.sh
# Arguments:    ./scripts/check-status.sh DLP-ABCD2345 123456
# ============================================================
set -uo pipefail
export AWS_PAGER=""
cd "$(dirname "$0")/.."
if [ -f .env ]; then set -a; source .env; set +a; fi

ENDPOINT="${LOCALSTACK_ENDPOINT:-http://localhost:4566}"
API_NAME="${API_GATEWAY_NAME:-dlp-registration-api}"
STAGE="${API_GATEWAY_STAGE:-local}"
export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-test}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-test}"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"

API_ID="$(aws --endpoint-url="$ENDPOINT" apigateway get-rest-apis --query "items[?name=='$API_NAME'].id | [0]" --output text 2>/dev/null || true)"
if [ -z "$API_ID" ] || [ "$API_ID" = "None" ]; then
  echo "API not found. Run ./scripts/setup.sh first." >&2; exit 1
fi
URL="$ENDPOINT/restapis/$API_ID/$STAGE/_user_request_/registrations/status"

if [ "$#" -eq 2 ]; then REF="$1"; PIN="$2"
elif [ "$#" -eq 0 ]; then
  echo "=== Digital Literacy Programme - check your application ==="
  read -r -p "Reference number: " REF
  read -r -s -p "PIN: " PIN; echo
else
  echo "Usage: $0   or   $0 REFERENCE PIN" >&2; exit 2
fi

BODY="$(python3 -c 'import json,sys; print(json.dumps({"reference": sys.argv[1], "pin": sys.argv[2]}))' "$REF" "$PIN")"
RESP="$(curl -s -w '\n%{http_code}' -X POST "$URL" -H 'Content-Type: application/json' -d "$BODY")"
CODE="$(echo "$RESP" | tail -n1)"; JSON="$(echo "$RESP" | sed '$d')"
getf() { echo "$JSON" | python3 -c 'import json,sys
try: print(json.loads(sys.stdin.read()).get(sys.argv[1],""))
except Exception: print("")' "$1"; }

echo; echo "HTTP $CODE"; echo "$JSON" | python3 -m json.tool 2>/dev/null || echo "$JSON"
echo
if [ "$CODE" = "200" ]; then
  echo "RESULT: your application is $(getf status) (APS $(getf aps), registered $(getf registeredAt))."
  echo "        $(getf nextSteps)"
else
  echo "RESULT: $(getf reason)"
  D="$(getf detail)"; [ -n "$D" ] && echo "WHY:    $D"
fi
