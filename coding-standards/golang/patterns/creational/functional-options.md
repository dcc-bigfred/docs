# Functional Options

This is not a Gang-of-Four pattern but the idiomatic Go answer to "many
optional constructor parameters". It is what you should reach for *before* a
[Builder](builder.md) for plain configuration. Part of
[Creational patterns](README.md).

## Go form

```go
package z21server

type Server struct {
    host    string
    port    uint16
    timeout time.Duration
    log     *zerolog.Logger
}

type Option func(*Server)

func New(host string, port uint16, opts ...Option) *Server {
    s := &Server{
        host:    host,
        port:    port,
        timeout: 5 * time.Second, // sensible default
    }
    for _, opt := range opts {
        opt(s)
    }
    return s
}

func WithTimeout(d time.Duration) Option {
    return func(s *Server) { s.timeout = d }
}

func WithLogger(l *zerolog.Logger) Option {
    return func(s *Server) { s.log = l }
}

// Usage:
//   s := z21server.New("192.168.1.42", 21105,
//       z21server.WithTimeout(2*time.Second),
//       z21server.WithLogger(&log),
//   )
```

## Why it works well in Go

- Variadic `...Option` reads clearly at the call site, named-argument style.
- Defaults live in `New`; options override selectively.
- Adding a new option does not change any existing call site —
  [Open/Closed](../solid.md#o--openclosed-principle) with no interfaces.
- Composable: an option can apply other options, and you can bundle presets
  (`DevelopmentOpts()` returning `[]Option`).

## Variants

- **Options that validate** return an `Option` that records an error on the
  struct; `New` checks it after applying all options.
- **Options that close over context** can be built from config files:
  `FromConfig(cfg) Option`.

## Avoid

- Options for *required* parameters — those belong as named arguments to
  `New`. Mixing required fields into options makes "did the caller set it?" a
  run-time question instead of a compile-time one.

## Related

- [Builder](builder.md) — the heavier alternative when construction has
  ordered steps or cross-field invariants.
- [Factory Method](factory-method.md) — often takes `...Option` to configure
  the chosen product.

---
*Sources: [Common Design Patterns In Golang](https://dev.to/truongpx396/common-design-patterns-in-golang-5789),
[Effective Design Patterns in Go (Leapcell)](https://leapcell.medium.com/effective-design-patterns-in-go-b607c9bcbfda).*
