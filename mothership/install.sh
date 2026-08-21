#!/usr/bin/env bash
#
# mothership/install.sh — install the Pwnagotchi A2A bridge as a systemd service
# on the Pi (or any host where pwnagotchi_a2a.py runs). Designed with Wheatley;
# see mothership/AGENT_SPEC.md.
#
# Run on the Pi:  sudo bash mothership/install.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SVC=/etc/systemd/system/pwnagotchi-a2a.service

# Install a copy so updates don't depend on the repo staying mounted.
INSTALL_DIR=/opt/pwnagotchi4b/mothership
install -d "$INSTALL_DIR"
cp "$HERE/pwnagotchi_a2a.py" "$INSTALL_DIR/"
cp "$HERE/config.json" "$INSTALL_DIR/"
[ -f "$HERE/AGENT_SPEC.md" ] && cp "$HERE/AGENT_SPEC.md" "$INSTALL_DIR/"

# Token: read from env or leave placeholder (skeleton runs permissive if empty).
TOKEN="${PWNAGOTCHI_A2A_TOKEN:-REPLACE_WITH_SHARED_SECRET}"
sed -i "s/\"a2a_token\": *\"[^\"]*\"/\"a2a_token\": \"$TOKEN\"/" "$INSTALL_DIR/config.json"

cat >"$SVC" <<UNIT
[Unit]
Description=Pwnagotchi A2A Mothership Bridge (port 8700)
After=network.target pwnagotchi.service

[Service]
Type=simple
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/bin/python3 $INSTALL_DIR/pwnagotchi_a2a.py
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now pwnagotchi-a2a.service
echo "==> pwnagotchi-a2a.service installed and started."
echo "    Health:  curl -s $INSTALL_DIR/config.json >/dev/null; curl http://localhost:8700/healthz"
echo "    Card:    curl http://localhost:8700/.well-known/agent-card.json"
