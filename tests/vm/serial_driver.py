#!/usr/bin/env python3
"""
tests/vm/serial_driver.py — drive the pwnagotchi4b VM over its serial console.

The Debian nocloud image allows `root` login on the serial tty WITHOUT a
password, so we don't need cloud-init or SSH at all. This driver:
  1. connects to QEMU's telnet-serial (127.0.0.1:2323)
  2. logs in as root (with retries — the post-reboot getty can race)
  3. fetches the test repo tarball from the host HTTP server (10.0.2.2:8000)
  4. extracts it to /opt/pwnagotchi4b, runs provision-guest.sh
  5. reboots, waits, runs verify-guest.sh, prints the result

Used by run.sh. No SSH, no cloud-init, no password.
"""
import os, socket, sys, time, tarfile, threading, http.server

SERIAL_HOST, SERIAL_PORT = "127.0.0.1", 2323
GATEWAY = "10.0.2.2"   # QEMU usernet host gateway
HTTP_PORT = 8000
REPO_TARBALL = os.environ.get("REPO_TARBALL", "/tmp/pwnagotchi4b-vmtest.tar.gz")


def recv(s, t=2.0):
    s.settimeout(t)
    data = b""
    try:
        while True:
            c = s.recv(4096)
            if not c:
                break
            data += c
    except socket.timeout:
        pass
    return data.decode(errors="replace")


def send(s, data, t=0.3):
    s.sendall(data if isinstance(data, bytes) else data.encode())
    time.sleep(t)


def wait_for(s, marker, timeout=60):
    buf = ""
    end = time.time() + timeout
    while time.time() < end:
        buf += recv(s, 1.0)
        if marker in buf:
            return True
        if "login:" in buf and "#" not in buf and "$" not in buf:
            send(s, "\n")
    return False


def run_cmd(s, cmd, wait=3.0):
    send(s, cmd + "\n")
    return recv(s, wait)


def login(s, retries=4):
    """Robustly log in as root over the serial getty, retrying past races."""
    for attempt in range(retries):
        # Clear any partial line / wake the prompt.
        send(s, "\n")
        if not wait_for(s, "localhost login:", timeout=40):
            print(f"[login] attempt {attempt+1}: no login prompt")
            continue
        send(s, "root\n")
        # Wait for either a shell prompt, a password prompt, or 'incorrect'.
        deadline = time.time() + 20
        seen = ""
        while time.time() < deadline:
            seen += recv(s, 1.0)
            if "Password:" in seen:
                # Shouldn't happen for nocloud root, but send empty just in case.
                send(s, "\n")
            if "incorrect" in seen:
                break
            if "#" in seen or "RDY#" in seen:
                # Shell prompt reached. Normalize PS1 and confirm.
                send(s, "stty -echo; export PS1='RDY# '\n")
                if wait_for(s, "RDY#", timeout=10):
                    return True
        print(f"[login] attempt {attempt+1}: did not reach shell")
    return False


def main():
    import http.server as H
    os.chdir(os.path.dirname(REPO_TARBALL) or ".")
    httpd = H.HTTPServer(("0.0.0.0", HTTP_PORT), H.SimpleHTTPRequestHandler)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()

    s = socket.create_connection((SERIAL_HOST, SERIAL_PORT), timeout=10)
    time.sleep(1)
    if not login(s):
        print("FAIL: root login did not yield a shell"); sys.exit(1)
    print("[ok] root shell on serial console")

    # Fetch + extract the test repo. The guest has `curl` (no wget), and
    # QEMU usernet gives it outbound + host-reachability at 10.0.2.2.
    run_cmd(s, f"curl -fsSL http://{GATEWAY}:{HTTP_PORT}/pwnagotchi4b-vmtest.tar.gz -o /tmp/repo.tgz", wait=15)
    out = run_cmd(s, "ls -l /tmp/repo.tgz 2>/dev/null && echo FETCH_OK || echo FETCH_FAIL", wait=3)
    print("[fetch]", out.strip()[-200:])
    if "FETCH_OK" not in out:
        print("FAIL: could not fetch repo tarball from host"); sys.exit(1)
    run_cmd(s, "mkdir -p /opt/pwnagotchi4b && tar xzf /tmp/repo.tgz -C /opt", wait=5)
    # The tarball top dir is "pwnagotchi4b-vmtest"; normalize it to /opt/pwnagotchi4b.
    run_cmd(s, "if [ -d /opt/pwnagotchi4b-vmtest ] && [ ! -e /opt/pwnagotchi4b/tools ]; then mv /opt/pwnagotchi4b-vmtest/* /opt/pwnagotchi4b/ 2>/dev/null; rmdir /opt/pwnagotchi4b-vmtest 2>/dev/null; fi", wait=3)
    out = run_cmd(s, "ls /opt/pwnagotchi4b/tools/firstboot.sh && echo REPO_OK", wait=3)
    if "REPO_OK" not in out:
        print("FAIL: repo not extracted"); print(out); sys.exit(1)
    print("[ok] test repo fetched + extracted into guest")

    # Provision: install units, write config, start A2A bridge.
    out = run_cmd(s, "bash /opt/pwnagotchi4b/tests/vm/provision-guest.sh", wait=15)
    print("[prov]", out.strip()[-400:])

    # Reboot so firstboot + watchdog fire on the new boot.
    run_cmd(s, "reboot", wait=2)
    print("[ok] reboot issued; waiting for return ...")
    time.sleep(20)
    if not wait_for(s, "localhost login:", timeout=90):
        print("FAIL: guest did not return after reboot"); sys.exit(1)
    if not login(s):
        print("FAIL: guest login after reboot failed"); sys.exit(1)
    print("[ok] guest back online post-reboot")

    # Boot diagnostics (decisive for debugging firstboot behavior).
    print("=== firstboot journal ===")
    print(run_cmd(s, "journalctl -u pwnagotchi4b-firstboot.service --no-pager -n 40 2>/dev/null", wait=5)[-1200:])
    print("=== firstboot sentinel + service state ===")
    print(run_cmd(s, "ls -l /var/lib/pwnagotchi4b/.firstboot_done 2>&1; systemctl is-enabled pwnagotchi4b-firstboot.service 2>&1; ls /usr/local/lib/python3.*/dist-packages/pwnagotchi/ui/hw/waveshare35b.py 2>&1", wait=4)[-600:])

    # Run in-guest verification.
    out = run_cmd(s, "bash /opt/pwnagotchi4b/tests/vm/verify-guest.sh", wait=25)
    print("=== verify-guest.sh output ===")
    print(out)
    httpd.shutdown()
    s.close()
    if "VM VERIFICATION PASSED" in out:
        print("VM INTEGRATION TEST PASSED")
        sys.exit(0)
    else:
        print("VM INTEGRATION TEST FAILED")
        sys.exit(1)


if __name__ == "__main__":
    main()
