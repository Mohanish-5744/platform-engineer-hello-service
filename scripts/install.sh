#!/usr/bin/env bash
# Install hello-service on a systemd-based Linux host from this repo.
#
#   sudo scripts/install.sh
#
# Does the same as terraform/cloud-init.yaml.tftpl does on EC2, using the same
# files from deploy/. CI runs it on the GitHub runner (a real systemd VM) to
# test start-up, crash recovery and hang recovery. Safe to run again.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_VERSION="${APP_VERSION:-1.0.0}"

die() { echo "ERROR: $*" >&2; exit 1; }

[[ "$(id -u)" -eq 0 ]] || die "run as root (sudo $0)"
[[ -d /run/systemd/system ]] || die "this host is not running systemd"
command -v python3 >/dev/null || die "python3 is required"
command -v curl >/dev/null || die "curl is required"

echo "==> Installing files"
install -d -m 0755 /opt/hello-service /etc/hello-service
install -m 0644 "${REPO_ROOT}/app/app.py" /opt/hello-service/app.py
echo "APP_VERSION=${APP_VERSION}" > /etc/hello-service/env
chmod 0644 /etc/hello-service/env
install -m 0755 "${REPO_ROOT}/deploy/healthcheck.sh" /usr/local/bin/hello-healthcheck.sh
for unit in hello.service hello-healthcheck.service hello-healthcheck.timer; do
  install -m 0644 "${REPO_ROOT}/deploy/systemd/${unit}" "/etc/systemd/system/${unit}"
done

echo "==> Enabling and (re)starting units"
systemctl daemon-reload
systemctl enable hello.service hello-healthcheck.timer
systemctl restart hello.service     # restart so a re-run picks up new code
systemctl start hello-healthcheck.timer

echo "==> Waiting for /health"
for _ in $(seq 1 10); do
  if curl -fsS --max-time 2 http://127.0.0.1/health; then
    echo "==> Installed"
    exit 0
  fi
  sleep 1
done

journalctl -u hello -n 30 --no-pager >&2 || true
die "service did not become healthy"
