# Pub/Sub over channels

Decouples producers from consumers using channels: publishers send to a
broker, subscribers receive on their own channels. This is the event-driven
cousin of the in-process [Observer](../behavioral/observer.md), safe to use
across goroutines. Part of [Concurrency patterns](README.md).

```go
package pubsub

type Broker struct {
    mu   sync.Mutex
    subs map[string][]chan Event
}

func New() *Broker { return &Broker{subs: make(map[string][]chan Event)} }

func (b *Broker) Subscribe(topic string) <-chan Event {
    ch := make(chan Event, 16)
    b.mu.Lock()
    b.subs[topic] = append(b.subs[topic], ch)
    b.mu.Unlock()
    return ch
}

func (b *Broker) Publish(topic string, e Event) {
    b.mu.Lock()
    subs := append([]chan Event(nil), b.subs[topic]...)
    b.mu.Unlock()
    for _, ch := range subs {
        select {
        case ch <- e:
        default: // drop if subscriber is slow; never block the publisher
        }
    }
}
```

- **Use case**: event broadcasting, sensor updates, layout state changes.
- **Benefit**: producers do not know how many consumers exist or how slow they
  are.
- **Discipline**: decide the slow-subscriber policy explicitly — drop
  (`default:`), block, or buffer. Buffer-then-drop is usually safest for
  telemetry; block for command delivery where losing an event is worse than a
  stall. Provide an `Unsubscribe` that closes the channel, and never publish
  on a closed channel.

## Related

- [Observer](../behavioral/observer.md) — the single-goroutine, callback-list
  form. Prefer Pub/Sub once events cross goroutine boundaries.

---
*Source: [Common Design Patterns In Golang](https://dev.to/truongpx396/common-design-patterns-in-golang-5789).*
