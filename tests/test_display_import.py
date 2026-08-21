#!/usr/bin/env python3
"""
tests/test_display_import.py — verify the custom display class is importable and
structurally correct WITHOUT a Raspberry Pi (no pwnagotchi install required).

It mocks the minimal pwnagotchi.ui.hw.base.DisplayImpl so we can import
display/waveshare35b.py and assert it exposes the required interface
(layout/initialize/render/clear) and the correct type name.
"""
from __future__ import annotations
import importlib.util
import os
import sys
import types

HERE = os.path.dirname(os.path.abspath(__file__))
DISPLAY_FILE = os.path.join(HERE, "..", "display", "waveshare35b.py")


def _build_fake_pwnagotchi():
    """Create a fake 'pwnagotchi' package with the bits waveshare35b.py imports."""
    pkg = types.ModuleType("pwnagotchi")
    ui = types.ModuleType("pwnagotchi.ui")
    hw = types.ModuleType("pwnagotchi.ui.hw")
    base = types.ModuleType("pwnagotchi.ui.hw.base")
    fonts = types.ModuleType("pwnagotchi.ui.fonts")

    class DisplayImpl:
        name = None

        def __init__(self, config, name):
            self.config = config
            self.name = name
            self._layout = {}

        def layout(self):
            raise NotImplementedError

        def initialize(self):
            raise NotImplementedError

        def render(self, canvas):
            raise NotImplementedError

        def clear(self):
            raise NotImplementedError

    base.DisplayImpl = DisplayImpl
    fonts.setup = lambda *a, **k: None
    fonts.Medium = "medium"
    fonts.status_font = lambda f: f

    hw.base = base
    ui.hw = hw
    ui.fonts = fonts
    pkg.ui = ui
    sys.modules["pwnagotchi"] = pkg
    sys.modules["pwnagotchi.ui"] = ui
    sys.modules["pwnagotchi.ui.hw"] = hw
    sys.modules["pwnagotchi.ui.hw.base"] = base
    sys.modules["pwnagotchi.ui.fonts"] = fonts


def main() -> int:
    _build_fake_pwnagotchi()
    spec = importlib.util.spec_from_file_location("waveshare35b_test", DISPLAY_FILE)
    mod = importlib.util.module_from_spec(spec)
    try:
        spec.loader.exec_module(mod)
    except Exception as exc:  # noqa: BLE001
        print("IMPORT FAILED:", exc, file=sys.stderr)
        return 1

    assert hasattr(mod, "Waveshare35b"), "Waveshare35b class missing"
    cls = mod.Waveshare35b
    for meth in ("layout", "initialize", "render", "clear"):
        assert callable(getattr(cls, meth, None)), f"missing method {meth}"

    # Instantiate with a dummy config and call layout; check dimensions.
    inst = cls({"ui": {"display": {"type": "waveshare35b", "rotation": 0}}})
    lay = inst.layout()
    assert lay["width"] == 320 and lay["height"] == 480, lay
    assert inst.name == "waveshare35b", inst.name
    print("[ok] Waveshare35b imports, has all 4 methods, layout 320x480, name=waveshare35b")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
