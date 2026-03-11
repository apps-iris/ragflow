#!/usr/bin/env bash
#
# Start all RAGFlow Docker services.
#
# Usage:
#   ./start.sh              # start with defaults from .env
#   ./start.sh --detach     # (same as default, runs detached)
#   ./start.sh --follow     # start and tail logs
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"
ENV_FILE="${SCRIPT_DIR}/.env"

if [[ ! -f "$COMPOSE_FILE" ]]; then
  echo "ERROR: docker-compose.yml not found at ${COMPOSE_FILE}" >&2
  exit 1
fi

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: .env file not found at ${ENV_FILE}" >&2
  exit 1
fi

FOLLOW=false
for arg in "$@"; do
  case "$arg" in
    --follow|-f) FOLLOW=true ;;
  esac
done

# ── Pre-flight: check for host port conflicts ──────────────────────────────
check_port() {
  local port="$1" service="$2"
  if ss -tlnp 2>/dev/null | grep -q ":${port} " || \
     netstat -tlnp 2>/dev/null | grep -q ":${port} "; then
    echo "WARNING: Port ${port} (${service}) is already in use on the host." >&2
  fi
}

# Source .env to read port variables (bash eval handles ${VAR:-default} natively)
set -a
eval "$(grep -v '^\s*#' "$ENV_FILE" | grep -v '^\s*$')"
set +a

echo "==> Checking for host port conflicts..."
check_port "${ES_PORT:-1200}"           "Elasticsearch"
check_port "${EXPOSE_MYSQL_PORT:-5455}" "MySQL"
check_port "${MINIO_PORT:-9000}"        "MinIO API"
check_port "${MINIO_CONSOLE_PORT:-9001}" "MinIO Console"
check_port "${REDIS_PORT:-6379}"        "Redis"
check_port "${SVR_HTTP_PORT:-9380}"     "RAGFlow API"
check_port "${SVR_WEB_HTTP_PORT:-8060}" "RAGFlow Web HTTP"
check_port "${SVR_WEB_HTTPS_PORT:-8443}" "RAGFlow Web HTTPS"
check_port "${ADMIN_SVR_HTTP_PORT:-9381}" "RAGFlow Admin"
check_port "${SVR_MCP_PORT:-9382}"      "RAGFlow MCP"
check_port "${TEI_PORT:-6380}"          "TEI Embedding"

# ── Clean up stale containers from the opposite DEVICE profile ─────────────
# When switching between cpu/gpu profiles, docker compose --remove-orphans
# does not remove containers from the inactive profile. Remove them manually.
ACTIVE_DEVICE="${DEVICE:-cpu}"
if [[ "$ACTIVE_DEVICE" == "gpu" ]]; then
  STALE_SERVICES=("ragflow-cpu" "tei-cpu")
else
  STALE_SERVICES=("ragflow-gpu" "tei-gpu")
fi

for svc in "${STALE_SERVICES[@]}"; do
  stale=$(docker compose -f "$COMPOSE_FILE" ps -a --format json 2>/dev/null \
    | python3 -c "
import sys, json
for line in sys.stdin.read().strip().split('\n'):
    if not line: continue
    obj = json.loads(line)
    if obj.get('Service','') == '${svc}':
        print(obj.get('Name',''))
" 2>/dev/null || true)
  if [[ -n "$stale" ]]; then
    echo "==> Removing stale container from inactive profile: ${stale}"
    docker stop "$stale" 2>/dev/null || true
    docker rm "$stale" 2>/dev/null || true
  fi
done

# ── Start services ──────────────────────────────────────────────────────────
echo "==> Starting RAGFlow services (DEVICE=${ACTIVE_DEVICE}, profiles: ${COMPOSE_PROFILES:-default})..."
docker compose -f "$COMPOSE_FILE" up -d --remove-orphans

# ── Wait for health checks ─────────────────────────────────────────────────
echo "==> Waiting for services to become healthy..."
MAX_WAIT=180
INTERVAL=5
elapsed=0
all_healthy=false

while [[ $elapsed -lt $MAX_WAIT ]]; do
  # Get status of all running containers in this project
  unhealthy=$(docker compose -f "$COMPOSE_FILE" ps --format json 2>/dev/null \
    | python3 -c "
import sys, json
lines = sys.stdin.read().strip().split('\n')
for line in lines:
    if not line:
        continue
    obj = json.loads(line)
    status = obj.get('Health', obj.get('Status', ''))
    if 'starting' in status.lower():
        print(obj.get('Service', obj.get('Name', 'unknown')))
" 2>/dev/null || true)

  if [[ -z "$unhealthy" ]]; then
    all_healthy=true
    break
  fi

  echo "    Still waiting on: $(echo "$unhealthy" | tr '\n' ', ' | sed 's/,$//')"
  sleep "$INTERVAL"
  elapsed=$((elapsed + INTERVAL))
done

# ── Report status ───────────────────────────────────────────────────────────
echo ""
echo "==> Service status:"
docker compose -f "$COMPOSE_FILE" ps

if $all_healthy; then
  echo ""
  echo "==> All services are up and healthy."
else
  echo ""
  echo "WARNING: Some services may not be fully healthy after ${MAX_WAIT}s."
  echo "         Check logs with: docker compose -f ${COMPOSE_FILE} logs"
fi

# ── Optionally follow logs ─────────────────────────────────────────────────
if $FOLLOW; then
  echo ""
  echo "==> Following logs (Ctrl+C to stop)..."
  docker compose -f "$COMPOSE_FILE" logs -f
fi
