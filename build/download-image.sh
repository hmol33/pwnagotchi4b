#!/usr/bin/env bash
#
# build/download-image.sh — fetch the official jayofelony/pwnagotchi 64-bit
# image (the maintained fork; supports RPi4B). Saves into build/downloads/.
#
# Run on your laptop. No sudo needed. Network access required.
set -euo pipefail

OUT_DIR="$(cd "$(dirname "$0")" && pwd)/downloads"
mkdir -p "$OUT_DIR"

# Latest 64-bit release asset name pattern (jayofelony/pwnagotchi).
REPO="jayofelony/pwnagotchi"
ASSET="pwnagotchi-64bit-2.9.5.8.img.xz"   # pin; update if a newer release exists

echo "==> resolving latest release of $REPO"
LATEST=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
          | grep -oE '"tag_name": *"[^"]+"' | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
echo "    latest tag: ${LATEST:-unknown}"

URL="https://github.com/$REPO/releases/download/${LATEST:-v2.9.5.8}/$ASSET"
DEST="$OUT_DIR/$ASSET"

if [ -f "$DEST" ]; then
  echo "==> $ASSET already present, skipping download."
else
  echo "==> downloading $URL"
  curl -fL --retry 3 -o "$DEST" "$URL"
fi

echo "==> verifying checksum (if .info present)"
INFO_URL="https://github.com/$REPO/releases/download/${LATEST:-v2.9.5.8}/pwnagotchi-64bit-2.9.5.8.info"
curl -fsSL "$INFO_URL" -o "$OUT_DIR/pwnagotchi-64bit-2.9.5.8.info" || echo "    (no .info checksum file; skipping verify)"

echo "==> done: $DEST"
echo "    Next: sudo bash tools/flash.sh"
