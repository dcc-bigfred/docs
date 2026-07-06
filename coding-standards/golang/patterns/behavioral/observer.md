# Observer

> Defines a one-to-many dependency so that when one object changes state, all
> dependents are notified.
>
> — [Refactoring Guru: Observer](https://refactoring.guru/design-patterns/observer)

Part of [Behavioral patterns](README.md).

## When it applies

- Event-driven systems: locomotive state changes, sensor updates, presence.
- Decoupling a producer from an unknown number of consumers.

## Go form

A `Subject` keeps a slice of `Observer` interfaces; `Register`/`Notify` are
the only methods needed. For cross-goroutine delivery, prefer channels
([Pub/Sub](../concurrency/pub-sub.md)) over in-process callback lists.

```go
package sensor

type Observer interface {
    OnChange(addr int, value int)
}

type Detector struct {
    mu        sync.Mutex
    observers []Observer
}

func (d *Detector) Subscribe(o Observer) {
    d.mu.Lock()
    defer d.mu.Unlock()
    d.observers = append(d.observers, o)
}

func (d *Detector) fire(addr, value int) {
    d.mu.Lock()
    obs := append([]Observer(nil), d.observers...)
    d.mu.Unlock()
    for _, o := range obs {
        o.OnChange(addr, value) // never call under the lock
    }
}
```

## Avoid

- Calling observers while holding the subject's lock — deadlock waiting to
  happen. Snapshot the list, release the lock, then fire.
- Synchronous observers that do slow work; route to a channel/queue instead.

## Related

- [Pub/Sub over channels](../concurrency/pub-sub.md) — the concurrency-safe,
  cross-goroutine cousin of Observer, which is what most Go event systems
  actually need.

---
*Source: [Refactoring Guru — Observer](https://refactoring.guru/design-patterns/observer).*
