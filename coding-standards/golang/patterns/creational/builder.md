# Builder

> Separates the construction of a complex object from its representation so
> the same construction process can create different representations.
>
> — [Refactoring Guru: Builder](https://refactoring.guru/design-patterns/builder) (paraphrased)

Part of [Creational patterns](README.md).

## When it applies

- A struct has many optional fields and several required ones.
- Construction has invariants that must hold before the value is usable.
- The same set of steps should produce different outputs (e.g. an SQL builder
  for different dialects).

## Go form

A **fluent builder** returning the same pointer is the common shape. Validate
invariants in `Build()`. In Go, [Functional Options](functional-options.md)
often replaces the fluent builder for configuration — prefer options unless
construction has ordered steps or cross-field invariants.

```go
package z21server

type Config struct {
    Host       string
    Port       uint16
    Timeout    time.Duration
    MaxClients int
}

type configBuilder struct {
    cfg Config
    err error
}

func NewBuilder(host string, port uint16) *configBuilder {
    return &configBuilder{cfg: Config{Host: host, Port: port}}
}

func (b *configBuilder) WithTimeout(d time.Duration) *configBuilder {
    if d <= 0 {
        b.err = fmt.Errorf("z21server: timeout must be positive, got %v", d)
        return b
    }
    b.cfg.Timeout = d
    return b
}

func (b *configBuilder) WithMaxClients(n int) *configBuilder {
    if n <= 0 {
        b.err = fmt.Errorf("z21server: max clients must be positive, got %d", n)
        return b
    }
    b.cfg.MaxClients = n
    return b
}

func (b *configBuilder) Build() (Config, error) {
    if b.err != nil {
        return Config{}, b.err
    }
    if b.cfg.Timeout == 0 {
        b.cfg.Timeout = 5 * time.Second // default
    }
    return b.cfg, nil
}
```

## Avoid

- Builders that only set fields with no validation — a struct literal with
  named fields is simpler.
- Mutating the builder after `Build()`; return a value, not a shared pointer.

## Related

- [Functional Options](functional-options.md) — the lighter alternative for
  plain configuration. Reach for a Builder only when options are not enough
  (ordered steps, cross-field invariants, multiple representations).

---
*Source: [Refactoring Guru — Builder](https://refactoring.guru/design-patterns/builder).*
