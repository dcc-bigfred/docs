# BigFred — embedded environment guidelines (EMBEDDED)

BigFred OS runs on a Raspberry Pi 5 with a microSD card (optional NVMe).
Root is read-only, logs live on tmpfs, and `/data` (ext4) holds SQLite,
Redis, and TSDB state. Power can be cut at any moment — application code
must remain correct under that failure mode.

This document is **normative** for PRs that touch persistence, logging, or
background I/O in `pkgs/bigfred`.

## 1. Storage and durability model

| Mount | Mode | Contents |
|-------|------|----------|
| `/` (ext4) | RO | `/usr`, `/etc`, init scripts |
| `/data` (ext4) | RW, `noatime,commit=15` | SQLite WAL, Redis RDB, VictoriaMetrics, Grafana data, operator config |
| tmpfs | RAM | `/tmp`, `/var/log`, `/run`, `/data/logs`, `/home/bigfred` |

- Kernel dirty-page flush is aligned to ~15s (`vm.dirty_*_centisecs=1500`).
- SQLite: `WAL` + `synchronous=NORMAL` (fsync mainly at checkpoint).
- Redis: RDB only, `save 120 100` (up to ~120s loss of session state).
- VictoriaMetrics: retention `3d`, in-memory flush `10m`.

**Acceptable loss:** the last ~15s of *fully committed* operator catalogue
actions on hard power loss.

**Unacceptable:** half-written multi-table catalogue state (partial
transaction).

## 2. SQLite transactions — primary rule

**Every action that writes to more than one SQLite table, or loops
inserts/updates/deletes across multiple rows, MUST run inside
`repo.WithTransaction(ctx, db, fn)`.**

Do:

```go
err := repo.WithTransaction(ctx, t.db, func(tctx context.Context) error {
	if err := t.trains.Insert(tctx, &row); err != nil {
		return err
	}
	return t.replaceMembers(tctx, row.ID, in.Members)
})
```

Don't (each statement auto-commits → partial write on power loss):

```go
if err := t.trains.Insert(ctx, &row); err != nil {
	return err
}
if err := t.replaceMembers(ctx, row.ID, in.Members); err != nil {
	return err
}
```

Checklist for SQLite-changing handlers:

- [ ] Writes span >1 table → wrapped in `WithTransaction`
- [ ] Join wipe + parent delete → same transaction
- [ ] Roster / `dcc_functions` purge → same transaction as catalogue delete
- [ ] Broadcast / Redis / pub-sub → **after** successful commit
- [ ] Reads / validation / auth → outside the transaction when possible

Single-row Insert/Update/Delete is already atomic; no wrapper required.

## 3. SQLite vs Redis vs command station

| Data | Store | Notes |
|------|-------|-------|
| Catalogue (users, vehicles, trains, layouts, CS, functions) | SQLite | Source of truth; transactional |
| Leases, sudo, takeover, remote pairing | Redis | Ephemeral; re-claim after reboot |
| Decoder speed / function state | Command station | Independent of hub DB |
| Audit, radio, presence | Redis streams / memory | Best-effort |

Do **not** put hot runtime throttle state in SQLite. Prefer Redis when the
value can be rebuilt from the catalogue or reclaimed by an operator.

On boot, loco-server rebuilds Redis roster snapshots from SQLite and ends
stale interlocking sessions (`ended_at IS NULL`).

## 4. Logging and diagnostics

- Application logs → `/data/logs/<service>/` (tmpfs; lost on reboot).
- Prefer `warn`+ on hot paths (`dcc-bus`, throttle). Avoid chatty `info`
  in loops.
- Temporary files → `/tmp` (tmpfs), never `/data`.
- On-device write diagnosis: `iotop -ao`, `iostat -x 1`.

## 5. Shutdown and startup

- SIGTERM → HTTP drain (~10s) → `PRAGMA wal_checkpoint(TRUNCATE)` →
  `sqlDB.Close()`.
- Startup → `MigrateUp` → `EndAllStale(interlocking_sessions)` →
  `SyncLayoutRosterToRedis`.
- Any new resource that can leave “open” rows after a crash MUST have a
  matching startup cleanup.

## 6. Anti-patterns

- `PRAGMA synchronous=OFF` — risk of corruption on power loss.
- Mounting `/data` with `data=writeback` or disabling the ext4 journal —
  weakens crash safety for SQLite/Redis.
- Swap on the SD card — wears flash; fails with RO root.
- Persistent high-rate logs under `/data/var/lib/...`.
- Background telemetry or polling writers into SQLite.

## 7. PR checklist (embedded)

- [ ] Multi-step SQLite writes use `repo.WithTransaction`
- [ ] Crash leftovers have a startup cleanup
- [ ] New logs / temp files land on tmpfs, not durable `/data` paths
- [ ] New Redis state is re-claimable after reboot (or documented as best-effort)
- [ ] No new continuous SQLite writers (telemetry, heartbeats)
- [ ] No N× auto-commit loops without a surrounding transaction
