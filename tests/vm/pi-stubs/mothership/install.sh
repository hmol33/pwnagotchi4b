#!/usr/bin/env bash
# pi-stubs/mothership/install.sh
set -euo pipefail
echo "==> [stub] mothership (A2A bridge) installer"
# Real installer deploys pwnagotchi_a2a.py as a systemd service. In the VM we
# start it manually from provision-guest.sh (no need for a persistent service
# that would conflict with the test's on-demand start). Here we just mark it
# enabled so the watchdog's check_a2a_service() (when CHECK_A2A=1) is happy.
mkdir -p /etc/systemd/system
cat > /etc/systemd/system/pwnagotchi-a2a.service <<'UNIT'
[Unit]
Description=pwnagotchi A2A bridge (stub-enabled for VM test)

[Service]
Type=simple
ExecStart=/usr/bin/true
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload 2>/dev/null || true
systemctl enable pwnagotchi-a2a.service 2>/dev/null || true
echo "==> [stub] pwnagotchi-a2a.service enabled"
