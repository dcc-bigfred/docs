# Handset sessions

A paired handset has **two** independent states. Mixing them up is the usual
reason a club operator cannot tell why a throttle vanished from the list, or
why pairing returns **You already have an active handset session**.

| State | Where it lives | What it means |
|-------|----------------|---------------|
| **Presence** | The `dcc-bus` daemon for that command station | The handset is on the **Remotes** client list right now |
| **Pairing** | Redis (`bigfred:remote:active:…`) | The user may come back **without a new pairing code / PIN** |

WiThrottle can leave the list and still come back without pairing again.
A Z21 handset (default settings) cannot: when the row disappears, the pairing
is gone too.

This page is about **session lifetime**. Drive leases (who may move which
address) are a separate layer — see [Slots](slots.md).

---

## Three clocks

Every paired handset is subject to three timeouts. They do not share a
single setting.

| Clock | Default | What happens |
|-------|---------|--------------|
| **Idle brake** (`handsetBrakeSecs`, 6–60 s, default **6 s**) | Set at pairing | Locos driven by that handset are braked. The session stays. The row shows **Braked (idle)**. |
| **Presence** | Protocol-specific (below) | The row is removed from the live client list |
| **Pairing** | Protocol-specific (below) | Redis session is deleted; the user must pair again |

Any UDP or TCP traffic counts as activity, including Z21 keepalives the app
sends in the background. “Silent” means **no packets at all**, not “the
operator is not touching the throttle”.

---

## Per protocol

### Z21 app / WlanMaus — IP stickiness **off** (default)

Follows [Z21 LAN §1.1](../../specs/bigfred/protos/z21.md#11-communication):
a client that sends no UDP for **60 seconds** is removed from the participant
list. BigFred also **unpairs** at that moment.

The session key is `IP:port`. A reconnect that changes the UDP source port
looks like a **new** handset.

| Event | Presence | Pairing | What the user sees |
|-------|----------|---------|--------------------|
| Silent **under 6 s** | Stays | Stays | Normal driving |
| Silent **6 s – 60 s** | Stays | Stays | Locos braked; row tagged **Braked (idle)** |
| Silent **over 60 s** | Gone | **Gone** | Must pair again |
| App closed / Wi-Fi drop, back **within 60 s on the same IP:port** | Refreshed | Stays | Continues |
| Reconnect with a **new UDP port** | New row | Old pairing still holds the user | Pairing fails with *already have an active session* until the old row times out (~60 s) or someone clicks **Remove paired handset** |
| `dcc-bus` restart | List empty, then rebuilt from Redis | Stays (up to 72 h idle TTL) | Can come back without pairing until that TTL |

There is **no** “Session expires …” caption on this row. Pairing dies with
presence, so a countdown would add nothing beyond **Last seen**.

### Z21 app / WlanMaus — IP stickiness **on**

**Admin → Command stations** → *Session bound to IP (IP stickiness)*.

The same flag does **two** things at once (they are not separately
configurable):

1. Session key is the **IP only**, so a new UDP port on the same address is
   still the same handset.
2. Presence **and** pairing last **72 hours** of silence instead of 60 s.

| Event | Presence | Pairing |
|-------|----------|---------|
| Silent **over 60 s** | Stays (until 72 h) | Stays |
| Reconnect, **same IP, new port** | Same row | Stays |
| Reconnect, **different IP** | New row | Old pairing still holds the user until unpair or 72 h |
| Two handsets behind the **same NAT IP** | **One** session | The second device inherits the first user’s pairing |

Turn this on only when the club router keeps a stable IP per handset
(DHCP reservation or NAT source-IP stickiness). Otherwise a later visitor
can receive an IP that still owns someone else’s pairing.

### WiThrottle / Engine Driver / WiFred

Presence and pairing are **split**. Closing the TCP socket (or the idle
sweep after **120 s** of silence on a stuck socket) removes the row.
Redis pairing survives until **72 hours** without activity, the handset
sends `Q`, or someone clicks **Remove paired handset**.

| Event | Presence | Pairing | What the user sees |
|-------|----------|---------|--------------------|
| Silent **under 6 s** | Stays | Stays | Normal driving |
| Silent **6 s+** with the socket still open | Stays | Stays | Locos braked; row tagged **Braked (idle)** |
| App closed / TCP disconnect | Gone | **Stays** (72 h) | Re-open the app on the same Wi-Fi — **no new pairing code** |
| Silent **over ~15 s** with heartbeat (`*+`) enabled | Gone (e-stop, then drop) | Stays | Same as disconnect |
| Idle **72 h** with no reconnect | Gone | **Gone** | Must pair again |
| `dcc-bus` restart | List empty | Stays | Reconnect without pairing |

The **Session expires …** caption is shown here. It is the Redis pairing
deadline (last seen + 72 h), not the TCP socket lifetime.

---

## What you see on Remotes

**Menu → My → Remotes**, per command station.

| UI | Meaning |
|----|---------|
| Row present | Presence in the live daemon |
| **Braked (idle)** | Idle-brake clock has fired; pairing is still valid |
| **Session expires …** | Pairing outlives presence (WiThrottle, or Z21 with IP stickiness). **Absence of this caption on a default Z21 row is expected.** |
| **Remove paired handset** | Deletes Redis pairing **and** presence. The owner can do this for their own session. |

---

## Troubleshooting

| Symptom | Likely cause | What to do |
|---------|--------------|------------|
| Pairing returns *You already have an active handset session* | Redis still holds a pairing for that user on this command station (another device, a Z21 port change, or a WiThrottle that disconnected but is still paired) | On **Remotes**, **Remove paired handset** for that user, or wait: ~60 s for default Z21, up to 72 h for WiThrottle / sticky Z21 |
| Z21 user must pair again after a minute in a tunnel / flaky Wi-Fi | Default Z21 follows LAN §1.1 (60 s, no UDP) | Expected. If the club has stable per-handset IPs, consider IP stickiness — and read the cost above |
| Z21 user must pair again after every screen lock, even after a few seconds | Source UDP port changed; old `IP:port` still occupies the user slot | Wait ~60 s, or enable IP stickiness if IPs are reserved |
| WiThrottle vanished from the list but still drives after reopening the app | Presence dropped; pairing survived | Expected — not a leak |
| Ghost Z21 on the list that nobody is holding | Sticky Z21 (or a daemon restart that restored pairing) with no recent UDP | **Remove paired handset**, or wait out the 72 h pairing TTL |
| Two WlanMaus units fight over the same locos after enabling stickiness | Both share one public/NAT IP, so they share one session | Turn stickiness off, or give each handset a reserved DHCP address |

---

## Related

- User walkthrough: [Remotes](../user/remotes.md)
- Z21 LAN idle rule: [Protocol §1.1](../../specs/bigfred/protos/z21.md#11-communication)
- Drive leases (who may move which address): [Slots](slots.md)
