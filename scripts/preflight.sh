#!/usr/bin/env bash
# ============================================================
# Checks that every tool the project needs is installed and that
# Docker is running, BEFORE anything is created. Called by setup.sh.
#
# Usage: ./scripts/preflight.sh
# ============================================================
set -uo pipefail

missing=0
need() { # command, install hint
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "  MISSING  $1  -  $2" >&2
    missing=1
  fi
}

echo "==> Checking prerequisites"
need docker  "install Docker Engine + Compose plugin (see docs/docker-setup.md)"
need aws     "install AWS CLI v2: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
need python3 "install Python 3.11+ (sudo apt install python3)"
need curl    "sudo apt install curl"
need zip     "sudo apt install zip   (setup.sh uses it to package the Lambda)"

if command -v docker >/dev/null 2>&1; then
  if ! docker compose version >/dev/null 2>&1; then
    echo "  MISSING  docker compose plugin  -  use 'docker compose' (space), not 'docker-compose'" >&2
    missing=1
  fi
  if ! docker info >/dev/null 2>&1; then
    echo "  NOT RUNNING  Docker daemon  -  start Docker Desktop, or: sudo systemctl start docker" >&2
    missing=1
  fi
fi

if [ ! -f .env ]; then
  echo "  NOTE  .env not found - defaults will be used. Recommended: cp .env.example .env"
fi

if [ "$missing" -ne 0 ]; then
  echo "Fix the items above, then re-run." >&2
  exit 1
fi
echo "    all prerequisites present"
