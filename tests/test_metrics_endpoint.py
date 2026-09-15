#!/usr/bin/env python3
"""
tests/test_metrics_endpoint.py — verify the /metrics endpoint on the A2A bridge.

Starts a fresh --simulate server on a dynamic port, exercises a few actions,
then queries /metrics and asserts the shape + counters.

Run:
    python3 tests/test_metrics_endpoint.py
"""

from __future__ import annotations

import json
import socket
import subprocess
import sys
import time
import urllib.request
import urllib.error

HERE = __import__("os").path.dirname(__import__("os").path.abspath(__file__))
MOTHERSHIP = __import__("os").path.join(HERE, "..", "mothership", "pwnagotchi_a2a.py")


def _free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return int(s.getsockname()[1])


def get(base: str, path: str) -> dict:
    with urllib.request.urlopen(base + path, timeout=5) as r:
        return json.loads(r.read().decode())


def post(base: str, payload: dict) -> dict:
    url = base + "/a2a/jsonrpc"
    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode(),
        method="POST",
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=10) as r:
        return json.loads(r.read().decode())


def main() -> int:
    import os

    port = _free_port()
    base = f"http://127.0.0.1:{port}"
    proc = subprocess.Popen(
        [sys.executable, os.path.abspath(MOTHERSHIP), "--simulate", "--port", str(port)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        # Wait for the server to bind.
        for _ in range(15):
            try:
                urllib.request.urlopen(base + "/healthz", timeout=1)
                break
            except Exception:
                time.sleep(0.5)
        else:
            print("TEST FAILED: server did not start on port %d" % port, file=sys.stderr)
            return 1

        # 1. /metrics exists and has the right top-level shape
        m = get(base, "/metrics")
        assert "timestamp" in m, m
        assert "server" in m, m
        assert "tasks" in m, m
        assert "peers" in m, m
        assert "actions_served" in m, m
        print("[ok] /metrics shape OK")

        # 2. server info — check the dynamic port we asked for
        assert m["server"]["name"] == "pwnagotchi4b"
        assert m["server"]["simulate"] is True
        assert m["server"]["port"] == port, m["server"]
        print("[ok] /metrics server info OK (port=%d)" % port)

        # 3. tasks initially empty — fresh server, nothing has happened yet
        assert m["tasks"]["active"] == 0, m["tasks"]
        assert m["tasks"]["completed"] == 0
        assert m["tasks"]["canceled"] == 0
        print("[ok] /metrics tasks initially empty")

        # 4. peers listed
        assert len(m["peers"]) == 2
        names = {p["name"] for p in m["peers"]}
        assert "glados-hermes" in names
        assert "wheatley-openclaw" in names
        print("[ok] /metrics peers OK")

        # 5. after actions, counters update
        post(base, {
            "jsonrpc": "2.0", "id": 1, "method": "message/send",
            "params": {"message": {
                "messageId": "t1", "contextId": "ctx-test", "role": "user",
                "parts": [{"kind": "text", "text": json.dumps({"action": "get_status"})}],
            }},
        })
        post(base, {
            "jsonrpc": "2.0", "id": 2, "method": "message/send",
            "params": {"message": {
                "messageId": "t2", "contextId": "ctx-test", "role": "user",
                "parts": [{"kind": "text", "text": json.dumps({"action": "set_mode", "args": {"mode": "manual"}})}],
            }},
        })
        post(base, {
            "jsonrpc": "2.0", "id": 3, "method": "message/send",
            "params": {"message": {
                "messageId": "t3", "contextId": "ctx-test", "role": "user",
                "parts": [{"kind": "text", "text": json.dumps({"action": "toggle_plugin", "args": {"name": "fancygotchi", "enabled": True}})}],
            }},
        })
        m2 = get(base, "/metrics")
        assert m2["tasks"]["active"] == 3, m2["tasks"]
        assert m2["tasks"]["completed"] == 3
        assert set(m2["actions_served"]) == {"get_status", "set_mode", "toggle_plugin"}, m2["actions_served"]
        print("[ok] /metrics counters after 3 actions OK")

        print("\nALL METRICS ENDPOINT TESTS PASSED")
        return 0
    except (AssertionError, urllib.error.URLError, KeyError, json.JSONDecodeError) as e:
        print("TEST FAILED:", e, file=sys.stderr)
        return 1
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except Exception:
            proc.kill()


if __name__ == "__main__":
    raise SystemExit(main())
