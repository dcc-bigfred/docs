# Factory Method

> Provides an interface for creating objects in a superclass, but allows
> subclasses to alter the type of objects that will be created.
>
> — [Refactoring Guru: Factory Method](https://refactoring.guru/design-patterns/factory-method)

Part of [Creational patterns](README.md).

## When it applies

- The caller should not know which concrete type it gets, only the interface.
- Construction depends on a runtime value (a protocol kind, a config flag).
- You want to return cached/pooled instances instead of fresh ones — a
  factory method can do this; a constructor cannot.

## Go form

Go has no subclasses, so the "subclass overrides the factory" form is
replaced by a **factory function** that returns an interface. The "creator
with core logic that calls the factory" form still applies — embed a base
type and let the concrete factory pick the product.

```go
// Product — common interface for anything that talks the DCC bus.
package dccbus

type CommandStation interface {
    Send(pkt Packet) error
    Name() string
}

// Factory function: caller does not know whether it gets Z21 or LocoNet.
func New(kind string, opts ...Option) (CommandStation, error) {
    switch kind {
    case "z21":
        return z21server.New(opts...), nil
    case "loconet":
        return loconet.New(opts...), nil
    default:
        return nil, fmt.Errorf("dccbus: unknown command station %q", kind)
    }
}
```

## Avoid

- A `New` that just forwards every call to `&T{}` with no logic — that is a
  useless indirection. Keep the constructor public instead.
- A giant `switch` that grows every sprint — once it does, the Factory Method
  shape (one factory per kind, registered in a map) is the refactor.

```go
// Registration-based factory — open for extension without editing the switch.
var stations = map[string]func(...Option) CommandStation{}

func Register(kind string, ctor func(...Option) CommandStation) {
    stations[kind] = ctor
}

func New(kind string, opts ...Option) (CommandStation, error) {
    ctor, ok := stations[kind]
    if !ok {
        return nil, fmt.Errorf("dccbus: unknown %q", kind)
    }
    return ctor(opts...), nil
}
```

The registered-map form is the Go expression of [Open/Closed](../solid.md#o--openclosed-principle):
new command stations are added in their own package without editing the
factory's switch.

## Related

- [Functional Options](functional-options.md) — the companion idiom for the
  optional parameters a factory often takes.
- [Builder](builder.md) — when construction has ordered steps or cross-field
  invariants rather than a simple kind switch.

---
*Source: [Refactoring Guru — Factory Method](https://refactoring.guru/design-patterns/factory-method).*
