"""Just enough of the Supervisor API for dartec_bootstrap's run.sh.

Answers the add-on's options with a GitHub token and a fresh run_token, so the
add-on believes a real provisioning run started it, and records every call in
/log/calls so a test can see whether Core was ever stopped.
"""
import json
import secrets
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

LOG = "/log/calls"


class Handler(BaseHTTPRequestHandler):
    def _answer(self, data=None):
        body = json.dumps({"result": "ok", "data": data or {}}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _record(self):
        with open(LOG, "a", encoding="utf-8") as f:
            f.write(f"{self.command} {self.path}\n")

    def do_GET(self):
        self._record()
        if self.path == "/addons/self/options/config":
            run_token = f"dartec1.{int(time.time())}.{secrets.token_urlsafe(24)}"
            return self._answer({"github_token": "github_pat_TEST", "run_token": run_token})
        return self._answer()

    def do_POST(self):
        self._record()
        length = int(self.headers.get("Content-Length") or 0)
        if length:
            self.rfile.read(length)
        return self._answer()

    def log_message(self, *args):
        pass


HTTPServer(("0.0.0.0", 80), Handler).serve_forever()
