#!/usr/bin/env bash
# tests/vm/make-seed.sh — build a cloud-init seed ISO for the VM.
# The volume label MUST be "cidata" — that is what cloud-init's NoCloud
# datasource looks for on a CD-ROM.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
CI="$HERE/cloud-init"
OUT="$HERE/seed.iso"
if command -v genisoimage >/dev/null; then
  genisoimage -output "$OUT" -volid cidata -joliet -rock "$CI/user-data" "$CI/meta-data"
elif command -v mkisofs >/dev/null; then
  mkisofs -output "$OUT" -volid cidata -joliet -rock "$CI/user-data" "$CI/meta-data"
elif command -v xorriso >/dev/null; then
  xorriso -as genisoimage -volid cidata -output "$OUT" -joliet -rock "$CI/user-data" "$CI/meta-data"
else
  echo "FAIL: need genisoimage/mkisofs/xorriso to build seed.iso" >&2; exit 1
fi
echo "[ok] seed.iso built at $OUT (volid=cidata)"
