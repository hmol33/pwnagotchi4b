#!/usr/bin/env python3
"""
glados_client.py — how GLaDOS (Hermes, A2A :9900) talks to the Pwnagotchi4b peer.

Dependency-light A2A client (urllib only). Mirrors the verified GLaDOS<->Wheatley
call recipe: raw JSON-RPC message/send with a {kind:text} part carrying a JSON
command, POSTed to the peer's /a2a/jsonrpc.

Improvements over the original:
  - JSON-RPC *error* field is surfaced instead of crashing on missing result.
  - fetch_handshakes accepts --limit.
  - `watch` polls get_status every INTERVAL s and prints a compact line
    (handy for a tmux pane or the Friday log).

Run:
    python3 glados_client.py --peer http://pwnagotchi4b.local:8700 get_status
    python3 glados_client.py set_mode --mode manual
    python3 glados_client.py toggle_plugin --name fancygotchi --enabled true
    python3 glados_client.py fetch_handshakes --limit 20
    python3 glados_client.py watch --interval 30
"""
from __future__ import annotations
import argparse
import json
import os
import sys
import time
import urllib.request
import urllib.error

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
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            payload = json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        body = e.read().decode(errors="replace")
        raise RuntimeError(f"HTTP {e.code}: {body[:200]}") from e
    except urllib.error.URLError as e:
        raise RuntimeError(f"connection failed: {e.reason}") from e

    # Surface JSON-RPC errors cleanly instead of KeyError on missing result.
    if "error" in payload:
        err = payload["error"]
        raise RuntimeError(f"A2A error {err.get('code')}: {err.get('message')}")
    result = payload.get("result", {})
    artifacts = result.get("artifacts", [])
    if artifacts:
        text = artifacts[0]["parts"][0]["text"]
        try:
            return json.loads(text)
        except Exception:
            return {"raw": text}
    return result


def watch(peer: str, token: str, interval: int) -> int:
    print(f"# watching {peer} every {interval}s (Ctrl-C to stop)", file=sys.stderr)
    try:
        while True:
            try:
                st = send(peer, token, "get_status", {})
                mode = st.get("mode", "?")
                pwnd = st.get("pwnd_tot", st.get("pwndrun", "?"))
                ups = st.get("ups", st.get("battery", "?"))
                print(f"{time.strftime('%H:%M:%S')} mode={mode} pwnd={pwnd} ups={ups}")
            except Exception as e:
                print(f"{time.strftime('%H:%M:%S')} ERR {e}")
            time.sleep(interval)
    except KeyboardInterrupt:
        return 0


def main() -> int:
    ap = argparse.ArgumentParser(description="GLaDOS client for the Pwnagotchi4b A2A peer")
    ap.add_argument("--peer", default=DEFAULT_PEER, help="Pwnagotchi A2A endpoint")
    ap.add_argument("--token", default=DEFAULT_TOKEN, help="A2A bearer token")
    sub = ap.add_subparsers(dest="action", required=True)

    sub.add_parser("get_status")
    p_hs = sub.add_parser("fetch_handshakes")
    p_hs.add_argument("--limit", type=int, default=20)
    sub.add_parser("shutdown")
    sub.add_parser("reboot")
    p_mode = sub.add_parser("set_mode"); p_mode.add_argument("--mode", default="auto")
    p_toggle = sub.add_parser("toggle_plugin")
    p_toggle.add_argument("--name", required=True)
    p_toggle.add_argument("--enabled", type=lambda x: x.lower() == "true", default=True)
    p_watch = sub.add_parser("watch")
    p_watch.add_argument("--interval", type=int, default=30)

    args = ap.parse_args()
    action = args.action
    cmd_args = {}
    if action == "set_mode":
        cmd_args = {"mode": args.mode}
    elif action == "toggle_plugin":
        cmd_args = {"name": args.name, "enabled": args.enabled}
    elif action == "fetch_handshakes":
        cmd_args = {"limit": args.limit}
    elif action == "watch":
        return watch(args.peer, args.token, args.interval)

    try:
        out = send(args.peer, args.token, action, cmd_args)
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    print(json.dumps(out, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
