#!/bin/bash

set -euo pipefail

# 2026 Docker Bootcamp - Part 2 smoke automation

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DJANGO_DIR="$PROJECT_ROOT/django_app_for_part_2/Django"
ELK_DIR="$PROJECT_ROOT/django_app_for_part_2/ELK"

LLM_MODEL="${LLM_MODEL:-ai/smollm2}"

log() {
  printf "[part2] %s\n" "$1"
}

cleanup() {
  if [ "${KEEP_STACK_UP:-0}" = "1" ]; then
    log "KEEP_STACK_UP=1 set; leaving stacks running for inspection"
    return 0
  fi
  (cd "$DJANGO_DIR" && docker compose down -v >/dev/null 2>&1 || true)
  (cd "$ELK_DIR" && docker compose --profile monitoring down -v >/dev/null 2>&1 || true)
}

trap cleanup EXIT

require_prereqs() {
  command -v docker >/dev/null
  docker info >/dev/null
}

ensure_secret_permissions() {
  local postgres_secret="$DJANGO_DIR/secrets/postgres_password.txt"
  if [ ! -f "$postgres_secret" ]; then
    if [ -f "$DJANGO_DIR/secrets/postgres_password.example.txt" ]; then
      cp "$DJANGO_DIR/secrets/postgres_password.example.txt" "$postgres_secret"
    fi
  fi
  [ -f "$postgres_secret" ] && chmod 600 "$postgres_secret"
}

wait_for_http() {
  local url="$1"
  local tries=40
  for _ in $(seq 1 "$tries"); do
    if curl -sSf "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep 3
  done
  return 1
}

wait_for_elasticsearch() {
  local elastic_password="${ELASTIC_PASSWORD:-bootcamp-elastic}"

  local tries=40
  for _ in $(seq 1 "$tries"); do
    if curl -sSf -u "elastic:${elastic_password}" "http://localhost:9200/_cluster/health" >/dev/null 2>&1; then
      return 0
    fi
    sleep 3
  done
  return 1
}

run_tests() {
  log "Starting ELK with monitoring profile"
  (
    cd "$ELK_DIR"
    docker compose --profile monitoring up -d
  )

  log "Waiting for Elasticsearch"
  wait_for_elasticsearch

  log "Starting Django core stack"
  (
    cd "$DJANGO_DIR"
    docker compose up -d
    docker compose -f docker-compose.yml -f docker-compose.otel.yml up -d
  )

  log "Waiting for Django"
  wait_for_http "http://localhost:8000/"

  log "Local LLM /ask smoke check"
  if docker model version >/dev/null 2>&1; then
    docker model pull "$LLM_MODEL" >/dev/null 2>&1 || log "WARNING: could not pull $LLM_MODEL"
    if curl -sSf "http://localhost:8000/ask" | grep -q '<textarea name="question"'; then
      log "/ask form renders"
    else
      log "WARNING: /ask form did not render as expected"
    fi
    ask_jar="$(mktemp)"
    ask_html="$(curl -sS -c "$ask_jar" "http://localhost:8000/ask" || true)"
    ask_token="$(printf '%s' "$ask_html" | grep -o 'name="csrfmiddlewaretoken" value="[^"]*"' | head -1 | sed 's/.*value="//;s/"$//')"
    ask_question="What is Docker in one sentence?"
    post_ask() {
      curl -sS --max-time 180 -b "$ask_jar" -c "$ask_jar" -e "http://localhost:8000/ask" \
        --data "csrfmiddlewaretoken=${ask_token}" \
        --data-urlencode "question=${ask_question}" \
        "http://localhost:8000/ask" || true
    }
    # First ask is a cache miss (calls the model)...
    if post_ask | grep -q "<h2>Answer"; then
      log "/ask returned an LLM answer (cache miss)"
    else
      log "WARNING: /ask did not return an answer; check Docker Model Runner"
    fi
    # ...asking the same question again should be served from the Valkey cache.
    if post_ask | grep -q "Served from the Valkey cache"; then
      log "/ask repeat question served from the Valkey cache (cache hit)"
    else
      log "WARNING: /ask did not report a Valkey cache hit on repeat"
    fi
    rm -f "$ask_jar"
  else
    log "docker model not available; skipping /ask checks"
  fi

  log "Generating OTel traffic"
  curl -s "http://localhost:8000/" >/dev/null
  curl -s "http://localhost:8000/sleep/1" >/dev/null || true
  curl -s "http://localhost:8000/error" >/dev/null || true

  log "Running tests via override"
  (
    cd "$DJANGO_DIR"
    docker compose -f docker-compose.yml -f docker-compose.tests.yml up --exit-code-from=web web >/dev/null
    docker compose -f docker-compose.yml -f docker-compose.tests.yml down >/dev/null || true
    docker compose -f docker-compose.yml -f docker-compose.otel.yml up -d >/dev/null
  )

  log "Running tests via exec"
  (
    cd "$DJANGO_DIR"
    docker compose exec -T web python manage.py test >/dev/null
  )

  log "Compose watch smoke check"
  (
    cd "$DJANGO_DIR"
    timeout 8 docker compose watch >/dev/null 2>&1 || true
  )

  log "Docker Scout quickview smoke check"
  docker scout quickview bootcamp-django >/dev/null || log "docker scout not available; skipping"

  log "Running strict APM E2E assertion"
  "$PROJECT_ROOT/scripts/test-apm-e2e.sh"

  log "Part 2 automation complete"
}

main() {
  require_prereqs
  ensure_secret_permissions
  cleanup || true
  run_tests
}

main "$@"
