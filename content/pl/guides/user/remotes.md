# Piloty

Możesz sterować pociągami z telefonu, tabletu lub fizycznego pilota przez
**aplikację Z21**, **ROCO Z21 WlanMaus**, **Engine Driver** albo **WiFred**.
BigFred stosuje te same uprawnienia co widok manetki w BigFredzie — prowadzisz
tylko lokomotywy, do których masz dostęp na makiecie.

<div class="screenshot-gallery" markdown="0">
<div class="screenshot-item">
<input type="checkbox" id="remote-device-z21" class="screenshot-lb-toggle">
<label for="remote-device-z21" class="screenshot-thumb">
<img src="/docs/assets/devices/tcs.png" alt="Aplikacja Z21">
<span>Aplikacja Z21</span>
</label>
<div class="screenshot-lightbox">
<label for="remote-device-z21" class="screenshot-lightbox-backdrop" aria-label="Zamknij"></label>
<img src="/docs/assets/devices/tcs.png" alt="Aplikacja Z21">
</div>
</div>
<div class="screenshot-item">
<input type="checkbox" id="remote-device-wlanmaus" class="screenshot-lb-toggle">
<label for="remote-device-wlanmaus" class="screenshot-thumb">
<img src="/docs/assets/devices/wlanmaus.jpg" alt="ROCO Z21 WlanMaus">
<span>ROCO Z21 WlanMaus</span>
</label>
<div class="screenshot-lightbox">
<label for="remote-device-wlanmaus" class="screenshot-lightbox-backdrop" aria-label="Zamknij"></label>
<img src="/docs/assets/devices/wlanmaus.jpg" alt="ROCO Z21 WlanMaus">
</div>
</div>
<div class="screenshot-item">
<input type="checkbox" id="remote-device-wifred" class="screenshot-lb-toggle">
<label for="remote-device-wifred" class="screenshot-thumb">
<img src="/docs/assets/devices/wifred.jpg" alt="WiFred">
<span>WiFred</span>
</label>
<div class="screenshot-lightbox">
<label for="remote-device-wifred" class="screenshot-lightbox-backdrop" aria-label="Zamknij"></label>
<img src="/docs/assets/devices/wifred.jpg" alt="WiFred">
</div>
</div>
</div>

## Strona parowania

1. Otwórz **menu** → **Moje** → **Piloty**.
2. Wybierz **centralkę** przypisaną do makiety.
3. W **zakresie pojazdów** zaznacz **wszystkie pojazdy, którymi mam uprawnienia
   sterować na makiecie**, albo wskaż konkretne lokomotywy.
4. Kliknij **Wygeneruj kod parowania**.

Strona pokaże kod i krótką instrukcję dla wybranego typu aplikacji. Kod jest ważny
tylko kilka minut — w razie potrzeby wygeneruj nowy.

Jeśli na liście nie ma centralki, poproś osobę obsługującą BigFreda w klubie o
włączenie obsługi pilotów na tej makiecie.

## Aplikacja Z21

1. Na stronie parowania wybierz zakładkę **Aplikacja Z21** i zanotuj wartości
   **CV3** oraz **CV4**.
2. W aplikacji Z21 połącz się z BigFredem adresem podanym w klubie (ten sam, co
   na stronie parowania).
3. Na dowolnej lokomotywie — nie ma znaczenia, którą wybierzesz; żadne wartości CV
   nie trafiają do prawdziwej lokomotywy — wejdź w programowanie i wpisz **CV3**
   oraz **CV4** zgodnie z wartościami z BigFreda.

Po udanym parowaniu strona pokaże status **Sparowany**.

## ROCO Z21 WlanMaus

### Parowanie klawiaturą

1. Otwórz dowolną lokomotywę.
2. Wpisz kod parowania klawiaturą funkcyjną (np. 168421 → F1 F6 F8 F4 F2 F1).

## Engine Driver / WiThrottle

1. Na stronie parowania wybierz zakładkę **WiThrottle / Engine Driver** i
   zanotuj kod parowania.
2. W aplikacji połącz się z BigFredem adresem podanym w klubie.
3. Dokończ parowanie na jeden z dwóch sposobów:
   - ustaw **nazwę urządzenia** na sześciocyfrowy kod (bez spacji), albo
   - z listy lokomotyw wybierz **Pair with BigFred** i naciśnij klawisze
     funkcyjne **F0–F9** po jednej cyfrze kodu (np. kod `122145`: F1, F2, F2, F1,
     F4, F5).

Po udanym parowaniu strona pokaże status **Sparowany**. Potem możesz wybrać
właściwą lokomotywę z listy.

## Podczas jazdy

- Trzymaj aplikację otwartą i połączoną. Przy zbyt długiej bezczynności BigFred
  kończy sesję i może zahamować składy — wtedy sparuj się ponownie.
- Listę dozwolonych lokomotyw możesz zmienić na stronie parowania i zapisać
  przyciskiem **Zapisz** bez nowego kodu.
- Po zakończeniu użyj **Rozłącz pilot** na stronie parowania albo zamknij aplikację
  w zwykły sposób.

## Coś nie działa?

| Problem | Co zrobić |
|---------|-----------|
| Brak centralki na liście | Poproś operatora BigFreda w klubie o włączenie pilotów na tej makiecie. |
| Kod parowania wygasł | Wygeneruj nowy kod na stronie parowania. |
| Lokomotywa nie jedzie | Sprawdź, czy jest na makiecie i w twoim zakresie pojazdów. |
| Połączenie się urwało | Otwórz aplikację ponownie w tej samej sieci Wi‑Fi i sparuj się jeszcze raz. |
