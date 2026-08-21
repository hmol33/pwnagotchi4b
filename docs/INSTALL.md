# docs/INSTALL.md — full step-by-step for pwnagotchi4b

> Authorized / educational use only. Only capture handshakes on networks you own
> or have explicit permission to test.

## 0. Bill of materials
- Raspberry Pi 4B (2 GB+)
- Off-brand Waveshare 3.5" (B) / ILI9486 SPI screen
- ≥16 GB A1 microSD
- Power supply (3 A recommended)
- A laptop (Linux) to flash the SD

## 1. On the laptop — download + flash + provision
```bash
git clone https://github.com/itsdarklikehell/pwnagotchi4b.git
cd pwnagotchi4b

# fetch the official 64-bit image (jayofelony/pwnagotchi)
bash build/download-image.sh

# flash + provision (INTERACTIVE — it will ask you to confirm the SD device)
sudo bash tools/flash.sh
```
`tools/flash.sh` downloads (if needed), flashes the image, then copies this repo
into the SD's `/opt/pwnagotchi4b/` and writes `config/config.toml` to
`/etc/pwnagotchi/config.toml`.

## 2. First boot on the Pi
Insert the SD, power on. Let it boot ~2 minutes. SSH in (default user `pi`, or
use the bettercap/USB gadget path per jayofelony wiki).

Confirm the screen controller:
```bash
dmesg | grep -i ili
ls /sys/bus/spi/devices/
```

## 3. Install components (on the Pi)
```bash
sudo bash /opt/pwnagotchi4b/display/install.sh        # custom class + fbcp|fbtft
sudo bash /opt/pwnagotchi4b/fancygotchi/install.sh    # Fancygotchi 2.0
sudo bash /opt/pwnagotchi4b/plugins/install.sh         # your curated plugins
sudo bash /opt/pwnagotchi4b/mothership/install.sh      # A2A bridge (:8700)
sudo reboot
```
`display/install.sh` auto-detects the backend:
- **legacy GL driver** → builds & runs `fbcp-ili9341` (fast, recommended).
- **KMS kernel** (`dtoverlay=vc4-kms-v3d`) → uses `fbtft` overlay (robust).

## 4. Verify locally
```bash
curl -s http://localhost:8700/.well-known/agent-card.json | head
curl -s http://localhost:8700/healthz
sudo journalctl -u pwnagotchi -n 50 | grep -i waveshare35b
sudo systemctl status fbcp-ili9341   # if fbcp backend
```

## 5. Unify forces — GLaDOS + Wheatley ↔ Pwnagotchi
From a GLaDOS (Hermes) or Wheatley (OpenClaw) host on the same LAN:
```bash
# set the Pi's reachable URL + shared token
export PWNAGOTCHI_A2A_URL=http://<pi-ip>:8700
export PWNAGOTCHI_A2A_TOKEN=<shared_secret>

python3 clients/glados_client.py get_status
python3 clients/wheatley_client.py set_mode --mode manual
python3 clients/wheatley_client.py toggle_plugin --name fancygotchi --enabled true
```
The two cores can also call the Pi over their native A2A (Hermes `:9900`,
OpenClaw `:18800`) by adding the Pi's Agent Card URL as a peer — see
`mothership/AGENT_SPEC.md` §6. The Pi reuses your existing `pwnmothership`
(state) and `fancyserver` (`:3699` control socket) — A2A is just the remote
layer on top.

## 6. Troubleshooting
- **Blank screen:** check `dmesg | grep -i ili`; confirm `/dev/fb1` exists; verify
  `ui.display.type = "waveshare35b"` in config.toml; re-run `display/install.sh`.
- **fbcp fails to start on Pi 5 / KMS:** expected — `install.sh` should have
  chosen fbtft; if not, force it by adding `dtoverlay=waveshare35b` to
  `/boot/config.txt` and removing `vc4-kms-v3d`.
- **A2A 401:** set `PWNAGOTCHI_A2A_TOKEN` on both the Pi (`config.json` /
  `mothership/install.sh`) and the clients.
- **A2A unreachable:** ensure port 8700 is open on the Pi's firewall and the
  client uses the Pi's LAN IP (mDNS `.local` needs Avahi).

## 7. Update
```bash
cd pwnagotchi4b && git pull
sudo bash tools/provision.sh pi@<pi-ip>   # re-sync repo + config to the Pi
```
