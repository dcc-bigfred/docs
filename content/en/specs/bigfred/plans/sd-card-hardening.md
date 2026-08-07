# Plan: BigFred OS SD-card wear reduction and embedded durability

**Status:** implemented (2026-08-07)
**Repos:** `bigfred-os`, `bigfred`, `docs`
**Related spec:** [`../architecture/EMBEDDED.md`](../architecture/EMBEDDED.md)

## Goal

Minimise writes to the hub microSD card (base configuration without NVMe)
so that unexpected power loss is less likely to corrupt the card or leave
the system in an inconsistent state. BigFred must still persist operator
catalogue data in SQLite; Redis may flush less often. Logs should not wear
flash when NVMe is absent.

## Design decisions

| Area | Decision | Rationale |
|------|----------|-----------|
| `/data` ext4 | `rw,noatime,commit=15` | Batch journal flushes (~15 s); avoids stacking 60 s windows with SQLite/Redis |
| Kernel writeback | `vm.dirty_*_centisecs=1500` | Align dirty-page flush with `commit=15` |
| Service logs | tmpfs 64 MiB on `/data/logs` | RAM-backed; lost on reboot; no SD wear |
| SQLite | WAL + `synchronous=NORMAL` | fsync mainly at checkpoint; acceptable loss of last ~15 s of commits on hard power cut |
| Redis | RDB `save 120 100`, AOF off | Ephemeral hub state; SQLite is source of truth |
| VictoriaMetrics | `RETENTION_PERIOD=3d`, flush `10m` | Cap metrics footprint and disk writes |
| Swap | `vm.swappiness=0` | No swap traffic to SD |
| Multi-table writes | `repo.WithTransaction` | Prevent partial catalogue state on power loss |

NVMe is optional: when present, `/data` may live on NVMe after
`prepare-nvme` migration; log tmpfs and write-reduction tuning still apply.

## Implementation — BigFred OS (`bigfred-os`)

### Filesystem and boot

| File | Change |
|------|--------|
| `os/overlays/etc/microinit/early-boot.sh` | `_data_opts="rw,noatime,commit=15"` on all `/data` mount paths; tmpfs `/data/logs` 64 MiB; explicit WARNING if tmpfs mount fails; `remount,rw,noatime,commit=15` after successful `prepare-nvme` |
| `os/overlays/etc/microinit/unmount.sh` | `umount /data/logs` before `/data` |
| `os/overlays/etc/fstab` | `/var/log` tmpfs reduced 64m → 16m (app logs under `/data/logs`) |

### Kernel

| File | Change |
|------|--------|
| `os/overlays/etc/sysctl.d/97-bigfred-writeback.conf` | **new** — `vm.dirty_writeback_centisecs`, `vm.dirty_expire_centisecs` = 1500; `vm.dirty_background_ratio` = 5; `vm.dirty_ratio` = 15 |
| `os/overlays/etc/sysctl.d/99-bigfred-latency.conf` | `vm.swappiness` 10 → 0 |

### Redis

| File | Change |
|------|--------|
| `os/overlays/etc/redis/redis.conf` | `save 120 100`; `rdbcompression yes`; `stop-writes-on-bgsave-error no` |
| `os/overlays/etc/init.d/redis` | Inline heredoc aligned with `redis.conf` |

### Observability stack

| File | Change |
|------|--------|
| `os/overlays/etc/grafana/grafana.ini` | `[paths] logs = /data/logs/grafana`; `[log] mode = file`, `level = warn` |
| `os/overlays/etc/alloy/config.alloy` | log `level` info → warn |
| `os/overlays/etc/default/victoriametrics` | `RETENTION_PERIOD=3d`; `INMEMORY_DATA_FLUSH_INTERVAL=10m` |
| `os/board/bigfred_hub/post-build.sh` | Grafana log dir → `/data/logs/grafana` |

### Log rotation and cron

| File | Change |
|------|--------|
| `os/overlays/etc/crontabs/root` | `rotate-hub-logs` hourly; `fake-hwclock` every 30 min |
| `apps/rotate-hub-logs/main.go` | `defaultRotateSize` 5 MiB; `defaultMaxBytes` 32 MiB (.gz); `defaultTotalBytes` 56 MiB (.log + .gz); `--total-bytes` flag; `enforceMaxTotal()` prunes oldest `.gz` when combined size exceeds budget |

### Diagnostics

| File | Change |
|------|--------|
| `os/configs/bigfred_hub_rpi5_defconfig` | `BR2_PACKAGE_IOTOP=y` |

## Implementation — loco-server (`bigfred`)

### SQLite connection and lifecycle

| File | Change |
|------|--------|
| `pkgs/bigfred/server/repo/db.go` | DSN pragmas: `synchronous(NORMAL)`, `wal_autocheckpoint(2000)`, `journal_size_limit(16777216)`, `mmap_size(33554432)`; `WithTransaction` helper |
| `pkgs/bigfred/server/cli/root.go` | `EndAllStale` on startup after migrate; `PRAGMA wal_checkpoint(TRUNCATE)` before shutdown |
| `pkgs/bigfred/server/repo/interlocking_sessions.go` | `EndAllStale` — close `ended_at IS NULL` sessions after crash |

### Transactional command layer

Multi-step catalogue operations wrapped in `repo.WithTransaction`:

| Package / file | Operations |
|----------------|------------|
| `cmd/train.go` | create/update/delete with members; `DeleteAll` cascade |
| `cmd/vehicle.go` | cascade delete with roster/functions |
| `cmd/user.go` | create/update with DCC pool rows |
| `cmd/dcc_pool.go` | pool replace |
| `cmd/layout.go` | create/update/delete with command stations, interlockings, roster |
| `cmd/command_station.go` | settings + related rows |
| `cmd/interlocking.go` | settings cascade |
| `cmd/interlocking_occupancy.go` | join/leave session + presence |
| `repo/layout_vehicles.go`, `repo/layout_signalmen.go` | `DeleteAllForLayout` helpers |

HTTP delete handlers (`http/vehicles.go`, `http/trains.go`) call transactional
`DeleteAll` and broadcast roster **after** commit.

## Implementation — documentation (`docs`)

| File | Change |
|------|--------|
| `content/en/specs/bigfred/architecture/EMBEDDED.md` | **new** — normative embedded guidelines (durability model, transactions, logging, shutdown, anti-patterns, PR checklist) |
| `content/en/specs/bigfred/architecture/README.md` | TOC entry for EMBEDDED |
| `content/en/specs/bigfred/plans/sd-card-hardening.md` | this plan |

## Code review follow-ups (resolved)

### bigfred-os Bugbot

1. **High — tmpfs cap vs rotation budget:** `defaultMaxBytes` only capped `.gz`
   archives; active `.log` files could fill the 64 MiB tmpfs before hourly
   rotation. **Fix:** `defaultTotalBytes=56 MiB` with `enforceMaxTotal()`;
   `defaultMaxBytes` lowered to 32 MiB.

2. **Medium — silent tmpfs mount failure:** `mount ... || true` hid failures.
   **Fix:** explicit `WARNING` lines with captured stderr; boot continues
   (logs are non-fatal).

3. **Medium — NVMe migration dropped `commit=15`:** `prepare-nvme` remounted
   `/data` with `rw,noatime` only until next reboot. **Fix:** remount with
   `commit=15` immediately after successful migration.

### bigfred Bugbot

No issues found in application changes.

### docs Bugbot

**Low — README TOC blurb misplaced:** offline-assets summary under EMBEDDED
entry. **Fix:** restored correct section placement.

## Durability model (summary)

| Mount | Mode | Loss on hard power cut |
|-------|------|------------------------|
| `/` | RO ext4 | N/A |
| `/data` | RW ext4 `commit=15` | Up to ~15 s of fully committed SQLite/Redis/VM data |
| `/data/logs`, `/tmp`, `/var/log` | tmpfs | All volatile logs |
| Redis leases / takeover | Redis RDB ~120 s | Re-claimable ephemeral state |

**Acceptable:** loss of recent commits and ephemeral Redis state.
**Unacceptable:** torn multi-table SQLite catalogue writes — prevented by
transactions and startup stale-session cleanup.

## Verification checklist

- [ ] Boot hub without NVMe: `mount | grep data` shows `commit=15`; `/data/logs` is tmpfs 64m
- [ ] `sysctl vm.dirty_writeback_centisecs` → 1500; `vm.swappiness` → 0
- [ ] `redis-cli CONFIG GET save` → `120 100`
- [ ] Create train with members, yank power mid-request → no orphan members after reboot
- [ ] `iotop -ao` during normal operation — confirm logs not hitting mmcblk0p3
- [ ] Graceful shutdown: `PRAGMA wal_checkpoint` in loco-server logs; clean unmount

## Out of scope / future work

- Persistent logs on NVMe-only profile (current plan uses tmpfs on `/data/logs` for all configs)
- `prepare-nvme` script itself emitting `commit=15` on remount (handled in `early-boot.sh` post-hook)
- Hardware RTC to reduce `fake-hwclock` writes further
