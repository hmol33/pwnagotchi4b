#!/usr/bin/env bash
# tests/vm/verify-guest.sh — run INSIDE the VM after the first reboot.
# Asserts the real first-boot orchestration + watchdog behaved correctly.
set -euo pipefail
RC=0
fail() { echo "[FAIL] $*"; RC=1; }
ok()   { echo "[ok] $*"; }

echo "=== VM verification ==="

# 1. first boot ran exactly once (sentinel present, service disabled).
if [ -f /var/lib/pwnagotchi4b/.firstboot_done ]; then
  ok "firstboot sentinel present (ran once)"
else
  fail "firstboot sentinel MISSING"
fi
if ! systemctl is-enabled pwnagotchi4b-firstboot.service 2>/dev/null | grep -q enabled; then
  ok "firstboot service self-disabled after running"
else
  fail "firstboot service still enabled"
fi

# 2. the four stubs produced healthy artifacts the watchdog checks.
if python3 -c 'import importlib, pwnagotchi.ui.hw as hw, os; p=os.path.dirname(hw.__file__); assert os.path.exists(p+"/waveshare35b.py"); assert "waveshare35b" in open(p+"/__init__.py").read(), "no marker in __init__"' 2>/tmp/disp_err; then
  ok "display class registered (waveshare35b present)"
else
  fail "display class NOT registered"; echo "    import error: $(cat /tmp/disp_err 2>/dev/null | tail -3 | tr '\n' ' ')"
fi
[ -f /usr/local/share/pwnagotchi/available-plugins/Fancygotchi.py ] && \
  ok "Fancygotchi plugin present" || fail "Fancygotchi plugin MISSING"

# 3. watchdog timer enabled.
systemctl is-enabled pwnagotchi4b-watchdog.timer 2>/dev/null | grep -q enabled && \
  ok "watchdog timer enabled" || fail "watchdog timer NOT enabled"

# 4. A2A bridge up + answering real JSON-RPC (a2a_sim.py on 0.0.0.0:8700).
curl -fsS http://127.0.0.1:8700/.well-known/agent-card.json >/dev/null 2>&1 && \
  ok "A2A agent card served" || fail "A2A agent card unreachable"
# /healthz is what tools/fleet_health.py (Cornelis's fleet poller) probes.
curl -fsS http://127.0.0.1:8700/healthz >/dev/null 2>&1 && \
  ok "A2A /healthz (fleet-poller endpoint) reachable" || fail "A2A /healthz unreachable"
# The stub can take a moment to bind; retry briefly.
RESP=""
for _ in 1 2 3 4 5; do
  RESP="$(curl -fsS -X POST http://127.0.0.1:8700/ -H 'Content-Type: application/json' \
    -d '{"jsonrpc":"2.0","id":1,"method":"get_status","params":{}}' 2>/dev/null)" && break
  sleep 1
done
if echo "$RESP" | grep -q '"artifact": "pwnagotchi-status-v1"'; then
  ok "A2A get_status returned expected artifact"
else
  fail "A2A get_status did not return expected artifact (got: ${RESP:0:120})"
fi
# Also exercise the real A2A route clients/glados_client.py &
# clients/wheatley_client.py POST to (/a2a/jsonrpc).
RESP2="$(curl -fsS -X POST http://127.0.0.1:8700/a2a/jsonrpc -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"get_status","params":{}}' 2>/dev/null)"
if echo "$RESP2" | grep -q '"artifact": "pwnagotchi-status-v1"'; then
  ok "A2A /a2a/jsonrpc (client route) answered get_status"
else
  fail "A2A /a2a/jsonrpc did not answer (got: ${RESP2:0:120})"
fi

# 5. watchdog reports healthy now (no broken state).
if bash /opt/pwnagotchi4b/tools/watchdog.sh 2>&1 | grep -q "healthy, nothing to do"; then
  ok "watchdog self-reports healthy"
else
  fail "watchdog did not report healthy"
fi

echo
if [ "$RC" -eq 0 ]; then echo "VM VERIFICATION PASSED"; else echo "VM VERIFICATION FAILED"; fi
exit $RC
