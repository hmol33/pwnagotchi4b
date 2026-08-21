#!/usr/bin/env bash
#
# build/flash-image.sh — flash the downloaded image to an SD card.
# INTERACTIVE: lists block devices and asks you to confirm before writing.
# Destructive! Only run with the target SD card inserted.
#
# Usage: sudo bash build/flash-image.sh [/path/to/image.img.xz] [device]
set -euo pipefail

IMG="${1:-build/downloads/pwnagotchi-64bit-2.9.5.8.img.xz}"
DEVICE="${2:-}"

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: run as root (sudo bash $0)" >&2; exit 1
fi

# Decompress if needed.
if [[ "$IMG" == *.xz ]]; then
  if command -v xzcat >/dev/null; then
    STREAM="xzcat \"$IMG\""
  elif command -v unxz >/dev/null; then
    STREAM="unxz -c \"$IMG\""
  else
    echo "ERROR: need xz utils to decompress" >&2; exit 1
  fi
else
  STREAM="cat \"$IMG\""
fi

if [ -z "$DEVICE" ]; then
  echo "==> Available block devices (pick your SD card — must NOT be your boot disk!):"
  lsblk -d -o NAME,SIZE,MODEL,TYPE | grep -iE 'sd|mmcblk|disk' || true
  read -rp "Enter device (e.g. /dev/sdb or /dev/mmcblk0): " DEVICE
fi

echo
echo "!! WARNING: ALL DATA ON $DEVICE WILL BE DESTROYED."
read -rp "Type 'YES' to proceed: " CONFIRM
[ "$CONFIRM" = "YES" ] || { echo "aborted."; exit 1; }

echo "==> flashing $IMG -> $DEVICE (this takes a while)..."
eval "$STREAM" | dd of="$DEVICE" bs=4M conv=fsync status=progress
sync
echo "==> flash complete."
echo "    Next: sudo bash tools/provision.sh $DEVICE"
