# RailBOX RB 2112 — Configuration Reference

Reference documentation for RailBOX **RB 2112** (and related **RB 21x0** / **RB 2110**) DCC **function-car** decoders for wagon lighting and accessories. This document is **not** tied to the BigFred or Loco runtime; it is intended as a future data source for decoder configuration.

| Item | Value |
|------|-------|
| Source | [RB 2112 manual (PDF)](https://www.railbox.pl/_files/ugd/6c739b_070e417f62084a31b67f5e4d6ae61a0d.pdf) (RailBOX) |
| Models | **RB 2112** and family variants — 13-output (RailCom®), 14-output, 21MTC (12 + 2 via jumper) |
| Scope | Wagon lighting, output mapping, brightness, lighting effects, RailCom® easy configuration |

**Decoder highlights:** DCC (NMRA) and **DCC S-9.2.1.1**, up to **14** function outputs (**125 mA** each), direction recognition (including analog), per-output brightness and effects, output-to-function mapping via CV bit tables, optional **RailCom®** auto-detection with RailBOX: Railroad Control.

**Not included:** motor control, sound, Wi-Fi — see [railbox-rb23xx.md](railbox-rb23xx.md) for locomotive sound decoders.

---

## Table of contents

1. [Hardware variants and limits](#1-hardware-variants-and-limits)
2. [Address and programming](#2-address-and-programming)
3. [Output mapping (function keys)](#3-output-mapping-function-keys)
4. [Lighting effects](#4-lighting-effects)
5. [Brightness](#5-brightness)
6. [Power-on behaviour and analog mode](#6-power-on-behaviour-and-analog-mode)
7. [Servo output](#7-servo-output)
8. [RailCom® easy configuration](#8-railcom-easy-configuration)
9. [Factory reset](#9-factory-reset)

**Appendix:** [A — Full CV table](#appendix-a--full-cv-table)

---

## 1. Hardware variants and limits

### 1.1 Purpose

RB **21x0** / **RB 2110** / **RB 2112** decoders are intended primarily for **wagon lighting** in HO scale. Supported formats: **DCC only** (not Motorola, Märklin, or MFX).

### 1.2 Variants (from manual)

| Variant | Outputs | Connector | RailCom® | Board size (approx.) |
|---------|---------|-----------|----------|----------------------|
| 13-output | 13 | Wire pads | Yes | 30 × 15 × 2.3 mm |
| 14-output | 14 | Wire pads | No | 27 × 14 × 2.3 mm |
| 21MTC (RailCom®) | 12 (+2 via jumper → I1/I2) | 21MTC | Yes | 26 × 15 × 3.2 mm |
| 21MTC | 12 (+2 via jumper) | 21MTC | No | 26 × 15 × 3.2 mm |

The first **seven** outputs plus supply have duplicate pads on the **reverse** side of the PCB.

### 1.3 Electrical limits

| Parameter | Value |
|-----------|-------|
| Supply | 12–20 V AC/DC or DCC |
| Standby current | ~25 mA |
| Peak current | up to **1 A** (total) |
| Per output | **125 mA** |

### 1.4 Wiring notes

- **LED lighting:** direct to decoder pads, LED strip, or factory LED board.
- **21MTC:** for ROBO® wagons or other 21MTC-equipped models; jumper can map two outputs to **I1** / **I2**.
- **Keep-alive capacitor:** optional external capacitor improves lighting on dirty track (see manual wiring diagram).
- **Servo:** requires external **5 V** regulator (linear or DC-DC) and **1 kΩ** resistor per servo (see manual).

---

## 2. Address and programming

Programming modes: **Direct Mode** (programming track) or **PoM** (programming on main).

| CV | Name | Range | Default | Description |
|----|------|-------|---------|-------------|
| **#1** | Short address | 1–127 | **3** | Decoder address |
| **#7** | Software version | 0–255 | — | Read only |
| **#8** | Manufacturer ID / reset | 0–255 | **13** | Read: manufacturer code; write **any value** → factory reset ([§9](#9-factory-reset)) |
| **#17** | Long address high byte | 192–231 | **192** | Long address with CV #18; enable via CV #29 bit 5 |
| **#18** | Long address low byte | 0–255 | **100** | Long address low byte |
| **#19** | Consist / MU address | 0–127 | **0** | If **> 0**, speed and direction follow this address |

### CV #29 — address and configuration (selected bits)

| Bit | Value | Function |
|-----|-------|----------|
| **1** | 2 | Speed steps: 0 = 14/27, 1 = 28/128 |
| **2** | 4 | Analog mode: 0 = DCC only, 1 = analog allowed |
| **3** | 8 | RailCom: 0 = off, 1 = on |
| **5** | 32 | Address type: 0 = short (CV #1), 1 = long (CV #17/#18) |

### CV #28 — RailCom configuration

| Bit | Function |
|-----|----------|
| **0** | CH1 address broadcast: 0 = off, 1 = on |
| **1** | CH2 enabled: 0 = off, 1 = on |
| **7** | Automatic detection: 0 = off, 1 = on |

---

## 3. Output mapping (function keys)

Unlike RB 23XX (which uses `map.txt`), RB 2112 maps **physical outputs O1–O14** to **function keys F0–F28** separately for **forward** and **reverse** direction using **bit-field CVs**.

### 3.1 Outputs O1–O7 (CV #120–#177)

Each CV configures one function for one direction. Bits **0–7** select outputs **O1–O7** (and F0 forward/reverse on bit 0/1 where applicable).

| CV | Function | Default | Active outputs (bits) |
|----|----------|---------|------------------------|
| **#120** | F0 forward (FL) | **1** | O1 (bit 0) |
| **#121** | F0 reverse (FR) | **2** | O2 (bit 1) |
| **#122** | F1 forward | **4** | O3 |
| **#123** | F1 reverse | **4** | O3 |
| **#124** | F2 forward | **8** | O4 |
| **#125** | F2 reverse | **8** | O4 |
| **#126** | F3 forward | **16** | O5 |
| **#127** | F3 reverse | **16** | O5 |
| **#128** | F4 forward | **32** | O6 |
| **#129** | F4 reverse | **32** | O6 |
| **#130** | F5 forward | **64** | O7 |
| **#131** | F5 reverse | **64** | O7 |
| **#132** | F6 forward | **128** | — (bit 7) |
| **#133** | F6 reverse | **128** | — |
| **#134–#177** | F7–F28 forward/reverse pairs | **0** (most) | Per-bit O1–O7 |

**Factory highlight:** **F15** forward default **252**, F15 reverse **252** — all outputs O2–O7 plus direction bits (wagon interior lighting preset).

Bit layout (outputs O1–O7): bit **0** = F0_F, bit **1** = F0_R, bits **2–7** = O2–O7 (see manual table header: O7…O2, F0_R, F0_F).

### 3.2 Outputs O8–O14 (CV #190–#247)

Extended mapping for additional outputs. Bit fields include **O8–O12** (and higher outputs on later CVs).

| CV range | Functions | Notes |
|----------|-----------|-------|
| **#190–#247** | F0–F28 forward/reverse | Defaults mostly **0**; **F7** forward/reverse default **1** (O9); **F8** default **2**; **F9–F11** defaults **4**, **8**, **16**; **F15** forward/reverse **31** (O9–O12) |

Bit layout for O8–O14 table: bits map to **O12…O8** per manual (CV #232–#247 for F21–F28).

**Programming tip:** Set the CV for the desired function and direction; write the **sum** of bit values for all outputs that should activate together.

---

## 4. Lighting effects

Each output has an independent **effect CV**. Range **0–120** (base effect + modifiers).

### 4.1 Effect CV assignment

| Output | Effect CV | Default |
|--------|-----------|---------|
| 1 | **#33** | 0 |
| 2 | **#34** | 0 |
| 3 | **#35** | 0 |
| 4 | **#36** | 0 |
| 5 | **#37** | 0 |
| 6 | **#38** | 0 |
| 7 | **#39** | 0 |
| 8 | **#40** | 0 |
| 9 | **#100** | 0 |
| 10 | **#101** | 0 |
| 11 | **#102** | 0 |
| 12 | **#103** | 0 |
| 13 | **#104** | 0 |
| 14 | **#105** | 0 |

### 4.2 Base effect values (CV #33 pattern)

| Value | Effect |
|-------|--------|
| **0** | Light bulb (steady) |
| **1** | Flash frequency 1 (period in CV #49) |
| **2** | Flash frequency 1, reversed phase |
| **3** | Flash frequency 2 (period in CV #50) |
| **4** | Flash frequency 2, reversed phase |
| **5** | Short pulse (duration in CV #53) |
| **6** | First custom sequence (CV #60–#72) |
| **7** | Second custom sequence (CV #73–#85) |
| **8** | **Servo mode** |

### 4.3 Effect modifiers (add to base value)

| Add | Effect |
|-----|--------|
| **+16** | Smooth fade using time from CV #51 |
| **+32** | Smooth fade using time from CV #52 |
| **+64** | Smooth fade over fixed **500 ms** |
| **+128** | Run custom sequence **once**, then stop |

### 4.4 Timing CVs

| CV | Name | Range | Default | Unit |
|----|------|-------|---------|------|
| **#49** | Flash period 1 | 0–255 | 100 | × 10 ms |
| **#50** | Flash period 2 | 0–255 | 100 | × 10 ms |
| **#51** | Fade time 1 | 0–255 | 10 | — |
| **#52** | Fade time 2 | 0–255 | 50 | — |
| **#53** | Single flash duration | 0–255 | 1 | — |
| **#54** | Custom sequence step time | 0–255 | 1 | — |

### 4.5 Factory custom sequences

| CV range | Content |
|----------|---------|
| **#60–#72** | First custom sequence (one byte per step); factory default `0xB5,0xFD,0x6F,…` |
| **#73–#85** | Second custom sequence; factory default `0xC7,0x9F,0xFF,…` |

---

## 5. Brightness

Per-output **maximum** and **minimum** brightness (PWM floor/ceiling).

### 5.1 Maximum brightness

| Output | CV | Default |
|--------|-----|---------|
| 1 | **#41** | 255 |
| 2 | **#42** | 255 |
| 3 | **#43** | 255 |
| 4 | **#44** | 255 |
| 5 | **#45** | 255 |
| 6 | **#46** | 255 |
| 7 | **#47** | 255 |
| 8 | **#48** | 255 |
| 9 | **#106** | 255 |
| 10 | **#107** | 255 |
| 11 | **#108** | 255 |
| 12 | **#109** | 255 |
| 13 | **#110** | 255 |

### 5.2 Minimum brightness

| Output | CV | Default |
|--------|-----|---------|
| 1–8 | **#90–#97** | 0 |
| 9–13 | **#182–#186** | 0 |

Effective brightness scales between minimum and maximum CVs for each output.

---

## 6. Power-on behaviour and analog mode

### 6.1 Output state after power-on (CV #55)

| CV #55 | Behaviour |
|--------|-----------|
| **1** (default) | Remember output states from before power was removed |
| **0** | Do not remember — outputs start from default mapping |

### 6.2 Analog mode default function states

When analog operation is enabled (CV #29 bit 2), default function states on entry:

**CV #13** — analog mode 1, F1–F8:

| Bit | Default | Function |
|-----|---------|----------|
| 0 | 1 | F1 on |
| 1–7 | 0 / 1 per manual | F2–F8 |

**CV #14** — analog mode 2, F0 and F9–F12:

| Bit | Default | Function |
|-----|---------|----------|
| 0 | 1 | F0 forward on |
| 1 | 0 | F0 reverse |
| 2–5 | 0 | F9–F12 |

---

## 7. Servo output

Set the target output's **effect CV** (§4) to base value **8** (Servo mode). External **5 V** supply and **1 kΩ** series resistor per servo are required (manual § wiring).

---

## 8. RailCom® easy configuration

Decoders marked with the RailCom® symbol support bidirectional communication with RailCom-capable command stations and the **RailBOX: Railroad Control** app.

### 8.1 Features (with RB 1110 central)

- Automatic detection of new decoders on the layout and **automatic address assignment**
- PoM read/write at any time on the main track
- Short decoder name for identification in the app

### 8.2 Short name and metadata

| CV | Range | Default | Description |
|----|-------|---------|-------------|
| **#257–#264** | ASCII | **"WAGON"** | Short decoder name (8 characters) |
| **#265** | 0–255 | 0 | Photo number low byte |
| **#266** | 0–255 | 0 | Photo number high byte |
| **#268** | bit field | 0 | Bits 4–7: decoder symbol type |

**CV #268** device type (bits 4–7):

| Value | Type |
|-------|------|
| 0 | Turnout |
| 1 | Semaphore |
| 2 | Turntable |
| 3 | **Lighting** (wagon) |

### 8.3 RailCom CV summary

| CV | Relevant bits |
|----|----------------|
| **#28** | Bit 0 CH1 address TX; bit 1 CH2; bit 7 auto-detection |
| **#29** | Bit 3 RailCom enable |

---

## 9. Factory reset

| Method | Value |
|--------|-------|
| Write **CV #8** | **Any value** triggers factory reset to defaults |

After reset, re-program address (CV #1 / #17–#18 / #29) and output mapping as needed. Use `--preserve-addr` with `loco prog factory-reset` to keep the current address (RailBOX family: CV #8 = **1** in the Loco CLI implementation for RB23xx; RB 2112 manual states any CV #8 write resets).

---

## Appendix A — Full CV table

Condensed from the manufacturer PDF. Output mapping detail: [§3](#3-output-mapping-function-keys).

### Address and identity

| CV | Range | Default | Description |
|----|-------|---------|-------------|
| **#1** | 1–127 | 3 | Short address |
| **#7** | 0–255 | — | Software version (read) |
| **#8** | 0–255 | 13 | Manufacturer / factory reset |
| **#13** | bit field | — | Analog mode 1, F1–F8 defaults |
| **#14** | bit field | — | Analog mode 2, F0r/F0f, F9–F12 |
| **#17** | 192–231 | 192 | Long address high |
| **#18** | 0–255 | 100 | Long address low |
| **#19** | 0–127 | 0 | Consist address |
| **#28** | bit field | — | RailCom configuration |
| **#29** | bit field | — | Speed steps, analog, RailCom, long address |

### Lighting effects (outputs 1–14)

| CV | Output | Range | Default |
|----|--------|-------|---------|
| **#33–#40** | 1–8 | 0–120 | 0 |
| **#100–#105** | 9–14 | 0–120 | 0 |

### Brightness

| CV | Output | Range | Default |
|----|--------|-------|---------|
| **#41–#48** | 1–8 max | 0–255 | 255 |
| **#90–#97** | 1–8 min | 0–255 | 0 |
| **#106–#110** | 9–13 max | 0–255 | 255 |
| **#182–#186** | 9–13 min | 0–255 | 0 |

### Effect timing and sequences

| CV | Default | Description |
|----|---------|-------------|
| **#49** | 100 | Flash period 1 (× 10 ms) |
| **#50** | 100 | Flash period 2 |
| **#51** | 10 | Fade time 1 |
| **#52** | 50 | Fade time 2 |
| **#53** | 1 | Single flash duration |
| **#54** | 1 | Custom sequence step |
| **#55** | 1 | Remember outputs after power loss |
| **#60–#72** | factory | Custom sequence 1 |
| **#73–#85** | factory | Custom sequence 2 |

### Output mapping

| CV range | Maps |
|----------|------|
| **#120–#177** | F0–F28 ↔ outputs O1–O7 (forward/reverse pairs) |
| **#190–#247** | F0–F28 ↔ outputs O8–O14 (forward/reverse pairs) |

### RailCom® naming

| CV | Description |
|----|-------------|
| **#257–#264** | Short name (ASCII), default `"WAGON"` |
| **#265–#266** | Photo index |
| **#268** | Decoder symbol / type |

---

## Relation to Loco CLI

| Feature | RB 2112 support in Loco |
|---------|-------------------------|
| Detection (CV #7 / #8) | Same manufacturer ID **172** (NMRA) as other RailBOX decoders when read on track |
| `loco prog factory-reset` | CV #8 write — value **1** for RailBOX family in Loco CLI |
| `loco prog brightness` | RB23xx CV mapping (#119–#125, #219–#222) targets locomotive decoders; RB 2112 uses **#41–#48** / **#106–#110** — not yet implemented |
| Output mapping | CV bit tables (#120+) — not yet implemented; use RailBOX: Railroad Control or direct CV programming |
