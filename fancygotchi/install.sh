#!/usr/bin/env bash
#
# fancygotchi/install.sh — install Fancygotchi 2.0 on the Pwnagotchi (RPi4B).
# Pulls V0r-T3x/Fancygotchi and installs the plugin + default theme bootstrap.
#
# Run on the Pi:  sudo bash fancygotchi/install.sh
set -euo pipefail

REPO="https://github.com/V0r-T3x/Fancygotchi.git"
PLUGIN_SRC="/opt/pwnagotchi4b/upstream/Fancygotchi"
PLUGIN_DST="/usr/local/share/pwnagotchi/available-plugins"
THEME_DST="/etc/pwnagotchi/fancygotchi/themes"

echo "==> installing Fancygotchi"
apt-get update -y
apt-get install -y git python3-pip

echo "==> fetching $REPO"
rm -rf "$PLUGIN_SRC"
git clone --depth 1 "$REPO" "$PLUGIN_SRC"

install -d "$PLUGIN_DST"
cp "$PLUGIN_SRC/Fancygotchi.py" "$PLUGIN_DST/"
cp "$PLUGIN_SRC/fancyshow.py"  "$PLUGIN_DST/" 2>/dev/null || true
# Companion plugins from your collection (if present in the clone)
for p in fancyserver fancytools; do
  [ -f "$PLUGIN_SRC/$p.py" ] && cp "$PLUGIN_SRC/$p.py" "$PLUGIN_DST/" || true
done

# Default theme bootstrap: Fancygotchi generates its config on first run, but we
# seed a minimal default so the first boot is clean.
install -d "$THEME_DST"
echo "==> Fancygotchi plugin installed. Enable via config.toml:"
echo "    main.plugins.Fancygotchi.enabled = true"
echo "    (theme = 'default' will be created on first launch)"

# Ensure fancyserver is available for the A2A bridge control path.
if [ -f "$PLUGIN_SRC/fancyserver.py" ]; then
  cp "$PLUGIN_SRC/fancyserver.py" "$PLUGIN_DST/"
  echo "==> fancyserver plugin present (used by mothership A2A bridge)."
fi
