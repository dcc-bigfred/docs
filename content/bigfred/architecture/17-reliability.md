# Reliability — reconnect and retry

BigFred is used on phones over a **local WiFi HTTP** deployment (club
layout or home). Brief radio drops, Android background-tab suspension,
and `dcc-bus` restarts are expected. This section documents the
**implemented** retry and grace mechanisms that keep throttle usable
without surprising emergency stops.

Related: [§6.3b Throttle overlay](./08-frontend-components.md#63b-throttle-mode--full-screen-overlay),
[§7e.7 Frontend integration](./16-dcc-bus/07-frontend-integration.md),
[§7e.4 WebSocket protocol](./16-dcc-bus/04-websocket-protocol.md),
[§4.5 Drive session & DMS](./06-communication-protocol/05-drive-session-dms.md).

---

## Overview

| Layer | Component | What is retried |
|---|---|---|
| Setup | `ThrottlePage` + `SocketContext` | Lazy `dcc-bus` spawn / `session.setCommandStation` |
| Control plane WS | `SocketContext` (`/api/v1/ws`) | Connection to `loco-server`; `system.radioStop`, takeover, radio, … |
| Data plane WS | `DccBusContext` (`dcc-bus` `/ws`) | Connection to picked command station |
| Driving commands | `useRetryingSend` | `loco.setSpeed`, `train.setSpeed`, `loco.setFunction` |
| Radio stop | `RadioStopButton` + `useRetryingSend` | `system.radioStop` on control plane |
| Backend session | `dcc-bus` `readLoop` | Dead-man's switch (DMS) grace on WebSocket drop |

The control plane and data plane **reconnect independently**. Command
retries on the data plane wait for the data-plane socket; radio stop
retries wait for the control-plane socket.

---

## Command station selection (lazy spawn)

When the driver opens Throttle and picks a command station, the SPA
must attach the session to a running `dcc-bus` daemon.

**Automatic attach** (`ThrottlePage`):

1. On `connected` + `session.sessionId` + `selectedCS > 0`, the page
   calls `setCommandStation(selectedCS)` on the control plane.
2. The server may lazy-spawn the daemon. While spawning it emits
   `session.commandStationChanged { status: "starting", wsUrl: null }`.
   `SocketContext` **keeps the previous `wsUrl`** during `starting` so
   `DccBusProvider` is not torn down mid-handshake.
3. On success: `ack { ok: true }` and/or
   `session.commandStationChanged { status: "running", wsUrl }`.
   `DccBusProvider` opens the data-plane WebSocket at `wsUrl`.

**Manual retry:**

- If spawn fails (`dcc_bus_unavailable`, `no_dcc_bus_ports_available`,
  …), the setup panel shows an error `Alert` with **„Spróbuj ponownie”**
  (`throttle:retry`). Clicking it bumps `retryTick`, which re-runs the
  attach `useEffect` (same as picking the station again).
- Retry is blocked with `control_offline` when the control-plane socket
  is down.

**Timeouts:**

| Call | Ack timeout |
|---|---|
| `session.setCommandStation` | **45 s** (spawn + dial budget) |
| Other `sendAction` frames | **12 s** |

There is **no** automatic timer retry for failed spawn — only the
user-facing button (or changing the picker selection).

---

## WebSocket reconnect — control plane

Implementation: `web/src/context/SocketContext.tsx`.

| Constant | Value | Role |
|---|---|---|
| `RECONNECT_INTERVAL_MS` | **250 ms** | First reconnect delay after drop |
| `RECONNECT_MAX_MS` | **2000 ms** | Exponential backoff cap |
| `CONNECT_TIMEOUT_MS` | **1000 ms** | Abort `CONNECTING` sockets that stall |

**Behaviour:**

1. On `onclose`, pending request acks resolve immediately with
   `control_offline` (not left hanging until ack timeout).
2. Reconnect is scheduled with backoff: 250 → 500 → 1000 → 2000 ms
   (reset to 250 ms after a successful `onopen`).
3. **`visibilitychange`** (tab visible) and **`online`** (network back)
   trigger an **immediate** `connect()` if the socket is not already
   `OPEN` or `CONNECTING`. This matters on Android, where background
   tabs freeze timers and kill sockets.
4. `reconnecting` is `true` only **after** the first successful open
   (avoids flashing reconnect UI on first login).

`waitForControlSocket` (used by `sendAction`) polls up to **5 s** for
an `OPEN` socket before returning `control_offline`.

---

## WebSocket reconnect — data plane

Implementation: `web/src/context/DccBusContext.tsx`.

Uses the **same** reconnect constants and `visibilitychange` / `online`
triggers as the control plane.

**Additional behaviour:**

1. On `onclose`, all pending command acks resolve with
   `dcc_bus_offline` (feeds command retry — see below).
2. Application **ping** every `heartbeatSecs` from `dcc-bus.opened`
   (daemon default **5 s**); server `pong` resets the dead-man timer.
3. When `status` returns to `"open"`, `ConnectedThrottle` re-issues
   `loco.subscribe` for the current vehicle / train member addresses.

**UI (settings icon in cockpit header):**

| State | Icon |
|---|---|
| Reconnecting after prior success (`reconnecting`, or `closed` / `error`) | `CircularProgress` |
| Command retry in flight (see below) | Rotating `SyncIcon` |
| Normal | `SettingsIcon` |

Reconnect takes priority over command retry in the icon. The setup
dialog still shows control/data plane chips; reconnect toasts were
removed in favour of the header spinner.

---

## Command retry (throttle driving)

Implementation: `web/src/hooks/useRetryingSend.ts`, wired through:

- `useDebouncedSpeedSend` → `loco.setSpeed`
- `useDebouncedTrainSpeedSend` → `train.setSpeed`
- `useKeyedRetryingSend` → `loco.setFunction` (per `address:fn` key)
- `RadioStopButton` → `system.radioStop` (`dispatchAsync`)

### Policy

| Error | Retry budget | Backoff |
|---|---|---|
| `ack_timeout` | **2** extra attempts after the first send (3 tries total) | **200 ms** between tries |
| `dcc_bus_offline` (data plane) | Until **3 s** elapsed since first attempt | **200 ms** |
| `control_offline` (control plane) | Until **3 s** elapsed since first attempt | **200 ms** |
| Any other `ack.error` | **No** retry | — |

Constants (exported for tests / tuning):

```ts
SPEED_RETRY_BACKOFF_MS = 200
SPEED_RETRY_MAX = 2
RETRY_MAX_WAIT_MS = 3_000
```

### Superseding (last-write-wins)

- **Speed / train speed:** a new slider move calls `cancel()` on the
  retry hook and replaces the debounced pending value. A stale speed
  never lands after a newer target.
- **Functions:** each `${dccAddress}:${fn}` has its own retry chain;
  toggling F1 does not cancel retry on F2. Re-toggling the same function
  supersedes only that key.
- **Radio stop:** a new confirm supersedes the previous `dispatchAsync`
  chain via the shared `useRetryingSend` generation counter.

### Debounce before send

| Path | Debounce |
|---|---|
| Vehicle speed (`queueSpeed`) | **100 ms** (`THROTTLE_SPEED_SEND_DELAY_MS`) |
| Train speed (`queueTrainSpeed`) | **120 ms** |

`sendSpeedNow` / direction change / stop bypass debounce but still use
retry.

### UI feedback

`commandRetrying` OR `radioStopRetrying` OR DCC command retry flags
drive the **sync spinner** on the settings icon (`ThrottleCockpit`).
`RadioStopButton` reports `onRetryingChange` upward so radio-stop
retries share the same indicator.

---

## Radio stop

`system.radioStop` travels on the **control plane** (not `dcc-bus`).
`RadioStopButton` uses `dispatchAsync` with the same retry policy as
driving commands (`control_offline` + `ack_timeout`).

The confirmation dialog stays open until `res.ok`; the run button shows
`busy` for the whole async retry window.

---

## Backend — dead-man's switch and WebSocket grace

Implementation: `pkgs/bigfred/dcc-bus/ws/handler.go`,
`pkgs/bigfred/dcc-bus/cmd/session.go`.

Daemon flags (defaults from `dcc-bus` CLI):

| Flag | Default | Meaning |
|---|---|---|
| `--heartbeat-secs` | **5** | Advertised to client; ping interval hint |
| `--deadman-secs` | **6** | Idle budget before DMS |

### Ping silence (`watchDeadman`)

If the session sends **no inbound frames** for `deadmanSecs`, the
daemon immediately calls `HandleSessionClose` with reason `deadman` and
applies emergency stop on that session's subscribed addresses (or all
user drive targets when it was the last tab).

### WebSocket drop (reconnect grace)

When the browser TCP/WebSocket closes for any reason **other than**
`deadman`:

1. The session is **unregistered** from the hub immediately (a new tab
   can connect).
2. `HandleSessionClose` / emergency stop is **delayed** by
   **`deadmanSecs`** (`delayedSessionClose`).
3. If the user reconnects within that window, `isLastSessionForUser`
   sees the new session and **skips** the layout-wide emergency stop.

This mirrors the ping budget: a short disconnect while the phone
switches apps should not stop the train.

### Emergency stop direction

`applyEmergencyStop` preserves the locomotive's cached **forward**
direction from Redis (`isLocoPlacedForward`) so a stop does not flip
consist direction on the layout.

---

## Mobile — screen wake

Implementation: `web/src/hooks/useWakeLock.ts` + `WakeLockKeeper` in
`App.tsx`.

BigFred is served over **plain HTTP** on LAN, so the
[Screen Wake Lock API](https://developer.mozilla.org/en-US/docs/Web/API/Screen_Wake_Lock_API)
is unavailable. The app uses **[NoSleep.js](https://github.com/richtr/NoSleep.js)**
(muted video fallback) after the first user gesture, re-enabled on
`visibilitychange` when the tab returns. This reduces WiFi power-save
and accidental disconnects during driving.

---

## Process-level recovery (supervisord)

When a `dcc-bus` process exits, **supervisord** restarts it
(`autorestart=true`, exponential backoff up to ~30 s — see
[§7d](./15-supervisord/03-lifecycle-and-health.md)). During restart
the data-plane dial fails; the SPA reconnect loop above applies. The
control plane stays up so session metadata and spawn state remain
available.

---

## Quick reference — source files

| Concern | Primary file(s) |
|---|---|
| Control WS | `web/src/context/SocketContext.tsx` |
| Data WS | `web/src/context/DccBusContext.tsx` |
| Command retry | `web/src/hooks/useRetryingSend.ts` |
| Throttle spawn / UI | `web/src/pages/ThrottlePage.tsx` |
| Cockpit indicators | `web/src/components/throttle/ThrottleCockpit.tsx` |
| Radio stop | `web/src/components/throttle/RadioStopButton.tsx` |
| DMS grace | `pkgs/bigfred/dcc-bus/ws/handler.go` |
| DMS actions | `pkgs/bigfred/dcc-bus/cmd/session.go` |
| Screen wake | `web/src/hooks/useWakeLock.ts` |
