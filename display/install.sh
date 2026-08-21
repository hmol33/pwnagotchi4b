#!/usr/bin/env bash
#
# display/install.sh — set up the Waveshare 3.5" (B) / ILI9486 display on a
# running Raspberry Pi 4B (or inside the flashed image's chroot during provision).
#
# Strategy (auto-detected):
#   1. fbcp-ili9341  (RECOMMENDED, fast DMA SPI) — built from source if needed.
#      Caveat: uses DispmanX; requires the LEGACY GL driver (not KMS). On pure
#      KMS kernels it will not work -> we fall back to fbtft.
#   2. fbtft         (FALLBACK, robust) — kernel framebuffer via dtoverlay.
#
# This script is idempotent and safe to re-run. It does NOT flash anything.
#
set -euo pipefail

PI_USER="${PI_USER:-pi}"
FB_REPO="https://github.com/juj/fbcp-ili9341.git"
DISPLAY_DIR="/opt/pwnagotchi4b/display"
HW_DIR="$(python3 - <<'PY' 2>/dev/null || echo /usr/local/lib/python3.11/dist-packages/pwnagotchi/ui/hw)
import pwnagotchi.ui.hw as hw, os
print(os.path.dirname(hw.__file__))
PY
)"
PIN_RST_GPIO=25   # GPIO25 (physical 22) — verify against your clone's schematic
PIN_DC_GPIO=24    # GPIO24 (physical 18)
PIN_BL_GPIO=18    # backlight (physical 12) — set high to enable

echo "==> pwnagotchi4b display installer"
echo "    HW dir : $HW_DIR"
echo "    RST/DC : GPIO$PIN_RST_GPIO / GPIO$PIN_DC_GPIO"

have_fbcp() { command -v fbcp-ili9341 >/dev/null 2>&1 || [ -x /usr/local/bin/fbcp-ili9341 ]; }

# --- 1. install the custom display class -------------------------------------
install_class() {
  echo "==> installing display/waveshare35b.py -> $HW_DIR"
  install -d "$HW_DIR"
  cp "$(dirname "$0")/waveshare35b.py" "$HW_DIR/waveshare35b.py"

  echo "==> registering 'waveshare35b' type in $HW_DIR/__init__.py"
  if ! grep -q "waveshare35b" "$HW_DIR/__init__.py"; then
    # Insert right before the function's final return / end. We add an elif branch.
    python3 - <<PY
import io, re, sys
p = "$HW_DIR/__init__.py"
s = open(p).read()
branch = '''    elif config['ui']['display']['type'] == 'waveshare35b':
        from pwnagotchi.ui.hw.waveshare35b import Waveshare35b
        return Waveshare35b(config)
'''
if 'waveshare35b' not in s:
    # place after the first 'def display_for' block's opening
    s = s.replace("def display_for(config):",
                  "def display_for(config):\n" + branch, 1)
    open(p,'w').write(s)
    print("    registered.")
else:
    print("    already registered.")
PY
  else
    echo "    already registered."
  fi
}

# --- 2. detect driver backend ------------------------------------------------
detect_backend() {
  # Prefer fbcp if legacy GL driver is active (DispmanX present).
  if grep -q "dtoverlay=vc4-kms-v3d" /boot/config.txt 2>/dev/null; then
    echo "fbtft"
  else
    echo "fbcp"
  fi
}

# --- 3. fbcp-ili9341 ---------------------------------------------------------
setup_fbcp() {
  if have_fbcp; then echo "==> fbcp-ili9341 already built"; return 0; fi
  echo "==> building fbcp-ili9341 (ILI9486 target) — this takes a few minutes"
  apt-get update -y
  apt-get install -y git cmake build-essential
  rm -rf /tmp/fbcp-ili9341
  git clone "$FB_REPO" /tmp/fbcp-ili9341
  mkdir -p /tmp/fbcp-ili9341/build && cd /tmp/fbcp-ili9341/build
  cmake -DILI9486=ON -DGPIO_TFT_DATA_CONTROL=24 -DGPIO_TFT_RESET_PIN=25 \
        -DSPI_BUS_CLOCK_DIVISOR=6 -DSTATISTICS=0 ..
  make -j"$(nproc)"
  install -m 0755 fbcp-ili9341 /usr/local/bin/fbcp-ili9341
  echo "==> fbcp-ili9341 installed"
}

enable_fbcp_service() {
  cat >/etc/systemd/system/fbcp-ili9341.service <<'UNIT'
[Unit]
Description=fbcp-ili9341 ILI9486 SPI display bridge
After=network.target

[Service]
ExecStart=/usr/local/bin/fbcp-ili9341
Restart=always
User=root

[Install]
WantedBy=multi-user.target
UNIT
  systemctl daemon-reload
  systemctl enable --now fbcp-ili9341.service
}

# --- 4. fbtft fallback -------------------------------------------------------
setup_fbtft() {
  echo "==> configuring fbtft overlay for Waveshare 3.5B (ILI9486)"
  # Disable the KMS 3D overlay if present (fbtft needs the legacy framebuffer)
  sed -i '/dtoverlay=vc4-kms-v3d/d' /boot/config.txt 2>/dev/null || true
  if ! grep -q "dtoverlay=waveshare35b" /boot/config.txt 2>/dev/null; then
    cat >>/boot/config.txt <<'CFG'

# pwnagotchi4b — Waveshare 3.5B (ILI9486) via fbtft
dtoverlay=waveshare35b
dtoverlay=ads7846,cs=1,penirq=17,penirq_pull=2,speed=1000000,keep_vref_on=0,swapxy=0,pmax=255,xohms=60,xmin=200,xmax=3900,ymin=200,ymax=3900
CFG
  fi
  # fbtft creates /dev/fb1 automatically on next boot.
}

# --- main --------------------------------------------------------------------
install_class
BACKEND="$(detect_backend)"
echo "==> selected backend: $BACKEND"
case "$BACKEND" in
  fbcp)
    setup_fbcp
    enable_fbcp_service
    ;;
  fbtft)
    setup_fbtft
    echo "    reboot required for fbtft /dev/fb1 to appear."
    ;;
esac

echo "==> done. Set ui.display.type = 'waveshare35b' in /etc/pwnagotchi/config.toml"
echo "==> reboot the Pi to activate the display."
