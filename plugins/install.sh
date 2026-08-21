#!/usr/bin/env bash
#
# plugins/install.sh — install curated plugins from your own
# itsdarklikehell/pwnagotchi-plugins collection onto the Pwnagotchi.
#
# Run on the Pi:  sudo bash plugins/install.sh
#
# By default it copies the WORKING plugins listed in TODO.md (the project's
# curated set). Override with PLUGIN_LIST="a.py b.py" or ALL=1 to copy everything.
set -euo pipefail

REPO="https://github.com/itsdarklikehell/pwnagotchi-plugins.git"
SRC="/opt/pwnagotchi4b/upstream/pwnagotchi-plugins"
DST="/usr/local/share/pwnagotchi/available-plugins"

# Curated "known working" set (subset of plugins/TODO.md "WORKING" list).
DEFAULT_PLUGINS=(
  memtemp.py
  display_settings.py
  IPDisplay.py
  webcfg.py
  auto_update.py
  bt-tether.py
  gps.py
  pwnmothership.py
  fancyserver.py
  fancygotchi.py
)

echo "==> installing plugins from $REPO"
apt-get update -y
apt-get install -y git
rm -rf "$SRC"
git clone --depth 1 "$REPO" "$SRC"

install -d "$DST"

if [ "${ALL:-0}" = "1" ]; then
  echo "==> copying ALL *.py plugins"
  cp "$SRC"/*.py "$DST/" 2>/dev/null || true
  # also copy any subdir plugins (e.g. defaults/)
  find "$SRC" -name '*.py' -exec cp {} "$DST/" \; 2>/dev/null || true
else
  LIST=("${PLUGIN_LIST[@]:-${DEFAULT_PLUGINS[@]}}")
  for p in "${LIST[@]}"; do
    if [ -f "$SRC/$p" ]; then
      cp "$SRC/$p" "$DST/"
      echo "    + $p"
    else
      echo "    ! not found: $p (skipped)"
    fi
  done
fi

echo "==> plugins installed to $DST"
echo "    Enable them in /etc/pwnagotchi/config.toml (see config/config.toml)."
