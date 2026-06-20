# BigFred Documentation

Documentation for the **BigFred** model railroad throttle hub: application
architecture, hardware deployment, and DCC decoder references.

## Sections

- **[BigFred](bigfred/)** — web application architecture, protocols,
  domain model, delivery milestones, and implementation plans
- **[BigFred OS](os/)** — Raspberry Pi 5 hub image (Buildroot), read-only
  root, `/data` persistence, and boot init
- **[Hardware](hardware/)** — Raspberry Pi 5 hub deployment, LocoNet
  and Z21 wiring, bring-up and testing
- **[Decoders](decoders/)** — CV reference sheets for supported sound
  and function decoders

## Local preview

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
mkdocs serve
```

Open [http://127.0.0.1:8000](http://127.0.0.1:8000).

## Source

This site is built from [github.com/dcc-bigfred/docs](https://github.com/dcc-bigfred/docs)
and published to [dcc-bigfred.github.io/docs](https://dcc-bigfred.github.io/docs/).
