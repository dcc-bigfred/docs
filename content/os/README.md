# BigFred OS

Documentation for **BigFred OS** — the reference operating-system image for a
**Raspberry Pi 5** layout hub. The image is built from the
[`bigfred-os`](https://github.com/dcc-bigfred/bigfred-os) repository (Buildroot
external tree) and is designed for **offline club LANs**: no Internet access at
runtime on the hub itself.

## Chapters

1. [Overview and boot init](./01-overview-and-init.md) — target hardware,
   read-only root with persistent `/data`, offline operation, BusyBox init
   and `S*` boot scripts

## Related documentation

- [Hardware §8 Hub OS image](../hardware/08-hub-os-image.md) — design goals,
  PREEMPT_RT, CPU isolation, storage sizing, and verification checklist
- [BigFred architecture §7b Offline assets](../bigfred/architecture/09b-offline-assets.md) —
  SPA assets bundled at build time (applies to `bigfred-os-ui` on the hub)

## Source repository

| Path | Role |
|------|------|
| `bigfred-os/os/` | Buildroot `BR2_EXTERNAL` — kernel, defconfig, overlays |
| `bigfred-os/os/overlays/` | `fstab`, `inittab`, `init.d/S*`, Redis/Grafana configs |
| `bigfred-os/apps/` | Hub Go binaries (`bigfred-os-ui`, `fanctl`, …) |

Build artefact: `os/output/images/hub-nvme.img` (symlink `sdcard.img`).
