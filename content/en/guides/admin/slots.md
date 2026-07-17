# Slots

BigFred tracks **who may drive which locomotive address** through the
**leaser** (`slotlease`) in every `dcc-bus` daemon. Behaviour on the
**physical command station** depends on the station kind:

| | **LocoNet** | **Z21** |
|---|-------------|---------|
| Slot table on the central | Yes (~117 entries, IN_USE / COMMON) | **No** — Z21 is push/pull over LAN |
| Physical slot acquire/release | LocoNet driver (`AcquireSlot` / `ReleaseSlot`) | Not applicable |
| Global slot budget (`max_loconet_slots`) | Yes (default 80) | **Not used** (unlimited in leaser) |
| Per-user driven cap | Yes (default 8) | Yes |
| Remote idle timeout | Yes | Yes |
| Slot diagnostics page | Budget + occupied addresses | Lease table only (no slot budget bar) |

Plain **`loco.subscribe` (view only) never creates a drive lease** — on any
station kind.

---

## LocoNet

Two layers:

| Layer | Role |
|-------|------|
| **Leaser** | Holders, per-user cap, global budget, diagnostics |
| **LocoNet driver** | Occupies / releases the slot on the central (NULL MOVE → IN_USE) |

**The driver reserves the slot on the central** when a user with drive
permission sends a drive command. The leaser only enforces policy and mirrors
state via `SlotObserver`.

### When a slot is taken (LocoNet)

| Action | Leaser | Driver |
|--------|--------|--------|
| **`loco.select`** (WS throttle) | Holder + optional `AcquireSlot` | IN_USE after select |
| First **`loco.setSpeed`** | `Reserve` | Acquire on `SetSpeed` / `SendFn` F0–F8 |
| **`train.select`** | Holder per powered member | Acquire per member |

Rejected if **CanDrive** fails, **`max_loconet_slots`** is full
(`bigfred_slot_budget_exceeded`), **`max_vehicles_per_user`** is exceeded
(`vehicle_cap_exceeded`), or — when **`allocate_physical_slots`** is on — the
loco is already IN_USE by another throttle (`slot_in_use`).

### When a slot is released (LocoNet)

| Situation | Timing |
|-----------|--------|
| **WS switcher** A→B | Holder removed; slot stays IN_USE **~60 s** (grace), then e-stop + `ReleaseSlot`. Re-select A in grace reuses the slot. |
| **`loco.deselect`**, session close, shutdown | E-stop + release **immediately** |
| **Per-user cap eviction** | **Immediate** |
| **Boot-stop** on idle roster locos | Brief acquire for stop only; **released** if slot was not already IN_USE |

WS-selected locos are **not** idle-released.

Z21 / WiThrottle rows in the table below apply when the **command station
is LocoNet** (remote drives that station's bus).

---

## Z21

The Z21 central has **no LocoNet-style slot table**. BigFred still uses the
**same leaser** for bookkeeping: who drives which address, caps, idle timeout,
and diagnostics.

There is **no `AcquireSlot` / `ReleaseSlot`** on Z21. A “lease” in the admin
table means **BigFred considers this user/session to be driving this address**
— not an IN_USE row on a slot table.

### When a lease is created (Z21)

| Action | Leaser | Z21 driver |
|--------|--------|------------|
| First **speed or function** from Z21 app / WiThrottle | `Select` + `Touch` (`source=z21` or `withrottle`) | Forwards DCC command to the central |
| **`GET_LOCO_INFO`** (pick loco in app) | **No lease** — subscribe/view only |
| **WS throttle** on a Z21 layout | Same as LocoNet leaser paths (`loco.select` / `Reserve`) | Z21 `SetSpeed` / functions only |

`prepareHandsetLease` runs on the first drive packet per address per handset
session. Switching to another loco in the Z21 app **does not auto-deselect**
the previous one (D15): each address driven recently stays leased until
**idle timeout** or disconnect.

### When a lease ends (Z21)

| Situation | Effect on central | Leaser |
|-----------|-------------------|--------|
| **Idle timeout** (`idle_timeout_secs`, default 60 s) | E-stop via Z21 LAN | Lease removed |
| **Handset disconnect** | — | `ReleaseSession` → e-stop affected addrs |
| **Per-user cap eviction** | E-stop evicted addr | Lease removed |
| **WS `loco.deselect` / session close** | E-stop | Lease removed (no slot grace — nothing to keep IN_USE on the central) |

There is **no `max_loconet_slots`** check on Z21 — the limit is only how
many addresses a user may **drive at once** (`max_vehicles_per_user`).

### Z21 vs LocoNet remotes on the same layout

If the layout's command station is **LocoNet**, Z21/WiThrottle clients are
not used on that bus. If it is **Z21**, LocoNet slot rules do not apply;
only leaser caps and idle timeout matter.

---

## Shared limits (configuration)

**Admin → Command stations:**

| Setting | LocoNet | Z21 |
|---------|---------|-----|
| **`max_loconet_slots`** | Max IN_USE slots through BigFred (default 80) | Hidden / N/A |
| **`allocate_physical_slots`** | Exclusive PE 1.0 allocation like a physical FRED (default **on**). Off = legacy piggyback on a FRED-held slot | Hidden / N/A |
| **`idle_timeout_secs`** | Remote idle release (default 60 s; 0 = off) | Same |
| **`max_vehicles_per_user`** (layout) | Max driven vehicles per user (default 8) | Same |

---

## Diagnosing in the UI

1. **Admin → Command stations**
2. **Slot diagnostics** (gauge icon) on the row  
   → **`/admin/dcc-bus/slots?cs=<id>`**

| Panel | LocoNet | Z21 |
|-------|---------|-----|
| **Slot budget** | `used / max_loconet_slots` | “Active leases (no LocoNet budget)” |
| **Per user** | Driven count vs cap | Same |
| **Occupied addresses** | Holders (`user · z21 · ws · …`) | Same; `z21` / `withrottle` = physical remote |

Status: **Live** / **Stale** / **Disconnected**.

On **LocoNet**, holder `0 · external` = driver reported IN_USE without a
BigFred holder; counts toward the budget.
