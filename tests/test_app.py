"""Unit tests for app/app.py. Run: python3 -m unittest discover -s tests -v"""

import json
import os
import sys
import threading
import unittest
import urllib.error
import urllib.request

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "app"))
import app  # noqa: E402


class AppTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Port 0: the OS picks a free port, so tests never clash with anything running.
        cls.server = app.build_server("127.0.0.1", 0)
        cls.base = f"http://127.0.0.1:{cls.server.server_address[1]}"
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()

    def get(self, path, method="GET"):
        req = urllib.request.Request(self.base + path, method=method)
        try:
            with urllib.request.urlopen(req, timeout=5) as resp:
                return resp.status, resp.headers, resp.read().decode()
        except urllib.error.HTTPError as err:
            return err.code, err.headers, err.read().decode()

    def test_root(self):
        status, _, body = self.get("/")
        self.assertEqual(status, 200)
        self.assertIn("Hello", body)

    def test_health(self):
        status, headers, body = self.get("/health")
        self.assertEqual(status, 200)
        self.assertEqual(headers["Content-Type"], "application/json")
        self.assertEqual(json.loads(body)["status"], "ok! Service is alive and responding.")

    def test_health_with_query_string(self):
        self.assertEqual(self.get("/health?probe=1")[0], 200)

    def test_head_returns_no_body(self):
        status, _, body = self.get("/health", method="HEAD")
        self.assertEqual(status, 200)
        self.assertEqual(body, "")

    def test_unknown_path_404(self):
        self.assertEqual(self.get("/nope")[0], 404)

    def test_post_not_allowed(self):
        self.assertEqual(self.get("/", method="POST")[0], 501)

    def test_server_header_hides_python(self):
        self.assertNotIn("Python", self.get("/")[1].get("Server", ""))

    def test_metrics_counts_requests(self):
        self.get("/health")
        self.get("/random-path-1")
        self.get("/random-path-2")
        status, _, body = self.get("/metrics")
        self.assertEqual(status, 200)
        self.assertIn('hello_requests_total{path="/health",code="200"}', body)
        self.assertIn("hello_uptime_seconds", body)
        # random paths are grouped, not one series each
        self.assertIn('path="other",code="404"', body)
        self.assertNotIn("random-path", body)


if __name__ == "__main__":
    unittest.main()
