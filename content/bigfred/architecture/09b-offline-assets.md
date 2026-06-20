## 7b. Offline-first frontend assets

BigFred runs on club LANs and on the hub OS image **without any Internet
access** — neither the operator's browser nor the Go server may depend
on third-party CDNs, Google Fonts, or runtime `npm`/`wget` fetches.

### 7b.1 Requirements

| Layer | Rule |
|-------|------|
| **Browser** | After the SPA loads, every font, stylesheet, script, worker, image and audio file is served from the **same origin** as the API (embedded `web/dist` or `--static-dir`). No `<link href="https://…">`, no dynamic `import()` of external modules, no `fetch()` to off-origin URLs for UI assets. |
| **Build** | Vite resolves all JS/CSS dependencies from `node_modules` at `npm run build` time. Fonts ship via **`@fontsource/*`** (or equivalent self-hosted files under `web/public/`). Sounds and icons are either imported in TS (`import url from "…"`) or live under `web/public/` and are copied into `dist/` by Vite. |
| **Server** | `loco-server` and `bigfred-os-ui` never download UI assets at startup. Production binaries embed a pre-built `web/dist` via `go:embed`. |
| **Development** | Vite may proxy `/api` to localhost; that is dev-only. Production acceptance is judged on the **`dist/`** artefact, not on `:5173`. |

Club rooms and the Raspberry Pi hub are treated as **air-gapped** for UI
purposes: if the bundle builds and passes the offline check, the runtime
works on an isolated VLAN.

### 7b.2 What is bundled today

| Asset class | Mechanism | Location |
|-------------|-----------|----------|
| React, MUI, TanStack Query, i18n | `npm` dependencies → Vite chunks | `web/dist/assets/*.js` |
| Roboto (UI) | `@fontsource/roboto` imported in `main.tsx` | hashed `.woff2` beside JS/CSS |
| JetBrains Mono (hub logs) | `@fontsource/jetbrains-mono` in hub OS UI | same |
| MUI icons | tree-shaken from `@mui/icons-material` | JS bundle |
| Throttle / function SVGs | `import … from "*.svg"` | inlined or hashed files |
| Radio / radiostop / PA Ogg | `import … from "*.ogg"` or `web/public/sounds/` | `dist/assets/` or `dist/sounds/` |
| Locale JSON | static `import` in `web/src/i18n/index.ts` | JS chunks (§7c.10) |

**Forbidden in `index.html` and application source:** `fonts.googleapis.com`,
`fonts.gstatic.com`, `unpkg.com`, `jsdelivr.net`, `cdnjs.cloudflare.com`, and
any other runtime CDN.

### 7b.3 Build pipeline

Both frontends share the same pattern:

```bash
cd web && npm ci && npm run build
# vite build → dist/
# check-offline-bundle.mjs scans dist/ for http(s):// (excluding .map)
```

`npm run build` runs the offline check automatically. CI and `make web-build`
must not skip it. The checker flags forbidden CDN hostnames, external
`<link>` / `<script>` tags in `index.html`, CSS `@import url(https://…)`, and
dynamic `import("https://…")` — it intentionally ignores SVG `xmlns` URIs and
React error-decoder strings that are never fetched at runtime.

Hub OS UI (`bigfred-os/apps/bigfred-os-ui`):

```bash
make -C apps/bigfred-os-ui build   # web-build + go:embed all:web/dist
```

Main BigFred SPA (`bigfred/web`):

```bash
make web-build                     # produces web/dist for go:embed (§7.1)
```

### 7b.4 Future dependencies (Monaco, maps, …)

When a feature needs a large third-party runtime (Monaco editor, map tiles,
…):

1. Add it as an **`npm` dependency**, not a `<script src="https://…">`.
2. Configure Vite to copy workers/WASM into `dist/` (e.g.
   `vite-plugin-monaco-editor` or `@monaco-editor/react` with
   `MonacoEnvironment.getWorkerUrl` pointing at a **local** `/assets/…`
   path).
3. Extend `scripts/check-offline-bundle.mjs` only if new file types need
   coverage; the default scan already catches leaked URLs in `.html`,
   `.js`, `.css` and `.json`.

Map **tiles** are out of scope for v1 (no basemap). If they are added later,
tile packs must be pre-seeded on the hub image or served from `/tiles/` on
the same host — never from a public tile CDN at runtime.

### 7b.5 Acceptance criteria

1. `npm run build` exits 0 and prints `offline bundle OK`.
2. With the server host and client on a network **without a default route
   to the Internet**, loading `/` renders login, typography and icons
   correctly (no pending requests to non-LAN hosts in DevTools → Network).
3. `check-offline-bundle.mjs` passes on `dist/` (no forbidden CDN hosts,
   no external `<link>` / `<script>` in HTML, no external CSS imports).
4. Adding a CDN link to `index.html` without updating the policy must
   fail CI via `check-offline-bundle.mjs`.
