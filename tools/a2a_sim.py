#!/usr/bin/env python3
"""
tools/a2a_sim.py — self-contained A2A JSON-RPC stub for pwnagotchi4b.

Used by the VM integration test (and locally) to provide a real, wire-level
A2A server on :8700 so the client/verify scripts can exercise the actual
JSON-RPC protocol without the full pwnagotchi mothership. It is NOT the
production bridge (that is mothership/pwnagotchi_a2a.py); it only mimics the
agent-card + JSON-RPC surface our tests assert against.

Endpoints:
  GET  /.well-known/agent-card.json
  GET  /healthz
  POST /  (JSON-RPC 2.0: get_status, toggle_plugin, set_mode)
"""
import argparse, json, sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

TOKEN = "vmtest"
CARD = {
    "protocolVersion": "0.2.0",
    "name": "pwnagotchi4b-a2a-stub",
    "description": "A2A stub for pwnagotchi4b integration tests",
    "url": "http://localhost:8700",
    "capabilities": {"streaming": False},
    "skills": [
        {"id": "get_status", "name": "Get Status", "description": "Returns pwnagotchi status"},
        {"id": "toggle_plugin", "name": "Toggle Plugin", "description": "Enable/disable a plugin"},
        {"id": "set_mode", "name": "Set Mode", "description": "Set pwnagotchi mode (AUTO/MANU"}
    ],
}

STATE = {"mode": "AUTO", "plugins": {"memtemp": True, "fancygotchi": True}}


def jsonrpc(method, params):
    if method == "get_status":
        return {
            "mode": STATE["mode"],
            "plugins": STATE["plugins"],
            "uptime_s": 1234,
            "artifact": "pwnagotchi-status-v1",
        }
    if method == "toggle_plugin":
        name = params.get("name")
        if name is None:
            raise ValueError("toggle_plugin requires 'name'")
        STATE["plugins"][name] = not STATE["plugins"].get(name, False)
        return {"name": name, "enabled": STATE["plugins"][name]}
    if method == "set_mode":
        mode = params.get("mode")
        if mode not in ("AUTO", "MANU", "AUTO-NL", "MANU-NL"):
            raise ValueError("invalid mode")
        STATE["mode"] = mode
        return {"mode": mode}
    raise ValueError(f"unknown method: {method}")


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, body, ctype="application/json"):
        data = body.encode() if isinstance(body, str) else body
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path == "/.well-known/agent-card.json":
            self._send(200, json.dumps(CARD))
        elif self.path == "/healthz":
            self._send(200, json.dumps({"status": "ok"}))
        else:
            self._send(404, json.dumps({"error": "not found"}))

    def do_POST(self):
        # Accept both the bare "/" route (legacy test) and the real A2A spec
        # route "/a2a/jsonrpc" that clients/glados_client.py &
        # clients/wheatley_client.py POST to.
        if self.path not in ("/", "/a2a/jsonrpc"):
            self._send(404, json.dumps({"error": "not found"}))
            return
        length = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(length) if length else b"{}"
        try:
            req = json.loads(raw or b"{}")
        except Exception as e:
            self._send(400, json.dumps({"error": f"bad json: {e}"}))
            return
        method = req.get("method", "")
        params = req.get("params", {}) or {}
        try:
            result = jsonrpc(method, params)
            self._send(200, json.dumps({"jsonrpc": "2.0", "id": req.get("id"), "result": result}))
        except Exception as e:
            self._send(200, json.dumps({"jsonrpc": "2.0", "id": req.get("id"), "error": {"message": str(e)}}))

    def log_message(self, *a):
        pass


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=8700)
    ap.add_argument("--token", default=TOKEN)
    a = ap.parse_args()
    srv = ThreadingHTTPServer((a.host, a.port), Handler)
    print(f"[a2a_sim] listening on {a.host}:{a.port}", flush=True)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
