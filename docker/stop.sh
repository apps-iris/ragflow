#!/usr/bin/env bash
#
# Stop all RAGFlow Docker services.
#
# Usage:
#   ./stop.sh              # stop and remove containers
#   ./stop.sh --volumes    # also remove named volumes (DATA LOSS)
#   ./stop.sh --keep       # stop containers without removing them
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"

if [[ ! -f "$COMPOSE_FILE" ]]; then
  echo "ERROR: docker-compose.yml not found at ${COMPOSE_FILE}" >&2
  exit 1
fi

REMOVE_VOLUMES=false
KEEP_CONTAINERS=false

for arg in "$@"; do
  case "$arg" in
    --volumes|-v) REMOVE_VOLUMES=true ;;
    --keep|-k)    KEEP_CONTAINERS=true ;;
  esac
done

echo "==> Current service status:"
docker compose -f "$COMPOSE_FILE" ps 2>/dev/null || true
echo ""

if $KEEP_CONTAINERS; then
  echo "==> Stopping RAGFlow services (keeping containers)..."
  docker compose -f "$COMPOSE_FILE" stop
elif $REMOVE_VOLUMES; then
  echo "==> Stopping RAGFlow services and removing volumes (DATA WILL BE LOST)..."
  read -r -p "Are you sure? [y/N] " confirm
  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    docker compose -f "$COMPOSE_FILE" down -v --remove-orphans
  else
    echo "Aborted."
    exit 0
  fi
else
  echo "==> Stopping RAGFlow services..."
  docker compose -f "$COMPOSE_FILE" down --remove-orphans
fi

echo ""
echo "==> Done. All RAGFlow services have been stopped."
