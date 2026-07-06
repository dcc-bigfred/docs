# Go coding standards

This collection describes the conventions, structural rules and design patterns
we follow when writing Go code in the BigFred ecosystem (`bigfred`, `bigfred-os`,
`loco`, the `dcc-bus` packages and related tooling). It is a **standard**, not
a tutorial: read it to align new code with the rest of the project and to
resolve disagreements in review.

The material is distilled from the sources listed at the bottom of each page
and adapted to our domain (DCC model railway control, LocoNet, Z21). Examples
use real package and type names from the repository wherever it makes sense.

## What is in here

1. **[Project layout](project-layout.md)** — the reference directory structure
   for a Go service or library, mapped onto how `bigfred` is organised today.
2. **[Idiomatic Go](idiomatic-go.md)** — formatting, naming, packages, error
   handling, interfaces and the conventions that make Go read like Go.
3. **[SOLID](solid.md)** — the five principles (SRP, OCP, LSP, ISP, DIP) and
   how Go's interfaces and embedding give them a lighter flavour.
4. **[Clean code](clean-code.md)** — clean-code principles and the code-smell
   catalogue we reject in review.
5. **[Design principles](design-principles.md)** — Dependency Injection,
   Inversion of Control, KISS, and how they translate to Go's structs and
   interfaces.
6. **[Design patterns](patterns/)** — one file per pattern, grouped by
   category:
   - **[Creational](patterns/creational/)** — Factory Method, Prototype,
     Builder, Singleton, and the Go-specific Functional Options pattern.
   - **[Structural](patterns/structural/)** — Adapter, Composite, Proxy,
     Facade, Decorator.
   - **[Behavioral](patterns/behavioral/)** — Command, State, Visitor,
     Iterator, Observer, Strategy, Chain of Responsibility.
   - **[Concurrency](patterns/concurrency/)** — Worker Pool, Fan-Out / Fan-In,
     Pipeline, Rate Limiting, Pub/Sub over channels.

## How to use it

- **New package?** Start from [Project layout](project-layout.md) to decide
  where it lives (`cmd/`, `internal/`, `pkg/`, …) and from
  [Idiomatic Go](idiomatic-go.md) for naming and file shape.
- **New abstraction?** Check [SOLID](solid.md) and
  [Design principles](design-principles.md) before introducing an interface —
  Go rewards a small interface defined at the point of use.
- **Writing or refactoring a function?** Read [Clean code](clean-code.md) and
  run the smell list over the diff.
- **Solving a recurring problem?** Skim the [pattern pages](patterns/); the
  Go examples are intentionally short so you can recognise the shape, not
  copy-paste blindly. Apply a pattern only when the problem actually matches;
  Go's first-class functions, goroutines and channels already cover many
  cases that need a full pattern in class-based languages.

> **A word on patterns in Go.** Go is not Java. Several "Gang of Four"
> patterns collapse into a function or a single interface in Go (Strategy is
> a function value, Command is a `func()`, Iterator is `range` over a
> channel). Each pattern page calls this out explicitly so we do not
> over-engineer. When in doubt, prefer the idiomatic Go form over the
> textbook class hierarchy.

## Sources

The pages below build on, and should be read alongside:

- [golang-standards/project-layout](https://github.com/golang-standards/project-layout/blob/master/README.md)
- [Effective Go](https://go.dev/doc/effective_go)
- [Common Design Patterns In Golang](https://dev.to/truongpx396/common-design-patterns-in-golang-5789)
- [Effective Design Patterns in Go (Leapcell)](https://leapcell.medium.com/effective-design-patterns-in-go-b607c9bcbfda)
- [Refactoring Guru — Design Patterns](https://refactoring.guru/design-patterns)
- [The Single Responsibility Principle — Uncle Bob](https://blog.cleancoder.com/uncle-bob/2014/05/08/SingleReponsibilityPrinciple.html)
- Wikipedia: [Dependency inversion](https://en.wikipedia.org/wiki/Dependency_inversion_principle),
  [Dependency injection](https://en.wikipedia.org/wiki/Dependency_injection),
  [Inversion of control](https://en.wikipedia.org/wiki/Inversion_of_control),
  [KISS principle](https://en.wikipedia.org/wiki/KISS_principle)
- [Writing efficient Go code — clean code principles, code smells, conventions](https://medium.com/@prawiraa.rivan/writing-efficient-go-code-clean-code-principles-code-smells-and-conventions-4117acfc2cb3)
