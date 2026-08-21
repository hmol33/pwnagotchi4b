#!/usr/bin/env python3
"""
wheatley_client.py — how Wheatley (OpenClaw, A2A :18800) talks to the
Pwnagotchi4b peer. Functionally identical to glados_client.py; kept separate so
each core has its own, voice-appropriate entry point and so the two motherships
can be driven independently (and compared).

The shape matches the verified GLaDOS<->Wheatley A2A recipe:
JSON-RPC message/send, {kind: text} part with a JSON command, read
result.artifacts[].parts[].text.

Run:
    python3 clients/wheatley_client.py --peer http://pwnagotchi4b.local:8700 get_status
    python3 clients/wheatley_client.py reboot --mode auto
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
                "messageId": "msg-wheatley-1",
                "contextId": "ctx-wheatley",
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
    ap = argparse.ArgumentParser(description="Wheatley client for the Pwnagotchi4b A2A peer")
    ap.add_argument("--peer", default=DEFAULT_PEER)
    ap.add_argument("--token", default=DEFAULT_TOKEN)
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
    cmd_args: dict = {}
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
