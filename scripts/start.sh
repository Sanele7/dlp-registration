#!/usr/bin/env bash
# ============================================================
# One command to get a working environment.
#
#   ./scripts/start.sh            fix common problems and start (keeps existing data)
#   ./scripts/start.sh --reset    clean slate: teardown, then start (0 registrations, 5 seats)
#
# It: checks the tools, picks the right Docker engine, removes a stale
# LocalStack container left on another engine, creates .env with 5 seats,
# starts LocalStack, runs setup.sh and verify.sh.
# ============================================================
set -uo pipefail
cd "$(dirname "$0")/.."

RESET=0
case "${1:-}" in
  "") ;;
  --reset) RESET=1 ;;
  *) echo "Usage: $0 [--reset]" >&2; exit 2 ;;
esac

fail() { echo "ERROR: $*" >&2; exit 1; }

echo "==> 1/6 Checking tools"
./scripts/preflight.sh || exit 1

echo "==> 2/6 Choosing the Docker engine"
CURRENT="$(docker context show 2>/dev/null || echo default)"
if [ "$CURRENT" != "default" ] && docker context ls -q 2>/dev/null | grep -qx default \
   && docker --context default info >/dev/null 2>&1; then
  docker context use default >/dev/null
  echo "    switched Docker context: $CURRENT -> default"
else
  echo "    using Docker context: $CURRENT"
fi

echo "==> 3/6 Removing any stale LocalStack container (on every Docker engine)"
if [ "$RESET" = "0" ]; then
  echo "    keeping the current container if it is running"
fi
if [ "$RESET" = "1" ]; then
  for c in $(docker context ls -q 2>/dev/null); do
    docker --context "$c" rm -f dlp-localstack >/dev/null 2>&1 || true
  done
  echo "    done"
else
  # Not resetting: only clear containers on the OTHER engines, which can hold port 4566
  ACTIVE="$(docker context show 2>/dev/null || echo default)"
  for c in $(docker context ls -q 2>/dev/null); do
    [ "$c" = "$ACTIVE" ] && continue
    docker --context "$c" rm -f dlp-localstack >/dev/null 2>&1 || true
  done
fi

echo "==> 4/6 Settings file (.env)"
[ -f .env ] || { cp .env.example .env; echo "    created .env from .env.example"; }
if grep -q '^PROGRAMME_CAPACITY=' .env; then
  sed -i.bak 's/^PROGRAMME_CAPACITY=.*/PROGRAMME_CAPACITY=5/' .env && rm -f .env.bak
else
  echo "PROGRAMME_CAPACITY=5" >> .env
fi
echo "    seats: 5"

if [ "$RESET" = "1" ]; then
  echo "==> Reset: tearing down the old environment"
  ./scripts/teardown.sh || fail "teardown failed (see the message above)"
fi

echo "==> 5/6 Starting LocalStack"
docker compose up -d || fail "docker compose could not start. Is Docker Desktop open? Is port 4566 free?"

echo "==> 6/6 Creating and verifying the resources"
./scripts/setup.sh || fail "setup failed (see the message above)"
./scripts/verify.sh || fail "verification failed (see the message above)"

echo
echo "READY."
echo "  Register a student:   ./scripts/register.sh"
echo "  Check an application: ./scripts/check-status.sh"
echo "  Admin view:           ./scripts/admin.sh"
echo "  Clean slate any time: ./scripts/start.sh --reset"
