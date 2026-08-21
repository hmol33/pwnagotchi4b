# display/ — off-brand Waveshare 3.5" (B) / ILI9486 screen support

The current `jayofelony/pwnagotchi` image has **no `waveshare35b` display type**,
and your panel is an off-brand ILI9486. This directory provides the missing piece.

## Files
- `waveshare35b.py` — custom Pwnagotchi `DisplayImpl` subclass that renders the
  canvas to the Linux framebuffer (`/dev/fb1`) as RGB565. Fancygotchi works
  automatically because it reads `ui.display.type`.
- `install.sh` — auto-detects the best backend, installs the class, and registers
  the `waveshare35b` type in `pwnagotchi/ui/hw/__init__.py`.

## Backends (chosen automatically)
1. **fbcp-ili9341 (recommended, fast):** `juj/fbcp-ili9341` built with
   `-DILI9486=ON`. Mirrors the Pi's framebuffer to the TFT over SPI via DMA.
   *Caveat:* uses the deprecated DispmanX API → needs the **legacy GL driver**
   (not `dtoverlay=vc4-kms-v3d`). Works on the Pi 4; does **not** work on Pi 5
   or pure-KMS kernels.
2. **fbtft (fallback, robust):** `dtoverlay=waveshare35b` drives `/dev/fb1`
   through the kernel framebuffer — also works under KMS. Slower refresh, but
   reliable.

## Install (on the Pi, or chrooted during provision)
```bash
sudo bash display/install.sh
sudo reboot
```
Then ensure `config.toml` has `ui.display.type = "waveshare35b"`.

## Verify
```bash
ls -l /dev/fb1            # framebuffer present
systemctl status fbcp-ili9341   # if fbcp backend
sudo journalctl -u pwnagotchi -n 50 | grep -i waveshare35b
```

## Pinout (adjust to your clone)
- SPI0: MOSI=GPIO10, SCLK=GPIO11, CS0=GPIO8
- D/C=GPIO24, RST=GPIO25, backlight=GPIO18
If your clone uses different pins, edit the `PIN_*` variables in `install.sh`
and re-run. Confirm the controller with `dmesg | grep -i ili` on first boot.
