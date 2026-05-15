#!/bin/bash

set -euo pipefail

# End-to-end APM validation for the 2026 bootcamp stack.
# This script asserts endpoint OTel traces from Django are ingested by Elastic.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DJANGO_DIR="$PROJECT_ROOT/django_app_for_part_2/Django"
ELK_DIR="$PROJECT_ROOT/django_app_for_part_2/ELK"

ELASTIC_PASSWORD="${ELASTIC_PASSWORD:-bootcamp-elastic}"
APM_SERVICE_NAME="${APM_SERVICE_NAME:-bootcamp-django}"
MAX_WAIT_SECONDS="${MAX_WAIT_SECONDS:-180}"
REQUIRED_ENDPOINTS=("/sleep/1" "/sleep/2" "/error")

log() {
  printf "[apm-e2e] %s\n" "$1"
}

fail() {
  printf "[apm-e2e] ERROR: %s\n" "$1" >&2
  exit 1
}

require_tools() {
  command -v docker >/dev/null || fail "docker is required"
  command -v curl >/dev/null || fail "curl is required"
  command -v python3 >/dev/null || fail "python3 is required"
  docker info >/dev/null 2>&1 || fail "docker daemon is not running"
}

ensure_secret_files() {
  if [ ! -f "$DJANGO_DIR/secrets/postgres_password.txt" ]; then
    if [ -f "$DJANGO_DIR/secrets/postgres_password.example.txt" ]; then
      cp "$DJANGO_DIR/secrets/postgres_password.example.txt" "$DJANGO_DIR/secrets/postgres_password.txt"
      log "Created Postgres password file from example"
    else
      fail "missing $DJANGO_DIR/secrets/postgres_password.txt"
    fi
  fi
  chmod 600 "$DJANGO_DIR/secrets/postgres_password.txt" || true
}

wait_for_http() {
  local url="$1"
  local timeout_seconds="${2:-120}"
  local elapsed=0

  while [ "$elapsed" -lt "$timeout_seconds" ]; do
    if curl -sSf "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
    elapsed=$((elapsed + 2))
  done

  return 1
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

start_stack() {
  log "Starting ELK (monitoring profile)"
  (
    cd "$ELK_DIR"
    ELASTIC_PASSWORD="$ELASTIC_PASSWORD" docker compose --profile monitoring up -d
  )

  log "Waiting for Elasticsearch and APM Server"
  wait_for_elasticsearch 180 || fail "Elasticsearch did not become healthy"
  wait_for_http "http://localhost:8200/" 180 || fail "APM server did not become healthy"

  log "Starting Django + OTel override"
  (
    cd "$DJANGO_DIR"
    docker compose -f docker-compose.yml -f docker-compose.otel.yml up -d --build
  )

  wait_for_http "http://localhost:8000/" 120 || fail "Django did not become healthy"
}

generate_traffic() {
  log "Generating Django traffic to produce spans"

  for endpoint in "/" "/admin/" "/sleep/1" "/sleep/2" "/error"; do
    curl -s "http://localhost:8000${endpoint}" >/dev/null || true
    sleep 1
  done
}

query_endpoint_trace_count() {
  local endpoint_path="$1"

  local query_response
  query_response="$(
    curl -sS -u "elastic:${ELASTIC_PASSWORD}" \
      -H "Content-Type: application/json" \
      -X POST "http://localhost:9200/_search" \
      -d "{
        \"size\": 0,
        \"query\": {
          \"bool\": {
            \"filter\": [
              {\"term\": {\"service.name\": \"${APM_SERVICE_NAME}\"}},
              {\"term\": {\"processor.event\": \"transaction\"}},
              {\"term\": {\"transaction.type\": \"request\"}},
              {\"term\": {\"url.path\": \"${endpoint_path}\"}},
              {\"range\": {\"@timestamp\": {\"gte\": \"now-15m\"}}}
            ]
          }
        }
      }"
  )"

  python3 - "$query_response" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
hits = payload.get("hits", {}).get("total", 0)
if isinstance(hits, dict):
    print(hits.get("value", 0))
else:
    print(hits or 0)
PY
}

assert_apm_ingestion() {
  log "Polling Elasticsearch for endpoint trace ingestion"

  local elapsed=0
  local all_present=0
  while [ "$elapsed" -lt "$MAX_WAIT_SECONDS" ]; do
    all_present=1
    for endpoint in "${REQUIRED_ENDPOINTS[@]}"; do
      count="$(query_endpoint_trace_count "$endpoint" || echo 0)"
      if [ "${count:-0}" -le 0 ]; then
        all_present=0
        break
      fi
    done

    if [ "$all_present" -eq 1 ]; then
      log "APM assertion passed for endpoint traces: ${REQUIRED_ENDPOINTS[*]}"
      return 0
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done

  fail "APM assertion failed: missing endpoint traces for ${REQUIRED_ENDPOINTS[*]} after ${MAX_WAIT_SECONDS}s"
}

main() {
  require_tools
  ensure_secret_files
  start_stack
  generate_traffic
  assert_apm_ingestion
  log "E2E APM validation complete"
}

main "$@"
