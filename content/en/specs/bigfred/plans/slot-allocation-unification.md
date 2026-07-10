# Plan: Slot allocation unification and orphaned external lease cleanup

Branch: `feat/slot-allocation-unification`
Date: 2026-07-10

Unify LocoNet slot allocate/release behaviour across UI, Z21, WiThrottle, and
system estop paths; eliminate hanging `external` leases (no user) that block
the `max_loconet_slots` budget; add periodic authoritative reconciliation and
admin manual release from the slots diagnostics page.

---

## 1. Non-technical summary

### Current state

Each locomotive driven through BigFred occupies one command-station slot
(default budget 80). The admin **Slot diagnostics** page shows who drives
which address.

**Problem:** entries labelled `0 · external` appear with **no assigned user**
and never disappear — often after layout-wide e-stop, daemon restart, or a
brief LocoNet disconnect. They consume the slot pool until operators see
"slot budget exceeded" despite nobody driving that many locos.

**Inconsistency:** the web UI releases slots on deselect; Z21 and WiThrottle
do not release on per-loco release (MT− / loco switch) — only on disconnect
or idle timeout.

### Target state

- Orphaned `external` leases are **reclaimed automatically** (periodic
  reconciliation against the physical slot table).
- **Active physical throttles are never yanked** — release only when the
  command station confirms the slot is not IN_USE.
- WiThrottle `MT−` releases slots like WS `loco.deselect`.
- E-stop no longer creates synthetic `external` leases.
- Admins can **manually release** any lease from the diagnostics table.
- **Admin → Slot diagnostics** menu entry links directly to the page.

---

## 2. Technical analysis

Core: `slotlease.Leaser` (`pkgs/bigfred/dcc-bus/slotlease/leaser.go`);
physical slots: LocoNet driver (`pkgs/loco/commandstation/loconet.go`).

`external` leases (`UserID=0`, `source="external"`) are created only in
`OnSlotInUse` when the driver calls `emitSlotInUse` without a matching BigFred
holder. The driver does **not** observe passive bus IN_USE for external FREDs
(despite `SlotObserver` interface wording).

Main generators of hanging `external`:

1. `applyEStopAll` → `EmergencyStop` → `acquireSlotWithHeld` → `emitSlotInUse`;
   when `heldBefore==true` the slot stays IN_USE and the lease persists.
2. Server control commands (`applyControlSetSpeed`) bypass the leaser.
3. Missed `OnSlotReleased` after reconnect / dropped packets — no runtime
   reconciliation (only `ReconcileBootSlots` at boot).

---

## 3. Implementation plan

### Part A — Remove causes

| ID | Change |
|----|--------|
| A1 | `acquireSlotWithHeldNoObserve` in LocoNet; `EmergencyStop` uses it |
| A2 | Document control-path orphans; optional `SuppressExternal` wrapper |
| A3 | `InboundDrivePort.Release` → `leaser.Deselect`; WiThrottle `MT−` |

### Part B — Reconciliation (LocoNet only)

| ID | Change |
|----|--------|
| B1 | `SlotReconciler.SlotStatus(addr)` on LocoNet driver |
| B2 | `Leaser.ReconcileSlots(prober)`; `ReleaseReconcile`; `slotReconcileMaxPerCycle = 16` |
| B3 | `RunSlotReconcile`; `slotReconcileInterval = 60s` constant in `router.go` |

Constants (code, not admin config):

- `slotReconcileInterval = 60 * time.Second` (`cmd/router.go`)
- `slotReconcileMaxPerCycle = 16` (`slotlease/leaser.go`)

### Part C — Docs / contract

- Align `SlotObserver` comment with implementation.
- Update `docs/content/en/guides/admin/slots.md` and `slotlease/README.md`.

### Part D — Admin UI

| ID | Change |
|----|--------|
| D1 | `Leaser.ForceRelease(addr)`; `POST /admin/slots/release`; server proxy |
| D2 | Release button + confirm dialog on `SlotsDiagnosticsPage` |
| D3 | Menu: Administration → Slot diagnostics → `/admin/dcc-bus/slots` |

---

## 4. Detailed diffs

See branch `feat/slot-allocation-unification` for the authoritative code
changes. Key files:

- `pkgs/loco/commandstation/loconet.go`, `loconet_estop.go`, `interface.go`
- `pkgs/bigfred/dcc-bus/slotlease/leaser.go`, `reason.go`
- `pkgs/bigfred/dcc-bus/cmd/router.go`, `handset_port.go`, `daemon.go`
- `pkgs/bigfred/dcc-bus/ws/slots_diag.go`, `handler.go`
- `pkgs/bigfred/server/http/dcc_bus_slots_proxy.go`, `router.go`
- `pkgs/bigfred/remotes/drive.go`
- `pkgs/bigfred/dcc-bus/withrottle/adapter.go`
- `web/src/pages/admin/SlotsDiagnosticsPage.tsx`, `AppShell.tsx`

---

## 5. Tests

- `leaser_test.go`: reconcile drop/keep/limit/race; `ForceRelease`
- `slots_diag_test.go`: `ServeRelease` auth and body validation
- `loconet_estop_test.go`: estop does not create external lease (regression)

---

## 6. Risks

- Z21 has no slot table — reconciliation is a no-op.
- Bus traffic bounded by lease-only probes + 16/cycle + 60s interval.
- Manual release e-stops the loco before releasing the slot.
