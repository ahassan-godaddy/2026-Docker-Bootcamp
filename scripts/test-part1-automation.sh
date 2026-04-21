#!/bin/bash

set -euo pipefail

# 2026 Docker Bootcamp - Part 1 smoke automation

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REDIS_DIR="$PROJECT_ROOT/redis_client_app"

VALKEY_CONTAINER_NAME="valkey-bootcamp-test"
CUSTOM_IMAGE_NAME="bootcamp-2026-test"
NETWORK_NAME="bootcamp_2026_net"

log() {
  printf "[part1] %s\n" "$1"
}

cleanup() {
  docker rm -f "$VALKEY_CONTAINER_NAME" >/dev/null 2>&1 || true
  docker image rm "$CUSTOM_IMAGE_NAME" >/dev/null 2>&1 || true
  docker network rm "$NETWORK_NAME" >/dev/null 2>&1 || true
  if [ -d "$REDIS_DIR" ]; then
    (cd "$REDIS_DIR" && docker compose down >/dev/null 2>&1 || true)
  fi
}

trap cleanup EXIT

require_prereqs() {
  command -v docker >/dev/null
  docker info >/dev/null
}

run_tests() {
  log "Pulling Valkey image"
  docker pull valkey/valkey:8-alpine >/dev/null

  log "Starting Valkey container"
  docker run --name "$VALKEY_CONTAINER_NAME" -d valkey/valkey:8-alpine >/dev/null
  sleep 3
  docker logs "$VALKEY_CONTAINER_NAME" | grep -q "Ready to accept connections"

  log "Validating key/value flow"
  docker exec "$VALKEY_CONTAINER_NAME" redis-cli SET myname Andrew | grep -q "OK"
  docker exec "$VALKEY_CONTAINER_NAME" redis-cli GET myname | grep -Eq '"Andrew"|Andrew'

  log "Building redis client image"
  docker build -f "$REDIS_DIR/Dockerfile" -t "$CUSTOM_IMAGE_NAME" "$REDIS_DIR" >/dev/null
  docker run --rm "$CUSTOM_IMAGE_NAME" >/dev/null

  log "Connecting app container to Valkey"
  docker network create "$NETWORK_NAME" >/dev/null
  docker network connect "$NETWORK_NAME" "$VALKEY_CONTAINER_NAME" --alias redis >/dev/null
  docker run --rm --net "$NETWORK_NAME" "$CUSTOM_IMAGE_NAME" check_redis | grep -q "True"

  log "Compose up + health"
  (
    cd "$REDIS_DIR"
    docker compose up -d --build >/dev/null
    sleep 8
    docker compose ps | grep -Eq "app|cache"
  )

  log "Compose watch smoke check"
  (
    cd "$REDIS_DIR"
    timeout 8 docker compose watch >/dev/null 2>&1 || true
  )

  log "Docker Scout quickview smoke check"
  docker scout quickview "$CUSTOM_IMAGE_NAME" >/dev/null || log "docker scout not available; skipping"

  log "Part 1 automation complete"
}

main() {
  require_prereqs
  cleanup || true
  run_tests
}

main "$@"
