"""
waveshare35b.py — custom Pwnagotchi display class for an off-brand
Waveshare 3.5" (B) / ILI9486 SPI screen (clone of the Waveshare 3.5B).

Why this exists
---------------
The current jayofelony/pwnagotchi image has NO `waveshare35b` display type.
Off-brand 3.5" ILI9486 panels are driven through a Linux framebuffer
(typically /dev/fb1) — either by the in-kernel fbtft overlay or by the
userspace fbcp-ili9341 bridge. This class renders Pwnagotchi's canvas into a
PIL Image and blits it to the framebuffer device. It subclasses pwnagotchi's
own DisplayImpl so Fancygotchi (which reads ui.display.type) works unchanged.

Placement on the Pi
-------------------
Copy this file to:  /usr/local/lib/python3.11/dist-packages/pwnagotchi/ui/hw/waveshare35b.py
Then register the type in /usr/local/lib/python3.11/dist-packages/pwnagotchi/ui/hw/__init__.py:
    elif config['ui']['display']['type'] == 'waveshare35b':
        from pwnagotchi.ui.hw.waveshare35b import Waveshare35b
        return Waveshare35b(config)
(See display/install.sh — it does this automatically.)

Set in config.toml:
    ui.display.type = "waveshare35b"
    ui.display.rotation = 0
"""

import logging
import os

import pwnagotchi.ui.fonts as fonts
from pwnagotchi.ui.hw.base import DisplayImpl

# numpy / PIL are imported lazily inside render() so this module imports cleanly
# even on hosts that don't have them (e.g. test harnesses, or pre-install steps).
np = None
Image = None

# Resolution of the ILI9486 3.5" panel (320x480). Pwnagotchi renders at the
# panel's native resolution; we keep a 1:1 blit so nothing is stretched.
SCREEN_W = 320
SCREEN_H = 480

# Framebuffer device created by fbcp-ili9341 (or the fbtft dtoverlay).
FB_DEVICE = os.environ.get("PWNAGOTCHI_FB", "/dev/fb1")


class Waveshare35b(DisplayImpl):
    def __init__(self, config):
        super(Waveshare35b, self).__init__(config, "waveshare35b")
        self._fb = None
        self._fb_file = None

    # --- layout -------------------------------------------------------------
    def layout(self):
        fonts.setup(10, 9, 10, 35, 25, 9)
        self._layout["width"] = SCREEN_W
        self._layout["height"] = SCREEN_H
        # Top area: face + name
        self._layout["face"] = (0, 40)
        self._layout["name"] = (5, 20)
        # Status row
        self._layout["channel"] = (0, 0)
        self._layout["aps"] = (28, 0)
        self._layout["uptime"] = (SCREEN_W - 65, 0)
        # Decoration lines
        self._layout["line1"] = [0, 14, SCREEN_W, 14]
        self._layout["line2"] = [0, SCREEN_H - 20, SCREEN_W, SCREEN_H - 20]
        # Friend / peer widgets
        self._layout["friend_face"] = (0, 92)
        self._layout["friend_name"] = (40, 94)
        # Bottom status line (handshakes / mode)
        self._layout["shakes"] = (0, SCREEN_H - 18)
        self._layout["mode"] = (SCREEN_W - 25, SCREEN_H - 18)
        self._layout["status"] = {
            "pos": (SCREEN_W // 2, 20),
            "font": fonts.status_font(fonts.Medium),
            "max": 26,
        }
        return self._layout

    # --- initialize ---------------------------------------------------------
    def initialize(self):
        logging.info("waveshare35b: initializing ILI9486 framebuffer display")
        if not os.path.exists(FB_DEVICE):
            raise RuntimeError(
                "waveshare35b: %s not found. Install fbcp-ili9341 or the fbtft "
                "overlay (see display/install.sh) so the panel exposes a "
                "framebuffer device." % FB_DEVICE
            )
        # Open the framebuffer for writing. The size is SCREEN_W*SCREEN_H*2 bytes
        # (RGB565). We open in 'r+b' so we can seek+write in place each frame.
        try:
            self._fb_file = open(FB_DEVICE, "r+b")
        except OSError as exc:
            raise RuntimeError("waveshare35b: cannot open %s: %s" % (FB_DEVICE, exc))
        self._fb = self._fb_file
        # Clear to black so we don't show garbage on first paint.
        self.clear()

    # --- render -------------------------------------------------------------
    def render(self, canvas):
        """Blit the Pwnagotchi canvas (PIL Image, RGB) to the framebuffer as RGB565."""
        if self._fb is None:
            logging.warning("waveshare35b: not initialized; skipping render")
            return

        global np, Image
        if np is None:
            try:
                import numpy as _np
                np = _np
            except Exception:
                np = False
        if Image is None:
            try:
                from PIL import Image as _Image
                Image = _Image
            except Exception:
                Image = False

        # Normalize to a PIL RGB image.
        if np and not isinstance(np, bool) and isinstance(canvas, np.ndarray):
            img = Image.fromarray(canvas.astype("uint8")).convert("RGB")
        else:
            img = canvas.convert("RGB")

        # Scale/crop to the panel while preserving aspect ratio (letterbox).
        w, h = img.size
        target_aspect = SCREEN_W / SCREEN_H
        src_aspect = w / h
        if src_aspect > target_aspect:
            new_h = SCREEN_H
            new_w = int(round(new_h * src_aspect))
        else:
            new_w = SCREEN_W
            new_h = int(round(new_w / src_aspect))
        resized = img.resize((new_w, new_h))
        left = (new_w - SCREEN_W) // 2
        top = (new_h - SCREEN_H) // 2
        cropped = resized.crop((left, top, left + SCREEN_W, top + SCREEN_H))

        # Convert RGB -> RGB565 packed little-endian.
        px = cropped.load()
        buf = bytearray(SCREEN_W * SCREEN_H * 2)
        idx = 0
        for y in range(SCREEN_H):
            for x in range(SCREEN_W):
                r, g, b = px[x, y]
                rgb565 = ((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3)
                buf[idx] = rgb565 & 0xFF
                buf[idx + 1] = (rgb565 >> 8) & 0xFF
                idx += 2

        # Apply rotation by writing a pre-rotated buffer if needed (cheap path:
        # rotation is handled upstream by fbcp/fbtft, so we write straight).
        self._fb.seek(0)
        self._fb.write(bytes(buf))
        self._fb.flush()

    # --- clear --------------------------------------------------------------
    def clear(self):
        if self._fb is None:
            return
        black = b"\x00\x00" * (SCREEN_W * SCREEN_H)
        self._fb.seek(0)
        self._fb.write(black)
        self._fb.flush()

