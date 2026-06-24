# BigFred Documentation

Source for the BigFred documentation site.

- **Published:** [dcc-bigfred.github.io/docs](https://dcc-bigfred.github.io/docs/)
- **Repository:** [github.com/dcc-bigfred/docs](https://github.com/dcc-bigfred/docs)

## Local preview

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
mkdocs serve
```

Open [http://127.0.0.1:8000](http://127.0.0.1:8000) (English) or [http://127.0.0.1:8000/pl/](http://127.0.0.1:8000/pl/) (Polish).

## Contents

| Section | Path (English) |
|---------|----------------|
| User guide | `content/en/guides/` |
| Technical specification | `content/en/specs/` |
| Related hardware & decoders | `content/en/related/` |

Polish translations live under `content/pl/` (same paths). English is the source of truth; keep `pl/` in sync when editing docs (see `.cursor/skills/docs-i18n/SKILL.md`).
