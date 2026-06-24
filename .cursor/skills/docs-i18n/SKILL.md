---
name: docs-i18n
description: >-
  Edits BigFred MkDocs documentation under docs/content/ with English as the
  source of truth and Polish translations kept in sync. Use when creating,
  updating, or restructuring markdown in docs/, guides/, specs/, or related/.
---

# BigFred documentation (EN → PL)

## Language policy

**English (`content/en/`) is the source of truth.** Polish (`content/pl/`) is a translation layer.

Whenever you change documentation:

1. Edit the **English** file first (`content/en/...`).
2. Update the matching **Polish** file (`content/pl/...`) in the same change — do not leave PL stale.
3. If you add a new page under `en/`, add the Polish counterpart under `pl/` (or rely on `fallback_to_default` only for untranslated technical specs — never for user-facing guides or the homepage).

## Layout

```
docs/content/
├── assets/          # shared (language-agnostic)
├── en/                # source of truth
│   ├── index.md
│   ├── guides/
│   ├── specs/
│   └── related/
└── pl/                # Polish translations (mirror en/ paths for translated pages)
    ├── index.md
    └── guides/
```

- Shared images/CSS: `content/assets/` (referenced as `assets/...` from both locales).
- i18n: `mkdocs-static-i18n`, `docs_structure: folder`, `fallback_to_default: true`.
- EN site root: `/` — PL: `/pl/`.

## Translation checklist

When touching `content/en/`:

- [ ] Same relative path exists in `content/pl/` if the page is user-facing (homepage, guides).
- [ ] Polish UI terms match the app: `bigfred/web/src/i18n/locales/pl/` (e.g. pojazd, skład, makiet(a), manetka).
- [ ] `.pages` nav labels updated in both `en/` and `pl/` when nav changes.
- [ ] Internal links stay extensionless (`.md` in source, no locale prefix in paths).
- [ ] Run `make build` in `docs/` before finishing.

## New English page workflow

1. Create `content/en/<path>.md` and wire it in the nearest `en/**/.pages`.
2. Create `content/pl/<path>.md` with a full Polish translation.
3. Update `content/pl/**/.pages` with Polish nav titles.
4. Add `nav_translations` entries in `docs/mkdocs.yml` only when nav keys are shared English strings that must appear translated on the PL site.

## Do not

- Edit only `content/pl/` without updating `content/en/`.
- Put new English content directly under `content/` (must be under `content/en/`).
- Duplicate `assets/` into locale folders.

## Build

```bash
cd docs && make build
# EN: site/index.html   PL: site/pl/index.html
```
