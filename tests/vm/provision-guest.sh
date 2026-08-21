#!/usr/bin/env bash
# tests/vm/provision-guest.sh — run INSIDE the VM after first boot.
# Installs the test repo, enables the firstboot + watchdog units, and starts the
# A2A bridge manually (the stub doesn't persist it as a service in the VM).
set -euo pipefail

REPO="${1:-/opt/pwnagotchi4b}"
SITE_PKGS="$(python3 -c 'import site,os; print(os.path.join(site.getsitepackages()[0]))' 2>/dev/null || echo /usr/local/lib/python3.11/dist-packages)"

echo "==> [vm] provisioning pwnagotchi4b from $REPO"

# Ensure the orchestration scripts are executable (defensive; the repo tracks
# them as +x, but a stray umask on copy/extract can drop the bit).
chmod +x "$REPO"/tools/*.sh "$REPO"/tests/vm/*.sh 2>/dev/null || true

# 0. Write a minimal pwnagotchi config so the watchdog's config health check
#    sees a "healthy" installed system (on the Pi, provision.sh writes this).
mkdir -p /etc/pwnagotchi
cat > /etc/pwnagotchi/config.toml <<'EOF'
# minimal config written by the VM integration-test provisioner
ui.display.type = "waveshare35b"
ui.display.color = "black"
main.name = "pwnagotchi4b-vm"
main.lang = "en"
main.whitelist = []
main.plugins = {}
EOF

# 1. Plant a fake `pwnagotchi` package so the display installer + watchdog health
#    check resolve a ui.hw location, exactly like on the real Pi image.
echo "==> [vm] planting fake pwnagotchi package at $SITE_PKGS"
rm -rf "$SITE_PKGS/pwnagotchi"
cp -r "$REPO/tests/vm/fake-pwnagotchi/pwnagotchi" "$SITE_PKGS/pwnagotchi"

# 2. Enable the firstboot + watchdog units.
echo "==> [vm] enabling firstboot + watchdog units"
install -m 0644 "$REPO/tools/firstboot.service" /etc/systemd/system/pwnagotchi4b-firstboot.service
install -m 0644 "$REPO/tools/watchdog.service"   /etc/systemd/system/pwnagotchi4b-watchdog.service
install -m 0644 "$REPO/tools/watchdog.timer"     /etc/systemd/system/pwnagotchi4b-watchdog.timer
# Drop the network-online requirement for the VM test (the nocloud image's
# networkd-wait-online can stall). Production keeps it; the Pi installers need
# apt/network. In the VM the installers are stubs.
mkdir -p /etc/systemd/system/pwnagotchi4b-firstboot.service.d
cat > /etc/systemd/system/pwnagotchi4b-firstboot.service.d/vm-test.conf <<'EOF'
[Unit]
After=
After=local-fs.target
Wants=
EOF
systemctl daemon-reload
systemctl enable pwnagotchi4b-firstboot.service
systemctl enable pwnagotchi4b-watchdog.timer

# 3. Install + enable the A2A stub bridge as a service so it survives reboot
#    (a bare `&` background job dies when provision-guest's shell exits / reboots).
echo "==> [vm] enabling A2A bridge (stub) service"
install -m 0644 "$REPO/tools/a2a_sim.service" /etc/systemd/system/pwnagotchi4b-a2a-stub.service
systemctl daemon-reload
systemctl enable pwnagotchi4b-a2a-stub.service
systemctl start pwnagotchi4b-a2a-stub.service
echo "==> [vm] firstboot + watchdog enabled; A2A bridge service started"
