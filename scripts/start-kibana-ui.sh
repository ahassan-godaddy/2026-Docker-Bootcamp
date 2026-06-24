#!/bin/bash

set -euo pipefail

# Start Elasticsearch (if needed), create a Kibana service account token, and launch Kibana.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ELK_DIR="$PROJECT_ROOT/django_app_for_part_2/ELK"

ELASTIC_PASSWORD="${ELASTIC_PASSWORD:-bootcamp-elastic}"
KIBANA_TOKEN_NAME="${KIBANA_TOKEN_NAME:-bootcamp-kibana}"
KIBANA_URL="${KIBANA_URL:-http://localhost:5601}"

log() {
  printf "[kibana-ui] %s\n" "$1"
}

fail() {
  printf "[kibana-ui] ERROR: %s\n" "$1" >&2
  exit 1
}

require_tools() {
  command -v docker >/dev/null || fail "docker is required"
  command -v curl >/dev/null || fail "curl is required"
  docker info >/dev/null 2>&1 || fail "docker daemon is not running"
}

wait_for_elasticsearch() {
  local timeout_seconds="${1:-180}"
  local elapsed=0

  while [ "$elapsed" -lt "$timeout_seconds" ]; do
    if curl -sSf -u "elastic:${ELASTIC_PASSWORD}" "http://localhost:9200/_cluster/health" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
    elapsed=$((elapsed + 2))
  done

  return 1
}

ensure_elasticsearch() {
  local running
  running="$(docker compose -f "$ELK_DIR/docker-compose.yml" ps elasticsearch --status running -q 2>/dev/null || true)"

  if [ -z "$running" ]; then
    log "Starting Elasticsearch"
    (
      cd "$ELK_DIR"
      ELASTIC_PASSWORD="$ELASTIC_PASSWORD" docker compose up -d elasticsearch
    )
  else
    log "Elasticsearch is already running"
  fi

  wait_for_elasticsearch 180 || fail "Elasticsearch did not become healthy"
}

create_kibana_token() {
  if [ -n "${KIBANA_SERVICE_ACCOUNT_TOKEN:-}" ]; then
    log "Using KIBANA_SERVICE_ACCOUNT_TOKEN from the environment"
    return 0
  fi

  log "Creating Kibana service account token (${KIBANA_TOKEN_NAME})"
  docker exec es /usr/share/elasticsearch/bin/elasticsearch-service-tokens delete elastic/kibana "$KIBANA_TOKEN_NAME" >/dev/null 2>&1 || true

  local token_output token_value
  token_output="$(docker exec es /usr/share/elasticsearch/bin/elasticsearch-service-tokens create elastic/kibana "$KIBANA_TOKEN_NAME")"
  token_value="$(printf '%s\n' "$token_output" | awk -F'= ' '/SERVICE TOKEN/ {print $2}' | tr -d '[:space:]')"

  [ -n "$token_value" ] || fail "failed to create Kibana service account token"
  export KIBANA_SERVICE_ACCOUNT_TOKEN="$token_value"
  log "Created Kibana service account token"
}

start_kibana_stack() {
  log "Starting ELK monitoring + ui profiles"
  (
    cd "$ELK_DIR"
    ELASTIC_PASSWORD="$ELASTIC_PASSWORD" \
      KIBANA_SERVICE_ACCOUNT_TOKEN="$KIBANA_SERVICE_ACCOUNT_TOKEN" \
      docker compose --profile monitoring --profile ui up -d
  )
}

wait_for_kibana() {
  local timeout_seconds="${1:-180}"
  local elapsed=0

  while [ "$elapsed" -lt "$timeout_seconds" ]; do
    if curl -sSf "$KIBANA_URL/" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
    elapsed=$((elapsed + 2))
  done

  return 1
}

main() {
  require_tools
  ensure_elasticsearch
  create_kibana_token
  start_kibana_stack
  wait_for_kibana 180 || fail "Kibana did not become healthy"
  log "Kibana is ready at ${KIBANA_URL}"
  log "APM UI: ${KIBANA_URL}/app/apm"
}

main "$@"
