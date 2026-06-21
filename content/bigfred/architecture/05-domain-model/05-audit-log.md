### 3a.5 Audit log

> **Implementation status: shipped (M2).** The audit log uses **Redis
> Streams** as its storage medium. The planned SQL-based implementation
> described below was superseded by this lighter-weight operational log.

---

#### Storage: Redis Stream

All audit entries are appended to a single global Redis Stream under the
key `bigfred:audit`. Entries are serialised as JSON and stored in the
stream's `payload` field. The stream is trimmed to ≈ 5 000 entries
(`MAXLEN ~ 5000 APPROX`) and its TTL is refreshed to **24 hours** on
every write, so an idle installation automatically evicts old data
without a janitor.

The `AuditService` lives in `pkgs/bigfred/server/service/audit.go` and
exposes two methods:

```go
// Publish implements cmd.AuditPublisher.
// layoutID = 0 means the event is not scoped to a specific layout.
func (s *AuditService) Publish(
    ctx      context.Context,
    layoutID uint,
    actor    cmd.AuditActor, // {UserID, Login}
    msg      string,         // i18n key, e.g. "audit_radio_stop"
    vars     map[string]string, // template variables interpolated on the frontend
) error

// List returns up to `limit` entries in newest-first order.
func (s *AuditService) List(ctx context.Context, limit int) ([]contract.AuditEntryWire, error)
```

`cmd.AuditPublisher` is the narrow interface injected into every cmd
struct that emits events. Passing `nil` is always safe — every call site
nil-guards the publisher.

---

#### Wire format (stored in each stream entry)

```json
{
  "layoutId":   2,
  "actorId":    42,
  "actorLogin": "Damian",
  "msg":        "audit_radio_stop",
  "vars":       { "layout": "Makieta główna" },
  "occurredAt": 1718784023000
}
```

The `streamId` field is the Redis entry ID and is **not** stored inside
the payload — it is populated at read time.

---

#### Audited events

| i18n key | Emitted by | Vars |
|---|---|---|
| `audit_radio_stop` | `cmd.RadioStop.Trigger` | — |
| `audit_estop_target` | `cmd.EStopTarget.Trigger` | `target`, `targetId` |
| `audit_layout_updated` | `httpapi.LayoutHandler.Update` | `name` |
| `audit_layout_locked` | `httpapi.LayoutHandler.Lock` | `name` |
| `audit_layout_unlocked` | `httpapi.LayoutHandler.Unlock` | `name` |
| `audit_command_station_updated` | `httpapi.CommandStationHandler.Update` | `name` |
| `audit_command_station_deleted` | `httpapi.CommandStationHandler.Delete` | `name` |
| `audit_takeover_granted` | `cmd.Takeover.autoGrant` | `driver`, `target`, `vehicle` |
| `audit_user_created` | `httpapi.UserHandler.Create` | `target` |
| `audit_user_updated` | `httpapi.UserHandler.Update` | `target` |
| `audit_user_deleted` | `httpapi.UserHandler.Delete` | `target` |
| `audit_user_activated` | `httpapi.UserHandler.Activate` | `target` |
| `audit_user_deactivated` | `httpapi.UserHandler.Deactivate` | `target` |
| `audit_roster_vehicle_added` | `httpapi.LayoutRosterHandler.AddVehicle` | `vehicle` |
| `audit_roster_vehicle_removed` | `httpapi.LayoutRosterHandler.RemoveVehicle` | `vehicle` |
| `audit_roster_train_added` | `httpapi.LayoutRosterHandler.AddTrain` | `train` |
| `audit_roster_train_removed` | `httpapi.LayoutRosterHandler.RemoveTrain` | `train` |

---

#### REST API

```
GET /api/v1/audit-log?limit=<n>
```

- Requires: authenticated session (any role).
- Returns `{ "entries": [...] }` with entries sorted newest-first.
- Default `limit` = 200, maximum = 500.
- Returns an empty list when Redis is unavailable.

---

#### Frontend

The **Audit log** view is accessible to all logged-in users via the
"My" menu in the top navigation bar (`/audit-log`). Refresh is manual
only (a "Refresh" button invalidates the React-Query cache and re-fetches).

Messages are translated on the frontend using the `audit` i18n namespace
(`web/src/i18n/locales/{pl,en}/audit.json`). The `msg` field is used as
the translation key under the `events` namespace group:

```ts
// example — audit:events.audit_radio_stop
t(`events.${entry.msg}`, { actorLogin: entry.actorLogin, ...entry.vars })
```

---

#### Write-path discipline

- Audit writes are **best-effort**: errors are silently discarded so a
  broken Redis connection never blocks a primary user action.
- There is no strict-mode variant — the operational nature of this log
  means data loss during a Redis outage is acceptable.

---

#### Retention & limitations compared to SQL

| Property | Redis Streams (current) | SQL (future option) |
|---|---|---|
| Ordering | Guaranteed (stream ID is monotonic) | Guaranteed |
| TTL | 24 h idle, auto-trimmed | Configurable (90 d in original design) |
| Max entries | ≈ 5 000 | Unlimited |
| Filtering | Client-side only | SQL WHERE |
| Persistence after restart | RDB by default (`save 60 100`; disable with `--redis-no-persist`) | Always |
| Access control | Any authenticated user | Admin-only (original design) |
