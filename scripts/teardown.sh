#!/usr/bin/env bash
# ============================================================
# Stops the environment and removes all runtime state.
# Verifies that nothing is left running.
#
# Required for Milestone 4 (teardown evidence).
#
# Usage: ./scripts/teardown.sh
# ============================================================

set -euo pipefail

echo "==> Stopping containers and removing volumes"
docker compose down -v

echo "==> Removing local runtime state"
# LocalStack creates ./volume as root inside the container, so a plain rm can
# fail with "Permission denied". Try rm first; if anything is left, delete it
# through a throwaway container using the LocalStack image that is already
# on this machine (no download needed).
rm -rf ./volume 2>/dev/null || true
if [ -d ./volume ]; then
  IMAGE="localstack/localstack:${LOCALSTACK_VERSION:-4.14.0}"
  docker run --rm --entrypoint sh -v "$PWD/volume:/v" "$IMAGE" \
    -c 'rm -rf /v/* /v/.[!.]* 2>/dev/null; true' || true
  rm -rf ./volume 2>/dev/null || true
fi

echo "==> Verifying nothing remains"
REMAINING=$(docker ps -a --filter "name=dlp-" --format "{{.Names}}" || true)
if [ -z "$REMAINING" ]; then
  echo "    no dlp containers remain"
else
  echo "    WARNING — these containers still exist:" >&2
  echo "$REMAINING" >&2
  exit 1
fi

if [ -d ./volume ]; then
  echo "    WARNING — ./volume still exists" >&2
  exit 1
else
  echo "    no local state remains"
fi

echo ""
echo "Teardown complete. Rebuild with: docker compose up -d && ./scripts/setup.sh"
