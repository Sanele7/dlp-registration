#!/usr/bin/env bash
# ============================================================
# Register one student from the command line.
#
# Interactive (asks for each value):  ./scripts/register.sh
# With arguments:
#   ./scripts/register.sh yes 0303155029083 60 50 50 50 50 50 70
#   ./scripts/register.sh no
# order: from KwaDlangezwa (yes/no), national ID, then English, Maths,
#        Physical Sciences, Life Sciences, Geography, isiZulu, Life Orientation
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
URL="$ENDPOINT/restapis/$API_ID/$STAGE/_user_request_/registrations"

NAMES=("English Home Language" "Mathematics" "Physical Sciences" "Life Sciences" "Geography" "isiZulu" "Life Orientation")

yesno() { case "$(echo "$1" | tr '[:upper:]' '[:lower:]')" in y|yes) echo yes;; n|no) echo no;; *) echo "";; esac; }

ID=""; VALUES=()
if [ "$#" -eq 0 ]; then
  echo "=== Digital Literacy Programme - student registration ==="
  while :; do
    read -r -p "Are you from KwaDlangezwa? (yes/no): " a
    RESIDENT="$(yesno "$a")"; [ -n "$RESIDENT" ] && break
    echo "Please answer yes or no."
  done
  if [ "$RESIDENT" = "yes" ]; then
    read -r -p "National ID (13 digits): " ID
    for n in "${NAMES[@]}"; do read -r -p "$n (%): " v; VALUES+=("$v"); done
  fi
elif [ "$#" -eq 1 ] && [ "$(yesno "$1")" = "no" ]; then
  RESIDENT="no"
elif [ "$#" -eq 9 ] && [ "$(yesno "$1")" = "yes" ]; then
  RESIDENT="yes"; ID="$2"; shift 2; VALUES=("$@")
else
  echo "Usage: $0   (interactive)" >&2
  echo "       $0 yes ID p1 p2 p3 p4 p5 p6 p7" >&2
  echo "       $0 no" >&2
  exit 2
fi

BODY="$(python3 - "$RESIDENT" "$ID" "${VALUES[@]}" <<'PY'
import json, sys
keys = ["englishHomeLanguage","mathematics","physicalSciences","lifeSciences","geography","isiZulu","lifeOrientation"]
resident, nid, vals = sys.argv[1] == "yes", sys.argv[2], sys.argv[3:]
if not resident:
    print(json.dumps({"fromKwaDlangezwa": False})); raise SystemExit
def num(v):
    try: return float(v) if "." in v else int(v)
    except ValueError: return v          # bad input is sent as-is so the service rejects it
print(json.dumps({"fromKwaDlangezwa": True, "nationalId": nid,
                  "subjectResults": [{"subject": k, "percentage": num(v)} for k, v in zip(keys, vals)]}))
PY
)"

echo; echo "Sending registration..."
RESP="$(curl -s -w '\n%{http_code}' -X POST "$URL" -H 'Content-Type: application/json' -d "$BODY")"
CODE="$(echo "$RESP" | tail -n1)"; JSON="$(echo "$RESP" | sed '$d')"
getf() { echo "$JSON" | python3 -c 'import json,sys
try: print(json.loads(sys.stdin.read()).get(sys.argv[1],""))
except Exception: print("")' "$1"; }

echo; echo "HTTP $CODE"; echo "$JSON" | python3 -m json.tool 2>/dev/null || echo "$JSON"
echo
if [ "$CODE" = "201" ]; then
  echo "RESULT: REGISTERED - a seat has been reserved."
  echo
  echo "  Reference number: $(getf reference)"
  echo "  PIN:              $(getf pin)"
  echo
  echo "  Write these down now. The PIN is shown only once."
  echo "  Check your application any time with: ./scripts/check-status.sh"
  echo
  echo "  $(getf nextSteps)"
else
  echo "RESULT: NOT REGISTERED ($(getf reason))"
  D="$(getf detail)"; [ -n "$D" ] && echo "WHY:    $D"
  case "$CODE" in
    422) echo "NEXT:   correct the input and submit again." ;;
    409) echo "NEXT:   no action possible for this ID." ;;
    503) echo "NEXT:   wait a moment and try again." ;;
  esac
  [ "$(getf reason)" = "NOT_RESIDENT" ] && echo "NEXT:   this application is closed. Only residents of KwaDlangezwa can apply."
fi
