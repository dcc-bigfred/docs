# Plan: p99 latency regression (set_speed / list_functions) and setSpeed `1 → 2` regression

Branch: `fix/throttle-e2e-reliability`
Author of analysis: Cursor
Date: 2026-06-29

This plan covers two regressions observed while testing the
`fix/throttle-e2e-reliability` branch since 2026-06-28:

1. **Performance regression** — p99 of `set_speed` and `list_functions`
   (metric `bigfred_dcc_bus_station_operation_duration_seconds`) jumped
   above 1.5 s for single-locomotive operation, versus a p99 below 100 ms
   during the 20-vehicle load test on 2026-06-23.
2. **Functional regression** — `loco.setSpeed` with payload speed `1` must
   be promoted to wire speed `2` (DCC wire speed `1` is emergency brake),
   but the deployed build sends wire speed `1` (or `0`) instead.

---

## 1. Performance regression

### 1.1 Evidence from Grafana (datasource `grafanacloud-prom`)

Metric: `bigfred_dcc_bus_station_operation_duration_seconds` (histogram,
wraps every command-station call in
`pkgs/bigfred/dcc-bus/service/station/instrumented.go`).

p99 (`histogram_quantile(0.99, sum(rate(..._bucket[10m])) by (le))`),
2026-06-23 → 2026-06-29, 10m rate, step 600s:

| Window (UTC, approx) | `set_speed` p99 | `list_functions` p99 | Notes |
|---|---|---|---|
| 2026-06-23 ~14:00 (20-vehicle load test) | **~9 ms** | n/a | Baseline. Confirms the user's "<100 ms" recollection. |
| 2026-06-23 evening | 1.5–2.4 s | 0.025–0.099 s | Different usage pattern (sporadic). |
| 2026-06-24 … 06-27 daytime | 0.00099–0.05 s | 0.00099–0.025 s | Idle / light use. |
| **2026-06-28 ~evening (1782678000)** | **1.63 s** | **2.44 s** | Single-loco test, op rate low. |
| 2026-06-28 late (1782710400 … 1782714000) | 0.62–2.36 s | 0.98 s | Burst of `set_speed` + `send_fn`. |

Supporting counters over the same window:

- `bigfred_dcc_bus_loconet_queue_depth{queue="tx"}` = **0** at every
  regression sample → the TX queue is **not** saturated; `set_speed` is not
  blocking on `txCh` back-pressure.
- `bigfred_dcc_bus_loconet_slot_ops_total{op="acquire_fail"}` = **0** and
  `{op="retry"}` ≈ **0** at every regression sample → slots are **not**
  failing or retrying; the slow calls are not failed acquisitions.
- `bigfred_dcc_bus_loconet_dropped_total` rate = **0** across the whole week
  → no RX packets (and therefore no sync replies) are being dropped by
  `dispatch`.
- `bigfred_dcc_bus_loconet_slot_ops_total{op="keepalive"}` rises from
  ~0.24/s (06-23 evening) to ~0.5/s (06-28 evening) → owned-slot count /
  keepalive activity is higher, but keepalive frames are `lnTxPriorityLow`
  and do **not** hold `reqMu`, so they are a symptom (more slots owned),
  not the bottleneck.

### 1.2 Root-cause hypothesis

The histogram measures the **command-station call only** (not the WS
broadcast, not Redis). Both `set_speed` and `list_functions` spike at the
**same timestamps**, and `txCh` is empty, so the shared bottleneck is the
**synchronous slot request/response path** (`reqMu` + `beginSync` +
`syncCh`), not the TX writer.

Relevant constants in `pkgs/loco/commandstation/loconet.go`:

```go
lnDefaultSlotTimeout   = 600 * time.Millisecond   // line 144
lnSlotAcquireRetries   = 1                          // line 148  → up to 2 attempts
slotRevalidateInterval = 30 * time.Second          // line 1124
lnKeepaliveTickInterval = 2 * time.Second          // line 165
```

Two pre-existing slow paths produce tail latency in the 1–2.4 s band, and
the new branch makes them fire more often:

1. **`set_speed` cold path — `validateSlot` (`loconet.go:1090`).**
   `acquireSlot` (`loconet.go:906`) is lock-free only while
   `recentlyAcquired(addr)` is true, i.e. while `slotAcquiredAt[addr]` is
   younger than `slotRevalidateInterval = 30 s`. `writeSpeed` refreshes it
   via `markAcquired` on every successful `SetSpeed` (`loconet.go:884`), so
   during **continuous** throttling the hot path holds and p99 stays ~9 ms
   (this is exactly the 20-vehicle load-test condition). The first
   `SetSpeed` after >30 s of idle on that address falls through to
   `validateSlot`, which under `reqMu` runs a full
   `acquireSlotFreshLocked` = `LOCO_ADR` + `RQ_SL_DATA` + `NULL_MOVE`, each
   round-trip bounded by `slotTimeout = 600 ms` → ~1.2–1.8 s. With a
   single loco driven sporadically, this 30 s boundary is hit regularly, so
   the tail dominates p99. `acquire_fail`/`retry` stay 0 because the
   acquisition eventually **succeeds** — just slowly.

2. **`list_functions` — `syncLocoStateFromBus` (`cmd/slot_resilience.go:32`).**
   `ListFunctions` (`loconet.go:806`) always takes `reqMu` + `beginSync` +
   `querySlotLocked` (there is no hot path). `syncLocoStateFromBus` calls
   `GetSpeed` **and** `ListFunctions` **synchronously per address**, i.e.
   two cold slot round-trips in a row → up to ~2.4 s. It is invoked from
   `reclaimSlotOwnership` (`cmd/subscribe.go:62`), which on every
   `loco.subscribe` spawns a goroutine that runs `ForceAcquireSlot` +
   `syncLocoStateFromBus` for **each** address. A load-test connect that
   subscribes to N locos therefore fires N × (1 force-acquire + 1 GetSpeed
   + 1 ListFunctions) = 3 N cold round-trips, each holding `reqMu` and
   serialising with every concurrent `set_speed` cold path and every
   `list_functions`. That burst is what pushes p99 to 1.6–2.4 s.

Neither slow path was introduced by this branch, but the branch changes
increase how often they are hit:

- The observer/state-feed rewiring (`M6`, `C2b`, `Fix S`) keeps slots
  owned for longer (keepalive rate 0.24 → 0.5/s), so the 30 s
  revalidation boundary is crossed under sporadic single-loco use instead
  of being masked by continuous fleet throttling.
- `reclaimSlotOwnership` runs the `ForceAcquireSlot + GetSpeed +
  ListFunctions` triple on every subscribe; the load-test client
  (`pkgs/bigfred/loadtest/dccbus/client.go`) re-subscribes on each
  connect, so the burst is repeated every test run.

### 1.3 Confirmation steps (before coding)

1. **Correlate `slot_ops{op="acquire"}` with the p99 spikes.** Run
   `sum(rate(bigfred_dcc_bus_loconet_slot_ops_total{op="acquire"}[10m]))`
   over the same window. Expect the acquire-rate to rise at the
   `set_speed`/`list_functions` p99 peaks, confirming cold-path
   acquisitions.
2. **Add a `validateSlot`-cause histogram.** Instrument
   `acquireSlot`/`validateSlot` with a counter split by `cause`
   (`hot`, `revalidate`, `force`) so we can confirm the tail is
   `revalidate`/`force` and not `hot`.
3. **pprof.** Capture a 30 s CPU profile during a single-loco sporadic
   drive and confirm time is concentrated in `validateSlot` /
   `acquireSlotFreshLocked` / `nullMoveLocked` / `readPacketUntil`.
4. **Reproduce locally** with a stub command station whose `LOCO_ADR` /
   `RQ_SL_DATA` replies are delayed by ~500 ms and a single load-test
   client that drives one address at 0.1 Hz with a 35 s gap every ~30 s;
   observe `set_speed` p99 ≈ `slotTimeout`.

### 1.4 Fixes (in priority order)

#### Fix P1 — Keep the hot path hot: refresh `slotAcquiredAt` from keepalive

The cheapest, highest-leverage fix. Today `refreshOneKeepaliveSlot`
(`loconet.go:1462`) only re-sends the SPD frame; it does **not** call
`markAcquired`, so a slot that is only being kept alive (not actively
driven) still ages out after 30 s and forces the next `SetSpeed` onto the
cold path.

- After a successful keepalive `txEnqueue`, call `l.markAcquired(addr)`.
  Rationale: keepalive re-uses the cached slot number to write SPD; if the
  command station still echoes that slot (which the observer will see as
  `OPC_SL_RD_DATA` for an owned loco), the mapping is implicitly
  reconfirmed. To stay safe, only refresh `slotAcquiredAt` when the slot
  is already owned (`getSlot` ok) — never adopt an unowned slot here
  (consistent with the existing `observe()` guard at `loconet.go:441`).
- Net effect: `recentlyAcquired` stays true for any address BigFred
  owns, so sporadic single-loco `SetSpeed` never hits `validateSlot`.
  p99 `set_speed` returns to the ~9 ms hot path.

Risk: if the command station silently purges a slot while BigFred only
keepalives it, `markAcquired` would let `SetSpeed` trust a stale slot
number. Mitigation: keep `slotRevalidateInterval` as the safety bound and
have the observer's `OPC_SL_RD_DATA` path `clearSlot` on a slot
reassignment (it already does at `loconet.go:441`).

#### Fix P2 — Make `reclaimSlotOwnership` non-blocking and shed the redundant round-trip

`syncLocoStateFromBus` does `GetSpeed` + `ListFunctions` = two cold
round-trips per address, behind `reqMu`, on every subscribe. For LocoNet
this is redundant because the `StateObserver` feed already pushes
speed/functions for owned locos.

- In `reclaimSlotOwnership` (`cmd/subscribe.go:62`), after
  `ForceAcquireSlot` succeeds, **seed the store from the observer/cache**
  instead of calling `GetSpeed` + `ListFunctions`. The authoritative slot
  data is already refreshed by `applySlotData` during `ForceAcquireSlot`;
  expose it (or read the cached `spd`/`dirf`/`snd`/`extFn` via accessor
  methods on `LocoNet`) and build the snapshot in-memory.
- If a bus read is still desired as a correctness belt-and-braces, do it
  **once per address** with a single `ListFunctions`-equivalent query and
  drop the separate `GetSpeed` (speed is already in the slot data).
- Bound concurrency: process the `targets` slice with a small worker pool
  (e.g. 2–3) instead of fire-and-forget, so a 20-loco subscribe cannot
  pile 20 simultaneous `reqMu` round-trips onto the bus.

#### Fix P3 — Shorten `slotTimeout` for slot-acquire round-trips

`lnDefaultSlotTimeout = 600 ms` is sized for service-mode CV reads
(`loconet.go:42` comment). Slot-acquire `LOCO_ADR` / `RQ_SL_DATA` replies
on a healthy LocoNet return in tens of ms. A 600 ms bound means a single
lost reply costs 600 ms, and `acquireSlotFreshLocked` chains several of
them.

- Introduce a separate `lnSlotReplyTimeout` (e.g. 150–200 ms) used by
  `acquireSlotFreshLocked` / `querySlotLocked` / `nullMoveLocked`, keeping
  `slotTimeout = 600 ms` only for programming. On a healthy bus this
  changes nothing; on a flaky bus a lost reply fails fast and the existing
  `lnSlotAcquireRetries = 1` retry covers it, capping the cold path at
  ~2 × 200 ms × 3 round-trips ≈ 1.2 s worst case instead of ~3.6 s.

#### Fix P4 — Drop the `forceRevalidateSlot + retry` double round-trip on `set_speed` failure

`applyMemberSetSpeed` (`cmd/set_speed.go:43`) on any `SetSpeed` error
(except `ErrSpeedSuperseded`) calls `forceRevalidateSlot` (a full
`ForceAcquireSlot`) and then retries `SetSpeed` — two cold round-trips on
top of the original failure. Under the P1 fix this is rare, but it should
still be tightened:

- Only `forceRevalidateSlot` when the error indicates a stale/missing slot
  (map the existing `ErrSlotBusUnavailable` / slot-missing codes), not for
  transient transport errors. Log + surface the others without the
  force-revalidate round-trip.

### 1.5 Verification

- Re-run the single-loco sporadic drive (1 loco, ~0.1 Hz, 35 s idle gaps)
  and the 20-vehicle load test against a build with P1+P2.
- Acceptance: p99 `set_speed` < 100 ms in both scenarios; p99
  `list_functions` < 200 ms; `slot_ops{op="acquire"}` rate drops to near
  zero during steady single-loco drive.
- Watch `loconet_queue_depth`, `loconet_dropped_total`,
  `slot_ops{op="acquire_fail"}` to confirm no new regressions.

---

## 2. setSpeed `1 → 2` regression

### 2.1 Expected behaviour

In DCC, **wire speed step 1 is emergency brake**, not the first moving
notch. A non-emergency `loco.setSpeed` with payload `1` (the first driving
notch) must be promoted to **wire speed 2** before being sent to the
command station. Emergency requests must still emit wire speed 1; stop
(payload 0) emits wire speed 0.

### 2.2 Current state of the code

The promotion is centralised in
`pkgs/bigfred/dcc-bus/service/speed.go`:

```go
func WireSpeedFromPayload(payload uint8, emergency bool) uint8 {
    if emergency {
        return 1
    }
    if payload == 1 {
        return 2
    }
    return payload
}
```

History:

- `2bc747c` (2026-06-23) "treat wire speed 1 as emergency stop, not crawl"
  mapped payload `1 → wire 0` (skip the e-stop step by stopping). This is
  the behaviour the deployed test build exposes: setting speed `1` either
  stops the loco (wire 0) or, on paths that bypass the helper, sends wire
  `1` (e-stop). Either way the loco does not crawl.
- The current working tree contains **uncommitted** edits
  (`git status` shows `pkgs/bigfred/dcc-bus/service/speed.go`,
  `service/speed_test.go`, `cmd/set_speed.go`, `cmd/control_redis.go`
  modified) that extract `WireSpeedFromPayload` and change the mapping to
  `1 → 2`, plus wire the store snapshot through
  `contract.UISpeedFromWire(service.WireSpeedFromPayload(...))` so the UI
  also reports `2` for a payload-`1` command. `TestDCCWriterSetSpeed`
  already asserts `{"payload 1 maps to first step (wire 2)", 1, false, 2}`.

So the **WS throttle path** (`HandleSetSpeed → applyMemberSetSpeed`) and
the **Redis control path** (`applyControlSetSpeed`) are already fixed in
the working tree. The remaining work is to audit the other drive entry
points, commit, and guard against future bypass.

### 2.3 Audit of every `SetSpeed` entry point

| Path | Source | Speed passed | Promoted? | Status |
|---|---|---|---|---|
| WS `loco.setSpeed` | `cmd/set_speed.go:43` → `r.dcc.SetSpeed(addr, speed, …)` | payload | ✅ via `DCCWriter.SetSpeed` → `WireSpeedFromPayload` | Fixed in working tree. |
| Redis control `loco.setSpeed` | `cmd/control_redis.go:58` → `r.dcc.SetSpeed` | payload | ✅ | Fixed in working tree (store snapshot also promoted). |
| Train `train.setSpeed` (per-member fan-out) | `cmd/train_set_speed.go` → `applyMemberSetSpeed` | payload | ✅ (reuses the WS path) | Verify (see action). |
| WiThrottle inbound `handleSpeed` | `withrottle/adapter.go:223` | `wireSpeed` from handset | `if estop || wireSpeed == 1 → ApplyHandsetPilotEStop`; otherwise `dccSpeedFromWire` then `drive.SetSpeed` | ✅ correct — a handset wire-speed `1` is intentionally e-stop, and `dccSpeedFromWire` maps the rest to payload. Confirm `dccSpeedFromWire` never yields payload `1` for a moving step. |
| Z21 inbound `HandleSetLocoDrive` | `z21server/adapter.go:184` | `speed` from `parseSetLocoDrive` | ❓ passes raw `speed` as `LocoSetSpeedWire.Speed` → reaches `DCCWriter.SetSpeed` → promoted. **But:** verify `parseSetLocoDrive` returns a *payload* speed, not a wire speed; if it returns wire speed `1` for "crawl", the promotion to `2` is wrong direction. | **Action needed.** |
| E-stop paths | `cmd/estop.go:155`, `instrumented.go:118` | wire `1` | ✅ intentional — emergency brake must be wire `1`. | Leave as-is. |
| Roster retire | `cmd/roster_retire.go:33` | wire `1` | ✅ intentional (force-stop on retire). | Leave as-is. |

### 2.4 Fixes

#### Fix S1 — Commit the in-progress `1 → 2` promotion

Stage and commit the existing working-tree edits in
`pkgs/bigfred/dcc-bus/service/speed.go`,
`service/speed_test.go`, `cmd/set_speed.go`, `cmd/control_redis.go`. They
implement the correct mapping and the UI-snapshot consistency. Keep the
`brakeRetryCount` retry guard keyed on `wireSpeed <= 1` (already done in
the diff), so retries only fire for genuine stop / e-stop.

#### Fix S2 — Audit `parseSetLocoDrive` (Z21) and `dccSpeedFromWire` (WiThrottle)

- Open `pkgs/bigfred/dcc-bus/z21server/adapter.go` `parseSetLocoDrive`
  and confirm the `speed` it returns is a **payload/UI** speed (0…speedSteps,
  where `1` means "first notch"). If it is a raw DCC wire speed, add a
  `wireToPayload` conversion before constructing `LocoSetSpeedWire`, or
  document why the subsequent `WireSpeedFromPayload` promotion is the
  correct boundary.
- Open `withrottle/...` `dccSpeedFromWire` and confirm it cannot return
  `1` for a moving step (it must skip wire `1`). Add a unit test
  asserting `dccSpeedFromWire(1, …)` is treated as e-stop upstream (already
  handled at `adapter.go:223`) and that `dccSpeedFromWire` for wire `≥ 2`
  yields payload `≥ 1` that round-trips through `WireSpeedFromPayload` to
  the same wire value.

#### Fix S3 — Add a regression guard

Add a table-driven test in `pkgs/bigfred/dcc-bus/service/speed_test.go`
that, for **every** drive entry point representative (WS, train, Redis
control, Z21, WiThrottle), asserts:

- payload `1`, emergency `false` → wire `2` on the station, store/UI
  snapshot `2`;
- payload `1`, emergency `true` → wire `1` on the station, snapshot `0`
  (`UISpeedFromWire(1) == 0`);
- payload `0` → wire `0`.

Add a `TestNoNonEmergencyWireSpeed1` invariant test that wraps a recording
station and fails if any non-emergency `SetSpeed` call records
`wireSpeed == 1`.

### 2.5 Verification

- `go test ./pkgs/bigfred/... -race` green, including the new regression
  guard.
- Manual: with a LocoNet command station, send `loco.setSpeed{speed:1}`
  from a WS client and confirm the locomotive crawls (wire `2`) and the
  `loco.state` snapshot reports `speed:2`. Send
  `loco.setSpeed{speed:1, emergency:true}` and confirm e-stop (wire `1`).

---

## 3. Order of work

The perf/speed fixes (§1–§2) and the slot-reservation redesign (§5)
share code: §5 **removes `reclaimSlotOwnership`** and the
subscribe→acquire path, which **subsumes Fix P2** (the
`syncLocoStateFromBus` round-trip shed). Therefore P2 is not done as a
standalone step — it falls out of §5.15 step 4. The standalone perf/speed
work that is *not* subsumed is P1, P3, P4, S1–S3:

1. **Fix S1 + S3** (commit the `1 → 2` promotion + regression guard) —
   small, self-contained, unblocks functional testing.
2. **Fix P1** (keepalive refreshes `slotAcquiredAt`) — biggest perf win,
   smallest risk.
3. **Confirmation step 1.3.1** (correlate `slot_ops{op="acquire"}` with
   p99) to confirm P1 addressed the tail before larger surgery.
4. **Fix P3 + P4** (shorter slot reply timeout; tighten
   `forceRevalidateSlot` trigger).
5. **Fix S2** (Z21/WiThrottle speed-boundary audit + tests).
6. Re-run both load tests and confirm Grafana p99 returns to baseline.
7. **Then §5 (slot reservation)** — step 4 of §5.15 removes
   `reclaimSlotOwnership`/`syncLocoStateFromBus`, delivering Fix P2 as a
   side effect; re-verify p99 after the redesign.

## 4. Open questions (perf & speed)

- Is the deployed test build the branch HEAD or an earlier commit? The
  `1 → 2` promotion only exists in the uncommitted working tree, so any
  build from a committed ref will still show the `1 → 0` / `1 → 1`
  behaviour. Confirm which ref was deployed on 2026-06-28 before
  re-testing.
- Should `slotRevalidateInterval` (30 s) be revisited in light of Fix P1?
  If keepalive refreshes `slotAcquiredAt`, the 30 s bound becomes a pure
  safety net for stale-slot detection and could be lengthened to e.g. 120 s
  to further reduce cold-path acquisitions during long idle periods.

---

# 5. Slot reservation — full implementation plan

## 5.1 Goal and invariants

BigFred must explicitly **lease** command-station slots and **release**
them when they are no longer *driven*. The guiding principle: **BigFred
is the authoritative driver of the vehicles it controls**, so a
command-station slot is needed **only while someone is driving** the
vehicle through BigFred. Mere viewers are served from BigFred's cache
(the in-memory `LocoStateStore` from C2b, mirrored to Redis), not from a
slot. This both fixes correctness (an abandoned loco must not hold a slot
indefinitely) and directly addresses the perf regression in §1: the
number of owned slots collapses to the number of *actively driven*
vehicles, so keepalive traffic and cold-path `validateSlot` acquisitions
shrink accordingly — a stronger fix than Fix P1 alone.

Invariants:

1. **One slot per address BigFred drives.** Selecting a single vehicle in
   UI / Z21 / WiThrottle leases exactly one slot for that address.
2. **Train = one slot per powered member.** Driving a train leases a slot
   for every *powered* (motorised) member; non-powered members get no
   slot. The lease is a single atomic group acquired/released together.
3. **Only the active driver holds the slot (driver-only — decided).** A
   slot is held while at least one session has the address **selected as
   its active drive target** (WS `loco.select`/`train.select`, or an
   active remote drive). **Viewers (plain `loco.subscribe`) do NOT hold a
   slot.** They receive state from `LocoStateStore` + Redis.
4. **Leasing is bounded per user.** A user may hold at most
   `layout.max_vehicles_per_user` (default **8**) concurrent **driven**
   vehicle leases on a layout. The cap counts slot-holding (selected)
   vehicles, not subscriptions.
5. **Releasing a moving loco = e-stop then release (decided).** Before
   `ReleaseSlot`, send `EmergencyStop` (wire speed 1) and wait for the
   station call to return; only then `ReleaseSlot`. `ReleaseSlot` itself
   is fire-and-forget (`loconet.go:1286`, `OPC_SLOT_STAT1` produces no
   reply) and explicitly does **not** stop the loco, so the e-stop must
   precede it.
6. **Slot exhaustion = reject (decided).** When the command station has
   no free slot for a new lease, reject with `loco.error` code
   `no_free_slot`. Do not queue; do not steal.
7. **Viewer state is passive (decided).** For vehicles BigFred is **not**
   driving (external FRED, idle on track, another instance), BigFred does
   **not** actively query their slot; the cache is fed by passive
   LocoNet observation only (see §5.12 for the freshness trade-off). Z21
   is unaffected (push-based, no slots).
8. **BigFred respects a global LocoNet slot budget (decided).** BigFred
   occupies at most `max_loconet_slots` (default **80**) **physical
   IN_USE slots** on a LocoNet command station (see D14 — counts every
   slot the driver holds on the CS, not only WS/Z21 holders). Over-budget
   → `loco.error` code `bigfred_slot_budget_exceeded`, no bus round-trip
   (after D20 grace eviction, when implemented).

## 5.2 Decisions recorded

| # | Question | Decision |
|---|---|---|
| D1 | Releasing a moving loco | **E-stop then release.** `EmergencyStop` → confirm → `ReleaseSlot`. |
| D2 | Train slot scope | **Powered members only.** Non-powered members get no slot. |
| D3 | Slot ownership | **Driver-only.** Only the session with the vehicle *selected* (or an active remote drive) holds the slot. Viewers do not. (Reverses the earlier "driver OR subscriber" choice — see §5.17 for the rationale.) |
| D4 | Switcher change | **Deferred release with grace (implemented).** Switcher change = `loco.select` new → `DeselectDeferred` old: the previous addr stays IN_USE on the CS for **`switcher_grace` (default 60 s)** so A→B→A reuse does not re-acquire on every toggle (anti-jongling). `SweepDeferred` e-stop-then-releases when grace elapses. Re-selecting the addr within grace cancels the pending release. **Immediate** e-stop-then-release still applies for cap eviction, idle, session close, and shutdown (not switcher). |
| D5 | Slot exhaustion UX | **Reject with `no_free_slot` error code.** |
| D6 | Per-user cap | **`max_vehicles_per_user`, default 8, in layout settings; counts driven (slot-holding) vehicles only.** |
| D7 | Idle timeout | **Z21/WiThrottle only, default 60 s, configurable per command station.** WS sessions do NOT idle-release (a WS-selected loco holds its slot until `loco.select` change or session close). |
| D8 | Viewer state for non-driven locos (LocoNet) | **Passive observation only.** No peek/refresh round-trip on subscribe; accept that quiet externally-driven locos may show stale state until a slot read happens on the bus. |
| D9 | Active-vehicle WS signal | **Add new `loco.select` / `train.select` frames** (none exists today; `protocol.go` has only subscribe/setSpeed/setFunction). |
| D10 | Cap counting unit | **Counts powered *Vehicles* only (not wagons/non-powered members), as N.** Rationale: the cap bounds command-station slot consumption, and a CS slot pool is ~117 — counting only motorised vehicles maps directly to slot usage. |
| D11 | Train over cap | **Reject `train.select` with `vehicle_cap_exceeded`; no auto-eviction.** Selecting a train that would push the user over `max_vehicles_per_user` is refused; the user must `deselect` something first. Nothing e-stops without an explicit user action. |
| D12 | `loco.select` ack semantics | **Synchronous ack.** The `ack` to `loco.select` waits for `AcquireSlot` to complete: ack OK when the slot is held (drive ready), ack fail with `no_free_slot` / `vehicle_cap_exceeded` otherwise. The UI knows precisely when drive is available. Accepted cost: the ack blocks for one bus round-trip (cold path ≤ ~1.2 s, hot path ~9 ms). |
| D13 | Idle timer vs external throttle | **Idle timer resets only on remote-originated drive actions; observed bus activity does NOT reset it.** Underlying assumption: a physical FRED cannot attach to a vehicle whose slot BigFred has already reserved (see §5.18). |
| D14 | Global LocoNet slot budget | **`max_loconet_slots`, default 80, per LocoNet command station.** The leaser's `Used` / budget gate counts **every slot physically IN_USE on the CS** that BigFred's LocoNet driver tracks: confirmed leases (`acquiredAt` set), switcher-grace leases (`releaseAt` set), and **`external` observer leases** (`userId=0`, `source=external` from `SlotObserver::OnSlotInUse`). Reserve-only bookings (`acquiredAt` zero, not yet driven) do **not** count until the driver reports IN_USE. Purpose: the budget bar matches real central occupancy, not merely "who clicked select in the UI". Enforced before new physical slot need in `Reserve`/`SelectTrain`; over-budget → `bigfred_slot_budget_exceeded` (after D20 grace eviction). LocoNet-only (Z21 has no slots). |
| D15 | Remote switch behaviour | **Idle-only — no auto-deselect on new select.** A Z21/WiThrottle client cycling through addresses keeps each old addr's slot until its 60 s idle timeout (D7) or disconnect (R1). Rationale: remotes have no explicit "deselect" signal; auto-deselect would need heuristics on which addr the client left. Accepted cost: a remote cycling N locos within 60 s holds N slots — bounded by the per-user cap (D6) and the global budget (D14), so it cannot run away. |
| D16 | Subscription (view) cap | **Per-session subscription count is bounded by `max_vehicles_per_user` (same setting as D6, default 8).** Reuses the existing layout setting; no new knob. Over-cap → `loco.error` code `subscription_cap` and the server drops the oldest subscription for that session. Protects the WS send queue (M4/M5) from unbounded `loco.state` fan-out. |
| D17 | Switcher-change e-stop UX | **Silent e-stop + toast.** Switching the active vehicle e-stops and releases the previous one (D4/R7) without a confirm dialog; the UI shows a transient toast "loco A zatrzymany" so the user is not surprised. Safe default; no extra round-trip. |
| D18 | `vehicle_cap_exceeded` payload | **Include the user's current driven-lease list.** The `loco.error` for `vehicle_cap_exceeded` (D11) carries the list of addresses the user currently has selected, so the UI can show "zwolnij jeden z: A, B, C" instead of a generic message. |
| D19 | Diagnostics slot table UI | **Add an admin-only diagnostic subpage** that streams the live `SlotLeaser` slot table plus the configured limits over a dedicated WebSocket, so operators can watch slot usage, FRED headroom, and per-user/per-budget consumption in real time. Read-only. See §5.19. |
| D20 | Budget pressure vs switcher grace | **Before refusing a new physical slot allocation** (`bigfred_slot_budget_exceeded`), **forcibly release up to 5** leases that are already in the **deferred-release (switcher grace)** window — the five **most recently** deferred (newest `releaseAt`). Each is e-stop-then-`ReleaseSlot` immediately (same as `SweepDeferred` after timeout). Only then re-check the budget; if still full, reject. Rationale: grace slots still occupy the CS and count toward D14; under pressure, anti-jongling yield gives way to making room for an active driver. **Implemented** — see §5.21. |

## 5.3 Data model — `SlotLeaser`

New component `pkgs/bigfred/dcc-bus/slotlease/leaser.go` (name tentative),
the single authority over which addresses BigFred is leasing. The
`LocoNet` driver keeps the low-level `AcquireSlot`/`ReleaseSlot`; the
leaser is the reference-counted owner above it. **Holders are drivers,
not viewers** — subscribing does not create a holder.

```go
type leaseKind uint8 // leaseSingle | leaseTrain

type holderKey struct {
    userID   uint
    session  string // WS session id, or remote client key
    source   string // "ws" | "z21" | "withrottle"
}

type lease struct {
    addr        uint16
    kind        leaseKind
    trainID     string         // set when kind == leaseTrain
    holders     map[holderKey]struct{}
    holderOrder []holderKey    // FIFO for "oldest" eviction
    lastDriveAt map[holderKey]time.Time // per-holder, for remote idle (D7)
    acquiredAt  time.Time
}

type Leaser struct {
    mu       sync.Mutex
    leases   map[uint16]*lease        // addr -> lease
    trains   map[string]*trainLease   // trainID -> group of addr leases
    perUser  map[uint]int             // userID -> count of driven addrs
    station  commandstation.SlotManager
    writer   *service.DCCWriter
    store    *state.LocoStateStore
    hub      StateBroadcaster
    maxPerUser  int
    maxSlots    int                   // D14: max_loconet_slots (LocoNet only; 0 = unlimited)
    idleTimeout time.Duration
    // ...
}
```

Key methods:

- `Select(userID, session, addr) (releasedAddr uint16, err error)` —
  WS drive-target selection. **Gates on `CanDrive(userID, vehicle)`
  first** — refuse with `loc.error` code `not_allowed` before touching
  the bus, so a user cannot reserve a slot for a vehicle they may not
  drive. Records this holder on the lease (creating it if absent) and
  calls `station.AcquireSlot` when the lease goes from 0 → 1 holders.
  Returns the addr evicted by the per-user cap (D6), if any. Errors:
  `ErrBigFredSlotBudgetExceeded` (D14, short-circuit, no bus call),
  `ErrVehicleCapExceeded` (D6/D11), `ErrNoFreeSlot` (D5).
- `SelectTrain(userID, session, trainID, poweredAddrs []uint16) error` —
  atomic: acquire all powered members; roll back on any failure.
- `Deselect(userID, session, addr)` — drop this holder; if no holders
  remain, e-stop-then-release (§5.6). This is the switcher-change release
  path (D4).
- `Touch(userID, session, addr)` — update `lastDriveAt[holder]`; called
  on every drive command from **remotes** (Z21/WiThrottle). WS holders
  are not idled (D7). Per D15, a remote `Select` of a new addr does
  **not** implicitly `Deselect` the old.
- `ReleaseSession(session)` — drop every lease held by the session
  (R1). Used on WS close and remote disconnect.
- `SweepIdle(now time.Time)` — for each lease whose **every** holder is
  a remote holder and whose youngest `lastDriveAt` is older than
  `idleTimeout`, e-stop-then-release. WS holders are never swept.

The leaser does **not** consult the WS subscription registry before
releasing — under driver-only (D3) viewers do not hold slots, so the
lease lifetime is governed solely by holders (drivers). Subscriptions
remain a separate, cheaper concern (state broadcast from the store).

**Concurrency design (critical for perf + reliability):** the leaser
`mu` guards only the in-memory lease/holder maps — it is **never** held
while `station.AcquireSlot`/`ReleaseSlot` runs (those are slow bus
calls). `Select` instead marks a per-addr `acquiring` state under `mu`,
releases `mu`, performs the bus acquire, then re-takes `mu` to publish
the lease. A concurrent `Deselect`/`ReleaseSession` that drops the last
holder while an acquire is in flight observes the `acquiring` state and
either (a) cancels by recording a "release pending" flag that `Select`
honours on completion (acquire → immediate release), or (b) waits on a
per-addr condition. This avoids both (i) re-serialising all leaser
operations behind bus round-trips — which would re-introduce the §1 p99
at a new layer — and (ii) orphaning a slot that was acquired just after
its last holder left.

## 5.4 Acquire paths

| Entry point | Action |
|---|---|
| WS `loco.subscribe` (UI opens a vehicle for **view**) | **No slot.** Registers the session for `loco.state` broadcasts from `LocoStateStore`. The store is seeded lazily from Redis on first read (`LoadMissingFromRedis`, already in place). |
| WS `loco.select` (new, §5.11) | `Select(user, sess, addr)` → `CanDrive` gate → `AcquireSlot`. This is the **only** WS path that acquires a slot. |
| WS `train.select` (new, §5.11) | `SelectTrain(user, sess, trainID, poweredMembers)` → atomic acquire (each member `CanDrive`-gated). |
| Z21 inbound `HandleSetLocoDrive` (`z21server/adapter.go:174`) | On first drive for `(client, addr)`, `Select(user, clientKey, addr)` (implicit select); `Touch` on every drive. Per D15, selecting addr B does **not** deselect the remote's previous addr A — A is released by idle (R2) or disconnect (R1). |
| WiThrottle `handleSpeed` (`withrottle/adapter.go:207`) | Same: `Select` on first drive for `(client, addr)`, `Touch` on every speed/dir/fn. The existing `if wireSpeed == 1 → ApplyHandsetPilotEStop` path stays. Same D15 no-auto-deselect rule. |
| Train drive (WS `train.setSpeed` fan-out) | The train must be selected via `train.select`; per-member `applyMemberSetSpeed` reuses the leased slots. If a `train.setSpeed` arrives without a prior `train.select`, lease on first drive (defensive). |

`Select` calls `station.AcquireSlot` (or `ForceAcquireSlot` for reclaim)
**without holding the leaser `mu`** (see §5.3 concurrency design). It
must **not** call `syncLocoStateFromBus` synchronously — the slot read
inside `AcquireSlot` already seeds the store via `applySlotData`; per
Fix P2, no extra `GetSpeed`/`ListFunctions` round-trip. **Synchronous
ack (D12):** the `ack` to `loco.select` returns only once the acquire
completes — ack OK when the slot is held (drive ready), ack fail with
`no_free_slot` / `bigfred_slot_budget_exceeded` / `vehicle_cap_exceeded`
otherwise. To avoid head-of-line blocking the session's WS read loop
(ping/pong, other commands) during a cold-path acquire (~1.2 s), the
router runs the acquire in a per-request goroutine and sends the `ack`
when it finishes; the read loop continues draining other frames in
parallel. On failure the UI stays in view-only mode and surfaces the
error.

## 5.5 Release paths (and additional cases proposed)

| # | Trigger | Action |
|---|---|---|
| R1 | WS session close / connection drop | `ReleaseSession(sess)` → for each lease, drop the holder; e-stop-then-release if last driver. (Replaces `reclaimSlotsStillSubscribed`'s slot concern; subscription cleanup stays separate.) |
| R2 | Remote (Z21/WiThrottle) idle timeout (D7) | `SweepIdle` e-stop-then-releases leases with only remote holders past the timeout. |
| R3 | Per-user cap exceeded (D6) | `Select` evicts the caller's oldest driven lease that is **not the current select target of any session**: e-stop-then-release, then acquire the new. |
| R4 | **Roster retire** (vehicle removed from layout) | `cmd/roster_retire.go` already sends wire 1; extend to `ReleaseSession` for every holder of the addr, then `ReleaseSlot`. |
| R5 | **Train dissolved / powered member removed** | E-stop-then-release the affected members' slots and drop the `trainLease` group. |
| R6 | **Drive permission revoked mid-session** (lease takeover / admin revoke) | `Deselect` for that `(user, addr)`; e-stop-then-release if last driver. |
| R7 | **WS `loco.select` of a different vehicle / `loco.deselect`** (switcher change, D4) | `Deselect` the previously-selected addr → e-stop-then-release if last driver. Then `Select` the new. UI shows a transient "loco A zatrzymany" toast (D17) — no confirm dialog. |
| R8 | **Daemon shutdown** | `e49157a` already stops locos; extend to `ReleaseSlot` for every leased addr so the command-station table is clean for the next boot. |

Cases deliberately **not** treated as release: *layout radio stop*
(temporary safety stop, keep the slot), *speed = 0* (the user may resume),
*function toggle* (drive activity, resets remote idle), *plain
`loco.unsubscribe`* (a viewer leaving does not release a driver's slot).

## 5.6 E-stop-then-release sequence

```go
func (l *Leaser) stopAndRelease(addr uint16) {
    // 1. Preserve the loco's current direction (don't snap to forward).
    prev := l.store.Snapshot(addr)
    forward := prev.Forward

    // 2. Emergency-stop with a bounded retry — never release the slot
    //    while the loco may still be moving. DCCWriter.SetSpeed(emergency)
    //    sends wire 1 and already background-retries on failure; here we
    //    also wait briefly for the first attempt so a transient bus error
    //    does not let the loco run away after ReleaseSlot.
    if err := l.writer.SetSpeed(addr, 0, forward, true); err != nil && !errors.Is(err, commandstation.ErrSpeedSuperseded) {
        // Best-effort: the background retry in DCCWriter keeps trying; we
        // proceed only after a short grace so a totally dead bus does not
        // block lease cleanup forever.
        select {
        case <-time.After(slotReleaseStopGrace): // e.g. 500 ms
        case <-l.stop:
        }
    }

    // 3. Mark the store stopped so the UI does not snap back; keep
    //    ControlledByUserID (Fix B2) and the real direction.
    snap := l.store.SetSpeedPreservingUser(addr, 0, forward, "slot_release")
    service.BroadcastLocoState(ctx, l.hub, snap)

    // 4. Release the slot. ReleaseSlot is fire-and-forget; on transport
    //    error retry a couple of times, and if still failing mark the
    //    addr for a deferred retry so it is not silently orphaned IN_USE
    //    on the command station (which would eat FRED headroom).
    if err := l.releaseSlotWithRetry(addr); err != nil {
        l.markReleasePending(addr) // sweeper will retry; see §5.7
    }
    l.metrics.incr(&l.metrics.slotReleasedByLeaser)
}
```

Why `SetSpeedPreservingUser` with the **real** `forward`: the release is
a server-originated action; we must not drop `ControlledByUserID`
mid-broadcast (Fix B2) nor flip the stored direction to `true` (which
would snap the UI's direction indicator). The e-stop uses the
`EmergencyStopper` capability when present
(`service/station/instrumented.go`), falling back to `SetSpeed(addr, 1,
forward, …)` via `DCCWriter` (`WireSpeedFromPayload(_, true) == 1`).

`releaseSlotWithRetry` re-sends `OPC_SLOT_STAT1 COMMON` a bounded number
of times (e.g. 3 × 100 ms). `markReleasePending` records the addr so the
idle sweeper (§5.7) re-attempts `ReleaseSlot` on later ticks; the lease
is still removed from the in-memory map so it stops consuming the
`max_loconet_slots` budget — but `slot_budget_used` is only truly
accurate once the CS confirms the release, hence the retry.

## 5.7 Remote idle timeout (D7)

- Config: `command_station.idle_timeout_secs`, default **60**, stored in
  the command-station config entity (same place as `speedSteps` /
  `heartbeatSecs` today). 0 disables.
- A single goroutine in the leaser ticks every
  `idle_timeout_secs / 4` (clamped to ≤ 15 s) and calls `SweepIdle`.
- `Touch` is called from the Z21 and WiThrottle adapters on **every**
  drive action (speed, direction, function). Observation of an external
  bus echo for that addr does **not** reset the timer — only an action
  *from* the remote does.
- A lease is idle-candidate when **all** its holders are remote holders
  and the youngest `lastDriveAt` is older than the timeout. WS holders
  are never swept (D7). Observed bus activity (e.g. a packet from a
  physical throttle) does **not** reset the timer — only an action
  *originating from the remote* does (D13).
- On fire: `stopAndRelease(addr)` (§5.6) and notify the remote with a
  `loco.error` code `idle_timeout` so the handset UI can show "session
  expired".
- The sweeper also drains the `markReleasePending` queue from §5.6
  (re-attempting `ReleaseSlot` for addrs whose earlier release write
  failed), so a transient transport error does not leave a slot
  orphaned IN_USE on the command station.

## 5.8 Per-user vehicle cap (D6)

- Config: `layout.max_vehicles_per_user`, default **8**, in the layout
  settings entity (server-side authoritative; mirrored to Redis like
  other layout settings).
- Counted as the number of distinct **driven powered Vehicles** a user
  holds across all their sessions (WS selects + remotes) on a layout. A
  train counts as N powered members (D10). Non-powered members (wagons)
  and plain subscriptions do not count.
- Enforcement point: `Select` / `SelectTrain`.
  - `Select` (single vehicle): when the new lease would push the user
    over the cap, evict the caller's oldest driven lease that is **not**
    any session's active select target (preferring a different
    train/group); `stopAndRelease` it; proceed with the new acquire. If
    every driven lease the user holds is some session's active select
    target, reject with `vehicle_cap_exceeded`.
  - `SelectTrain` (D11): when the train would push the user over the
    cap, **reject with `vehicle_cap_exceeded` — no auto-eviction**. The
    user must `deselect` something first. Rationale: silently e-stopping
    one loco to fit a multi-loco train is surprising; an explicit reject
    is predictable.
- This bounds the slot-acquisition burst the perf plan (§1.4 P2) worried
  about: a single user can never cause more than
  `max_vehicles_per_user` simultaneous cold-path acquisitions, and only
  for vehicles they actually drive.

## 5.9 Slot exhaustion and the BigFred slot budget (D5, D14)

Two distinct refusal reasons, both surfaced as `loco.error`:

1. **BigFred over its self-imposed budget (D14).** Before allocating a
   **new physical slot** (addr not already IN_USE on the CS), the
   `SlotLeaser` checks `budgetActiveLocked() < max_loconet_slots`
   where `budgetActiveLocked` counts CS-occupied slots (§5.20, D14).
   **Implemented (D20):** if at the limit, `ensureBudgetHeadroomLocked`
   evicts the newest switcher-grace leases one at a time (up to five
   attempts) via `stopAndRelease(..., ReleaseGraceEvict)`, then
   re-checks; only if still full, refuse
   **without touching the bus** — return
   `commandstation.ErrBigFredSlotBudgetExceeded`, mapped to WS code
   `bigfred_slot_budget_exceeded`. The UI shows a localised message such
   as "BigFred osiągnął limit slotów na centralce; zwolnij pojazd lub
   zwiększ limit w ustawieniach centralki."
2. **Command station truly full (D5).** `station.AcquireSlot` /
   `ForceAcquireSlot` already fail fast when no free slot is available
   (`545bac4`). Map that error to `commandstation.ErrNoFreeSlot` and WS
   code `no_free_slot`. This should be rare in practice because D14
   keeps BigFred well below the physical pool; it is the safety net for
   when FREDs fill the remaining headroom.

WS mapping (`116664e fix(dcc-bus): map LocoNet slot errors to distinct
WS codes`): add **both** `no_free_slot` and `bigfred_slot_budget_exceeded`
to the error→code table so `loco.select` / `train.select` /
`HandleSetSpeed` / `HandleTrainSetSpeed` return the matching
`loco.error{code}`. Neither auto-retries (no queueing, no stealing).

Check order in `Select` / `SelectTrain`: (a) per-user cap (D6, evict or
reject) → (b) global budget (D14, reject) → (c) `AcquireSlot` (D5,
reject). The budget check (b) is a pure in-memory counter, so it adds no
bus cost and short-circuits before any round-trip.

## 5.10 Configuration changes

| Setting | Scope | Default | Storage |
|---|---|---|---|
| `max_vehicles_per_user` | Layout | 8 | layout settings entity (server + Redis mirror); validated > 0, ≤ `max_loconet_slots` on the layout's LocoNet CS. |
| `max_loconet_slots` (D14) | Command station (LocoNet only) | 80 | command-station config entity (alongside `speedSteps`, `heartbeatSecs`); validated > 0 and < the CS's physical slot pool (~117). UI field shown only for LocoNet-kind stations. Help text: *"Ile slotów może jednocześnie zająć BigFred na centralce (fizycznie IN_USE); pozostałe zostaną dla fizycznych FRED'ów."* |
| `switcher_grace_secs` | Command station (LocoNet only) | 60 | How long a deselected addr keeps its slot IN_USE after switcher change (D4) before `SweepDeferred` releases it. |
| `idle_timeout_secs` | Command station | 60 | command-station config entity (alongside `speedSteps`, `heartbeatSecs`); 0 = disabled. |
| `slot_reply_timeout` (from Fix P3) | Command station | 200 ms | command-station config entity. |

These settings need: contract wire types, server admin endpoint, Redis
publish, daemon read at `dcc-bus` boot, and UI admin fields (the
`remotes` / WiThrottle pairing page already has a command-station admin
toggle per `cad4737`/`177acbb` — extend it). `max_loconet_slots` and
`idle_timeout_secs` fields are shown only for LocoNet-kind command
stations (Z21 has no slots). The `bigfred_slot_budget_exceeded`
`loco.error` message is localised per audience: admins see "…lub
zwiększ limit w ustawieniach centralki", regular users see only
"zwolnij pojazd i spróbuj ponownie" (they cannot change the setting).

**Boot-time slot reconciliation (reliability, B5):** on `dcc-bus`
startup, before the leaser accepts any `Select`, the driver must
reconcile BigFred's in-memory lease count with the command station's
actual slot table. After a crash/unclean shutdown, BigFred's old slots
remain IN_USE on the CS (purged only after ~200 s by the master); a
naïve `len(leases) < max_loconet_slots` check would let BigFred lease a
fresh 80 on top of the orphaned 80, bursting the pool and breaking the
FRED-headroom guarantee. Reconciliation walks the CS slot table (or the
cached slot→addr map populated from a burst of `OPC_RQ_SL_DATA` on boot)
and `ReleaseSlot`s every slot BigFred still owns IN_USE but has no live
lease for; only then does the leaser open for business. This also covers
the `markReleasePending` orphans from §5.6.

## 5.11 WS protocol additions

- **`loco.select`** — payload `{address uint16}`. Marks the address as
  the session's active drive target and **leases** the slot (D3/D4).
  Switcher change = `loco.select` new (server releases the previous
  selection for this session via R7). **Synchronous ack (D12):** the
  `ack` waits for `AcquireSlot` to complete — ack OK when the slot is
  held (drive ready), ack fail with `no_free_slot` or
  `vehicle_cap_exceeded` otherwise. The UI enters drive mode only on ack
  OK; on failure it stays in view-only mode and surfaces the error.
- **`loco.deselect`** — payload `{address uint16}`. Clears the active
  drive target and releases the slot if this was the last driver
  (R7). The session may remain subscribed for viewing.
- **`train.select`** — payload `{trainId string}`. Leases all powered
  members (D2). Replaces implicit per-member leasing on first
  `train.setSpeed`.
- **`loco.subscribe` / `loco.unsubscribe`** — unchanged semantics, but
  **no longer acquire/release slots**; they only control `loco.state`
  broadcast delivery from the store. Per D16, a session may hold at most
  `max_vehicles_per_user` concurrent subscriptions; over-cap drops the
  oldest subscription and emits `loco.error{code:"subscription_cap"}`.
- **New `loco.error` codes**: `no_free_slot` (D5),
  `bigfred_slot_budget_exceeded` (D14), `vehicle_cap_exceeded` (D6/D11,
  payload includes the user's current driven-addr list per D18),
  `subscription_cap` (D16), `idle_timeout` (D7), `not_allowed` (CanDrive
  gate on `loco.select`/`train.select`, §5.3).

Validation (`pkgs/bigfred/dcc-bus/validation/ws.go`): add `LocoSelect`
(addr != 0) and `TrainSelect` (trainId != "") validators. The
`LocoSubscribe` max-addresses-per-frame check is now bounded by
`max_vehicles_per_user` (D16) and enforced as a per-session running
count, not just a per-frame check.

## 5.12 Integration with keepalive, observer, store, and viewer state

- **Keepalive** (`loconet.go:1442`): unchanged at the driver level — it
  still refreshes owned slots. The leaser is the *only* caller of
  `AcquireSlot`/`ReleaseSlot` above the driver, so "owned" == "leased
  (driven)". With driver-only, the owned set is exactly the driven set,
  so keepalive traffic tracks actual driving — this is the primary fix
  for the `slot_ops{op="keepalive"}` 0.24→0.5/s growth observed in §1.
  Combined with Fix P1 (keepalive calls `markAcquired`), every driven
  slot stays on the `set_speed` hot path; both p99 contributors from §1
  (cold-path `validateSlot` and `syncLocoStateFromBus` round-trips) are
  addressed because `syncLocoStateFromBus` is no longer called on
  subscribe (viewers don't acquire) and `reclaimSlotOwnership` is
  removed.
- **Viewer state (LocoNet, D8 passive):** `observe()` already emits a
  `LocoObservation` for every `OPC_SL_RD_DATA` it sees on the bus,
  regardless of ownership (`loconet.go:454`), and builds the reverse
  slot→addr map from all slot reads (`slotToAddr`, `loconet.go:1272`).
  So for any vehicle whose slot is read on the bus (by any throttle),
  BigFred gets full speed/dir/F0–F8 state and can attribute subsequent
  `OPC_LOCO_SPD`/`DIRF`. **Accepted trade-off (D8):** a quiet externally-
  driven vehicle whose slot is never read on the bus will show stale
  state until some slot read occurs. No active peek is sent. F9–F28 for
  non-driven locos are not observable on LocoNet anyway (slot data only
  carries F0–F8); this is a pre-existing limitation, unchanged.
- **Z21:** unaffected. Z21 is push-based; viewing = `SubscribeLocoInfo`
  (already separate from driving), no slot concept.
- **Store:** viewers read `LocoStateStore` (in-memory) seeded from Redis
  via `LoadMissingFromRedis`. The store's `ApplyObservation` keeps it
  fresh from the passive observer. `SetSpeedPreservingUser` is used on
  e-stop-then-release so `ControlledByUserID` survives the broadcast
  (Fix B2).
- **Subscription registry:** no longer consulted by the leaser (driver-
  only). It remains the authority for *which sessions receive
  `loco.state` broadcasts*.

## 5.13 Metrics

New OTel counters (extend `pkgs/bigfred/dcc-bus/.../metrics`):

- `slot_leased_total{source}` — per acquire.
- `slot_released_total{reason}` where `reason ∈
  {session_close, idle_timeout, cap_evict, roster_retire,
  train_dissolved, permission_revoked, switcher_change, shutdown,
  boot_reconcile, grace_evict}` (`grace_evict` = D20).
- `slot_release_estop_total` — e-stop-then-release sequences.
- `slot_release_pending_total` — `ReleaseSlot` write failures queued for
  retry (§5.6).
- `slot_no_free_slot_total` — CS-truly-full rejections (D5).
- `slot_budget_exceeded_total` — BigFred over `max_loconet_slots`
  rejections (D14).
- `slot_cap_evict_total` — per-user cap evictions (D6).
- `slot_not_allowed_total` — `Select` rejected by the `CanDrive` gate.
- `slot_active` (gauge) — current driven address count, labelled by
  `source`.
- `slot_budget_used` (gauge) — BigFred's current total leased slot
  count vs `max_loconet_slots` (D14), so Grafana can plot headroom left
  for FREDs.
- `slot_select_total{source}` / `slot_deselect_total{source}` — select
  churn, to monitor switcher-change release frequency.
- `loco_subscribe_cap_total` — subscription-cap drops (D16).
- `slot_diagnostic_subscribers` (gauge) — live diagnostic WS clients
  (D19), to confirm the admin page is not leaking connections.

These let Grafana confirm the keepalive growth from §1 reverses
(`slot_active` ≪ subscribed count) and that release reasons are as
expected.

## 5.14 Tests

- **Unit (`slotlease`):**
  - `Select` then `Deselect` last holder → `ReleaseSlot` called once,
    e-stop sent first.
  - `loco.subscribe` does **not** call `AcquireSlot` (driver-only
    invariant).
  - Per-user cap (single vehicle): 8th `Select` evicts oldest
    non-active; 9th when all are active selects →
    `vehicle_cap_exceeded`.
  - Per-user cap (train, D11): `SelectTrain` that would exceed the cap
    → `vehicle_cap_exceeded` and **no** existing lease e-stopped or
    released.
  - Global LocoNet budget (D14): with `max_loconet_slots = 3` and 3
    leases held by different users, a 4th `Select` →
    `bigfred_slot_budget_exceeded` and **no** `AcquireSlot` call on the
    station (short-circuit).
  - Train lease atomic rollback: inject `ErrNoFreeSlot` on the 3rd member
    → first two released, error returned.
  - `SweepIdle`: remote-only lease past timeout → released; same lease
    with a WS holder → kept; `Touch` resets the timer; observed bus
    activity does **not** reset it (D13).
  - `loco.select` sync ack (D12): ack returns only after `AcquireSlot`;
    on `ErrNoFreeSlot` the ack carries `no_free_slot`.
  - Switcher change: `Select(A)` then `Select(B)` → A released
    (e-stop-then-release), B leased.
  - E-stop-then-release ordering (record calls on a fake station):
    direction is **preserved** from the snapshot (a reversing loco is
    not snapped to forward); e-stop is retried before `ReleaseSlot`; a
    `ReleaseSlot` write failure marks the addr release-pending.
  - Concurrency (§5.3): `Deselect` arriving while `Select` is mid-acquire
    → on acquire completion the slot is released (no orphan); `mu` is
    not held during the bus call (a second `Select` for a *different*
    addr is not blocked by the first's acquire).
  - `CanDrive` gate: `Select` for a vehicle the user may not drive →
    `not_allowed` and **no** `AcquireSlot` call.
  - Subscription cap (D16): subscribing beyond `max_vehicles_per_user`
    → oldest subscription dropped, `subscription_cap` emitted, no slot
    involved.
  - Boot reconciliation (§5.10): at startup, orphan IN_USE slots from a
    prior crash are `ReleaseSlot`-ed before the leaser opens.
  - Budget counts physical CS slots (D14 / §5.20): `external` observer
    leases and grace-window slots increment `Used`; reserve-only does not.
  - D20 (implemented): at budget limit, `ensureBudgetHeadroomLocked`
    evicts up to five newest grace slots (one per attempt) before
    `bigfred_slot_budget_exceeded`.
  - Diagnostic snapshot (D19): `DiagnosticSnapshot()` reflects all
    leases/holders/limits; admin WS rejects non-admin with 403; the
    stream is throttled (a burst of 10 mutations yields ≤ 2 frames/s).
- **Integration (`dcc-bus/cmd`):** WS `subscribe` (no slot) + `select`
  (slot) + `deselect`/switcher (release) + close (release); Z21 drive
  then 60 s idle → `idle_timeout` and slot released.
- **Race:** `-race` on concurrent `Select`/`Deselect`/`SweepIdle`/
  `ReleaseSession`.
- **Existing tests:** update `loconet_slot_test.go` and
  `subscribe`/`estop` tests that assumed `reclaimSlotOwnership` runs
  `ForceAcquireSlot` on subscribe; subscribe no longer acquires, select
  does.

## 5.15 Order of work (slot reservation)

1. Introduce `commandstation.ErrNoFreeSlot` +
   `ErrBigFredSlotBudgetExceeded` + WS codes `no_free_slot` /
   `bigfred_slot_budget_exceeded` (D5/D14) — small, unblocks the rest.
2. Implement `SlotLeaser` with `Select`/`SelectTrain`/`Deselect`/
   `ReleaseSession`/`Touch`/`SweepIdle` + e-stop-then-release (with
   direction preservation, e-stop retry, release-pending), the
   `CanDrive` gate, and the §5.3 concurrency design; unit tests
   (including "subscribe does not acquire").
3. Add `loco.select` / `loco.deselect` / `train.select` WS frames,
   validation, and router handlers (per-request goroutine so the sync
   ack does not head-of-line block the read loop); UI sends
   `loco.select` on switcher change + toast (D17).
4. Wire WS `select`/`deselect`/session-close and Z21/WiThrottle first-
   drive `Select`/`Touch` (D15 no-auto-deselect) through the leaser;
   **remove `reclaimSlotOwnership`** and the subscribe→acquire path
   (this subsumes Fix P2 — see §3 note); seed store from slot reply
   instead of `syncLocoStateFromBus`.
5. Per-user cap (D6/D10/D11) + `max_vehicles_per_user` config + UI
   admin. Single-vehicle `Select` auto-evicts oldest non-active when
   feasible; `SelectTrain` over cap rejects with `vehicle_cap_exceeded`
   (payload carries the user's driven list, D18; no auto-evict).
6. Global LocoNet slot budget (D14) + `max_loconet_slots` config + UI
   admin field (LocoNet-kind only, help text per §5.10) +
   `bigfred_slot_budget_exceeded` WS code; leaser short-circuits
   `AcquireSlot` when `len(leases) >= maxSlots`. **Boot-time slot
   reconciliation (§5.10) before the leaser opens.**
7. Subscription cap (D16) — bound per-session subscriptions by
   `max_vehicles_per_user`; `subscription_cap` error + drop-oldest.
8. Remote idle timeout (D7) + `idle_timeout_secs` config + `SweepIdle`
   (also drains `markReleasePending` orphans from §5.6).
9. Additional release cases R4–R6, R8 (roster retire, train dissolve,
   permission revoke, shutdown).
10. Metrics (§5.13) + Grafana panel updates.
11. Diagnostics slot table UI (D19) — leaser `DiagnosticSnapshot` +
    admin WS endpoint `slots.snapshot` stream + `/admin/dcc-bus/slots`
    page.
12. Re-run load tests; confirm `slot_active`/`slot_budget_used` and
    keepalive rate track actual driving (not subscriptions), and p99
    stays at baseline.
13. **D20 grace eviction under budget pressure (done)** —
    `ensureBudgetHeadroomLocked` before `bigfred_slot_budget_exceeded`;
    unit tests for ordering (newest grace first), minimum evictions, and
    five-attempt cap.
14. **Boot-stop slot hygiene (done in code, verify in prod)** — confirm
    daemon startup no longer leaves one `external` lease per roster loco
    (§5.20).

## 5.16 Open questions (slot reservation)

All slot-reservation questions are resolved (D1–D20). No outstanding
items ahead of D20 implementation.

## 5.17 Why driver-only (reversal of the earlier D3)

The earlier round chose "driver OR subscriber holds the slot" to keep
the current "viewing keeps the slot warm" behaviour. On reflection this
undermined both the perf goal (every subscribed loco keeps a slot +
keepalive, which is exactly the §1 keepalive growth) and the new release
policies (switcher-change / idle release are ineffective while any
viewer subscribes). Since BigFred is authoritative for the vehicles it
drives and the full state already flows to `LocoStateStore` + Redis
(C2b), viewers do not need a command-station slot to see state. Driver-
only therefore:

- collapses the owned-slot set to the driven set (fixes the §1 keepalive
  growth at its source, stronger than Fix P1);
- makes switcher-change release (D4) and idle release (D7) effective;
- makes the per-user cap (D6) a true slot-acquisition bound.

The accepted trade-off (D8) is that a *non-BigFred-driven* vehicle whose
slot is never read on the LocoNet bus may show stale state to viewers.
This is acceptable because (a) actively-driven external locos trigger
slot reads on the bus, and (b) Z21 — the other supported command station
— is push-based and unaffected.

## 5.18 Assumption: exclusive slot ownership (D13)

D13 assumes that once BigFred has reserved a slot for an address (IN_USE
via `AcquireSlot`), a physical throttle such as a FRED cannot attach to
the *same* address and drive it through that slot. Under this assumption
the Q4 scenario (an external FRED driving a BigFred-leased loco while
the remote idle timer runs) does not arise, so the idle timer needs to
react only to remote-originated actions.

Caveat worth recording for implementation: on LocoNet, whether a second
throttle can share an IN_USE slot is **command-station firmware
dependent**. Some masters return the same slot to a second requester
(shared IN_USE, both may write SPD/DIRF); others require an explicit
NULL_MOVE / dispatch handoff. BigFred cannot enforce exclusivity at the
protocol level — it cannot prevent a FRED from sending `OPC_LOCO_ADR`
for an address it has reserved. The chosen idle behaviour (release to
COMMON after remote idle, no reset on observed activity) is safe **if**
the exclusivity assumption holds. If a deployed CS shares slots and a
FRED is actively driving through BigFred's slot when the remote idles
out, BigFred's `ReleaseSlot` (OPC_SLOT_STAT1 COMMON) could disrupt the
FRED. Mitigations to evaluate during implementation:

- Before idle-releasing, check the observer for recent *non-BigFred*
  SPD/DIRF on that addr; if present, defer the release (but cap the
  defer so a slot cannot live forever).
- Treat slot-sharing CS behaviour as an operational constraint documented
  per CS model, and only enable remote idle release on CSes known to
  enforce exclusive IN_USE.

This does not change D13's default; it only scopes where the default is
guaranteed safe.

## 5.19 Diagnostics: live slot table UI (D19)

An admin-only subpage that renders the `SlotLeaser`'s current state in
real time over a dedicated WebSocket, so an operator can verify FRED
headroom, diagnose "why can't I select loco X" (`no_free_slot` /
`bigfred_slot_budget_exceeded` / `vehicle_cap_exceeded`), and watch
idle-timeout releases happen.

**Backend / protocol.**

- A dedicated diagnostic WS endpoint, separate from the dcc-bus throttle
  protocol (§5.11): e.g. `GET /api/admin/dcc-bus/slots/ws` (upgrade).
  Admin-role gated; non-admin → 403. It is read-only — no drive actions
  originate here.
- The leaser exposes:
  ```go
  type LeaseInfo struct {
      Addr          uint16
      Kind          string   // "single" | "train"
      TrainID       string
      Holders       []HolderInfo
      AcquiredAt    int64    // unix ms
      ReleasePending bool    // §5.6 markReleasePending
  }
  type HolderInfo struct {
      UserID      uint
      Session     string    // shortened for display
      Source      string    // "ws" | "z21" | "withrottle"
      LastDriveAt int64     // unix ms; 0 for WS holders
  }
  type SlotsDiagnostic struct {
      MaxPerUser int
      MaxSlots   int        // max_loconet_slots (0 if Z21 / unlimited)
      Used       int        // budgetActiveLocked: CS-occupied slots (D14)
      PerUser    map[uint]int
      Leases     []LeaseInfo
      At         int64
  }
  func (l *Leaser) DiagnosticSnapshot() SlotsDiagnostic
  ```
  Snapshot is taken under the leaser `mu` (cheap; no bus calls).
- Streaming model: the leaser emits on a small `diagCh` (buffered, drop
  if slow) whenever a lease is created/destroyed or a holder is
  added/removed/touched; the diagnostic WS goroutine forwards a
  `slots.snapshot` frame on each event, **throttled to ≤ 2 frames/s** to
  avoid flooding. A 1 s ticker additionally forces a snapshot so
  `lastDriveAt` age / idle-remaining deltas refresh even without lease
  mutations. On connect, the first snapshot is sent immediately so the
  table is populated before any event.

**Frontend.**

- Route: an admin subpage, e.g. `/admin/dcc-bus/slots` (linked from the
  command-station admin section alongside the `max_loconet_slots` /
  `idle_timeout_secs` fields from §5.10).
- Layout:
  - **Header summary:** `Used / MaxSlots` budget bar (D14) with the
    remaining-for-FREDs number; `max_vehicles_per_user` value; total
    active leases; counts by source (`ws`/`z21`/`withrottle`).
  - **Per-user panel:** one row per user with driven-vehicle count vs
    `max_vehicles_per_user`, bar + numeric, sorted descending.
  - **Slot table:** one row per leased addr — addr, kind
    (single/train + trainID), holders (user · source · session-short ·
    idle-since or "—"), acquiredAt (relative), `releasePending` badge.
    Rows whose every holder is a remote past ~80 % of `idle_timeout_secs`
    are highlighted (imminent idle release).
- Reconnect on WS close with backoff; show a "live / stale" indicator
  based on the `At` timestamp (stale if older than ~3 s).

**Operational notes.**

- The page is observability-only; it must not acquire slots or send
  drive commands. A future "admin force-release" button is explicitly
  out of scope for this plan.
- The WS frame is a new admin-only envelope type `slots.snapshot`; it is
  **not** part of the dcc-bus throttle protocol (§5.11) and is not sent
  to throttle sessions.

## 5.20 Implementation progress — observer model and budget fixes (2026-06-30)

Branch `fix/throttle-e2e-reliability`. The original §5 design assumed the
leaser is the **sole** caller of `AcquireSlot`/`ReleaseSlot`. In
production the LocoNet **driver** also acquires slots on `SetSpeed`,
`SendFn` (F0–F8), `EmergencyStop`, and `GetSpeed` without going through
`Select`. The implementation below keeps the leaser as policy/diag
authority while syncing with the driver's physical slot table.

### Architecture (implemented)

| Piece | Location | Role |
|---|---|---|
| `SlotObserver` | `pkgs/loco/commandstation/interface.go` | `OnSlotInUse` / `OnSlotReleased` callbacks |
| LocoNet emits | `loconet.go` (`emitSlotInUse` after `acquireSlot`; `emitSlotReleased` on `clearSlot` / master purge) | Driver → leaser sync |
| `SetSlotObserver(leaser)` | `cmd/router.go` `initLeaser` | Wiring at daemon boot |
| `Reserve` | `slotlease/leaser.go` | Records BigFred holder **without** bus acquire; driver acquires on first `SetSpeed` |
| `Select` | `slotlease/leaser.go` | `Reserve` + synchronous `AcquireSlot` (handset, tests, `loco.select` ack path) |
| `OnSlotInUse` | `slotlease/leaser.go` | Confirms `acquiredAt` on existing lease, or creates **`external`** lease (`userId=0`) |
| `DeselectDeferred` + `SweepDeferred` | `slotlease/leaser.go`, `cmd/select.go` | D4 switcher grace (default 60 s) |
| WS throttle | `DccBusContext.tsx`, `ThrottlePage.tsx` | `loco.select` / `train.select` on drive-target change; `SetSpeed` → `Reserve` |
| Admin diag WS | `ws/slots_diag.go` | `slots.snapshot` stream; **responds `{type:"pong"}` to `{type:"ping"}`** so `useWsConnection` does not reconnect-loop |
| Diag JSON | `slotlease/diagnostic.go` | `holders` always serialised as `[]`, never `null` (grace leases with zero holders) |

### Budget counting (implemented — D14 correction)

`budgetActiveLocked()` counts leases where the slot is **physically on
the CS**:

- `acquiredAt != zero` (confirmed IN_USE), **or**
- `releaseAt != zero` (switcher grace — still IN_USE until `SweepDeferred`).

This includes **`external`** observer leases. It excludes reserve-only
bookings (select without drive yet). The admin page **"Zajęte adresy"**
lists all leases; the **budget bar** uses `Used` from the same counter.

### Boot-stop / estop slot hygiene (implemented)

`applyEStopAll` (daemon startup, shutdown, radio stop) calls
`EmergencyStop` directly, **not** `Reserve`. Previously every roster loco
got `OnSlotInUse` → spurious `external` rows in diagnostics.

**Fix (`loconet_estop.go`):** after sending wire speed 1, if the slot
was **not** already IN_USE on the CS before this call (`heldBefore ==
false` — we had to NULL_MOVE / freshly occupy), call `ReleaseSlot` so
transient acquires do not consume budget or pollute the slot table.
Slots already IN_USE (active drive, physical FRED) are left untouched.

### Diagnostics semantics (for operators)

| Holder display | Meaning |
|---|---|
| `N · ws · session · —` | BigFred user N drives via throttle UI |
| `0 · external · · —` | CS slot IN_USE, leaser has no BigFred holder (e.g. `SendFn`/`GetSpeed` without `Reserve`, or brief observer window before release) — **counts toward budget** |
| empty holders + **Zwolnienie oczekuje** | Switcher grace (D4); slot still IN_USE |

### Tests added

- `loconet_estop_test.go` — transient release vs keep held / CS IN_USE
- `slotlease/leaser_test.go` — `TestBudgetCountsPhysicalSlots`
- `slotlease/diagnostic_test.go` — empty holders JSON array
- `cmd/select_test.go` — deferred deselect + `SweepDeferred`

### Still to do

- Wire `switcher_grace_secs` to config entity (currently hardcoded default in leaser).
- Boot-stop through leaser (optional): `Reserve` with `source=system` if policy needs audit trail.

## 5.21 D20 — grace eviction before budget reject (implemented)

When `Reserve`, `Select`, or `SelectTrain` needs a **new physical slot**
(`needsPhysicalSlot == true`) and `budgetActiveLocked() >= maxSlots`:

1. `ensureBudgetHeadroomLocked` (in `Reserve` / `SelectTrain`) under leaser `mu`:
   - While `budgetActiveLocked() + needed > maxSlots` and fewer than five
     eviction attempts: `takeDeferredReleasesLocked(1)` — collect leases
     with `releaseAt != zero` and no holders, pick the newest `releaseAt`.
   - For each: delete lease, unlock, `stopAndRelease(addr,
     ReleaseGraceEvict)`, re-lock.
2. Re-check `budgetActiveLocked() + needed <= maxSlots`.
3. If still full → `ErrBigFredSlotBudgetExceeded` (unchanged).
4. Else proceed with `Reserve` / acquire as today.

**Invariants:**

- Never evict leases with active BigFred holders (grace leases have zero
  holders by definition).
- Cap eviction (D6) and idle release paths are unchanged — D20 applies
  only to the global budget gate.
- Metric: `slot_released_total{reason="grace_evict"}` (extend §5.13).

**UI:** no change required; freed headroom may allow the pending
`loco.select` to succeed on retry or on the next drive command.
