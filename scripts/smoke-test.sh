#!/usr/bin/env bash
# Black-box test of a running hello-service from the outside.
# Used in CI (local app and systemd install), after deploy.sh, and by
# the manual "live smoke test" CI job.
#
#   scripts/smoke-test.sh http://<host>[:port]
#
# Env: RETRIES / DELAY       how long to wait for /health (default 30 x 10s)
#      CHECK_SSH_CLOSED=true  also assert port 22 is not reachable
# Exit: 0 ok, 1 check failed, 2 bad usage

set -euo pipefail

BASE_URL="${1:-}"
RETRIES="${RETRIES:-30}"
DELAY="${DELAY:-10}"
CHECK_SSH_CLOSED="${CHECK_SSH_CLOSED:-true}"
AWS_ACCESS_KEY="AKIAIOSFODNN7EXAMPLE"

pass() { echo "PASS  $*"; }
fail() { echo "FAIL  $*" >&2; exit 1; }

# Validate input: this also runs in CI with a URL typed into a form.
if [[ ! "$BASE_URL" =~ ^https?://[A-Za-z0-9.:-]+/?$ ]]; then
  echo "usage: $0 http://<host>[:port]" >&2
  exit 2
fi
BASE_URL="${BASE_URL%/}"
HOST="$(sed -E 's#^https?://##; s#:[0-9]+$##' <<<"$BASE_URL")"

echo "Waiting for ${BASE_URL}/health (up to $((RETRIES * DELAY))s)"
for i in $(seq 1 "$RETRIES"); do
  curl -fsS --max-time 5 -o /dev/null "${BASE_URL}/health" 2>/dev/null && break
  [[ "$i" -eq "$RETRIES" ]] && fail "/health not reachable after ${RETRIES} attempts"
  sleep "$DELAY"
done
pass "/health reachable"

health="$(curl -fsS --max-time 5 "${BASE_URL}/health")"
grep -q '"status": "ok! Service is alive and responding."' <<<"$health" || fail "/health returned: $health"
pass "/health status ok! Service is alive and responding.: $health"

root="$(curl -fsS --max-time 5 "${BASE_URL}/")"
grep -q "Hello" <<<"$root" || fail "/ returned: $root"
pass "/ returns: $root"

code="$(curl -s --max-time 5 -o /dev/null -w '%{http_code}' "${BASE_URL}/nope")"
[[ "$code" == "404" ]] || fail "/nope returned HTTP $code, expected 404"
pass "unknown path returns 404"

curl -fsS --max-time 5 "${BASE_URL}/metrics" | grep -q '^hello_requests_total' \
  || fail "/metrics has no hello_requests_total"
pass "/metrics exposes request counters"

if [[ "$CHECK_SSH_CLOSED" == "true" ]]; then
  # The security group drops packets, so the connect attempt times out.
  if timeout 5 bash -c "exec 3<>/dev/tcp/${HOST}/22" 2>/dev/null; then
    fail "port 22 on ${HOST} is reachable, it should be blocked"
  fi
  pass "port 22 not reachable"
fi

echo "All smoke tests passed for ${BASE_URL}"
