#!/usr/bin/env bash
#
# tools/provision.sh — inject pwnagotchi4b config, plugins, display class and
# A2A bridge files into a flashed SD card's root filesystem (mounted), OR into a
# running Pi over SSH if given a host.
#
# Usage:
#   sudo bash tools/provision.sh [DEVICE_OR_MOUNT]      # e.g. /dev/sdb or /mnt/sd
#   bash tools/provision.sh pi@192.168.0.10             # SSH to a live Pi
#
# What it does:
#   - copies this whole repo to  /opt/pwnagotchi4b/   (so the Pi can finish setup)
#   - writes config/config.toml -> /etc/pwnagotchi/config.toml
#   - installs the headless FIRST-BOOT orchestrator (tools/firstboot.{sh,service})
#     so the Pi runs all four component installers on its first boot, then reboots.
# It does NOT start services or flash; the first boot on the Pi does the rest.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="${1:-}"

if [ -z "$TARGET" ]; then
  echo "Usage: sudo bash tools/provision.sh [DEVICE|MOUNT|user@host]" >&2
  exit 1
fi

# --- SSH mode ----------------------------------------------------------------
if [[ "$TARGET" == *@* ]]; then
  echo "==> provisioning live Pi at $TARGET over SSH"
  ssh "$TARGET" "sudo mkdir -p /opt/pwnagotchi4b /etc/pwnagotchi /var/lib/pwnagotchi4b"
  rsync -avz --exclude='.git' --exclude='build/downloads' "$REPO_ROOT/" "$TARGET:/opt/pwnagotchi4b/"
  ssh "$TARGET" "sudo cp /opt/pwnagotchi4b/config/config.toml /etc/pwnagotchi/config.toml"
  ssh "$TARGET" "sudo install -m 0644 /opt/pwnagotchi4b/tools/firstboot.service /etc/systemd/system/ && sudo install -d /var/lib/pwnagotchi4b && sudo systemctl daemon-reload && sudo systemctl enable pwnagotchi4b-firstboot.service"
  echo "==> done over SSH. The first boot will run all four installers automatically."
  exit 0
fi

# --- block device / mount mode ----------------------------------------------
if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: mount mode needs root (sudo bash $0 ...)" >&2; exit 1
fi

# If a raw device, mount the root partition.
MOUNTED=0
if [[ "$TARGET" == /dev/* ]]; then
  # Pick the rootfs partition (usually p2 for sdX, or mmcblk0p2)
  ROOT_PART="${TARGET}p2"; [ -b "$ROOT_PART" ] || ROOT_PART="${TARGET}2"
  BOOT_PART="${TARGET}p1"; [ -b "$BOOT_PART" ] || BOOT_PART="${TARGET}1"
  MNT="$(mktemp -d)"
  mkdir -p "$MNT"
  mount "$ROOT_PART" "$MNT"
  mount "$BOOT_PART" "$MNT/boot" 2>/dev/null || true
  MOUNTED=1
  ROOTFS="$MNT"
else
  ROOTFS="$TARGET"
fi

cleanup() { [ "$MOUNTED" = "1" ] && { umount "$ROOTFS/boot" 2>/dev/null; umount "$ROOTFS" 2>/dev/null; rmdir "$MNT" 2>/dev/null; }; }
trap cleanup EXIT

echo "==> provisioning rootfs at $ROOTFS"
mkdir -p "$ROOTFS/opt/pwnagotchi4b" "$ROOTFS/etc/pwnagotchi" "$ROOTFS/var/lib/pwnagotchi4b"
rsync -av --exclude='.git' --exclude='build/downloads' "$REPO_ROOT/" "$ROOTFS/opt/pwnagotchi4b/" >/dev/null
cp "$REPO_ROOT/config/config.toml" "$ROOTFS/etc/pwnagotchi/config.toml"
# Install the headless first-boot orchestrator as a systemd oneshot that fires
# on the Pi's first boot (ConditionPathExists=!/var/lib/pwnagotchi4b/.firstboot_done).
install -m 0644 "$REPO_ROOT/tools/firstboot.service" "$ROOTFS/etc/systemd/system/pwnagotchi4b-firstboot.service"
# Enable it (systemd symlink into multi-user.target.wants).
mkdir -p "$ROOTFS/etc/systemd/system/multi-user.target.wants"
ln -sf "../pwnagotchi4b-firstboot.service" "$ROOTFS/etc/systemd/system/multi-user.target.wants/pwnagotchi4b-firstboot.service"
echo "==> config.toml written to $ROOTFS/etc/pwnagotchi/config.toml"
echo "==> repo copied to $ROOTFS/opt/pwnagotchi4b/"
echo "==> first-boot service ENABLED (runs all four installers on first boot, then reboots)."
echo "    Unmount, insert into the Pi, and power on — setup is fully hands-off."
