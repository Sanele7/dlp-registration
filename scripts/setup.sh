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
# The function may write to one named table and nothing else.
# Deliberately NOT dynamodb:* and NOT Resource: "*".
if aws_local iam get-role --role-name dlp-lambda-role > /dev/null 2>&1; then
  echo "    role already exists, skipping"
else
  aws_local iam create-role \
    --role-name dlp-lambda-role \
    --assume-role-policy-document file://infra/trust-policy.json > /dev/null
  aws_local iam put-role-policy \
    --role-name dlp-lambda-role \
    --policy-name dlp-registration-write \
    --policy-document file://infra/lambda-policy.json > /dev/null
  echo "    created"
fi

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
      --environment "Variables={REGISTRATIONS_TABLE=${TABLE},PROGRAMME_CAPACITY=${PROGRAMME_CAPACITY:-10}}" \
      > /dev/null
    echo "    created"
  fi
fi

echo ""
echo "Setup complete."
echo "  Endpoint: ${ENDPOINT}"
echo "  Table:    ${TABLE}"
echo "  Function: ${FUNCTION}"
