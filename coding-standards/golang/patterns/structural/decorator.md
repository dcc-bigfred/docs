# Decorator

> Dynamically adds behavior to objects by wrapping them.
>
> — [Refactoring Guru: Decorator](https://refactoring.guru/design-patterns/decorator)

Part of [Structural patterns](README.md).

## When it applies

- You want to layer cross-cutting behaviour (logging, metrics, retries,
  caching, auth) around a core implementation without modifying it.
- You want to compose those layers in different combinations at the
  composition root.

## Go form

In Go, decorators are usually **functions that wrap a function** (the
`http.HandlerFunc` middleware idiom) or **structs that embed an interface and
override one method**. The function form is preferred when the decorated thing
is a single function; the struct form when it is a multi-method interface.

```go
// Function decorator: retry around a packet send.
type SendFunc func(ctx context.Context, pkt Packet) error

func WithRetry(max int, wait time.Duration, next SendFunc) SendFunc {
    return func(ctx context.Context, pkt Packet) error {
        var err error
        for attempt := 0; attempt < max; attempt++ {
            if err = next(ctx, pkt); err == nil {
                return nil
            }
            select {
            case <-time.After(wait):
            case <-ctx.Done():
                return ctx.Err()
            }
        }
        return fmt.Errorf("send: %d attempts: %w", max, err)
    }
}
```

```go
// Struct decorator: metrics around a CommandStation.
type meteredStation struct {
    CommandStation           // embedded interface promotes all methods
    metrics *Metrics
}

func NewMetered(inner CommandStation, m *Metrics) CommandStation {
    return &meteredStation{CommandStation: inner, metrics: m}
}

func (m *meteredStation) Send(pkt Packet) error {
    start := time.Now()
    err := m.CommandStation.Send(pkt)
    m.metrics.Observe("send", time.Since(start), err)
    return err
}
```

## Avoid

- Decorator stacks so deep you cannot tell which layer runs first — give each
  layer a name and assemble them in one place (`main`).
- Using decorators where a simple `if debug` flag would do — don't pay the
  abstraction cost for a one-off.

## Decorator vs Proxy vs Adapter vs Facade

They share the "wraps something" structure; the **intent** differs:

| Pattern | Same interface as target? | Intent |
| --- | --- | --- |
| Adapter | No (translates to a *different* one) | Make incompatible interfaces work together |
| Proxy | Yes | Control access (lazy, cache, auth, logging) |
| Decorator | Yes | Add behaviour, often composable and stackable |
| Facade | New, simpler interface | Hide a complex subsystem behind one entry point |

## Related

- [Chain of Responsibility](../behavioral/chain-of-responsibility.md) —
  HTTP middleware decorators are both Decorator and Chain of Responsibility at
  once.

---
*Source: [Refactoring Guru — Decorator](https://refactoring.guru/design-patterns/decorator).*
