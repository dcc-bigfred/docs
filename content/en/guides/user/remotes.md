# Remotes

You can steer trains from a phone, tablet or physical remote with a **Z21 app**, **ROCO Z21 WlanMaus**, 
**Engine Driver** or **WiFred**. BigFred uses the same roster and permissions as
the BigFred throttle view — you only drive locomotives you are allowed to use on the layout.

<div class="screenshot-gallery" markdown="0">
<div class="screenshot-item">
<input type="checkbox" id="remote-device-z21" class="screenshot-lb-toggle">
<label for="remote-device-z21" class="screenshot-thumb">
<img src="assets/devices/tcs.png" alt="Z21 app">
<span>Z21 app</span>
</label>
<div class="screenshot-lightbox">
<label for="remote-device-z21" class="screenshot-lightbox-backdrop" aria-label="Close"></label>
<img src="assets/devices/tcs.png" alt="Z21 app">
</div>
</div>
<div class="screenshot-item">
<input type="checkbox" id="remote-device-wlanmaus" class="screenshot-lb-toggle">
<label for="remote-device-wlanmaus" class="screenshot-thumb">
<img src="assets/devices/wlanmaus.jpg" alt="ROCO Z21 WlanMaus">
<span>ROCO Z21 WlanMaus</span>
</label>
<div class="screenshot-lightbox">
<label for="remote-device-wlanmaus" class="screenshot-lightbox-backdrop" aria-label="Close"></label>
<img src="assets/devices/wlanmaus.jpg" alt="ROCO Z21 WlanMaus">
</div>
</div>
<div class="screenshot-item">
<input type="checkbox" id="remote-device-wifred" class="screenshot-lb-toggle">
<label for="remote-device-wifred" class="screenshot-thumb">
<img src="assets/devices/wifred.jpg" alt="WiFred">
<span>WiFred</span>
</label>
<div class="screenshot-lightbox">
<label for="remote-device-wifred" class="screenshot-lightbox-backdrop" aria-label="Close"></label>
<img src="assets/devices/wifred.jpg" alt="WiFred">
</div>
</div>
</div>

## Open the pairing page

1. Open **Menu** → **My** → **Handsets**.
2. Choose the **command station** for your layout.
3. Under **Vehicle scope**, either tick **All vehicles I have permission to drive
   on this layout**, or pick specific locomotives.
4. Click **Generate pairing code**.

The page shows a code and short instructions for your app type. Codes expire after
a few minutes — generate a new one if needed.

If no command station appears, ask whoever runs BigFred at your club to enable
handset support for your layout.

## Z21 app

1. On the pairing page, open the **Z21 app** tab and note **CV3** and **CV4**.
2. In the Z21 app, connect to BigFred using the address your club uses (the same
   one shown on the pairing page).
3. On any locomotive — it does not matter which you choose; no CV values are sent to a real locomotive — open programming and enter **CV3** and **CV4** with the values from BigFred.

When pairing works, the page shows **Paired**.

## ROCO Z21 WlanMaus

### Pairing with the keyboard

1. Open any locomotive
2. Enter your pairing code with the keyboard (e.g. 168421 -> F1 F6 F8 F4 F2 F1)

## Engine Driver / WiThrottle

1. On the pairing page, open the **WiThrottle / Engine Driver** tab and note the
   pairing code.
2. In the app, connect to BigFred using the address your club uses.
3. Complete pairing in one of these ways:
   - set **Device name** to the six-digit code (no spaces), or
   - from the loco list, select **Pair with BigFred** and press function keys
     **F0–F9** once per digit (for example code `122145`: F1, F2, F2, F1, F4, F5).

When pairing works, the page shows **Paired**. You can then choose a real
locomotive from the roster.

## While you drive

- Keep the app open and connected. If it stays idle too long, BigFred ends the
  session and may brake your trains — pair again if that happens.
- You can change which locomotives you may drive on the pairing page and click
  **Save** without generating a new code.
- When you finish, use **Disconnect handset** on the pairing page or close the app
  normally.

## Something wrong?

| Problem | What to try |
|---------|-------------|
| No command station in the list | Ask your club’s BigFred operator to enable handsets for this layout. |
| Pairing code expired | Generate a new code on the pairing page. |
| The loco does not move | Check that it is on the layout roster and included in your allowed vehicles. |
| Connection dropped | Open the app again on the same Wi‑Fi and pair once more. |
