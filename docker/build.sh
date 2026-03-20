#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo "==> Building RAGFlow image: rag-carla"
docker build --platform linux/amd64 -f "${ROOT_DIR}/Dockerfile" -t rag-carla "${ROOT_DIR}"

echo "==> Stopping services..."
"${SCRIPT_DIR}/stop.sh"

echo "==> Starting services..."
"${SCRIPT_DIR}/start.sh"
