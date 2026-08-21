#!/usr/bin/env bash
#
# tests/test_watchdog.sh — REAL verification of the self-healing watchdog.
#
# Exercises four paths WITHOUT a Pi and WITHOUT rebooting:
#   1. HEALTHY      -> exit 0, runs no installer, logs "healthy".
#   2. BROKEN+RECOVER_FAILS -> attempts recovery, increments attempt counter,
#                     records fail flag, exits 1, does NOT reboot (broken box
#                     must not reboot-loop).
#   3. BROKEN+RECOVER_OK    -> recovery succeeds, decides to reboot (NO_REBOOT=1
#                     holds it so the test doesn't actually reboot).
#   4. CAPPED       -> after MAX+1 simulated attempts, gives up (exit 2), no reboot.
#
# Health paths are env-overridable (PWNAGOTCHI4B_CFG / _HW_DIR / _PLUGIN_DIR)
# so we can drive a deterministic broken/healthy state on this laptop. For the
# recovery-OK scenario we point run_steps at a fake repo whose installers are
# no-op scripts that succeed.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
WD="$REPO/tools/watchdog.sh"

[ -f "$WD" ] || { echo "FAIL: $WD not found"; exit 1; }

TMP="$(mktemp -d)"
LOG="$TMP/watchdog.log"
ATT="$TMP/.attempts"
FAILFLAG="$TMP/watchdog.fail"
mkdir -p "$TMP/lib" "$TMP/etc/pwnagotchi" "$TMP/share" "$TMP/fakerepo"

# A "good" hw dir + plugin dir, for the healthy scenario.
mkdir -p "$TMP/hwgood"; touch "$TMP/hwgood/waveshare35b.py"; echo "waveshare35b" > "$TMP/hwgood/__init__.py"
mkdir -p "$TMP/plugood"; touch "$TMP/plugood/Fancygotchi.py"

# A fake repo with four no-op installers that SUCCEED (for the recover-OK path).
for s in display fancygotchi plugins mothership; do
  mkdir -p "$TMP/fakerepo/$s"
  printf '#!/usr/bin/env bash\necho "[fake] %s ok"\n' "$s" > "$TMP/fakerepo/$s/install.sh"
  chmod +x "$TMP/fakerepo/$s/install.sh"
done
# The watchdog sources tools/run_steps.sh relative to PWNAGOTCHI4B_DIR.
mkdir -p "$TMP/fakerepo/tools"
cp "$REPO/tools/run_steps.sh" "$TMP/fakerepo/tools/run_steps.sh"

run_wd() {
  local scenario="$1"; shift
  local repo="$REPO"
  if [ "$scenario" = "healthy" ]; then
    echo "main.name = test" > "$TMP/etc/pwnagotchi/config.toml"
    CFG="$TMP/etc/pwnagotchi/config.toml"; HW="$TMP/hwgood"; PL="$TMP/plugood"
  elif [ "$scenario" = "broken_ok" ]; then
    rm -f "$TMP/etc/pwnagotchi/config.toml"
    CFG="/nonexistent/config.toml"; HW="/nonexistent/hw"; PL="/nonexistent/plugins"
    repo="$TMP/fakerepo"   # installers that succeed
  else   # broken_fail
    rm -f "$TMP/etc/pwnagotchi/config.toml"
    CFG="/nonexistent/config.toml"; HW="/nonexistent/hw"; PL="/nonexistent/plugins"
  fi
  PWNAGOTCHI4B_DIR="$repo" \
  PWNAGOTCHI4B_LOG="$LOG" \
  PWNAGOTCHI4B_WATCHDOG_ATTEMPTS="$ATT" \
  PWNAGOTCHI4B_WATCHDOG_FAIL="$FAILFLAG" \
  PWNAGOTCHI4B_WATCHDOG_NOREBOOT=1 \
  PWNAGOTCHI4B_WATCHDOG_MAX=3 \
  PWNAGOTCHI4B_CFG="$CFG" \
  PWNAGOTCHI4B_HW_DIR="$HW" \
  PWNAGOTCHI4B_PLUGIN_DIR="$PL" \
  bash "$WD" "$@"
}

echo "=== scenario 1: HEALTHY ==="
run_wd healthy && echo "[ok] healthy -> exit 0"
grep -q "healthy, nothing to do" "$LOG" || { echo "FAIL: healthy not detected"; cat "$LOG"; exit 1; }
echo "[ok] logged healthy, no recovery"

echo
echo "=== scenario 2: BROKEN + recovery FAILS -> no reboot, record fail ==="
: > "$LOG"; : > "$ATT"; rm -f "$FAILFLAG"
run_wd broken_fail || true
grep -q "\[BROKEN\] health: config" "$LOG" || { echo "FAIL: broken not detected"; cat "$LOG"; exit 1; }
grep -q "attempting recovery" "$LOG" || { echo "FAIL: no recovery attempt"; cat "$LOG"; exit 1; }
attempts="$(cat "$ATT")"
[ "$attempts" = "1" ] || { echo "FAIL: attempt counter not 1 (got $attempts)"; exit 1; }
[ -f "$FAILFLAG" ] || { echo "FAIL: fail flag not recorded"; exit 1; }
grep -q "recovery run had failures" "$LOG" || { echo "FAIL: no failure note"; cat "$LOG"; exit 1; }
grep -q "rebooting to apply" "$LOG" && { echo "FAIL: must NOT reboot a still-broken box"; cat "$LOG"; exit 1; }
echo "[ok] broken+fail -> recovery attempted, attempt#=1, fail flag set, NO reboot"

echo
echo "=== scenario 3: BROKEN + recovery OK -> recovery applied (NO_REBOOT holds reboot) ==="
: > "$LOG"; : > "$ATT"; rm -f "$FAILFLAG"
run_wd broken_ok || true
grep -q "recovery applied (NO_REBOOT=1)" "$LOG" || { echo "FAIL: successful recovery not applied"; cat "$LOG"; exit 1; }
grep -q "recovery run had failures" "$LOG" && { echo "FAIL: recovery should have succeeded"; cat "$LOG"; exit 1; }
echo "[ok] broken+ok -> recovery succeeded, reboot would fire (NO_REBOOT held it)"

echo
echo "=== scenario 4: CAPPED (simulate MAX+1 attempts) ==="
echo "3" > "$ATT"
: > "$LOG"
run_wd broken_fail && rc=0 || rc=$?
[ "$rc" = "2" ] || { echo "FAIL: expected exit 2 (give up), got $rc"; cat "$LOG"; exit 1; }
grep -q "exceed MAX" "$LOG" || { echo "FAIL: no give-up message"; cat "$LOG"; exit 1; }
echo "[ok] capped -> exit 2, gave up (no reboot loop)"

rm -rf "$TMP"
echo
echo "WATCHDOG TEST PASSED"
