# 1. Overview and boot init

BigFred OS is a **minimal Linux image** for the club layout hub. It is not a
general-purpose desktop distribution: there is no package manager on the device,
no cloud agents, and **no dependency on Internet access** after the image is
flashed.

The reference implementation lives in the [`bigfred-os`](https://github.com/dcc-bigfred/bigfred-os)
repository under `os/` (Buildroot external) and `apps/` (hub binaries).

## 1.1 Target hardware

| Item | Choice |
|------|--------|
| **Board** | **Raspberry Pi 5** (64-bit, `bcm2712`) |
| **Boot medium** | **microSD** (endurance class) or **NVMe** via M.2 HAT+ — same three-partition layout |
| **Cooling** | Pi 5 active cooler; `fanctl` adjusts speed by SoC temperature |
| **Network** | Wired Ethernet (`eth0`) on the club LAN — static or DHCP via `configure-ethernet` |
| **USB** | Uhlenbrock 63120 LocoNet adapter (when using `loconet_serial` command stations) |

The defconfig `configs/bigfred_hub_rpi5_defconfig` pins the toolchain to
**aarch64 + musl**, enables **eudev**, and ships **BusyBox** as PID 1. Kernel
fragments in `configs/linux-hub.fragment` add **PREEMPT_RT**, ext4, and USB-ACM
support.

BigFred application binaries (`loco-server`, `dcc-bus`, embedded `web/dist`) are
**not** part of the base image build; clubs install them separately (see
[Hardware §8.10](../hardware/08-hub-os-image.md#810-building-the-image)).

## 1.2 Offline operation

| Phase | Internet |
|-------|----------|
| **Image build** (developer CI or club workstation) | May use the network to download Buildroot sources, kernel tarballs, and prebuilt Grafana/VictoriaMetrics packages |
| **Hub runtime** | **Not required** — all OS packages and hub UI assets are on local storage |

At runtime the hub only talks to devices on the **club LAN** (command stations,
operator browsers, optional metrics consumers). There are no runtime `wget`,
CDN font loads, or package updates on the device. The admin UI
(`bigfred-os-ui`) follows the same offline-asset rules as the main BigFred SPA
([§7b](../bigfred/architecture/09b-offline-assets.md)).

## 1.3 Storage model: read-only root, read-write `/data`

Power-loss tolerance and simple upgrades rely on splitting **immutable system
files** from **mutable state**.

```text
┌─────────────────────────────────────────────────────────────┐
│  Boot medium (microSD or NVMe) — three partitions           │
├──────────────┬──────────────────────┬─────────────────────────┤
│  p1 /boot    │  p2 /  (rootfs)      │  p3 /data               │
│  FAT32, RW   │  ext4, READ-ONLY    │  ext4, READ-WRITE       │
│  firmware,   │  /usr, /etc,        │  SQLite, Redis, logs,   │
│  kernel, DTB │  /sbin, BusyBox    │  Grafana/VM data,       │
│              │  init scripts        │  operator config        │
└──────────────┴──────────────────────┴─────────────────────────┘

  tmpfs: /tmp, /var/log, /var/run  (ephemeral — lost on reboot)
```

### Kernel and `fstab`

The kernel mounts root **read-only** from the start:

```text
# os/board/bigfred_hub/cmdline.txt (excerpt)
root=/dev/nvme0n1p2 rootfstype=ext4 ro rootwait …
```

`os/overlays/etc/fstab` declares the persistent data partition and volatile
mounts:

```fstab
/dev/nvme0n1p2  /       ext4  ro,noatime           0  1
/dev/nvme0n1p3  /data   ext4  rw,noatime           0  2

tmpfs           /tmp      tmpfs  defaults,size=64m   0  0
tmpfs           /var/log  tmpfs  defaults,size=64m   0  0
tmpfs           /var/run  tmpfs  defaults,size=16m   0  0
```

`S10-mount` runs `mount -a`, then **`mount -o remount,ro /`** so the root
filesystem stays read-only even if an earlier step mounted it read-write.

### Boot device names

The reference overlay uses **`/dev/nvme0n1p*`** because the default hub build
expects root on **NVMe**. When the same image layout is used on **microSD** only,
replace device nodes with **`/dev/mmcblk0p*`** in `cmdline.txt` and `fstab`
(boot = p1, root = p2, data = p3). The partition **roles** are identical; only
the block-device path changes.

### What lives on `/data`

`S10-mount` creates the directory tree expected by hub services:

| Path | Purpose |
|------|---------|
| `/data/etc/` | Operator-editable config (`bigfred-os-ui.conf`, `redis.conf`, `configure-ethernet.conf`, …) |
| `/data/sqlite/` | `loco-server` database (when BigFred is installed) |
| `/data/redis/` | Redis RDB / working files |
| `/data/alloy/` | Grafana Alloy state (optional) |
| `/data/opt/grafana/` | Grafana data, logs, plugins |
| `/data/opt/victoriametrics/` | VictoriaMetrics time-series storage |
| `/data/logs/<service>/` | Persistent rotated logs (`bigfred`, `redis`, `alloy`, …) |

On **first boot**, if `/data/etc/bigfred-os-ui.conf` is missing, `S10-mount`
seeds it from the read-only template `/etc/bigfred/bigfred-os-ui.conf`
(`post-build.sh` installs the template). The same applies to
`/data/etc/redis.conf` from `/etc/redis/redis.conf` (RDB `save 60 100`,
`appendonly no`).

If partition p3 is empty, `S10-mount` may **`mkfs.ext4 -L bigfred-data`**
before mounting (factory-fresh flash).

## 1.4 Init: from firmware to services

BigFred OS uses **BusyBox `init`** — not systemd. The boot chain is short and
deterministic.

```mermaid
flowchart TD
  FW[Raspberry Pi firmware] --> K[Linux kernel]
  K --> INIT[BusyBox init PID 1]
  INIT --> RCS[/etc/init.d/rcS]
  RCS --> S05[S05-cron]
  S05 --> S10[S10-mount]
  S10 --> S15[S15-network]
  S15 --> S20[S20-sysctl]
  S20 --> S30[S30-redis]
  S30 --> S35[S35-victoriametrics]
  S35 --> S40[S40-alloy]
  S40 --> S42[S42-grafana]
  S42 --> S48[S48-bigfred-os-ui]
  S48 --> S50[S50-fanctl]
  S50 --> S90[S90-dropbear]
  S90 --> S95[S95-watchdog]
  INIT --> GETTY[getty tty1 + ttyAMA10]
```

### 1.4.1 `inittab`

File: `os/overlays/etc/inittab`

| Line | Action |
|------|--------|
| `::sysinit:/etc/init.d/rcS` | Run all `S??*` scripts once at boot |
| `::respawn:…getty…tty1` | Local console |
| `::respawn:…getty…ttyAMA10` | Serial console (115200) |
| `::shutdown:…umount -a -r` | Clean unmount on shutdown |

### 1.4.2 `rcS`

File: `os/overlays/etc/init.d/rcS`

Iterates `/etc/init.d/S??*` in **lexicographic order** and invokes each
executable script with the `start` argument. This is standard SysV-style
ordering by numeric prefix.

### 1.4.3 Boot scripts (`S05` … `S95`)

All scripts live in `os/overlays/etc/init.d/`. They use `start-stop-daemon`
where a long-running daemon is needed.

| Script | Order | Role |
|--------|-------|------|
| **`S05-cron`** | 1 | Starts BusyBox `crond` (`/etc/crontabs/root` — nightly `rotate-hub-logs`) |
| **`S10-mount`** | 2 | `mount -a`; mount or format **`/data`**; create data dirs; seed `/data/etc/`; **remount `/` read-only** |
| **`S15-network`** | 3 | Runs `/usr/sbin/configure-ethernet` — static club IP or DHCP; no cloud |
| **`S20-sysctl`** | 4 | Applies `/etc/sysctl.d/*.conf` (`sched_rt_runtime_us`, `swappiness`); sets **performance** cpufreq governor |
| **`S30-redis`** | 5 | `redis-server /data/etc/redis.conf` — RDB `save 60 100`, data dir `/data/redis`, pinned to CPUs **0–1** |
| **`S35-victoriametrics`** | 6 | VictoriaMetrics on `:8428`, storage `/data/opt/victoriametrics` |
| **`S40-alloy`** | 7 | Grafana Alloy (optional package) — skips if binary absent |
| **`S42-grafana`** | 8 | Grafana OSS — data under `/data/opt/grafana` |
| **`S48-bigfred-os-ui`** | 9 | Hub admin UI on `:8090`, config `/data/etc/bigfred-os-ui.conf` |
| **`S50-fanctl`** | 10 | Pi 5 fan policy daemon |
| **`S90-dropbear`** | 11 | SSH for on-site administration |
| **`S95-watchdog`** | 12 | Kernel watchdog (`/dev/watchdog`) — reboot on hang |

**Not enabled in the base image:** `S60-bigfred` (`loco-server` + `dcc-bus`).
An example stub ships as `S60-bigfred.example`; rename and edit after installing
BigFred binaries (see [Hardware §8.3](../hardware/08-hub-os-image.md#83-boot-sequence)).

### 1.4.4 CPU affinity

Kernel **cmdline** isolates CPUs **2–3** for low-jitter workloads:

```text
isolcpus=2,3 nohz_full=2,3 rcu_nocbs=2,3 irqaffinity=0,1 rcu_nocb_poll
```

Init scripts pin **housekeeping** daemons to CPUs **0–1** with `taskset -cp 0,1`
(Redis, VictoriaMetrics, Grafana, Alloy, `bigfred-os-ui`). When `S60-bigfred` is
enabled, `loco-server` and `dcc-bus` should run on **`taskset -c 2,3`**
([Hardware §8.6](../hardware/08-hub-os-image.md#86-preempt_rt-kernel)).

### 1.4.5 Shutdown

On `reboot` or `poweroff`, BusyBox init runs `umount -a -r` from `inittab`.
`S10-mount stop` unmounts `/data` when init scripts are invoked with `stop`
(manual service restart uses per-script `stop`/`start`).

## 1.5 Image layout vs runtime

`post-image.sh` assembles **`hub-nvme.img`** with **genimage**:

| Partition | Content |
|-----------|---------|
| **boot** (FAT32, 64 MiB) | `Image`, DTBs, `config.txt`, `cmdline.txt`, Pi firmware blobs |
| **root** (ext4) | Buildroot root filesystem — mounted **RO** at runtime |
| **data** (ext4, 512 MiB initial) | Pre-created empty tree under `TARGET_DIR/data` |

Flash with `scripts/flash-nvme.sh` or `dd` to the target block device. The
symlink `output/images/sdcard.img` points at the same image file for
microSD writers.

## 1.6 Operator-facing services after boot

When all `S*` scripts complete, a typical hub exposes:

| Service | Port | Notes |
|---------|------|-------|
| `bigfred-os-ui` | **8090** | Logs / admin (credentials in `/data/etc/bigfred-os-ui.conf`) |
| Grafana | **3000** | Default admin password from image build (`bigfred` in defconfig — change before deploy) |
| VictoriaMetrics | **8428** | Grafana datasource |
| Redis | **6379** | Loopback only |
| Dropbear SSH | **22** | Root login enabled in defconfig — change password via `make menuconfig` |

Exact URLs and credentials belong in the club runbook, not in the image alone.

## 1.7 Summary

BigFred OS on Raspberry Pi 5 is an **offline-capable**, **read-only root**
image with all mutable state on **`/data`**. **BusyBox init** runs a fixed
sequence of **`S05`–`S95` scripts**: mount persistent storage, bring up the
LAN, tune the kernel for RT workloads, start Redis and observability stack,
launch the hub admin UI, and enable SSH and the hardware watchdog. BigFred
application processes slot in at **`S60-bigfred`** once their binaries are
installed.

Next chapters (planned): Buildroot workflow, overlay customization, hub apps,
and integration with `loco-server` / `dcc-bus`.

[Back to BigFred OS index](./README.md)
