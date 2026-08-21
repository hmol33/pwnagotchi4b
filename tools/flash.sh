#!/usr/bin/env bash
#
# tools/flash.sh — one-shot: download (if needed) + flash + provision the SD card.
# Wraps build/download-image.sh, build/flash-image.sh and tools/provision.sh.
# INTERACTIVE & DESTRUCTIVE. Run on your laptop with the target SD inserted.
#
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==== pwnagotchi4b: download -> flash -> provision ===="
bash build/download-image.sh
sudo bash build/flash-image.sh

echo
echo "==== done. The SD card is flashed and provisioned. ===="
echo "Insert into the RPi4B and power on. Then on the Pi run:"
echo "    sudo bash /boot/pwnagotchi4b/display/install.sh"
echo "    sudo bash /boot/pwnagotchi4b/fancygotchi/install.sh"
echo "    sudo bash /boot/pwnagotchi4b/plugins/install.sh"
echo "    sudo bash /boot/pwnagotchi4b/mothership/install.sh"
echo "(provision.sh already copied this repo into /boot/pwnagotchi4b/ for you.)"
