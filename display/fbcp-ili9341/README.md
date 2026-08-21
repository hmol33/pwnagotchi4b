# fbcp-ili9341 build notes (pwnagotchi4b)

We vendor the upstream build as a reference. The actual build is performed by
`../install.sh` (it clones `https://github.com/juj/fbcp-ili9341.git` on the Pi).

## Why this driver
Your off-brand Waveshare 3.5B uses the **ILI9486** controller. `juj/fbcp-ili9341`
ships a first-class `ili9486.cpp` / `ili9486l.h` target and is the fastest path
to a smooth 320x480 UI on a Pi 4 over SPI.

## Build flags used by install.sh
```
cmake -DILI9486=ON \
      -DGPIO_TFT_DATA_CONTROL=24 \
      -DGPIO_TFT_RESET_PIN=25 \
      -DSPI_BUS_CLOCK_DIVISOR=6 \
      -DSTATISTICS=0 ..
make -j$(nproc)
```
`SPI_BUS_CLOCK_DIVISOR` may need tuning: lower = faster (but unstable on long
cables); 6 is a safe start for ILI9486 on a Pi 4.

## IMPORTANT platform caveat (from upstream, Feb 2024)
> fbcp-ili9341 was built on the Raspberry Pi's VideoCore DispmanX API, which is
> deprecated and **unavailable on Raspberry Pi 5 and newer distros by default**.

So:
- **Pi 4 + legacy GL driver** → fbcp works (recommended).
- **Pi 5 / KMS-only kernel** → fbcp will fail; `install.sh` auto-selects the
  **fbtft fallback** instead. That is expected, not a bug.

## Upstream
https://github.com/juj/fbcp-ili9341  (archived; pin the commit used by install.sh
if you need reproducibility).
