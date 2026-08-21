#!/usr/bin/env bash
# pi-stubs/plugins/install.sh
set -euo pipefail
echo "==> [stub] plugins installer (curated set)"
PLUGIN_DIR="/usr/local/share/pwnagotchi/available-plugins"
mkdir -p "$PLUGIN_DIR"
for p in memtemp display_settings fancyserver pwnmothership; do
  echo "# stub plugin $p" > "$PLUGIN_DIR/$p.py"
done
echo "==> [stub] curated plugins planted at $PLUGIN_DIR"
