#!/usr/bin/env bash
# ============================================================
# Runs the AWS CLI against the local emulator with the right
# endpoint, region and (fake) credentials already set, so it works
# in any fresh terminal without `aws configure`.
#
# Usage: ./scripts/awslocal.sh dynamodb scan --table-name dlp-registrations
# ============================================================
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -f .env ]; then set -a; source .env; set +a; fi

export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-test}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-test}"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"

exec aws --endpoint-url="${LOCALSTACK_ENDPOINT:-http://localhost:4566}" "$@"
