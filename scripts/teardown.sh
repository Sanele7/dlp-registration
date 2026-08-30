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
rm -rf ./volume

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
