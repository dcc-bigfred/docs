# Adapter

> Allows objects with incompatible interfaces to collaborate.
>
> — [Refactoring Guru: Adapter](https://refactoring.guru/design-patterns/adapter)

Part of [Structural patterns](README.md).

## When it applies

- You have a third-party or legacy type whose interface does not match the one
  your code expects.
- You want to use a library without letting its API leak through your domain
  boundary.

## Go form

An **object adapter** is a struct that embeds (or holds) the adaptee and
implements the target interface, translating each call. Go's implicit
interfaces mean the adapter does not need to declare it implements anything —
satisfying the method set is enough.

```go
package dccbus

// Target interface our code wants.
type CommandStation interface {
    SetSpeed(addr int, speed int) error
}

// Adaptee: a legacy LocoNet library with a very different call shape.
type legacyLoconet struct{ /* … */ }
func (l *legacyLoconet) Write(msg []byte) error { /* … */ return nil }

// Adapter.
type loconetAdapter struct{ bus *legacyLoconet }

func NewLoconetAdapter(bus *legacyLoconet) CommandStation {
    return &loconetAdapter{bus: bus}
}

func (a *loconetAdapter) SetSpeed(addr int, speed int) error {
    pkt := encodeLocoSpeed(addr, speed) // translate to the legacy byte format
    return a.bus.Write(pkt)
}
```

## Avoid

- Adapters that add nothing — if the adaptee already satisfies the target
  interface, the adapter is dead weight.
- "Two-way adapters" with methods from both interfaces; they violate
  [Interface Segregation](../solid.md#i--interface-segregation-principle) and
  confuse callers.

## Related

- [Decorator](decorator.md), [Proxy](proxy.md), [Facade](facade.md) — same
  "wraps something" structure, different intent. See the comparison table in
  [Decorator](decorator.md#decorator-vs-proxy-vs-adapter-vs-facade).

---
*Source: [Refactoring Guru — Adapter](https://refactoring.guru/design-patterns/adapter).*
