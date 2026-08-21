#!/usr/bin/env python3
"""
glados_client.py — how GLaDOS (Hermes, A2A :9900) talks to the Pwnagotchi4b peer.

This is a thin, dependency-light client that mirrors the verified A2A call
recipe used between GLaDOS and Wheatley: raw JSON-RPC `message/send` with a
`{kind: text}` part carrying a JSON command string, sent to the peer's
`/a2a/jsonrpc` endpoint.

Run:
    python3 clients/glados_client.py --peer http://pwnagotchi4b.local:8700 get_status
    python3 clients/glados_client.py --peer http://10.0.0.42:8700 set_mode --mode manual
    python3 clients/glados_client.py toggle_plugin --name fancygotchi --enabled true

No third-party deps required (uses urllib). The actual GLaDOS<->Pi A2A call from
within a Hermes session uses the same payload shape (see the hermes-openclaw-a2a
skill: build with jq, POST to /a2a/jsonrpc, read result.artifacts[].parts[].text).
"""
from __future__ import annotations
import argparse
import json
import os
import sys
import urllib.request

DEFAULT_PEER = os.environ.get("PWNAGOTCHI_A2A_URL", "http://pwnagotchi4b.local:8700")
DEFAULT_TOKEN = os.environ.get("PWNAGOTCHI_A2A_TOKEN", "")


def send(peer_url: str, token: str, action: str, args: dict | None = None) -> dict:
    url = peer_url.rstrip("/") + "/a2a/jsonrpc"
    message = {
        "jsonrpc": "2.0",
        "id": 1,
        "method": "message/send",
        "params": {
            "message": {
                "messageId": "msg-glados-1",
                "contextId": "ctx-glados",
                "role": "user",
                "parts": [
                    {"kind": "text", "text": json.dumps({"action": action, "args": args or {}})}
                ],
            }
        },
    }
    data = json.dumps(message).encode()
    req = urllib.request.Request(url, data=data, method="POST",
                                 headers={"Content-Type": "application/json"})
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    with urllib.request.urlopen(req, timeout=30) as resp:
        payload = json.loads(resp.read().decode())
    # Pull the artifact text out (mirrors how GLaDOS/Wheatley read A2A replies).
    result = payload.get("result", {})
    artifacts = result.get("artifacts", [])
    if artifacts:
        text = artifacts[0]["parts"][0]["text"]
        try:
            return json.loads(text)
        except Exception:
            return {"raw": text}
    return result


def main() -> int:
    ap = argparse.ArgumentParser(description="GLaDOS client for the Pwnagotchi4b A2A peer")
    ap.add_argument("--peer", default=DEFAULT_PEER, help="Pwnagotchi A2A endpoint")
    ap.add_argument("--token", default=DEFAULT_TOKEN, help="A2A bearer token")
    sub = ap.add_subparsers(dest="action", required=True)

    sub.add_parser("get_status")
    sub.add_parser("fetch_handshakes")
    sub.add_parser("shutdown")
    sub.add_parser("reboot")

    p_mode = sub.add_parser("set_mode"); p_mode.add_argument("--mode", default="auto")
    p_toggle = sub.add_parser("toggle_plugin")
    p_toggle.add_argument("--name", required=True)
    p_toggle.add_argument("--enabled", type=lambda x: x.lower() == "true", default=True)

    args = ap.parse_args()
    action = args.action
    cmd_args = {}
    if action == "set_mode":
        cmd_args = {"mode": args.mode}
    elif action == "toggle_plugin":
        cmd_args = {"name": args.name, "enabled": args.enabled}

    try:
        out = send(args.peer, args.token, action, cmd_args)
    except Exception as exc:  # noqa: BLE001
        print(f"ERROR contacting {args.peer}: {exc}", file=sys.stderr)
        return 1
    print(json.dumps(out, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
