# Design patterns

Design patterns are reusable solutions to recurring design problems. They
are not prescriptive — they are a vocabulary and a set of shapes you
recognise, then adapt. In Go the toolbox is smaller than in class-based
languages: first-class functions, interfaces, struct embedding and goroutines
already cover many cases that need a full pattern elsewhere.

> **A word on patterns in Go.** Go is not Java. Several "Gang of Four"
> patterns collapse into a function or a single interface in Go (Strategy is
> a function value, Command is a `func()`, Iterator is `range` over a
> channel). Each pattern page calls this out explicitly so we do not
> over-engineer. When in doubt, prefer the idiomatic Go form over the
> textbook class hierarchy — and reach for [KISS](../design-principles.md)
> before any pattern.

## Catalogue

### Creational — [creational/](creational/)

Isolate the code that decides *what* to construct from the code that *uses*
the result.

- [Factory Method](creational/factory-method.md)
- [Prototype](creational/prototype.md)
- [Builder](creational/builder.md)
- [Singleton](creational/singleton.md)
- [Functional Options](creational/functional-options.md) — Go-native

### Structural — [structural/](structural/)

Compose types into larger structures without tight coupling.

- [Adapter](structural/adapter.md)
- [Composite](structural/composite.md)
- [Proxy](structural/proxy.md)
- [Facade](structural/facade.md)
- [Decorator](structural/decorator.md)

### Behavioral — [behavioral/](behavioral/)

Assign responsibility for communication between objects.

- [Command](behavioral/command.md)
- [State](behavioral/state.md)
- [Visitor](behavioral/visitor.md)
- [Iterator](behavioral/iterator.md)
- [Observer](behavioral/observer.md)
- [Strategy](behavioral/strategy.md)
- [Chain of Responsibility](behavioral/chain-of-responsibility.md)

### Concurrency — [concurrency/](concurrency/)

The idiomatic Go shapes built on goroutines, channels and `select`. Not GoF
patterns.

- [Worker Pool](concurrency/worker-pool.md)
- [Fan-Out / Fan-In](concurrency/fan-out-fan-in.md)
- [Pipeline](concurrency/pipeline.md)
- [Rate Limiting](concurrency/rate-limiting.md)
- [Pub/Sub over channels](concurrency/pub-sub.md)

## When to reach for a pattern

1. The problem actually matches the pattern's intent — not just its shape.
2. The simpler Go form (a function, a small interface, a plain struct) does
   not carry enough information.
3. You can name the pattern at the call site so the next reader recognises it.

If you cannot tick all three, [KISS](../design-principles.md) says: don't.

## Concurrency: cross-cutting rules

These apply to every [concurrency pattern](concurrency/) above and to ad-hoc
goroutine code:

- **Context everywhere.** Every stage, worker and loop must accept a
  `context.Context` and exit on `ctx.Done()`.
- **Close from the sender.** The goroutine that owns a channel closes it;
  receivers never close.
- **WaitGroups pair with `defer Done()`.** Put `defer wg.Done()` as the first
  line of every worker goroutine.
- **Bounded buffers or explicit drops.** Unbounded channels turn slow
  consumers into memory leaks.
- **Race detector.** Run `go test -race ./...` for any code that touches these
  patterns; it catches the ownership mistakes that compile fine and fail in
  production.

---
*Sources: [Refactoring Guru — Design Patterns](https://refactoring.guru/design-patterns),
[Common Design Patterns In Golang](https://dev.to/truongpx396/common-design-patterns-in-golang-5789),
[Effective Design Patterns in Go (Leapcell)](https://leapcell.medium.com/effective-design-patterns-in-go-b607c9bcbfda).*
