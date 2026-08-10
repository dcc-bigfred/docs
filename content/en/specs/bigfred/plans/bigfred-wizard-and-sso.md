# Implementation plan — BigFred Wizard & SSO

Party/event kiosk on the hub tablet: **bigfred-wizard** (Rust + React on
`:8091`) simplifies BigFred for participants (accounts, locomotives, handset
pairing, CV programming). The organizer authenticates via **BigFred OAuth2 SSO**;
the wizard operates with the organizer’s privileges (typically admin).

Related code:

- BigFred server — `bigfred/pkgs/bigfred/server/`
- dcc-bus — `bigfred/pkgs/bigfred/dcc-bus/`
- Hub app — `bigfred-os/apps/bigfred-wizard/`

---

## Goals and architecture

| Concern | Decision |
|---------|----------|
| Deploy | Hub-only (`bigfred-os` image), port **8091** |
| Organizer auth | OAuth2 authorization code (no PKCE on LAN); silent SSO if BigFred session cookie already present |
| Wizard config | `$DATA_DIR/etc/bigfred/wizard/bigfred-wizard.json` |
| OAuth clients | Drop-in `$DATA_DIR/etc/bigfred/oauth-clients/{name}.json` (hot-reload); wizard seed `corsEnabled: false` |
| Browser → BigFred | Same-origin to `:8091`; Rust reverse-proxies HTTP to BigFred loopback |
| Participant ops | Generic `X-BigFred-Impersonate-As: <login>` middleware (admin actor, subject identity) |
| User DCC | `POST /users` + `autoAllocateDccCount: N` — free addresses from **50** upward |
| CV programming | CS flags + dcc-bus WS commands; **Rust** holds resilient WS via BigFred `/api/v1/dcc-bus/{id}/ws`; React uses wizard HTTP only |

```text
[React wizard] ──HTTP──► [Rust :8091] ──HTTP──► [BigFred :8080]
                              │
                              └──WS──► [BigFred /api/v1/dcc-bus/{id}/ws] ──► [dcc-bus]
```

### Silent SSO

`GET /api/v1/auth/oauth/authorize` with a valid `bigfred_session` cookie issues a
one-time code and redirects to the client **without** showing LoginPage. Login
is only shown when there is no session. LoginPage with `return_to` also
auto-navigates when already authenticated.

### Impersonation

Header `X-BigFred-Impersonate-As` after `RequireAuth`: actor must be effective
admin; subject replaces `Identity` for ownership/pairing; `RequireRole` uses
**actor**.

### Command-station programming flags

| Field | Meaning |
|-------|---------|
| `programming` | CV/addr commands allowed on this CS |
| `hideInThrottle` | Omit from throttle available-stations list |
| `defaultProgrammingTrackOutput` | `"pom"` \| `"prog"` (per-command `mode` override) |

dcc-bus frames: `loco.cvWrite`, `loco.cvRead`, `loco.addrSet`, `loco.addrGet`.

Wizard programming HTTP (Rust):

- `POST /api/v1/wizard/programming/cvs/read|write`
- `POST /api/v1/wizard/programming/address/get|set`
- `GET /api/v1/wizard/programming/status`

Rust picks the first catalogue CS with `programming: true`, EnsureRunning, and
maintains a reconnecting WS through BigFred’s standard dcc-bus proxy.

### Wizard tiles (post-SSO)

1. Create account  
2. Phone app (WiThrottle)  
3. Roco Wlanmaus (Z21)  
4. LongFred (WiThrottle)  
5. Configure locomotive (CV/addr + vehicle/roster)

---

## Implementation phases

0. English docs (this file) + `.pages`  
A. OAuth drop-in + authorize/token + Bearer + LoginPage silent SSO  
A2. Impersonate middleware + `autoAllocateDccCount`  
A3. CS flags + dcc-bus CV/addr commands  
B. Wizard skeleton + SSO + tiles  
B2. Rust dcc-bus client + programming HTTP  
C–E. Flows, pairing, polish  

---

## Security notes

- `clientSecret` stays on Rust / drop-in file; never in React  
- OAuth codes: 60s TTL, single-use  
- `return_to` / `redirect_uri`: exact allowlist / same-origin paths only  
- Idle logout via `idleTimeoutSecs` (default 24h) on the tablet  
