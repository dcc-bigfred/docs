## 4. Communication Protocol

Two transports carry the application's traffic: REST for CRUD-like,
idempotent reads/writes, and a single WebSocket for everything that is
short, frequent and event-driven (throttle, takeover, radio,
Radio Stop, dead-man's switch, scripts).

## [REST](./01-rest.md)

Full endpoint catalogue under `/api/v1`.

## [WebSocket](./02-websocket.md)

Actions, events, envelope format.

## [Takeover state machine](./03-takeover-state-machine.md)

## [Radio – delivery rules](./04-radio-delivery.md)

## [Drive Session & Dead-Man's Switch](./05-drive-session-dms.md)

## [Radio Stop – layout-wide emergency halt](./06-radio-stop.md)
