#!/usr/bin/env bash
# pi-stubs/display/install.sh
# Stub of display/install.sh for VM testing. The real installer builds fbcp /
# fbtft and registers the custom pwnagotchi display class. In the VM we instead
# plant a FAKE pwnagotchi package with a `ui.hw` module and register the class,
# so the watchdog's real `import pwnagotchi.ui.hw` + "waveshare35b registered"
# health check passes without a Pi.
set -euo pipefail
echo "==> [stub] display installer: registering waveshare35b display class"
FAKE_PKG="$(python3 -c 'import site,os; print(os.path.join(site.getsitepackages()[0], "pwnagotchi"))' 2>/dev/null || echo /usr/local/lib/python3.11/dist-packages/pwnagotchi)"
mkdir -p "$FAKE_PKG/ui/hw"
cat > "$FAKE_PKG/__init__.py" <<'PY'
__version__ = "2.9.5.8"
PY
cat > "$FAKE_PKG/ui/__init__.py" <<'PY'
PY
cat > "$FAKE_PKG/ui/fonts.py" <<'PY'
def setup(*a, **k): pass
Medium = "medium"
def status_font(f): return f
PY
cat > "$FAKE_PKG/ui/hw/__init__.py" <<'PY'
__path__ = __import__('pkgutil').extend_path(__path__, __name__)
PY
# The custom class file (real one won't import without numpy/PIL; use a marker).
cat > "$FAKE_PKG/ui/hw/waveshare35b.py" <<'PY'
# stub marker for VM health check
PY
# Register the type so the watchdog's grep finds it (must be valid Python —
# a bare `waveshare35b` line would NameError on import; use a comment marker).
if ! grep -q "waveshare35b" "$FAKE_PKG/ui/hw/__init__.py"; then
  echo "# waveshare35b display class registered" >> "$FAKE_PKG/ui/hw/__init__.py"
fi
echo "==> [stub] display class registered at $FAKE_PKG/ui/hw/waveshare35b.py"
