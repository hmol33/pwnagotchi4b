#!/usr/bin/env bash
#
# tools/watchdog.sh — pwnagotchi4b self-healing watchdog.
#
# Runs on every boot (and on a timer via watchdog.timer) and checks whether the
# unit is in a "broken" state, e.g.:
#   - pwnagotchi config missing/unparseable
#   - custom display class (waveshare35b) not installed where pwnagotchi expects it
#   - Fancygotchi plugin missing
#   - A2A bridge service not active/enabled
#   - run_steps reported a failure (watchdog.fail present)
#
# If broken, it re-runs the four installers (or just the failing ones) to
# recover, then reboots if it changed anything. Bounded by an attempt counter so
# a persistently broken SD cannot reboot-loop forever.
#
# Safety:
#   - PWNAGOTCHI4B_WATCHDOG_MAX (default 3) caps how many times it will REBOOT
#     to recover. After that it gives up and just logs + leaves the box up.
#   - PWNAGOTCHI4B_WATCHDOG_NOREBOOT=1 makes it repair in place (no reboot).
#
# Env overrides:
#   DRYRUN=1   log the diagnosis + planned actions, but run nothing / no reboot.
#   (and the PWNAGOTCHI4B_DIR / *_LOG / *_DRYRUN vars honored by run_steps.sh)
#
set -uo pipefail

REPO_DIR="${PWNAGOTCHI4B_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
LOG="${PWNAGOTCHI4B_LOG:-/var/log/pwnagotchi4b/watchdog.log}"
ATTEMPTS_FLAG="${PWNAGOTCHI4B_WATCHDOG_ATTEMPTS:-/var/lib/pwnagotchi4b/.watchdog_attempts}"
FAILFLAG="${PWNAGOTCHI4B_WATCHDOG_FAIL:-/var/lib/pwnagotchi4b/watchdog.fail}"
MAX_ATTEMPTS="${PWNAGOTCHI4B_WATCHDOG_MAX:-3}"
NO_REBOOT="${PWNAGOTCHI4B_WATCHDOG_NOREBOOT:-0}"
DRYRUN="${DRYRUN:-0}"

mkdir -p "$(dirname "$LOG")" "$(dirname "$ATTEMPTS_FLAG")"
source "$REPO_DIR/tools/run_steps.sh"

log() { echo "[$(date '+%F %T')] $*" | tee -a "$LOG"; }

# Reboot wrapper: honors DRYRUN / NO_REBOOT so the script is testable without a
# real reboot. The systemd unit performs the actual reboot in production.
do_reboot() {
  if [ "$DRYRUN" = "1" ] || [ "$NO_REBOOT" = "1" ]; then
    # Exact wording is asserted by tests/test_watchdog.sh (scenario 3).
    log "=== recovery applied (NO_REBOOT=1): would reboot now ($*); skipped. ==="
    return 0
  fi
  log "=== rebooting to apply: $* ==="
  reboot
}

# --- broken-state predicates -------------------------------------------------
# Each returns 0 if OK, 1 if broken. Kept simple + dependency-free.
# Paths are overridable via env so the watchdog is testable and relocatable.
CFG_FILE="${PWNAGOTCHI4B_CFG:-/etc/pwnagotchi/config.toml}"
HW_DIR="${PWNAGOTCHI4B_HW_DIR:-}"
if [ -z "$HW_DIR" ]; then
  HW_DIR="$(python3 -c 'import pwnagotchi.ui.hw as hw, os; print(os.path.dirname(hw.__file__))' 2>/dev/null || echo /usr/local/lib/python3.11/dist-packages/pwnagotchi/ui/hw)"
fi
PLUGIN_DIR="${PWNAGOTCHI4B_PLUGIN_DIR:-/usr/local/share/pwnagotchi/available-plugins}"
# The A2A service is only a health target if it was requested at build time.
# Env: PWNAGOTCHI4B_CHECK_A2A=1 to enforce it (default: off, since the bridge
# can be legitimately disabled on a given unit).
CHECK_A2A="${PWNAGOTCHI4B_CHECK_A2A:-0}"

check_config() {
  [ -f "$CFG_FILE" ] || return 1
  grep -q '^main.name' "$CFG_FILE" 2>/dev/null || return 1
  return 0
}
check_display_class() {
  # The custom class must exist under pwnagotchi's hw dir and be registered.
  if [ -f "$HW_DIR/waveshare35b.py" ] && grep -q "waveshare35b" "$HW_DIR/__init__.py" 2>/dev/null; then
    return 0
  fi
  return 1
}
check_fancygotchi() {
  [ -f "$PLUGIN_DIR/Fancygotchi.py" ] || return 1
  return 0
}
check_a2a_service() {
  # Only meaningful if the bridge was ever requested. We check enablement, not
  # liveness (the unit may legitimately be down if the token is wrong).
  systemctl list-unit-files pwnagotchi-a2a.service 2>/dev/null | grep -q "enabled" || return 1
  return 0
}
check_prior_failure() {
  [ -f /var/lib/pwnagotchi4b/watchdog.fail ] && return 0
  return 1
}

# --- main --------------------------------------------------------------------
log "=== pwnagotchi4b watchdog run (repo=$REPO_DIR) ==="

BROKEN=0
FAILED_STEPS=()
for pred in config:config display_class:display fancygotchi:fancygotchi; do
  name="${pred%%:*}"; step="${pred#*:}"
  if check_"$name"; then
    log "[ok] health: $name"
  else
    log "[BROKEN] health: $name"
    BROKEN=1
    FAILED_STEPS+=("$step")
  fi
done
# The A2A bridge is only a health target if explicitly requested at build time.
if [ "${CHECK_A2A:-0}" = "1" ]; then
  if check_a2a_service; then
    log "[ok] health: a2a_service"
  else
    log "[BROKEN] health: a2a_service"
    BROKEN=1
    FAILED_STEPS+=("mothership")
  fi
fi
if check_prior_failure; then
  log "[BROKEN] prior run_steps failure recorded"
  BROKEN=1
fi

if [ "$BROKEN" -eq 0 ]; then
  log "=== watchdog: healthy, nothing to do."
  rm -f /var/lib/pwnagotchi4b/watchdog.fail
  exit 0
fi

# Broken. Decide whether to attempt recovery (bounded by attempt counter).
if [ "$DRYRUN" != "1" ]; then
  attempts=0
  [ -f "$ATTEMPTS_FLAG" ] && attempts="$(cat "$ATTEMPTS_FLAG" 2>/dev/null || echo 0)"
  attempts="$((attempts + 1))"
  echo "$attempts" > "$ATTEMPTS_FLAG"
else
  attempts=1
fi

if [ "$attempts" -gt "$MAX_ATTEMPTS" ]; then
  log "!! watchdog attempts ($attempts) exceed MAX ($MAX_ATTEMPTS); giving up to avoid reboot loop."
  log "   Manual recovery: review $LOG and re-run /opt/pwnagotchi4b/tools/firstboot.sh"
  exit 2
fi

log "=== attempting recovery (attempt $attempts/$MAX_ATTEMPTS) ==="

# Run either the specific failing steps (if we could localize them) or everything.
if [ "${#FAILED_STEPS[@]}" -gt 0 ]; then
  run_steps "${FAILED_STEPS[@]}" && rc=0 || rc=1
else
  run_steps && rc=0 || rc=1
fi

if [ "$rc" -ne 0 ]; then
  log "!! recovery run had failures; recording for next boot (no reboot while broken)"
  mkdir -p "$(dirname "$FAILFLAG")"
  touch "$FAILFLAG"
  # Do NOT reboot a still-broken box. Leave it up so it can be inspected, and
  # let the next boot or the hourly timer retry (bounded by the attempt counter).
  exit 1
fi

# Recovery succeeded — clear any prior failure marker and (optionally) reboot so
# the freshly installed components take effect.
rm -f "$FAILFLAG"

do_reboot "recovery succeeded"