#!/usr/bin/env bash
#
# tools/firstboot.sh — HEADLESS first-boot orchestrator for pwnagotchi4b.
#
# Runs the four component installers exactly once, on the Pi's first boot, with
# no user interaction:
#   1. display/install.sh     (custom waveshare35b class + fbcp|fbtft backend)
#   2. fancygotchi/install.sh (Fancygotchi 2.0 + theme bootstrap)
#   3. plugins/install.sh     (your itsdarklikehell/pwnagotchi-plugins)
#   4. mothership/install.sh  (A2A bridge systemd service on :8700)
#
# After all four, it touches a sentinel flag, disables itself, and reboots so the
# freshly registered display class + fbtft/fbcp overlay take effect. The whole
# flow is idempotent and safe to re-run (installers are guarded internally).
#
# Env overrides (used by the dry-run test; normally not set):
#   DRYRUN=1            log actions but do not run installers or reboot
#   PWNAGOTCHI4B_DIR=   where the repo lives (default: parent of this script)
#   DONE_FLAG=          sentinel path (default: /var/lib/pwnagotchi4b/.firstboot_done)
#   FIRSTBOOT_LOG=      log file (default: /var/log/pwnagotchi4b/firstboot.log)
#
set -uo pipefail

# --- locate repo + paths ------------------------------------------------------
REPO_DIR="${PWNAGOTCHI4B_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
DONE_FLAG="${DONE_FLAG:-/var/lib/pwnagotchi4b/.firstboot_done}"
LOG="${FIRSTBOOT_LOG:-/var/log/pwnagotchi4b/firstboot.log}"
DRYRUN="${DRYRUN:-0}"

# The four installers, in dependency order.
STEPS=(
  "display:display/install.sh"
  "fancygotchi:fancygotchi/install.sh"
  "plugins:plugins/install.sh"
  "mothership:mothership/install.sh"
)

mkdir -p "$(dirname "$DONE_FLAG")" "$(dirname "$LOG")"

log() { echo "[$(date '+%F %T')] $*" | tee -a "$LOG"; }

# Already ran? (the systemd unit also guards via ConditionPathExists, but be safe)
if [ -f "$DONE_FLAG" ]; then
  log "firstboot already completed ($DONE_FLAG present); exiting."
  exit 0
fi

log "=== pwnagotchi4b headless first-boot setup starting (repo=$REPO_DIR) ==="

run_all() {
  local failed=0
  for step in "${STEPS[@]}"; do
    local label="${step%%:*}"
    local rel="${step#*:}"
    local script="$REPO_DIR/$rel"
    log "--- step: $label ($script) ---"
    if [ ! -f "$script" ]; then
      log "!! MISSING: $script — skipping $label"
      failed=1
      continue
    fi
    if [ "$DRYRUN" = "1" ]; then
      log "[dry-run] would run: bash $script"
    else
      if bash "$script" >>"$LOG" 2>&1; then
        log "[ok] $label finished"
      else
        log "!! $label returned non-zero (continuing)"
        failed=1
      fi
    fi
  done
  return $failed
}

# Run once; if anything failed (e.g. transient apt/git network error), retry
# exactly once. This avoids an infinite reboot loop on a persistent failure
# while still surviving a flaky first-boot network.
run_all && ok=1 || ok=0
if [ "$ok" -eq 0 ]; then
  log "first pass had failures; retrying once before flagging done"
  run_all && ok=1 || ok=0
fi

if [ "$ok" -eq 0 ]; then
  log "!! some steps failed after retry — see $LOG for details."
fi

if [ "$DRYRUN" = "1" ]; then
  log "[dry-run] NOT touching sentinel, NOT disabling service, NOT rebooting."
  exit 0
fi

log "=== flagging first boot done and disabling the oneshot ==="
touch "$DONE_FLAG"
systemctl disable pwnagotchi4b-firstboot.service 2>/dev/null || true

log "=== rebooting to activate display + services ==="
reboot
