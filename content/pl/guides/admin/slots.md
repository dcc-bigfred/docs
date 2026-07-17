# Sloty

BigFred śledzi **kto może prowadzić który adres lokomotywy** przez **leaser**
(`slotlease`) w każdym daemonie `dcc-bus`. Zachowanie na **fizycznej
centralce** zależy od jej typu:

| | **LocoNet** | **Z21** |
|---|-------------|---------|
| Tabela slotów na centralce | Tak (~117 wpisów, IN_USE / COMMON) | **Nie** — Z21 to push/pull po LAN |
| Acquire / release slotu | Sterownik LocoNet | Nie dotyczy |
| Budżet globalny (`max_loconet_slots`) | Tak (domyślnie 80) | **Nie używany** (w leaserze bez limitu) |
| Limit pojazdów per user | Tak (domyślnie 8) | Tak |
| Idle zdalnego pilota | Tak | Tak |
| Strona diagnostyki | Budżet + zajęte adresy | Tylko tabela lease (bez paska budżetu) |

Sam **`loco.subscribe` (podgląd) nie tworzy lease** — na każdym typie
centrali.

---

## LocoNet

Dwie warstwy:

| Warstwa | Rola |
|---------|------|
| **Leaser** | Posiadacze, limit per user, budżet, diagnostyka |
| **Sterownik LocoNet** | Zajęcie / zwolnienie slotu na centralce (NULL MOVE → IN_USE) |

**Slot na centralce rezerwuje sterownik**, gdy użytkownik z prawem jazdy
wysyła polecenie jazdy. Leaser egzekwuje politykę i synchronizuje stan przez
`SlotObserver`.

### Kiedy slot jest zajmowany (LocoNet)

| Akcja | Leaser | Sterownik |
|-------|--------|-----------|
| **`loco.select`** (throttle WS) | Holder + opcjonalnie `AcquireSlot` | IN_USE po select |
| Pierwszy **`loco.setSpeed`** | `Reserve` | Acquire przy `SetSpeed` / `SendFn` F0–F8 |
| **`train.select`** | Holder na każdy członek z trakcją | Acquire per adres |

Odrzucenie przy braku **CanDrive**, pełnym **`max_loconet_slots`**
(`bigfred_slot_budget_exceeded`), limicie **`max_vehicles_per_user`**
(`vehicle_cap_exceeded`) albo — gdy **`allocate_physical_slots`** jest włączone —
lokomotywie już IN_USE przez inny manipulator (`slot_in_use`).

### Kiedy slot jest zwalniany (LocoNet)

| Sytuacja | Czas |
|----------|------|
| **Przełącznik WS** A→B | Holder znika; slot IN_USE **~60 s** (grace), potem e-stop + `ReleaseSlot`. Powrót na A w grace reużywa slot. |
| **`loco.deselect`**, zamknięcie sesji, shutdown | E-stop + release **natychmiast** |
| **Eviction przy limicie usera** | **Natychmiast** |
| **Boot-stop** rosteru | Chwilowy acquire na stop; **zwolnienie**, jeśli slot nie był wcześniej IN_USE |

Lok wybrany w WS **nie** jest zwalniany po idle.

Wiersze Z21 / WiThrottle w tabeli idle (niżej) dotyczą pilota zdalnego
podłączonego do **centralki LocoNet**.

---

## Z21

Centrala Z21 **nie ma tabeli slotów** jak LocoNet. BigFred używa **tego
samego leasera** do księgowania: kto prowadzi adres, limity, idle,
diagnostyka.

Na Z21 **nie ma** `AcquireSlot` / `ReleaseSlot`. Wpis „lease” w diagnostyce
oznacza, że **BigFred uznaje user/sesję za prowadzącego ten adres** — nie
wiersz IN_USE w tabeli centrali.

### Kiedy powstaje lease (Z21)

| Akcja | Leaser | Sterownik Z21 |
|-------|--------|---------------|
| Pierwsza **jazda lub funkcja** z aplikacji Z21 / WiThrottle | `Select` + `Touch` (`source=z21` / `withrottle`) | Przekazanie komendy DCC do centrali |
| **`GET_LOCO_INFO`** (wybór lok w aplikacji) | **Bez lease** — tylko podgląd |
| **Throttle WS** na layoucie Z21 | Jak w LocoNet (`loco.select` / `Reserve`) | `SetSpeed` / funkcje przez Z21 |

`prepareHandsetLease` przy pierwszym pakiecie jazdy na dany adres i sesję
pilota. Przełączenie na inną lok w aplikacji Z21 **nie odznacza** poprzedniej
(D15): każdy niedawno prowadzony adres trzyma lease do **idle timeout** lub
rozłączenia.

### Kiedy lease się kończy (Z21)

| Sytuacja | Centrala | Leaser |
|----------|----------|--------|
| **Idle timeout** (`idle_timeout_secs`, domyślnie 60 s) | E-stop po LAN Z21 | Usunięcie lease |
| **Rozłączenie pilota** | — | `ReleaseSession` → e-stop |
| **Eviction limitu usera** | E-stop | Usunięcie lease |
| **WS `loco.deselect` / zamknięcie sesji** | E-stop | Usunięcie lease (bez grace slotu — na centralce nic nie trzyma IN_USE) |

Na Z21 **nie ma** sprawdzania `max_loconet_slots` — liczy się tylko ile
adresów user **prowadzi naraz** (`max_vehicles_per_user`).

### Z21 a LocoNet na tym samym layoucie

Layout ma **jedną** centralkę: albo LocoNet (sloty na magistrali), albo Z21
(bez slotów). Pilota Z21 podłączasz do daemonu obsługującego centralę Z21;
reguły slotów LocoNet wtedy nie obowiązują.

---

## Wspólne limity (konfiguracja)

**Admin → Centralki:**

| Ustawienie | LocoNet | Z21 |
|------------|---------|-----|
| **`max_loconet_slots`** | Max slotów IN_USE przez BigFreda (domyślnie 80) | Ukryte / N/A |
| **`allocate_physical_slots`** | Wyłączna alokacja PE 1.0 jak fizyczny FRED (domyślnie **wł.**). Wył. = legacy piggyback na slot FRED-a | Ukryte / N/A |
| **`idle_timeout_secs`** | Zwolnienie pilota po bezczynności (domyślnie 60 s; 0 = wył.) | To samo |
| **`max_vehicles_per_user`** (layout) | Max prowadzonych pojazdów / user (domyślnie 8) | To samo |

---

## Diagnostyka w UI

1. **Admin → Centralki**
2. **Diagnostyka slotów** (ikona wskaźnika) przy wierszu  
   → **`/admin/dcc-bus/slots?cs=<id>`**

| Panel | LocoNet | Z21 |
|-------|---------|-----|
| **Budżet slotów** | `zajęte / max_loconet_slots` | „Aktywne lease (brak budżetu LocoNet)” |
| **Per użytkownik** | Prowadzone vs limit | To samo |
| **Zajęte adresy** | Posiadacze (`user · z21 · ws · …`) | To samo; `z21` / `withrottle` = pilot fizyczny |

Status: **Na żywo** / **Nieaktualne** / **Rozłączono**.

Na **LocoNet** wpis `0 · external` = IN_USE zgłoszone przez sterownik bez
holdera BigFreda; wlicza się do budżetu.
