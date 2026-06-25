#!/usr/bin/env bash
# Smoke test for the geo-microservice gateway.
#
# Hits /health, /geocode and /route against a RUNNING stack and fails loudly if
# any endpoint is down or returns the wrong shape. This is a black-box check
# against live HTTP — start the stack first (`docker compose up`).
#
#   BASE_URL  gateway base URL            (default http://localhost:8080)
#   API_KEY   sent as X-API-Key if set    (match the deployment's API_KEY)
#   TIMEOUT   per-request timeout, seconds (default 10)
#
# Usage:
#   ./bin/smoke.sh
#   BASE_URL=http://host:8080 API_KEY=secret ./bin/smoke.sh
#   make smoke API_KEY=1234

set -uo pipefail

BASE_URL="${BASE_URL:-http://localhost:8080}"
API_KEY="${API_KEY:-}"
TIMEOUT="${TIMEOUT:-10}"

AUTH=()
if [[ -n "$API_KEY" ]]; then
  AUTH=(-H "X-API-Key: ${API_KEY}")
fi

pass=0
fail=0

# check <name> <expected-substring> <curl args...>
check() {
  local name="$1" expect="$2"
  shift 2
  local out code body
  out=$(curl -sS -m "$TIMEOUT" -H 'Accept: application/json' ${AUTH[@]+"${AUTH[@]}"} -w $'\n%{http_code}' "$@" 2>&1)
  code="${out##*$'\n'}"
  body="${out%$'\n'*}"
  if [[ "$code" == "200" && "$body" == *"$expect"* ]]; then
    printf '  \033[32mPASS\033[0m  %s (200)\n' "$name"
    pass=$((pass + 1))
  else
    printf '  \033[31mFAIL\033[0m  %s (HTTP %s)\n' "$name" "$code"
    printf '        expected body to contain: %s\n' "$expect"
    printf '        got: %.300s\n' "$body"
    fail=$((fail + 1))
  fi
}

echo "Smoke testing ${BASE_URL}"
[[ -n "$API_KEY" ]] && echo "(sending X-API-Key header)"
echo

check '/health' '"status":"ok"' "${BASE_URL}/health"

check '/geocode' '"lat"' -G \
  --data-urlencode 'query=Webergasse 1 Dresden' \
  "${BASE_URL}/geocode"

check '/route' 'distanceInMeters' -G \
  --data-urlencode 'from=Webergasse 1 Dresden' \
  --data-urlencode 'to=Peschelstr 33 Dresden' \
  "${BASE_URL}/route"

echo
echo "${pass} passed, ${fail} failed"
[[ "$fail" -eq 0 ]]
