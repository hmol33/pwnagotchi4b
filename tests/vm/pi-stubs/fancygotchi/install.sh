#!/usr/bin/env bash
# pi-stubs/fancygotchi/install.sh
set -euo pipefail
echo "==> [stub] fancygotchi installer"
PLUGIN_DIR="/usr/local/share/pwnagotchi/available-plugins"
mkdir -p "$PLUGIN_DIR"
# Real installer fetches V0r-T3x/Fancygotchi; stub plants the plugin file the
# watchdog's check_fancygotchi() looks for.
cat > "$PLUGIN_DIR/Fancygotchi.py" <<'PY'
# stub marker for VM health check
PY
echo "==> [stub] Fancygotchi.py planted at $PLUGIN_DIR"
