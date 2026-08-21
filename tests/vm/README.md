# tests/vm/ — real VM integration test for pwnagotchi4b

This directory boots a **real x86_64 Debian VM** (QEMU/KVM) and runs the
pwnagotchi4b **first-boot orchestration + self-healing watchdog + A2A bridge**
end-to-end — the actual scripts from the repo, not mocks.

## Why x86_64, not the Pi image?

The Pi is `aarch64` and the *interesting* hardware (ILI9486 SPI screen, fbcp,
fbtft) **cannot exist in a VM** — there is no SPI display to drive. So a VM
test of the *Pi image itself* is impossible and would be dishonest to claim.

What a VM **can** test for real (and what this harness exercises):
- `tools/firstboot.sh` runs the four component installers exactly once, then
  reboots — using **Pi-installer STUBS** (the real `apt`/`git`/hardware steps are
  faked so the VM doesn't need a Pi or the internet to a Pi repo).
- `tools/watchdog.sh` runs on boot + timer, detects healthy/broken, recovers,
  and respects the reboot cap.
- `mothership/pwnagotchi_a2a.py` binds `:8700` and answers real JSON-RPC calls
  (`get_status`, `toggle_plugin`, `set_mode`).
- The systemd units (`pwnagotchi4b-firstboot.service`,
  `pwnagotchi4b-watchdog.{service,timer}`) are enabled and fire on a real boot.

The display-class health check is satisfied by a **fake pwnagotchi package**
the harness plants, so `import pwnagotchi.ui.hw` resolves and the
`waveshare35b` registration is real on-disk.

## What is NOT tested here (Pi-only, by nature)
- Actual framebuffer render to /dev/fb1, fbcp-ili9341 build, fbtft overlay.
  Those need the physical panel. Covered only by `tests/test_display_import.py`
  (class structure) on the host.

## Quick start
```bash
# 1. install QEMU (no sudo needed on this host via Homebrew):
brew install qemu
#    …or system-wide:  sudo apt-get install -y qemu-system-x86 libvirt-clients

# 2. run the integration test (downloads a Debian cloud image on first run):
bash tests/vm/run.sh
```
`run.sh` is idempotent: it reuses a cached cloud image + seed, boots the VM,
provisions the test repo, triggers a first boot, then asserts the watchdog +
A2A bridge behave. Output is printed; non-zero exit = something regressed.

## Files
- `prepare-testrepo.sh` — builds `/tmp/pwnagotchi4b-vmtest`: a copy of THIS repo
  with the four Pi installers swapped for `pi-stubs/` (so firstboot runs real
  orchestration without needing a Pi).
- `pi-stubs/` — the four stub installers + a fake pwnagotchi python package.
- `cloud-init/user-data`, `cloud-init/meta-data` — VM bootstrap (ssh key,
  hostname, packages).
- `make-seed.sh` — builds the cloud-init seed ISO.
- `provision-guest.sh` — run *inside* the VM: installs the test repo, enables
  the firstboot + watchdog units, starts the A2A bridge.
- `verify-guest.sh` — assertions run *inside* the VM after a reboot:
  firstboot ran once (sentinel present), watchdog timer enabled, A2A answers a
  real `get_status` JSON-RPC.
- `run.sh` — orchestrates everything from the host.

## Caveat
Requires KVM (`/dev/kvm`) or falls back to slow TCG. On this x86_64 host KVM is
available, so the boot is fast. The Debian cloud image (~300 MB) is downloaded
once and cached.
