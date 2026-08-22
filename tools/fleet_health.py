#!/usr/bin/env python3
"""
fleet_health.py — poll de hele thuis-vloot en print een compact statusrapport.
Gebruikt door het vrijdagmiddag-zeemansverslag (en handmatig in een tmux-pane).

Controleert:
  - Bot-mesh: Corneel (:9900), Dorus (:18800), Maarten (:114:9900)
  - Diensten: Calibre-web, Prowlarr, Transmission, Immich, Readarr, ComfyUI, STT, TTS
  - Pwnagotchi4b peer (optioneel, als PWNAGOTCHI_A2A_URL gezet is)

Geen externe deps (urllib + socket). Geen secrets in output.
"""
from __future__ import annotations
import os, socket, sys, time, urllib.request, json

# (host, port, label) — intern/lokaal
SERVICES = [
    ("192.168.178.62", 9900, "Corneel A2A"),
    ("192.168.178.62", 18800, "Dorus A2A"),
    ("192.168.178.114", 9900, "Maarten A2A"),
    ("192.168.178.115", 8083, "Calibre-web"),
    ("192.168.178.117", 9696, "Prowlarr"),
    ("192.168.178.118", 9091, "Transmission"),
    ("192.168.178.119", 2283, "Immich"),
    ("192.168.178.120", 8787, "Readarr"),
    ("192.168.178.62", 8188, "ComfyUI"),
    ("192.168.178.22", 8081, "STT whisper"),
    ("192.168.178.120", 8080, "TTS piper"),
]

def check_tcp(host: str, port: int, timeout: float = 2.0) -> bool:
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True
    except OSError:
        return False

def main() -> int:
    print("=== ⚓ Vloot-status (%s) ===" % time.strftime("%Y-%m-%d %H:%M"))
    up = down = 0
    for host, port, label in SERVICES:
        ok = check_tcp(host, port)
        mark = "🟢" if ok else "🔴"
        print(f"  {mark} {label:16s} {host}:{port}")
        up += ok; down += (not ok)
    # Pwnagotchi peer (optioneel)
    pw = os.environ.get("PWNAGOTCHI_A2A_URL")
    if pw:
        try:
            base = pw.rstrip("/")
            with urllib.request.urlopen(base + "/healthz", timeout=5) as r:
                print(f"  🟢 Pwnagotchi4b      {base} ({r.status})")
                up += 1
        except Exception:
            print(f"  🔴 Pwnagotchi4b      {base} (down)")
            down += 1
    print(f"--- {up} schepen varen, {down} aan de ketting ---")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
