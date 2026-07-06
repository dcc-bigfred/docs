# Design principles

The patterns in [patterns/](patterns/) only make sense against the principles
they serve. This page covers the principles that are *not* part of SOLID but
govern Go design day to day: **Dependency Injection**, **Inversion of
Control**, and **KISS**. The SOLID principles themselves live in
[solid.md](solid.md); DIP is summarised there and expanded here as a mechanism.

## Dependency Injection (DI)

> Dependency injection is a programming technique in which an object or
> function receives other objects or functions that it requires, as opposed to
> creating them internally.
>
> — [Wikipedia: Dependency injection](https://en.wikipedia.org/wiki/Dependency_injection)

DI is the *mechanism* that satisfies the Dependency Inversion Principle (the
"D" of SOLID, see [solid.md](solid.md)). A client declares what it needs
(usually via its constructor) and an external **injector** (the composition
root) supplies it. The four classic forms are constructor, method, setter and
interface injection; in Go **constructor injection dominates**.

### In Go

There is no DI container needed. The composition root is `cmd/<app>/main.go`,
which wires concrete implementations together and passes them to
constructors. The [Wikipedia Go example](https://en.wikipedia.org/wiki/Dependency_injection#Go)
passes a logger, `*sql.DB` and Redis client from `main` → router → controller
→ storage. We follow the same shape:

```go
// cmd/server/main.go — the composition root
func main() {
    log := zerolog.New(os.Stderr)
    db  := mustOpenDB(cfg.DSN)
    cs  := z21server.New(db, log)

    app := lease.NewService(cs.LocoStore())
    app.Run()
}
```

Rules:

- **Inject at construction, not via globals.** No `var DB *sql.DB` at package
  level that everyone reads.
- **The composition root is the *only* place that calls `new` / constructors
  for "injectable" services.** Below that, everything takes its dependencies
  as parameters.
- **Constructor injection keeps objects in a valid state** — a `Service`
  constructed without its store cannot exist, so there is no nil-deref at use
  time.
- **Method injection** for per-call dependencies (e.g. a `context.Context` or
  a per-request authoriser).
- **Avoid setter injection.** It lets a half-constructed object escape and
  invites data races. If you must, document the requirement and guard it.

## Inversion of Control (IoC)

> Inversion of control is a design principle in which custom-written portions
> of a computer program receive the flow of control from an external source
> (e.g. a framework). "Don't call us, we'll call you."
>
> — [Wikipedia: Inversion of control](https://en.wikipedia.org/wiki/Inversion_of_control)

IoC is the broader idea: your code is *called* by the framework/runtime
rather than calling it. Event loops, HTTP routers, `http.ServeMux` handlers,
`testing.T.Run` callbacks, the `database/sql` driver interface — all are IoC.
DI is one specific form ("inverting control over the implementations of
dependencies").

### In Go

- An `http.Handler` implements `ServeHTTP(w, r)` and is *called* by
  `net/http`. You do not drive the event loop.
- A `database/sql` driver implements `driver.Driver`; `database/sql` calls it.
- The standard library is built this way, so IoC in Go rarely needs a
  framework — you implement a small interface and hand the value to the
  library.
- Do not confuse the two IoC meanings: the original ("framework calls you")
  vs. the Java-framework sense ("container injects your dependencies"). Both
  apply in Go, but the first is far more common and needs no tooling.

```go
// IoC: you implement ServeHTTP; net/http calls it.
type LocoHandler struct{ svc *lease.Service }

func (h *LocoHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
    // the framework hands you the request; you do not run the loop
}

// main wires it: mux.Handle("/locos", &LocoHandler{svc: app})
```

## KISS — Keep It Simple, Stupid

> KISS implies that simplicity should be a design goal.
>
> — [Wikipedia: KISS principle](https://en.wikipedia.org/wiki/KISS_principle)

KISS is the meta-principle: every other principle here is subordinate to it.
A simpler solution that is obviously correct beats a clever one that is
subtly wrong. Variants abound ("keep it short and simple", "keep it stupidly
simple"); they all point the same way. KISS is also closely tied to
**YAGNI** ("You Aren't Gonna Need It") — do not build for hypothetical
futures.

### In Go

Go's design is KISS all the way down: one way to format, one way to do
dependencies (modules), no generics until they could be added simply,
explicit over implicit. Apply the same taste to your code:

- **Reach for the smallest tool that works.** A `sync.Mutex` before a channel
  pipeline; a plain struct before an interface; a function before a method.
- **Avoid speculative generality** (YAGNI). Do not add an interface "in case
  we swap implementations" — add it when you actually swap.
- **Prefer explicit wiring over reflection/magic.** A 30-line `main` that
  constructs everything by hand is clearer than a DI container with
  annotations.
- **Delete code.** "Perfection is reached not when there is nothing left to
  add, but when there is nothing left to take away" (Saint-Exupéry, quoted in
  the KISS article).

## How the principles interact

```
KISS  ──governs──▶  everything
SRP   ──drives───▶  package/type boundaries        (see solid.md)
DIP   ──achieved─▶  by DI (constructor injection) using Go interfaces
DI    ──enables──▶  IoC (the framework calls code that depends on abstractions)
```

When a design decision is hard, walk the chain: *What changes for different
reasons? (SRP) → What abstraction separates them? (DIP) → Who supplies the
implementation? (DI) → Who drives the flow? (IoC) → Is there a simpler shape?
(KISS)*

---
*Sources: Wikipedia
([Dependency injection](https://en.wikipedia.org/wiki/Dependency_injection),
[Inversion of control](https://en.wikipedia.org/wiki/Inversion_of_control),
[KISS principle](https://en.wikipedia.org/wiki/KISS_principle)).*
