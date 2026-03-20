#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

RAGFLOW_IMAGE=$(grep -E '^\s*RAGFLOW_IMAGE=' "${SCRIPT_DIR}/.env" | head -1 | cut -d= -f2- | awk '{print $1}')

echo "==> Building RAGFlow image: ${RAGFLOW_IMAGE}"
docker build --platform linux/amd64 -f "${ROOT_DIR}/Dockerfile" -t "${RAGFLOW_IMAGE}" "${ROOT_DIR}"

echo "==> Stopping services..."
"${SCRIPT_DIR}/stop.sh"

echo "==> Starting services..."
"${SCRIPT_DIR}/start.sh"
