#!/usr/bin/env bash
#
# tools/firstboot.sh — HEADLESS first-boot orchestrator for pwnagotchi4b.
#
# Runs the four component installers exactly once, on the Pi's first boot, with
# no user interaction, then reboots so the freshly registered display class +
# fbtft/fbcp overlay take effect.
#
# The actual step-running lives in tools/run_steps.sh (shared with watchdog.sh).
# If a step fails (e.g. transient apt/git network error), it retries once.
# The systemd unit also guards via ConditionPathExists, but the sentinel is the
# authoritative "already done" marker.
#
# Env overrides (used by the dry-run test; normally not set):
#   DRYRUN=1            log actions but do not run installers or reboot
#   PWNAGOTCHI4B_DIR=   where the repo lives (default: parent of this script)
#   DONE_FLAG=          sentinel path (default: /var/lib/pwnagotchi4b/.firstboot_done)
#   FIRSTBOOT_LOG=      log file (default: /var/log/pwnagotchi4b/firstboot.log)
#
set -uo pipefail

REPO_DIR="${PWNAGOTCHI4B_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
DONE_FLAG="${DONE_FLAG:-/var/lib/pwnagotchi4b/.firstboot_done}"
PWNAGOTCHI4B_LOG="${FIRSTBOOT_LOG:-/var/log/pwnagotchi4b/firstboot.log}"
DRYRUN="${DRYRUN:-0}"
NO_REBOOT="${NO_REBOOT:-0}"

mkdir -p "$(dirname "$DONE_FLAG")" "$(dirname "$PWNAGOTCHI4B_LOG")"
source "$REPO_DIR/tools/run_steps.sh"

log() { echo "[$(date '+%F %T')] $*" | tee -a "$PWNAGOTCHI4B_LOG"; }

# Reboot wrapper: honors DRYRUN / NO_REBOOT so the script is testable without a
# real reboot. The systemd unit performs the actual reboot in production.
do_reboot() {
  if [ "$DRYRUN" = "1" ] || [ "$NO_REBOOT" = "1" ]; then
    log "[dry-run/no-reboot] would reboot here (skipped)."
    return 0
  fi
  log "=== rebooting to activate display + services ==="
  reboot
}

# Already ran? (the systemd unit also guards via ConditionPathExists, but be safe)
if [ -f "$DONE_FLAG" ]; then
  log "firstboot already completed ($DONE_FLAG present); exiting."
  exit 0
fi

log "=== pwnagotchi4b headless first-boot setup starting (repo=$REPO_DIR) ==="

run_steps && ok=1 || ok=0
if [ "$ok" -eq 0 ]; then
  log "first pass had failures; retrying once before flagging done"
  run_steps && ok=1 || ok=0
fi

if [ "$ok" -eq 0 ]; then
  log "!! some steps failed after retry — see $PWNAGOTCHI4B_LOG for details."
fi

if [ "$DRYRUN" = "1" ]; then
  log "[dry-run] NOT touching sentinel, NOT disabling service, NOT rebooting."
  exit 0
fi

log "=== flagging first boot done and disabling the oneshot ==="
touch "$DONE_FLAG"
systemctl disable pwnagotchi4b-firstboot.service 2>/dev/null || true

do_reboot
