#!/usr/bin/env bash
#
# tests/vm/run.sh — host orchestrator for the pwnagotchi4b VM integration test.
#
# Approach (robust, no cloud-init / no SSH password dance):
#   - boot a real x86_64 Debian VM under QEMU/KVM
#   - the Debian nocloud image allows `root` login on the SERIAL console with no
#     password, so we drive it entirely over a telnet-serial link
#   - the host serves the (stubbed) test repo via a tiny HTTP server; the guest
#     fetches it over QEMU's user-mode network gateway (10.0.2.2)
#   - serial_driver.py logs in, provisions, reboots (so firstboot + watchdog
#     fire), then runs verify-guest.sh and reports PASS/FAIL
#
# Requires: qemu-system-x86_64 (Homebrew: brew install qemu) and /dev/kvm.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$HERE/.work"
mkdir -p "$WORK"

IMAGE="$WORK/debian.qcow2"
A2A_PORT=8700

# --- 1. qemu -----------------------------------------------------------------
QEMU="$(command -v qemu-system-x86_64 2>/dev/null || true)"
if [ -z "$QEMU" ]; then
  BREW_QEMU="$(brew --prefix 2>/dev/null)/bin/qemu-system-x86_64"
  [ -x "$BREW_QEMU" ] && QEMU="$BREW_QEMU"
fi
if [ -z "$QEMU" ]; then
  echo "FAIL: qemu-system-x86_64 not found. Install: brew install qemu" >&2; exit 1
fi
echo "[ok] using $QEMU"

# --- 2. cloud image (download once) ------------------------------------------
if [ ! -f "$IMAGE" ]; then
  echo "==> downloading Debian 12 cloud image (one-time) ..."
  curl -fL --retry 3 -o "$WORK/debian.raw.qcow2" \
    https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-nocloud-amd64.qcow2
  qemu-img convert -f qcow2 -O qcow2 "$WORK/debian.raw.qcow2" "$IMAGE"
  qemu-img resize "$IMAGE" 12G
  rm -f "$WORK/debian.raw.qcow2"
fi
echo "[ok] image ready: $IMAGE"

# Boot from a throwaway overlay so each run starts from the pristine base image
# (otherwise unit/enabled-state changes persist on the base qcow2 across runs).
RUN_IMAGE="$WORK/run.qcow2"
qemu-img create -f qcow2 -b "$IMAGE" -F qcow2 "$RUN_IMAGE" >/dev/null
trap 'rm -f "$RUN_IMAGE"; [ -f "$WORK/vm.pid" ] && kill "$(cat "$WORK/vm.pid")" 2>/dev/null || true' EXIT

# --- 3. build stubbed test repo (tarball) ------------------------------------
bash "$HERE/prepare-testrepo.sh"
tar czf "$WORK/pwnagotchi4b-vmtest.tar.gz" -C /tmp pwnagotchi4b-vmtest
echo "[ok] tarball: $WORK/pwnagotchi4b-vmtest.tar.gz"

# --- 4. launch VM with telnet serial -----------------------------------------
echo "==> launching VM (serial on 127.0.0.1:2323) ..."
"$QEMU" -machine q35 -cpu max -smp 2 -m 2048 \
  -enable-kvm -display none \
  -drive file="$RUN_IMAGE",format=qcow2,if=virtio \
  -netdev user,id=n0,hostfwd=tcp::"$A2A_PORT"-:8700 \
  -device virtio-net-pci,netdev=n0 \
  -serial telnet:127.0.0.1:2323,server,nowait \
  -daemonize -pidfile "$WORK/vm.pid"

cleanup() { [ -f "$WORK/vm.pid" ] && kill "$(cat "$WORK/vm.pid")" 2>/dev/null || true; }
trap cleanup EXIT

echo "==> driving guest over serial console (root, no password) ..."
REPO_TARBALL="$WORK/pwnagotchi4b-vmtest.tar.gz" python3 "$HERE/serial_driver.py"
RC=$?

echo
if [ "$RC" -eq 0 ]; then echo "VM INTEGRATION TEST PASSED"; else echo "VM INTEGRATION TEST FAILED"; fi
exit $RC
