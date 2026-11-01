#!/usr/bin/env bash
# Installed to /usr/local/bin/hello-healthcheck.sh, run every minute by the timer.
#
# Restart=always only helps when the process exits. If the app hangs, the
# process is still "running" but serves nothing, so check the real endpoint.
# 3 failed attempts -> log to journald, restart the service, exit 1.

set -euo pipefail

HEALTH_URL="${HEALTH_URL:-http://127.0.0.1:80/health}"
SERVICE_NAME="${SERVICE_NAME:-hello.service}"
ATTEMPTS="${ATTEMPTS:-3}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-3}"
SLEEP_SECONDS="${SLEEP_SECONDS:-2}"

for attempt in $(seq 1 "$ATTEMPTS"); do
  if curl -fsS --max-time "$TIMEOUT_SECONDS" -o /dev/null "$HEALTH_URL"; then
    exit 0
  fi
  echo "attempt ${attempt}/${ATTEMPTS} failed: ${HEALTH_URL}" >&2
  sleep "$SLEEP_SECONDS"
done

logger -t hello-healthcheck -p user.err \
  "UNHEALTHY: ${HEALTH_URL} failed ${ATTEMPTS} times, restarting ${SERVICE_NAME}"

if systemctl restart "$SERVICE_NAME"; then
  logger -t hello-healthcheck -p user.warning "restarted ${SERVICE_NAME}"
else
  logger -t hello-healthcheck -p user.crit "could not restart ${SERVICE_NAME}"
fi

# Non-zero so the failed run is visible in `systemctl status hello-healthcheck`.
exit 1
