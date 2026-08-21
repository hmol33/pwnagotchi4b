#!/usr/bin/env bash
# tests/vm/prepare-testrepo.sh
# Build a test copy of the repo where the four Pi installers are replaced by
# no-op stubs, so tools/firstboot.sh + tools/watchdog.sh run their REAL
# orchestration logic in a VM without needing a Raspberry Pi or Pi-specific
# hardware. The stubs still write the artifacts the health checks look for, so
# the watchdog sees a "healthy" installed system after first boot.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
OUT="/tmp/pwnagotchi4b-vmtest"
STUBS="$HERE/pi-stubs"

rm -rf "$OUT"
cp -r "$REPO" "$OUT"
rm -rf "$OUT/.git" "$OUT/__pycache__" "$OUT/tests/vm/.work" "$OUT/pwnagotchi4b-vmtest.tar.gz"
# Copy the VM test scripts + stubs + cloud-init into the test repo copy so the
# guest can run them (provision-guest.sh / verify-guest.sh must be present).
mkdir -p "$OUT/tests/vm"
cp "$HERE"/*.sh "$OUT/tests/vm/" 2>/dev/null || true
cp -r "$HERE/pi-stubs" "$OUT/tests/vm/pi-stubs"
cp -r "$HERE/cloud-init" "$OUT/tests/vm/cloud-init" 2>/dev/null || true

# Replace the four real Pi installers with the matching stubs (same names).
for comp in display fancygotchi plugins mothership; do
  cp "$STUBS/$comp/install.sh" "$OUT/$comp/install.sh"
done

# The watchdog/firstboot source tools/run_steps.sh — keep the real one.
echo "[ok] test repo prepared at $OUT (Pi installers -> stubs)"
