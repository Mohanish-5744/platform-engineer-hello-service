#!/usr/bin/env python3
"""Minimal HTTP service: GET / , GET /health , GET /metrics.

Standard library only, so the host needs nothing beyond python3 (Amazon
Linux 2023 ships 3.9, so avoid newer syntax). Logs go to stdout; under
systemd that ends up in journald.

Config via env vars: HOST (default 127.0.0.1), PORT (default 8080),
APP_VERSION (default "dev").
"""

import json
import logging
import os
import signal
import sys
import threading
import time
from collections import Counter
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

APP_NAME = "hello-service"
START_TIME = time.monotonic()

# Request counter for /metrics, keyed by (path, status code).
# Unknown paths are grouped as "other" so a scanner hitting random URLs
KNOWN_PATHS = ("/", "/health", "/metrics")
REQUESTS = Counter()
REQUESTS_LOCK = threading.Lock()

log = logging.getLogger(APP_NAME)


def uptime_seconds():
    return int(time.monotonic() - START_TIME)


def render_metrics():
    """Prometheus text exposition format."""
    lines = [
        "# HELP hello_requests_total HTTP requests by path and status code.",
        "# TYPE hello_requests_total counter",
    ]
    with REQUESTS_LOCK:
        for (path, code), count in sorted(REQUESTS.items()):
            lines.append(f'hello_requests_total{{path="{path}",code="{code}"}} {count}')
    lines += [
        "# HELP hello_uptime_seconds Seconds since the process started.",
        "# TYPE hello_uptime_seconds gauge",
        f"hello_uptime_seconds {uptime_seconds()}",
    ]
    return "\n".join(lines) + "\n"


class Handler(BaseHTTPRequestHandler):
    server_version = APP_NAME
    sys_version = ""

    def do_GET(self):
        self.route(send_body=True)

    def do_HEAD(self):
        self.route(send_body=False)

    def route(self, send_body):
        path = self.path.split("?", 1)[0]

        if path == "/":
            self.respond(path, 200, "text/plain; charset=utf-8",
                         f"Hello from {APP_NAME}!\n", send_body)
        elif path == "/health":
            body = json.dumps({
                "status": "ok! Service is alive and responding.",
                "service": APP_NAME,
                "version": os.environ.get("APP_VERSION", "dev"),
                "uptime_seconds": uptime_seconds(),
            })
            self.respond(path, 200, "application/json", body + "\n", send_body)
        elif path == "/metrics":
            self.respond(path, 200, "text/plain; version=0.0.4", render_metrics(), send_body)
        else:
            self.respond(path, 404, "text/plain; charset=utf-8", "Not found\n", send_body)

    def respond(self, path, status, content_type, body, send_body):
        label = path if path in KNOWN_PATHS else "other"
        with REQUESTS_LOCK:
            REQUESTS[(label, status)] += 1

        data = body.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        if send_body:
            self.wfile.write(data)

    def log_message(self, fmt, *args):
        log.info("%s %s", self.address_string(), fmt % args)


def build_server(host, port):
    # Threaded so one slow client can't block /health.
    return ThreadingHTTPServer((host, port), Handler)


def main():
    logging.basicConfig(stream=sys.stdout, level=logging.INFO,
                        format="%(asctime)s %(levelname)s %(message)s")

    host = os.environ.get("HOST", "127.0.0.1")
    try:
        port = int(os.environ.get("PORT", "8080"))
    except ValueError:
        log.error("PORT must be a number, got %r", os.environ.get("PORT"))
        return 2

    try:
        server = build_server(host, port)
    except OSError as exc:
        log.error("cannot bind %s:%s: %s", host, port, exc)
        return 1

    def on_sigterm(signum, frame):
        raise KeyboardInterrupt

    signal.signal(signal.SIGTERM, on_sigterm)

    log.info("listening on %s:%s version=%s", host, port, os.environ.get("APP_VERSION", "dev"))
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        log.info("stopping")
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
