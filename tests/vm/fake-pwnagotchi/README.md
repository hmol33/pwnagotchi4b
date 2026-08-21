# Fake `pwnagotchi` package for VM testing.
#
# The real pwnagotchi image ships the `pwnagotchi` Python package; our display
# installer and the watchdog's health check both resolve install paths via
# `python3 -c 'import pwnagotchi.ui.hw ...'`. A bare Debian VM has no such
# package, so the VM test plants this harmless fake into site-packages. It only
# needs to be importable and expose a `ui.hw` location the stub can write into.
