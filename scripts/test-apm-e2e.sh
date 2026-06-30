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

# Local LLM (/ask endpoint) settings. The /ask checks require Docker Model
# Runner; they are auto-skipped when DMR is unavailable. Force on/off with
# TEST_ASK_ENDPOINT=1 / TEST_ASK_ENDPOINT=0.
LLM_MODEL="${LLM_MODEL:-ai/smollm2}"
TEST_ASK_ENDPOINT="${TEST_ASK_ENDPOINT:-auto}"

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

dmr_available() {
  docker model version >/dev/null 2>&1
}

should_test_ask() {
  case "$TEST_ASK_ENDPOINT" in
    1 | true | TRUE | yes) return 0 ;;
    0 | false | FALSE | no) return 1 ;;
    *) dmr_available ;;
  esac
}

ask_llm() {
  # Drive the Django /ask form the same way a browser does, including the
  # CSRF token dance, and print the HTML response body.
  local question="$1"
  local jar html token
  jar="$(mktemp)"
  html="$(curl -sS -c "$jar" "http://localhost:8000/ask" || true)"
  token="$(printf '%s' "$html" | grep -o 'name="csrfmiddlewaretoken" value="[^"]*"' | head -1 | sed 's/.*value="//;s/"$//')"
  curl -sS --max-time 180 -b "$jar" -c "$jar" -e "http://localhost:8000/ask" \
    --data "csrfmiddlewaretoken=${token}" \
    --data-urlencode "question=${question}" \
    "http://localhost:8000/ask" || true
  rm -f "$jar"
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
    docker compose -f docker-compose.yml -f docker-compose.otel.yml down --remove-orphans >/dev/null 2>&1 || true
    docker compose -f docker-compose.yml -f docker-compose.otel.yml up -d --build
  )

  wait_for_http "http://localhost:8000/" 120 || fail "Django did not become healthy"

  if should_test_ask; then
    log "Pulling local LLM model ($LLM_MODEL) for /ask checks"
    docker model pull "$LLM_MODEL" >/dev/null 2>&1 ||
      log "WARNING: could not pull $LLM_MODEL; /ask span assertion may fail"
  else
    log "Docker Model Runner unavailable; skipping /ask checks"
  fi
}

generate_traffic() {
  log "Generating Django traffic to produce spans"

  for endpoint in "/" "/admin/" "/sleep/1" "/sleep/2" "/error"; do
    curl -s "http://localhost:8000${endpoint}" >/dev/null || true
    sleep 1
  done

  if should_test_ask; then
    log "Exercising /ask endpoint to produce LLM + Valkey cache spans"
    curl -s "http://localhost:8000/ask" >/dev/null || true # GET renders the form

    # Ask the same question twice: the first call is a cache miss (Valkey
    # lookup + LLM call + Valkey write), the second is a cache hit.
    local question="What is a Docker container in one short sentence?"
    local first second
    first="$(ask_llm "$question")"
    if printf '%s' "$first" | grep -q "<h2>Answer"; then
      log "/ask returned an answer from the local LLM (cache miss)"
    else
      log "WARNING: /ask did not return an answer; span assertions may fail"
    fi
    sleep 1
    second="$(ask_llm "$question")"
    if printf '%s' "$second" | grep -q "Served from the Valkey cache"; then
      log "/ask second response served from the Valkey cache (cache hit)"
    else
      log "WARNING: /ask did not report a cache hit on the repeat question"
    fi
    sleep 1
  fi
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

query_llm_span_count() {
  # Count outbound spans from Django to the model runner. The OTel requests
  # instrumentation produces an external HTTP span whose destination resource
  # is the model-runner host, which Elastic maps to span.destination.service.resource.
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
              {\"term\": {\"processor.event\": \"span\"}},
              {\"wildcard\": {\"span.destination.service.resource\": \"*model-runner*\"}},
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

query_cache_span_count() {
  # Count Valkey/Redis spans from Django. The OTel redis instrumentation maps
  # cache commands to spans with span.subtype "redis".
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
              {\"term\": {\"processor.event\": \"span\"}},
              {\"term\": {\"span.subtype\": \"redis\"}},
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

assert_llm_apm() {
  log "Polling Elasticsearch for /ask transaction, LLM span, and Valkey cache span"

  local elapsed=0
  while [ "$elapsed" -lt "$MAX_WAIT_SECONDS" ]; do
    local tx_count span_count cache_count
    tx_count="$(query_endpoint_trace_count "/ask" || echo 0)"
    span_count="$(query_llm_span_count || echo 0)"
    cache_count="$(query_cache_span_count || echo 0)"
    if [ "${tx_count:-0}" -gt 0 ] && [ "${span_count:-0}" -gt 0 ] && [ "${cache_count:-0}" -gt 0 ]; then
      log "LLM APM assertion passed (/ask transaction + model-runner span + Valkey cache span ingested)"
      return 0
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done

  fail "LLM APM assertion failed: missing /ask transaction, model-runner span, or Valkey span after ${MAX_WAIT_SECONDS}s"
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
  if should_test_ask; then
    assert_llm_apm
  else
    log "Skipping /ask APM assertion (Docker Model Runner unavailable)"
  fi
  log "E2E APM validation complete"
}

main "$@"
