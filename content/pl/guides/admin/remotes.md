# Sesje pilotów

Sparowany pilot ma **dwa** niezależne stany. Ich pomieszanie to najczęstszy
powód, dla którego operator klubu nie rozumie, czemu pilota nie ma na liście
albo czemu parowanie zwraca **Masz już aktywną sesję pilota**.

| Stan | Gdzie żyje | Co oznacza |
|------|------------|------------|
| **Obecność** | Daemon `dcc-bus` tej centralki | Pilot jest **teraz** na liście klientów na stronie **Piloty** |
| **Parowanie** | Redis (`bigfred:remote:active:…`) | Użytkownik może wrócić **bez nowego kodu / PIN-u** |

WiThrottle może zniknąć z listy i wrócić bez ponownego parowania.
Pilot Z21 (ustawienia domyślne) nie: gdy wiersz znika, parowanie ginie razem
z nim.

Ta strona dotyczy **życia sesji**. Lease jazdy (kto może ruszyć który adres)
to osobna warstwa — zobacz [Sloty](slots.md).

---

## Trzy zegary

Każdy sparowany pilot podlega trzem timeoutom. Nie dzielą jednego ustawienia.

| Zegar | Domyślnie | Co się dzieje |
|-------|-----------|---------------|
| **Hamulec bezczynności** (`handsetBrakeSecs`, 6–60 s, domyślnie **6 s**) | Ustawiany przy parowaniu | Lokomotywy tego pilota są hamowane. Sesja zostaje. Wiersz dostaje znacznik **Zahamowano (bezczynność)**. |
| **Obecność** | Zależnie od protokołu (niżej) | Wiersz znika z żywej listy klientów |
| **Parowanie** | Zależnie od protokołu (niżej) | Sesja w Redisie jest kasowana; trzeba parować od nowa |

Każdy ruch UDP albo TCP liczy się jako aktywność, w tym keepalive’e, które
aplikacja Z21 wysyła w tle. „Cisza” znaczy **zero pakietów**, a nie „operator
nie rusza manetki”.

---

## Per protokół

### Aplikacja Z21 / WlanMaus — przypisanie do IP **wyłączone** (domyślnie)

Zgodnie z [Z21 LAN §1.1](../../specs/bigfred/protos/z21.md#11-communication):
klient, który nie wysyła UDP przez **60 sekund**, znika z listy uczestników.
BigFred w tej samej chwili **odparowuje**.

Klucz sesji to `IP:port`. Reconnect ze zmienionym portem źródłowym UDP
wygląda jak **nowy** pilot.

| Zdarzenie | Obecność | Parowanie | Co widzi użytkownik |
|-----------|----------|-----------|---------------------|
| Cisza **poniżej 6 s** | Zostaje | Zostaje | Normalna jazda |
| Cisza **6 s – 60 s** | Zostaje | Zostaje | Składy zahamowane; wiersz **Zahamowano (bezczynność)** |
| Cisza **ponad 60 s** | Znika | **Znika** | Trzeba parować od nowa |
| Aplikacja zamknięta / zanik Wi-Fi, powrót **w 60 s na tym samym IP:port** | Odświeżona | Zostaje | Kontynuacja |
| Reconnect z **nowym portem UDP** | Nowy wiersz | Stare parowanie nadal zajmuje użytkownika | Parowanie zwraca *masz już aktywną sesję*, aż stary wiersz wygaśnie (~60 s) albo ktoś kliknie **Usuń sparowanego pilota** |
| Restart `dcc-bus` | Lista pusta, potem odtworzona z Redisa | Zostaje (do 72 h bezczynnego TTL) | Można wrócić bez parowania aż do tego TTL |

Na tym wierszu **nie ma** podpisu „Sesja wygasa …”. Parowanie ginie razem z
obecnością, więc odliczanie nic by nie dodało ponad **Ostatnio widziany**.

### Aplikacja Z21 / WlanMaus — przypisanie do IP **włączone**

**Admin → Centralki** → *Przypisanie sesji do IP (IP stickiness)*.

Ta sama flaga robi **dwie** rzeczy naraz (nie da się ich rozdzielić w
konfiguracji):

1. Klucz sesji to samo **IP**, więc nowy port UDP na tym adresie to nadal
   ten sam pilot.
2. Obecność **i** parowanie trwają **72 godziny** ciszy zamiast 60 s.

| Zdarzenie | Obecność | Parowanie |
|-----------|----------|-----------|
| Cisza **ponad 60 s** | Zostaje (do 72 h) | Zostaje |
| Reconnect, **to samo IP, nowy port** | Ten sam wiersz | Zostaje |
| Reconnect, **inne IP** | Nowy wiersz | Stare parowanie trzyma użytkownika do odparowania albo 72 h |
| Dwa piloty za **tym samym IP NAT** | **Jedna** sesja | Drugie urządzenie dziedziczy parowanie pierwszego użytkownika |

Włączaj to tylko wtedy, gdy router klubu trzyma stabilne IP per pilot
(rezerwacja DHCP albo stickiness źródłowego IP na NAT). W przeciwnym razie
kolejny gość może dostać adres, na którym wciąż wisi cudze parowanie.

### WiThrottle / Engine Driver / WiFred

Obecność i parowanie są **rozdzielone**. Zamknięcie gniazda TCP (albo idle
sweep po **120 s** ciszy na zawieszonym gnieździe) usuwa wiersz. Parowanie w
Redisie żyje aż do **72 godzin** bez aktywności, aż pilot wyśle `Q`, albo aż
ktoś kliknie **Usuń sparowanego pilota**.

| Zdarzenie | Obecność | Parowanie | Co widzi użytkownik |
|-----------|----------|-----------|---------------------|
| Cisza **poniżej 6 s** | Zostaje | Zostaje | Normalna jazda |
| Cisza **6 s+** przy otwartym gnieździe | Zostaje | Zostaje | Składy zahamowane; wiersz **Zahamowano (bezczynność)** |
| Aplikacja zamknięta / rozłączenie TCP | Znika | **Zostaje** (72 h) | Ponowne otwarcie aplikacji w tej samej sieci Wi-Fi — **bez nowego kodu** |
| Cisza **ponad ~15 s** przy włączonym heartbeat (`*+`) | Znika (e-stop, potem zrzut obecności) | Zostaje | Jak przy rozłączeniu |
| Bezczynność **72 h** bez powrotu | Znika | **Znika** | Trzeba parować od nowa |
| Restart `dcc-bus` | Lista pusta | Zostaje | Reconnect bez parowania |

Podpis **Sesja wygasa …** jest tu pokazywany. To deadline parowania w Redisie
(ostatnio widziany + 72 h), a nie żywotność gniazda TCP.

---

## Co widać na stronie Piloty

**Menu → Moje → Piloty**, per centralka.

| UI | Znaczenie |
|----|-----------|
| Wiersz na liście | Obecność w żywym daemonie |
| **Zahamowano (bezczynność)** | Wszedł zegar hamulca; parowanie nadal ważne |
| **Sesja wygasa …** | Parowanie przeżywa obecność (WiThrottle albo Z21 z przypisaniem do IP). **Brak tego podpisu przy domyślnym Z21 jest oczekiwany.** |
| **Usuń sparowanego pilota** | Kasuje parowanie w Redisie **i** obecność. Właściciel może to zrobić dla własnej sesji. |

---

## Diagnostyka

| Objaw | Prawdopodobna przyczyna | Co zrobić |
|-------|-------------------------|-----------|
| Parowanie zwraca *Masz już aktywną sesję pilota* | Redis nadal trzyma parowanie tego użytkownika na tej centralce (inne urządzenie, zmiana portu Z21 albo WiThrottle, które się rozłączyło, ale wciąż jest sparowane) | Na **Pilotach** **Usuń sparowanego pilota** dla tego użytkownika albo poczekaj: ~60 s przy domyślnym Z21, do 72 h przy WiThrottle / sticky Z21 |
| Użytkownik Z21 musi parować od nowa po minucie w tunelu / na chwiejnym Wi-Fi | Domyślny Z21 idzie za LAN §1.1 (60 s bez UDP) | Oczekiwane. Jeśli klub ma stabilne IP per pilot, rozważ przypisanie do IP — i przeczytaj koszt wyżej |
| Użytkownik Z21 musi parować od nowa po każdym zablokowaniu ekranu, nawet po kilku sekundach | Zmienił się źródłowy port UDP; stary `IP:port` nadal zajmuje slot użytkownika | Poczekaj ~60 s albo włącz przypisanie do IP, jeśli adresy są zarezerwowane |
| WiThrottle zniknął z listy, a po otwarciu aplikacji dalej jedzie | Obecność spadła; parowanie przeżyło | Oczekiwane — to nie wyciek |
| Duch Z21 na liście, którego nikt nie trzyma | Sticky Z21 (albo restart daemona, który odtworzył parowanie) bez niedawnego UDP | **Usuń sparowanego pilota** albo poczekaj na 72 h TTL parowania |
| Dwa WlanMausy walczą o te same loki po włączeniu stickiness | Dzielą jedno publiczne/NAT IP, więc dzielą jedną sesję | Wyłącz stickiness albo daj każdemu pilotowi zarezerwowany adres DHCP |

---

## Powiązane

- Instrukcja użytkownika: [Piloty](../user/remotes.md)
- Reguła bezczynności Z21 LAN: [Protokół §1.1](../../specs/bigfred/protos/z21.md#11-communication)
- Lease jazdy (kto może ruszyć który adres): [Sloty](slots.md)
