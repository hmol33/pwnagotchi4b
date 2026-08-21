# Pwnagotchi A2A "Mothership" Bridge — Agent Specification

**Component:** Pwnagotchi-side A2A agent endpoint (the *little one* that GLaDOS and Wheatley boss around)
**Repo:** `pwnagotchi4b` · **Dir:** `mothership/`
**Status:** Design + runnable skeleton. **No hardware flashing/execution.** All local integration points are guarded and stubbed.

---

## 0. Topology (who talks to whom)

```
                 A2A (JSON-RPC, bearer token)
   ┌──────────────────────┐   message/send    ┌──────────────────────────┐
   │ GLaDOS / Hermes      │ ─────────────────▶ │  Pwnagotchi4b agent     │
   │ A2A :9900            │ ◀───────────────── │  (this peer) :8700      │
   └──────────────────────┘   tasks + artifacts│  Flask/aiohttp service  │
                                               │         │                │
   ┌──────────────────────┐   message/send    │         │ localhost       │
   │ Wheatley / OpenClaw  │ ─────────────────▶│         ▼                │
   │ A2A :18800           │ ◀─────────────────│  ┌────────────┐ ┌─────────────────┐
   └──────────────────────┘                   │  │ pwnagotchi │ │ fancyserver    │
                                               │  │ API :8666  │ │ Listener :3699 │
                                               │  └────────────┘ └─────────────────┘
                                               └──────────────────────────┘
```

- The Pi is a **new A2A agent peer** named `pwnagotchi4b`, speaking the same A2A JSON-RPC the OpenClaw gateway already uses (`/a2a/jsonrpc`, Agent Card at `/.well-known/agent-card.json`).
- It is a *leaf* agent: it does **not** need to call other agents back over A2A except for the optional one-shot registration handshake (see §6).
- Local control path reuses the **two existing seeds**:
  - **pwnmothership** plugin → read state from `http://127.0.0.1:8666/api/v1/...`
  - **fancyserver** plugin → send control commands to the multiprocessing `Listener` on `127.0.0.1:3699` (shutdown, restart-auto/manual, reboot-auto/manual, plugin <name> <True/False>).

---

## 1. A2A Agent Card (canonical JSON)

Served at `GET http://<pi>:8700/.well-known/agent-card.json`. This is the single source of truth GLaDOS/Wheatley fetch to learn the peer's skills and endpoint.

```json
{
  "protocolVersion": "0.2.0",
  "name": "pwnagotchi4b",
  "description": "A2A agent peer for a Pwnagotchi on a Raspberry Pi 4B (Waveshare 3.5B / ILI9486 fbtft). Exposes telemetry and remote control to mothership agents GLaDOS (Hermes) and Wheatley (OpenClaw).",
  "url": "http://pwnagotchi4b.local:8700",
  "provider": {
    "organization": "itsdarklikehell",
    "url": "https://github.com/itsdarklikehell/pwnagotchi4b"
  },
  "version": "0.1.0",
  "capabilities": {
    "streaming": false,
    "pushNotifications": false,
    "stateTransitionHistory": true
  },
  "defaultInputModes": ["application/json"],
  "defaultOutputModes": ["application/json"],
  "authentication": {
    "schemes": ["bearer"]
  },
  "skills": [
    {
      "id": "get_status",
      "name": "Get Pwnagotchi status",
      "description": "Returns the current Pwnagotchi state artifact (mode, battery/UPS, pwnd stats, wifi, temp, cpu, mem, peers, face, version).",
      "tags": ["status", "telemetry", "monitoring"],
      "examples": ["{\"action\":\"get_status\"}"],
      "inputModes": ["application/json"],
      "outputModes": ["application/json"]
    },
    {
      "id": "fetch_handshakes",
      "name": "Fetch handshake list",
      "description": "Returns the list of captured handshake files (path, filename, size, age).",
      "tags": ["handshakes", "pcap", "loot"],
      "examples": ["{\"action\":\"fetch_handshakes\",\"args\":{\"limit\":20}}"],
      "inputModes": ["application/json"],
      "outputModes": ["application/json"]
    },
    {
      "id": "set_mode",
      "name": "Set Pwnagotchi mode",
      "description": "Switch between AUTO and MANUAL mode. Maps to a fancyserver restart-auto / restart-manual.",
      "tags": ["control", "mode"],
      "examples": ["{\"action\":\"set_mode\",\"args\":{\"mode\":\"manual\"}}"],
      "inputModes": ["application/json"],
      "outputModes": ["application/json"]
    },
    {
      "id": "reboot",
      "name": "Reboot the unit",
      "description": "Reboot the Raspberry Pi (reboot-auto / reboot-manual via fancyserver).",
      "tags": ["control", "power"],
      "examples": ["{\"action\":\"reboot\",\"args\":{\"mode\":\"auto\"}}"],
      "inputModes": ["application/json"],
      "outputModes": ["application/json"]
    },
    {
      "id": "shutdown",
      "name": "Shutdown the unit",
      "description": "Cleanly shut down the Raspberry Pi (fancyserver 'shutdown').",
      "tags": ["control", "power"],
      "examples": ["{\"action\":\"shutdown\"}"],
      "inputModes": ["application/json"],
      "outputModes": ["application/json"]
    },
    {
      "id": "toggle_plugin",
      "name": "Toggle a Pwnagotchi plugin",
      "description": "Enable/disable a named Pwnagotchi plugin (fancyserver 'plugin <name> <True/False>').",
      "tags": ["control", "plugin"],
      "examples": ["{\"action\":\"toggle_plugin\",\"args\":{\"name\":\"fancygotchi\",\"enabled\":true}}"],
      "inputModes": ["application/json"],
      "outputModes": ["application/json"]
    }
  ]
}
```

> `url` should be the Pi's reachable address. On a flat LAN use `http://<pi-ip>:8700`; mDNS `pwnagotchi4b.local` works if Avahi is enabled. The card is intentionally **public** (no auth) so peers can discover it; only `/a2a/jsonrpc` requires the bearer token (§5).

---

## 2. A2A wire conventions used here

We follow the standard A2A JSON-RPC envelope. Inside a `message/send`, the instruction travels as a **single `text` part containing a JSON command string**:

```json
{
  "jsonrpc": "2.0",
  "id": "req-0001",
  "method": "message/send",
  "params": {
    "message": {
      "messageId": "msg-0001",
      "contextId": "ctx-bridge",
      "taskId": "task-0001",
      "role": "user",
      "parts": [
        { "kind": "text", "text": "{\"action\":\"get_status\"}" }
      ]
    }
  }
}
```

The server echoes `taskId` (or mints one with `uuid4` if absent), performs the action, and returns an A2A **Task** with `artifacts`:

```json
{
  "jsonrpc": "2.0",
  "id": "req-0001",
  "result": {
    "id": "task-0001",
    "contextId": "ctx-bridge",
    "status": { "state": "completed", "timestamp": "2026-08-21T14:47:00Z" },
    "artifacts": [
      {
        "artifactId": "art-0001",
        "name": "pwnagotchi_state",
        "parts": [
          { "kind": "text", "text": "{ ...state json... }" }
        ]
      }
    ],
    "history": [ { "role": "user", "parts": [ { "kind": "text", "text": "{\"action\":\"get_status\"}" } ] } ]
  }
}
```

`status.state` values: `submitted → working → completed | failed | canceled`. Destructive actions (`reboot`, `shutdown`) return `completed` immediately with an `ack` artifact noting the command was dispatched (the unit may go dark before a second confirm — that's expected).

Implemented JSON-RPC methods: `message/send`, `tasks/get` (re-read a stored task), `tasks/cancel` (stub). Everything else → `-32601 Method not found`. Auth failures → HTTP `401` + JSON-RPC error `-32001`.

---

## 3. State schema (reuses `pwnmothership` fields)

The `get_status` artifact is normalized to this shape so GLaDOS/Wheatley get a stable contract regardless of pwnagotchi API quirks. Sources: `:8666/api/v1/status` (+ `/peers`, `/handshakes` where useful), `fancyserver` for live plugin/UPS state.

| Field | Type | Source | Notes |
|---|---|---|---|
| `name` | string | status.bot.name | Unit name |
| `version` | string | status.bot.version | Pwnagotchi version |
| `fingerprint` | string | status.bot.identity.fingerprint | Unique unit id (also used by pwnmothership) |
| `mode` | string | status.bot.mode | `auto` \| `manual` \| `ai` |
| `face` | string | status.bot.face | Current Fancygotchi face |
| `pwnd_run` | int | status.bot.pwnd_run | Handshakes this run |
| `pwnd_tot` | int | status.bot.pwnd_tot | Handshakes all-time |
| `aps` | int | status.wifi.aps \| status.bot.ap_tot | Access points seen |
| `channel` | int | status.wifi.channel | Current 2.4GHz channel |
| `handshakes` | int | count of `/api/v1/handshakes` | Count (full list via `fetch_handshakes`) |
| `peers` | array | `/api/v1/peers` | Nearby Pwnagotchi peers |
| `uptime` | int | status.uptime | Seconds since boot |
| `cpu` | float | status.cpu | Load % |
| `temp` | float | status.temp | Temperature °C |
| `memory` | float | status.mem | Memory used % |
| `battery` | object | status.ups / UPS plugin | `{percent, voltage, charging}` (null if no UPS) |
| `timestamp` | string | generated | ISO-8601 capture time |

Example artifact data:

```json
{
  "name": "pwnagotchi4b",
  "version": "1.5.5",
  "fingerprint": "aa:bb:cc:dd:ee:ff",
  "mode": "auto",
  "face": "happy",
  "pwnd_run": 3,
  "pwnd_tot": 1287,
  "aps": 42,
  "channel": 6,
  "handshakes": 1287,
  "peers": ["unit-2", "unit-7"],
  "uptime": 93144,
  "cpu": 18.2,
  "temp": 47.5,
  "memory": 33.1,
  "battery": { "percent": 87, "voltage": 4.12, "charging": true },
  "timestamp": "2026-08-21T14:47:00Z"
}
```

---

## 4. Command surface → A2A mapping

| A2A `action` | `args` | Local effect (Pi) | Artifact |
|---|---|---|---|
| `get_status` | — | `GET :8666/api/v1/status` (+ peers) | `pwnagotchi_state` |
| `fetch_handshakes` | `{limit?}` | `GET :8666/api/v1/handshakes` | `handshake_list` |
| `set_mode` | `{mode:"auto"\|"manual"}` | fancyserver `restart-auto` / `restart-manual` | `ack` |
| `reboot` | `{mode?:"auto"\|"manual"}` | fancyserver `reboot-auto` / `reboot-manual` | `ack` |
| `shutdown` | — | fancyserver `shutdown` | `ack` |
| `toggle_plugin` | `{name, enabled:bool}` | fancyserver `plugin <name> <True/False>` | `plugin_status` |

> `set_mode` and `reboot` both restart the pwnagotchi process (mode is chosen at launch); `set_mode` is the *semantic* one GLaDOS/Wheatley should prefer. `restart` is an alias of `reboot` kept for symmetry.

---

## 5. Authentication approach (shared bearer token)

Mirror the OpenClaw gateway's model: a **single shared bearer token** issued for the Pi peer.

- Env / config: `PWNAGOTCHI_A2A_TOKEN` (fallback `mothership/config.json → a2a_token`). If unset, the skeleton runs in **permissive/dev mode** and logs a warning — never ship that.
- Clients (GLaDOS :9900, Wheatley :18800) send:
  `Authorization: Bearer <token>`
- Server: missing/invalid token on `/a2a/jsonrpc` → `401` + JSON-RPC `-32001 Unauthorized`. The Agent Card endpoint stays open for discovery.
- Token storage on the callers: each peer keeps the Pi's token in its A2A *agent/peer* config (same place it keeps its own gateway token), not hardcoded in agents.
- Optional hardening (later): mTLS or a per-peer token, but bearer is sufficient on a trusted LAN. The fancyserver `Listener` additionally has its own `authkey` (`FANCYSERVER_AUTHKEY`); the A2A layer never forwards that to remote peers.

---

## 6. How the Pi registers as a peer with GLaDOS / Wheatley

A2A has no built-in registry, so we use **card fetch + optional push handshake**:

1. **Passive discovery (primary).** GLaDOS and Wheatley are given the Pi's Agent Card URL (`http://<pi>:8700/.well-known/agent-card.json`) in their peer config. On startup / on demand they `GET` the card, learn the `:8700` endpoint and the skill list, and store `pwnagotchi4b` as a known peer. No action needed from the Pi beyond serving the card.
2. **Active push (bootstrap).** On first boot the Pi can announce itself: `pwnagotchi_a2a.py --register` sends a `message/send` to each mothership peer's `/a2a/jsonrpc` with a `register` action carrying its own Agent Card. The mothership peers validate the Pi's bearer token (sent in the request) and add it. This is handy when the Pi's IP is dynamic.
3. **pwnmothership extension (optional).** The existing `pwnmothership` plugin already POSTs state to a central host; extend it to also POST `{agent_card_url, token_hint}` on boot so the motherships learn the Pi without manual config.

Peer bootstrap config (on the Pi, `mothership/config.json`):

```json
{
  "a2a_token": "REPLACE_WITH_SHARED_SECRET",
  "fancyserver_authkey": "REPLACE_WITH_FANCYSERVER_KEY",
  "peers": [
    { "name": "glados-hermes", "url": "http://<glados-host>:9900", "token": "GLADOS_PEER_TOKEN" },
    { "name": "wheatley-openclaw", "url": "http://<wheatley-host>:18800", "token": "WHEATLEY_PEER_TOKEN" }
  ]
}
```

---

## 7. Open questions / TODO before hardware

- [ ] Confirm exact pwnagotchi `:8666/api/v1/status` field names on the target image (1.5.5 vs 1.6.x differ slightly) and adjust the `get_status` mapping.
- [ ] Confirm fancyserver `Listener` `authkey` and whether it echoes a response after each command.
- [ ] Decide whether `set_mode` should be non-destructive (live mode flip via `/api/v1/config` + reload) vs the restart approach — depends on image support.
- [ ] Add a tiny heartbeat: Pi pushes `get_status` to motherships every N minutes (reuse pwnmothership cadence) so they notice if it goes offline.
- [ ] Consider A2A `message/stream` later if we want live face/telemetry streaming.
```
