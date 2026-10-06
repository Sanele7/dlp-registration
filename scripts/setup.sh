#!/usr/bin/env bash
# ============================================================
# Creates the DynamoDB table and deploys the Lambda function
# into the running LocalStack container.
#
# Safe to re-run. Existing resources are left alone.
#
# Usage: ./scripts/setup.sh
# ============================================================

set -euo pipefail
export AWS_PAGER=""

# Fail early, with install hints, if a required tool is missing
"$(dirname "$0")/preflight.sh" || exit 1

# Load .env if present
if [ -f .env ]; then
  set -a; source .env; set +a
fi

ENDPOINT="${LOCALSTACK_ENDPOINT:-http://localhost:4566}"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
TABLE="${REGISTRATIONS_TABLE:-dlp-registrations}"
FUNCTION="${LAMBDA_FUNCTION_NAME:-dlp-registration-processor}"

export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-test}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-test}"
export AWS_DEFAULT_REGION="$REGION"

aws_local() { aws --endpoint-url="$ENDPOINT" "$@"; }

echo "==> Waiting for LocalStack to become healthy"
for i in {1..30}; do
  if curl -sf "${ENDPOINT}/_localstack/health" > /dev/null 2>&1; then
    echo "    ready"
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "ERROR: LocalStack did not become healthy in 60 seconds." >&2
    echo "Check:  docker compose logs localstack" >&2
    exit 1
  fi
  sleep 2
done

echo "==> Creating DynamoDB table: ${TABLE}"
if aws_local dynamodb describe-table --table-name "$TABLE" > /dev/null 2>&1; then
  echo "    already exists, skipping"
else
  aws_local dynamodb create-table \
    --table-name "$TABLE" \
    --attribute-definitions AttributeName=idHash,AttributeType=S \
    --key-schema AttributeName=idHash,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST > /dev/null
  aws_local dynamodb wait table-exists --table-name "$TABLE"
  echo "    created"
fi

echo "==> Applying least-privilege IAM policy"
# Re-apply the policy on every setup so an existing local role also receives
# newly required permissions without granting broader access.
if aws_local iam get-role --role-name dlp-lambda-role > /dev/null 2>&1; then
  aws_local iam put-role-policy \
    --role-name dlp-lambda-role \
    --policy-name dlp-registration-write \
    --policy-document file://infra/lambda-policy.json > /dev/null
  echo "    policy refreshed"
else
  aws_local iam create-role \
    --role-name dlp-lambda-role \
    --assume-role-policy-document file://infra/trust-policy.json > /dev/null
  aws_local iam put-role-policy \
    --role-name dlp-lambda-role \
    --policy-name dlp-registration-write \
    --policy-document file://infra/lambda-policy.json > /dev/null
  echo "    role created"
fi

echo "==> Initialising capacity counter"
aws_local dynamodb put-item \
  --table-name "$TABLE" \
  --item "{\"idHash\":{\"S\":\"CAPACITY#programme\"},\"remaining\":{\"N\":\"${PROGRAMME_CAPACITY:-5}\"}}" \
  --condition-expression "attribute_not_exists(idHash)" > /dev/null 2>&1 || true
echo "==> Deploying Lambda function: ${FUNCTION}"
if [ ! -f src/handlers/registration.py ]; then
  echo "    SKIPPED — src/handlers/registration.py does not exist yet."
  echo "    Bandile writes this. Re-run setup.sh once it is in place."
else
  rm -f /tmp/dlp-lambda.zip
  (cd src && zip -qr /tmp/dlp-lambda.zip .)

  if aws_local lambda get-function --function-name "$FUNCTION" > /dev/null 2>&1; then
    aws_local lambda update-function-code \
      --function-name "$FUNCTION" \
      --zip-file fileb:///tmp/dlp-lambda.zip > /dev/null
    echo "    updated"
  else
    aws_local lambda create-function \
      --function-name "$FUNCTION" \
      --runtime python3.11 \
      --handler handlers.registration.handler \
      --role arn:aws:iam::000000000000:role/dlp-lambda-role \
      --zip-file fileb:///tmp/dlp-lambda.zip \
      --environment "Variables={REGISTRATIONS_TABLE=${TABLE},PROGRAMME_CAPACITY=${PROGRAMME_CAPACITY:-5}}" \
      > /dev/null
    echo "    created"
  fi
fi

echo "==> Configuring API Gateway routes: POST /registrations and POST /registrations/status"
API_NAME="${API_GATEWAY_NAME:-dlp-registration-api}"
STAGE="${API_GATEWAY_STAGE:-local}"

API_ID="$(aws_local apigateway get-rest-apis --query "items[?name=='${API_NAME}'].id | [0]" --output text 2>/dev/null || true)"
if [ -z "$API_ID" ] || [ "$API_ID" = "None" ]; then
  API_ID="$(aws_local apigateway create-rest-api --name "$API_NAME" --endpoint-configuration types=REGIONAL --query id --output text)"
  ROOT_ID="$(aws_local apigateway get-resources --rest-api-id "$API_ID" --query "items[?path=='/'].id | [0]" --output text)"
  RESOURCE_ID="$(aws_local apigateway create-resource --rest-api-id "$API_ID" --parent-id "$ROOT_ID" --path-part registrations --query id --output text)"
  aws_local apigateway put-method --rest-api-id "$API_ID" --resource-id "$RESOURCE_ID" --http-method POST --authorization-type NONE > /dev/null
  LAMBDA_ARN="$(aws_local lambda get-function --function-name "$FUNCTION" --query 'Configuration.FunctionArn' --output text)"
  INTEGRATION_URI="arn:aws:apigateway:${REGION}:lambda:path/2015-03-31/functions/${LAMBDA_ARN}/invocations"
  aws_local apigateway put-integration --rest-api-id "$API_ID" --resource-id "$RESOURCE_ID" --http-method POST --type AWS_PROXY --integration-http-method POST --uri "$INTEGRATION_URI" > /dev/null
  aws_local lambda add-permission --function-name "$FUNCTION" --statement-id "apigateway-${API_ID}" --action lambda:InvokeFunction --principal apigateway.amazonaws.com --source-arn "arn:aws:execute-api:${REGION}:000000000000:${API_ID}/*/POST/registrations" > /dev/null 2>&1 || true
  aws_local apigateway create-deployment --rest-api-id "$API_ID" --stage-name "$STAGE" > /dev/null
  echo "    created: $API_ID"
else
  echo "    already exists: $API_ID"
fi

# Status route (reference + PIN lookup). Idempotent, so existing environments get it too.
REG_RES="$(aws_local apigateway get-resources --rest-api-id "$API_ID" --query "items[?path=='/registrations'].id | [0]" --output text)"
STATUS_RES="$(aws_local apigateway get-resources --rest-api-id "$API_ID" --query "items[?path=='/registrations/status'].id | [0]" --output text)"
if [ -z "$STATUS_RES" ] || [ "$STATUS_RES" = "None" ]; then
  STATUS_RES="$(aws_local apigateway create-resource --rest-api-id "$API_ID" --parent-id "$REG_RES" --path-part status --query id --output text)"
  aws_local apigateway put-method --rest-api-id "$API_ID" --resource-id "$STATUS_RES" --http-method POST --authorization-type NONE > /dev/null
  LAMBDA_ARN="$(aws_local lambda get-function --function-name "$FUNCTION" --query 'Configuration.FunctionArn' --output text)"
  INTEGRATION_URI="arn:aws:apigateway:${REGION}:lambda:path/2015-03-31/functions/${LAMBDA_ARN}/invocations"
  aws_local apigateway put-integration --rest-api-id "$API_ID" --resource-id "$STATUS_RES" --http-method POST --type AWS_PROXY --integration-http-method POST --uri "$INTEGRATION_URI" > /dev/null
  aws_local lambda add-permission --function-name "$FUNCTION" --statement-id "apigateway-status-${API_ID}" --action lambda:InvokeFunction --principal apigateway.amazonaws.com --source-arn "arn:aws:execute-api:${REGION}:000000000000:${API_ID}/*/POST/registrations/status" > /dev/null 2>&1 || true
  aws_local apigateway create-deployment --rest-api-id "$API_ID" --stage-name "$STAGE" > /dev/null
  echo "    status route created"
else
  echo "    status route already exists"
fi

echo ""
echo "Setup complete."
echo "  Endpoint: ${ENDPOINT}"
echo "  Table:    ${TABLE}"
echo "  Function: ${FUNCTION}"
echo "  API:      http://localhost:4566/restapis/${API_ID}/${STAGE}/_user_request_/registrations"
echo "  Status:   http://localhost:4566/restapis/${API_ID}/${STAGE}/_user_request_/registrations/status"
