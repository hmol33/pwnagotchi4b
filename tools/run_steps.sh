#!/usr/bin/env bash
#
# tools/run_steps.sh — shared step-runner for pwnagotchi4b setup.
#
# Runs the four component installers in dependency order:
#   1. display/install.sh     (custom waveshare35b class + fbcp|fbtft backend)
#   2. fancygotchi/install.sh (Fancygotchi 2.0 + theme bootstrap)
#   3. plugins/install.sh     (your itsdarklikehell/pwnagotchi-plugins)
#   4. mothership/install.sh  (A2A bridge systemd service on :8700)
#
# Used by tools/firstboot.sh (first boot) and tools/watchdog.sh (recovery).
# Each installer is guarded internally (idempotent), so re-running is safe.
#
# Usage (sourced by the callers, NOT executed directly):
#   source "$(dirname "$0")/run_steps.sh"
#   run_steps            # runs all; returns 0 if all ok, 1 if any failed
#   run_steps display    # runs only the named step(s)
#
set -uo pipefail

# Canonical dry-run flag: honor either DRYRUN (callers) or PWNAGOTCHI4B_DRYRUN (legacy).
PWNAGOTCHI4B_DRYRUN="${DRYRUN:-${PWNAGOTCHI4B_DRYRUN:-0}}"

# The four installers, in dependency order. label:relative/path
PWNAGOTCHI4B_STEPS=(
  "display:display/install.sh"
  "fancygotchi:fancygotchi/install.sh"
  "plugins:plugins/install.sh"
  "mothership:mothership/install.sh"
)

log() { echo "[$(date '+%F %T')] $*" | tee -a "${PWNAGOTCHI4B_LOG:-/var/log/pwnagotchi4b/firstboot.log}"; }

# run_steps [label ...] — run all steps, or only the named labels if given.
run_steps() {
  local wanted=("$@")
  local failed=0
  local repo_dir="${PWNAGOTCHI4B_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
  for step in "${PWNAGOTCHI4B_STEPS[@]}"; do
    local label="${step%%:*}"
    local rel="${step#*:}"
    if [ "${#wanted[@]}" -gt 0 ] && [[ ! " ${wanted[*]} " =~ ${label} ]]; then
      continue
    fi
    local script="$repo_dir/$rel"
    log "--- step: $label ($script) ---"
    if [ ! -f "$script" ]; then
      log "!! MISSING: $script — skipping $label"
      failed=1
      continue
    fi
    if [ "${PWNAGOTCHI4B_DRYRUN:-0}" = "1" ]; then
      log "[dry-run] would run: bash $script"
    else
      if bash "$script" >>"${PWNAGOTCHI4B_LOG:-/var/log/pwnagotchi4b/firstboot.log}" 2>&1; then
        log "[ok] $label finished"
      else
        log "!! $label returned non-zero (continuing)"
        failed=1
      fi
    fi
  done
  return $failed
}
