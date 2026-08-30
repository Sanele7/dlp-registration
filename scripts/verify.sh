#!/usr/bin/env bash
# ============================================================
# Confirms the environment is up and correctly configured.
# Run this after setup.sh, and after any rebuild.
#
# Usage: ./scripts/verify.sh
# ============================================================

set -uo pipefail

if [ -f .env ]; then set -a; source .env; set +a; fi

ENDPOINT="${LOCALSTACK_ENDPOINT:-http://localhost:4566}"
TABLE="${REGISTRATIONS_TABLE:-dlp-registrations}"

export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-test}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-test}"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"

PASS=0; FAIL=0
check() {
  if eval "$2" > /dev/null 2>&1; then
    echo "  PASS  $1"; PASS=$((PASS+1))
  else
    echo "  FAIL  $1"; FAIL=$((FAIL+1))
  fi
}

echo "Environment verification"
echo "------------------------"
check "Docker is running"          "docker info"
check "LocalStack container is up" "docker ps --filter name=dlp-localstack --filter status=running | grep -q dlp-localstack"
check "LocalStack is healthy"      "curl -sf ${ENDPOINT}/_localstack/health"
check "DynamoDB table exists"      "aws --endpoint-url=${ENDPOINT} dynamodb describe-table --table-name ${TABLE}"
check "IAM role exists"            "aws --endpoint-url=${ENDPOINT} iam get-role --role-name dlp-lambda-role"

echo "------------------------"
echo "  ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ] || exit 1
