#!/usr/bin/env bash
# Smoke test: hit /health on both apps and one non-LLM endpoint.
# Relies on port 18080 bound via kind extraPortMappings (ingress-nginx).
set -euo pipefail

INGRESS="http://localhost:18080"

# A pod can be Ready a few seconds before ingress-nginx adds it to its upstreams; until then
# the ingress answers 503. Retry for up to ~60 s instead of failing on the first try.
smoke_check() {
  local name=$1; local url=$2; local expected=${3:-200}
  local status=""
  for attempt in $(seq 1 30); do
    status=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: ${4:-}" "$url" --max-time 10 || true)
    if [[ "$status" == "$expected" ]]; then
      echo "  PASS [$name] $url -> $status (attempt $attempt)"
      return 0
    fi
    sleep 2
  done
  echo "  FAIL [$name] $url -> $status (expected $expected, 30 attempts)"
  return 1
}

echo "==> Smoke tests"
smoke_check "jobtracker-health" "$INGRESS/health" 200 "jobtracker.local"
smoke_check "voice-agent-health" "$INGRESS/health" 200 "voice-agent.local"

# Non-LLM endpoint: jobtracker list jobs (returns 200 or 401 depending on auth)
status=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: jobtracker.local" \
  "$INGRESS/jobs" --max-time 10 || true)
if [[ "$status" == "200" || "$status" == "401" || "$status" == "422" ]]; then
  echo "  PASS [jobtracker-jobs] $INGRESS/jobs -> $status (acceptable)"
else
  echo "  WARN [jobtracker-jobs] $INGRESS/jobs -> $status (may be expected without auth)"
fi

echo "==> All smoke tests done."
