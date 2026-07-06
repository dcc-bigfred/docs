# SOLID

SOLID is a set of five design principles intended to make object-oriented code
more understandable, flexible and maintainable. Coined by Robert C. Martin
("Uncle Bob") in the early 2000s, the acronym gathers principles that predate
it by decades. They are not Go-specific, but Go's interfaces and struct
embedding give them a distinct, often lighter flavour than in class-based
languages.

| Letter | Principle | One-line meaning |
| --- | --- | --- |
| **S** | Single Responsibility | A module has one reason to change — one actor it serves. |
| **O** | Open/Closed | Open for extension, closed for modification. |
| **L** | Liskov Substitution | Subtypes must be substitutable for their base types. |
| **I** | Interface Segregation | Many small, client-specific interfaces beat one fat interface. |
| **D** | Dependency Inversion | Depend on abstractions, not concrete details. |

The "D" overlaps with [Design principles](design-principles.md), where
Dependency Injection and Inversion of Control are discussed as the mechanisms
that realise it. This page keeps the five together for the canonical SOLID
view.

---

## S — Single Responsibility Principle

> Gather together the things that change for the same reasons. Separate those
> things that change for different reasons.
>
> — [Uncle Bob, The Single Responsibility Principle](https://blog.cleancoder.com/uncle-bob/2014/05/08/SingleReponsibilityPrinciple.html)

The SRP is widely misread as "a function should do one thing". It is really
about **people**: a module should have one reason to change, and that reason
is a single actor (person or tightly coupled group) whose interests it
serves. The classic example is an `Employee` type with `CalculatePay()`
(driven by Finance), `ReportHours()` (driven by Operations) and `Save()`
(driven by DBAs). Putting all three in one type means a change requested by
one actor can break the others.

### In Go

- A **package** is the unit of responsibility. `pkgs/bigfred/server/domain`
  owns the domain model; `pkgs/bigfred/dcc-bus/z21server` owns the Z21 wire
  protocol; the audit-log code owns audit invariants. Each is changed by a
  different concern and lives separately.
- A **struct** with methods serving unrelated actors is the SRP violation to
  look for. Split it: a `PayCalculator`, an `HoursReporter`, an
  `EmployeeRepository` — each depending only on the data it needs.
- A **function** that mixes layers (SQL inside a handler, HTML inside a
  calculation) violates SRP by mixing the actors that own each layer.

```go
// Smell: one type serving three actors.
type Employee struct{ /* … */ }
func (e *Employee) CalculatePay() Money   { /* finance */ }
func (e *Employee) ReportHours() string   { /* operations */ }
func (e *Employee) Save(db *sql.DB) error { /* DBAs */ }

// Better: split by actor, share the immutable data.
type Employee struct{ /* pure data */ }

type PayCalculator struct{ rules PayRules }
type HoursReporter struct{ fmt  ReportFormat }
type EmployeeStore struct{ db *sql.DB }
```

---

## O — Open/Closed Principle

> Software entities should be open for extension, but closed for modification.
>
> — Bertrand Meyer, *Object-Oriented Software Construction* (1988)

You should be able to add new behaviour without editing existing, working
code. The classic mechanism is polymorphism: new behaviour arrives as a new
implementation of an existing interface, and the caller — which depends on
the interface — does not change.

### In Go

Go interfaces are implicitly satisfied, which makes OCP almost free when you
have the right interface:

```go
// The audit sink is an interface; adding a new sink (file, syslog, NATS)
// does not touch the audit service.
type Sink interface {
    Append(ctx context.Context, entry Entry) error
}

type Service struct{ sink Sink }

// A new sink is added in its own package — AuditService is closed for
// modification, open for extension.
package nats_sink

type NATSSink struct{ conn *nats.Conn }
func (s *NATSSink) Append(ctx context.Context, e Entry) error { /* … */ }
```

The **Functional Options** pattern (see
[Creational patterns](patterns/creational/functional-options.md)) is another
OCP win: adding `WithFoo()` does not change any existing call site.

### Watch out

- OCP is not "every change must be a new type". Adding a field to a private
  struct, or a case to an internal switch, is fine — those are not contracts
  external code depends on. Reserve OCP discipline for the public surface.
- Do not pre-build extension points speculatively (YAGNI). Make the code
  extensible *when a second implementation actually shows up*.

---

## L — Liskov Substitution Principle

> If `S` is a subtype of `T`, then objects of type `T` may be replaced with
> objects of type `S` without breaking the program.
>
> — Barbara Liskov, 1987

A subtype must honour the contract of its base type: same inputs accepted,
same (or stronger) postconditions, no new exceptions callers do not expect.
Callers that depend on the base type must not need to know which subtype they
hold.

### In Go

Go has no inheritance, so LSP applies to **interface implementations** and to
**embedded structs** whose methods are promoted. The violations to look for:

- An implementation that panics on inputs the interface contract allows.
- An implementation that returns `errNotImplemented` for a method the
  interface advertises as always-working.
- A wrapper (decorator/proxy) that silently changes error semantics or
  concurrency guarantees — see
  [Structural patterns](patterns/structural/proxy.md).

```go
// Bad: a "read-only" store that implements LocoStore but panics on Update.
type ReadOnlyStore struct{ inner LocoStore }
func (s *ReadOnlyStore) Update(ctx context.Context, l Loco) error {
    panic("read-only") // callers of LocoStore do not expect this
}
```

A read-only store is not a `LocoStore`; it is a different, smaller interface
(`LocoReader`). LSP tells you to split the interface rather than fake the
methods — which is exactly Interface Segregation below.

---

## I — Interface Segregation Principle

> Clients should not be forced to depend on methods they do not use.
>
> — Robert C. Martin

Many small, client-specific interfaces are better than one fat "god
interface". A caller should depend only on the methods it actually calls.

### In Go

This is the Go-idiom heartland: **"the smaller the interface, the more
reusable"**. `io.Reader` is one method; `io.Writer` is one method; you
compose them into `io.ReadWriter` only when a caller needs both. Define
interfaces at the point of use, sized to what that caller needs.

```go
// Bad: one fat interface forces every store to implement everything.
type Store interface {
    GetLoco(ctx context.Context, id int) (Loco, error)
    UpdateLoco(ctx context.Context, l Loco) error
    ListLeases(ctx context.Context) ([]Lease, error)
    AppendAudit(ctx context.Context, e Entry) error
}

// Better: segregate by client. The lease service needs only LocoReader.
type LocoReader interface {
    GetLoco(ctx context.Context, id int) (Loco, error)
}
type LocoWriter interface {
    UpdateLoco(ctx context.Context, l Loco) error
}
type LeaseLister interface {
    ListLeases(ctx context.Context) ([]Lease, error)
}
type AuditSink interface {
    AppendAudit(ctx context.Context, e Entry) error
}
```

The Go standard library lives by this — `sort.Interface` is three methods,
`http.Handler` is one. Follow the same taste.

---

## D — Dependency Inversion Principle

> 1. High-level modules should not import anything from low-level modules. Both
>    should depend on abstractions (e.g., interfaces).
> 2. Abstractions should not depend on details. Details (concrete
>    implementations) should depend on abstractions.
>
> — [Wikipedia: Dependency inversion principle](https://en.wikipedia.org/wiki/Dependency_inversion_principle)

In a traditionally layered architecture, policy code depends on utility code,
which limits reuse of the policy. DIP inserts an **abstraction** (an interface)
owned by the high-level layer, and the low-level layer implements it. The
dependency direction is inverted: the low-level layer now depends on the
high-level layer's interface.

### In Go

Go interfaces make DIP trivial, and the "accept interfaces, return structs"
idiom is DIP in miniature.

```go
// High-level policy: the lease service defines the store it needs.
package lease

type LocoStore interface {
    Get(ctx context.Context, id int) (Loco, error)
    Update(ctx context.Context, l Loco) error
}

type Service struct{ store LocoStore }

func NewService(store LocoStore) *Service { return &Service{store: store} }
```

```go
// Low-level detail: the SQLite repository implements the high-level
// interface. The arrow points up, not down.
package sqlite

type LocoRepo struct{ db *sql.DB }

func (r *LocoRepo) Get(ctx context.Context, id int) (lease.Loco, error) { /* … */ }
```

The `lease` package never imports `sqlite`. Tests pass a fake `LocoStore`. A
future Redis-backed store drops in without touching `lease`.

### DIP caveats (from the Wikipedia article)

- Slapping an interface on every class does not reduce coupling by itself —
  only *thinking about the abstraction of the interaction* does.
- An interface with a single implementation whose only other implementation
  is a mock is a code smell, not DIP.
- Generalising DIP everywhere forces factories/DI containers and makes code
  harder to follow. Apply it where there is a real second implementation or a
  genuine testing seam.

The mechanisms that satisfy DIP — **Dependency Injection** and **Inversion of
Control** — are covered in [Design principles](design-principles.md).

---

## How the five fit together

```
SRP  ──tells you───▶  where to draw package/type boundaries
OCP  ──tells you───▶  how to add behaviour without editing old code
LSP  ──tells you───▶  what an implementation must promise
ISP  ──tells you───▶  how big each interface should be
DIP  ──tells you───▶  which direction dependencies should point
```

SRP decides the seams; ISP sizes the interfaces at those seams; DIP points
them at abstractions; LSP keeps the implementations honest; OCP is the
payoff — new behaviour is additive, not surgical.

---
*Sources: [The Single Responsibility Principle — Uncle Bob](https://blog.cleancoder.com/uncle-bob/2014/05/08/SingleReponsibilityPrinciple.html),
Wikipedia [Dependency inversion principle](https://en.wikipedia.org/wiki/Dependency_inversion_principle),
[Writing efficient Go code](https://medium.com/@prawiraa.rivan/writing-efficient-go-code-clean-code-principles-code-smells-and-conventions-4117acfc2cb3).*
