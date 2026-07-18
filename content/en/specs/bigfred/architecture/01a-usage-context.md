## 1a. Usage context

This section records the **operational assumptions** under which BigFred
is designed and deployed. Architectural choices elsewhere in this
specification — transport security, latency budgets, process layout,
authentication strength — should be read in light of these constraints.

Related: [§1 Goals](./01-goals.md), [§6 Frontend components](./08-frontend-components.md),
[§7b Offline-first frontend assets](./09b-offline-assets.md),
[§7a Authentication](./10-authn-authz/README.md), [§17 Reliability](./17-reliability.md).

### 1a.1 Network environment

BigFred is intended for use **only on a local area network (LAN)** — a
club room, exhibition hall, or home layout. It is **not** exposed to the
public Internet and **does not require Internet access** to operate.

The hub image and the SPA are built to be **fully self-contained**: all
UI assets, fonts, and sounds are served locally (see §7b). A layout can
run on an isolated VLAN with no upstream connectivity.

### 1a.2 Scale and responsiveness

A typical deployment must support on the order of **100–150 DCC vehicles
active at the same time** across one or more command stations on a single
layout. That scale drives the `dcc-bus` per-`(layout × command station)`
split (§7e), Redis-backed state fan-out, and the separation of control-
and data-plane WebSockets.

**Latency should be kept as low as practicable.** Throttle commands
(speed, direction, functions) are real-time control traffic; users
expect immediate feedback on phones and tablets over Wi-Fi. Design and
implementation choices should favour short request paths and push-based
state sync over polling wherever the command station allows it.

### 1a.3 Physical deployment

Getting BigFred running should be **as simple as possible** for a club
operator:

1. Flash an SD card with the **BigFred OS** image.
2. Insert the card into a **Raspberry Pi 5** and power it on.
3. Connect a **Uhlenbrock LocoNet adapter** (USB) *or* point BigFred at
   a **Roco Z21** on the LAN — no adapter is needed when the Z21 is the
   command station.

No separate database install, reverse proxy, or TLS certificate setup is
expected for a standard hub deployment. The Pi hosts `loco-server`,
`supervisord`, Redis, and the per-station `dcc-bus` daemons; clients
reach it over the club Wi-Fi. `loco-server` advertises itself via mDNS
as **`http://bigfred.local:8080`** (no Avahi daemon on the hub; clients
need OS mDNS/Bonjour support to resolve `.local`).

### 1a.4 End users and usability

The **day-to-day operators** of BigFred — drivers (*maszyniści*),
signalmen (*nastawniczycy*), and occasional guest users at a club
session — are assumed to be **entirely non-technical**. They are model
railway enthusiasts, not IT staff: they should not need to understand
WebSockets, DCC address pools, process supervisors, or hub
administration to drive a locomotive.

Design and documentation should reflect that audience:

- **Simple, step-by-step instructions** for getting onto the layout
  (connect to club Wi-Fi → open the browser → log in with `login` +
  PIN → pick a vehicle from the dashboard → open throttle). Error
  messages must be plain language with a clear next action, not stack
  traces or internal reason codes shown raw to the user.
- **A straightforward interface** with a shallow learning curve. The
  primary flows — login, dashboard, throttle, basic vehicle
  registration — should be obvious on first use without reading a
  manual. Advanced administration (user pools, command-station
  wiring, script editing) is confined to the `admin` role and may be
  richer, but the driving surface stays focused: speed slider,
  direction, function buttons, and the minimum chrome needed for
  leases, radio, and takeover.
- **Mobile-first interaction** — most users hold a phone or tablet while
  walking the layout. Touch targets, typography, and layout breakpoints
  follow §6; PIN entry and throttle control must work one-handed.
- **Forgiving session behaviour** — brief Wi-Fi drops, switching apps,
  or opening a second tab should not surprise the user with unexplained
  failures (see §17). Reconnect and retry should be automatic wherever
  safe.

Feature proposals that add power-user knobs, diagnostic panels, or
configuration exposed to every role should be weighed against this
constraint: if a driver would need a README paragraph to use it, it
probably belongs behind `admin` or out of the product.

### 1a.5 Role as control hub

BigFred is the **central control hub** for a layout session. It provides:

- the **built-in web application** (dashboard, throttle, interlocking
  views, administration), and
- a **mediated path for external throttles** (physical handsets, third-
  party apps) through the same permission and session model.

Because all driving authority flows through BigFred, the server acts as
a **policy firewall between clients and command stations**:

- only authenticated users with the right role and DCC pool may drive a
  given address;
- leases, takeovers, and the dead-man's switch are enforced server-side;
- malformed or unauthorised throttle traffic never reaches the
  command station directly.

That boundary also **protects command stations from faulty or hostile
clients** — a misbehaving phone app or a pilot that hammers the bus
cannot bypass BigFred's rate limits and authorization checks.

### 1a.6 Security posture

BigFred does **not** store sensitive personal or financial data. Accounts
hold a `login`, a hashed PIN, role assignments, and layout metadata —
nothing that warrants the defence depth of a public Internet service.

The expected security model is therefore **proportionate to a trusted
LAN**:

| Concern | Approach |
|---|---|
| User identity | `login` + short numeric **PIN** (easy to remember and type on a phone in a club room); hashed at rest, rate-limited on failure (§7a.1). |
| Authorization | Role-based access (`driver`, `signalman`, `admin`), DCC address pools, leases, and the security-policy layer (§7a). |
| Transport | Clients connect over **plain HTTP / WS** on the LAN. **HTTPS is not required** for the hub deployment described here. |
| Link-layer encryption | Wi-Fi is assumed to run **WPA2 or WPA3**. Encryption between phone/tablet and the access point, and between the Pi and the LAN, is delegated to the wireless layer rather than duplicated at the application layer. |
| Internet-grade hardening | No WAF, no public certificate lifecycle, no OAuth/OIDC integration — these are out of scope for an air-gapped club hub. |

This is a deliberate trade-off: lower operational friction on the Pi,
faster WebSocket setup, and no certificate maintenance, in exchange for
the requirement that BigFred **never** be port-forwarded or published
outside the LAN.

If a future deployment needs remote access over the Internet, that is a
**different product context** and would require TLS, stronger
authentication, and an explicit threat model — not covered by this
section.
