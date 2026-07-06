# Proxy

> Provides a substitute or placeholder for another object to control access to
> it.
>
> — [Refactoring Guru: Proxy](https://refactoring.guru/design-patterns/proxy)

Part of [Structural patterns](README.md).

## When it applies

- **Virtual proxy**: lazy-init a heavyweight resource (a Z21 connection opened
  on first command).
- **Protection proxy**: check permissions before forwarding (an
  audit-authorised `CommandStation`).
- **Caching proxy**: return cached results for repeated reads (cached
  locomotive metadata).
- **Logging / metrics proxy**: wrap a real service to record every call.

## Go form

A proxy implements the same interface as the target and holds a reference to
it, doing work before/after delegating. Embedding the target promotes its
methods so the proxy only overrides what it intercepts.

```go
package dccbus

// Caching proxy for expensive locomotive lookups.
type cachedStore struct {
    inner LocoStore
    mu    sync.Mutex
    cache map[int]Loco
}

func NewCachedStore(inner LocoStore) LocoStore {
    return &cachedStore{inner: inner, cache: make(map[int]Loco)}
}

func (c *cachedStore) Get(ctx context.Context, id int) (Loco, error) {
    c.mu.Lock()
    if l, ok := c.cache[id]; ok {
        c.mu.Unlock()
        return l, nil
    }
    c.mu.Unlock()

    l, err := c.inner.Get(ctx, id)
    if err != nil {
        return Loco{}, err
    }
    c.mu.Lock()
    c.cache[id] = l
    c.mu.Unlock()
    return l, nil
}
```

## Avoid

- Proxies that change the contract (different errors, different concurrency
  guarantees) without documenting it — a proxy must be a drop-in. Silent
  contract changes are [Liskov Substitution](../solid.md#l--liskov-substitution-principle)
  violations.
- Stacking many proxies without a clear order; the order of
  logging → caching → auth matters and should be explicit at the composition
  root.

## Related

- [Decorator](decorator.md) — same wrapping shape, but a Decorator *adds*
  behaviour while a Proxy *controls access*.
- [Facade](facade.md) — hides a subsystem behind a new interface; a Proxy
  keeps the interface.

---
*Source: [Refactoring Guru — Proxy](https://refactoring.guru/design-patterns/proxy).*
