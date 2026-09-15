#!/usr/bin/env python3
"""
glados_client.py — how GLaDOS (Hermes, A2A :9900) talks to the Pwnagotchi4b peer.

Thin wrapper around clients.a2a_client — the real logic lives there.
"""

from __future__ import annotations

import sys

from a2a_client import build_parser, resolve_cmd_args, send, watch

CLIENT_NAME = "glados"


def main() -> int:
    ap = build_parser("GLaDOS client for the Pwnagotchi4b A2A peer", CLIENT_NAME)
    args = ap.parse_args()
    action = args.action
    cmd_args = resolve_cmd_args(action, args)

    if action == "watch":
        return watch(args.peer, args.token, args.interval, client_name=CLIENT_NAME)

    try:
        out = send(args.peer, args.token, action, cmd_args, client_name=CLIENT_NAME)
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    print(json.dumps(out, indent=2))
    return 0


if __name__ == "__main__":
    import json
    raise SystemExit(main())
