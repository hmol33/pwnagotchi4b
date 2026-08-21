#!/usr/bin/env bash
#
# tests/test_firstboot.sh — dry-run verification of the headless first-boot
# orchestrator. Runs tools/firstboot.sh with DRYRUN=1 and asserts it locates
# and schedules all four component installers, then skips the reboot.
#
# No Pi, no network, no root required.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
FB="$REPO/tools/firstboot.sh"

[ -f "$FB" ] || { echo "FAIL: $FB not found"; exit 1; }
command -v bash >/dev/null || { echo "FAIL: bash missing"; exit 1; }

LOG="$(mktemp)"
FLAG="$(mktemp -d)/.firstboot_done"
export DRYRUN=1
export PWNAGOTCHI4B_DIR="$REPO"
export DONE_FLAG="$FLAG"
export FIRSTBOOT_LOG="$LOG"

if bash "$FB" >/dev/null 2>>"$LOG"; then
  echo "[ok] firstboot.sh dry-run executed"
else
  echo "[FAIL] firstboot.sh exited non-zero"; cat "$LOG"; exit 1
fi

# Each of the four installers must have been located + scheduled.
for s in display fancygotchi plugins mothership; do
  if grep -q "step: $s " "$LOG" && grep -q "would run: bash $REPO/$s" "$LOG"; then
    echo "[ok] step '$s' located + scheduled"
  else
    echo "[FAIL] step '$s' not scheduled"; sed 's/^/    /' "$LOG"; exit 1
  fi
done

# Dry-run must NOT touch the sentinel and must skip the reboot.
if [ -f "$FLAG" ]; then
  echo "[FAIL] dry-run created sentinel flag"; exit 1
fi
if grep -q "NOT rebooting" "$LOG"; then
  echo "[ok] dry-run skipped reboot"
else
  echo "[FAIL] reboot not skipped in dry-run"; exit 1
fi

rm -rf "$LOG" "$(dirname "$FLAG")"
echo
echo "FIRSTBOOT DRY-RUN TEST PASSED"
