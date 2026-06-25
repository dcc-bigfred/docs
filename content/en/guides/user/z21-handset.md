# Z21 handset

BigFred can act as a **virtual Z21 command station** on your club LAN. Stock Z21 apps
(tablet or phone) connect to the `dcc-bus` host over UDP and drive locomotives you
are allowed to control — the same roster rules as the web throttle.

## Before you start

An **admin** must:

1. Open **Menu** → **Administration** → **Command stations**.
2. Edit the Z21 command station attached to your layout.
3. Turn on **Z21 handset server** and save.

The `dcc-bus` daemon must be running for that layout (it starts automatically when the
layout is active). UDP port **21105** on the `dcc-bus` host must be reachable from
your phone or tablet.

!!! note "Outbound vs inbound Z21"
    If BigFred also talks to a **physical** Z21 on the same machine, the outbound
    client must use a **different IP** than the inbound listener — both cannot bind
    the same UDP port on one address.

## Pair your handset

1. Open **Menu** → **My** → **Z21 handset** (`/remotes/z21`).
2. Pick the **command station** for your layout.
3. Choose **vehicle scope**:
   - tick **All vehicles I can drive on this layout**, or
   - select specific locomotives from the roster.
4. Click **Generate pairing code**. You will see **CV3** and **CV4** values (valid for
   about five minutes).
5. In the Z21 app, set the command-station **IP** to the `dcc-bus` host and port
   **21105**.
6. Open **POM** (programming on the main) on any locomotive and enter **CV3** and
   **CV4** with the values shown in BigFred.

When pairing succeeds, the page shows **Paired** with your handset address
(`IP:port`).

## While connected

- The Z21 app must keep sending traffic. Per Z21 protocol §1.1, **more than 60 seconds
  without any UDP packet** ends the session — you must pair again.
- Close the Z21 app normally when finished so it sends **`LAN_LOGOFF`**; abrupt Wi-Fi
  loss unpairs after the 60 s idle timeout.
- You can change allowed vehicles on `/remotes/z21` and click **Save** without
  re-pairing.
- Use **Disconnect handset** to end the session immediately.

## Troubleshooting

| Symptom | What to check |
|---------|----------------|
| No command station in the list | Admin has not enabled **Z21 handset server** for a station on this layout. |
| Pairing code expired | Generate a new code; codes last about five minutes. |
| Drive commands ignored | Vehicle not in your scope, not on the roster, or you lack drive rights (owner/lessee). |
| Session drops while using the app | Wi-Fi sleep, firewall, or no UDP for 60 s — keep the app in the foreground on the LAN. |

For protocol and implementation detail, see the [Z21 server plan](../../specs/bigfred/plans/z21-server-dcc-bus.md).
