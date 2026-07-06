# Idiomatic Go

Go rewards code that reads the way other Go code reads. A line-for-line
translation from Java or Python usually produces something that compiles but
feels wrong. This page collects the Go-specific conventions that make code
idiomatic, readable and maintainable. It is a summary of
[Effective Go](https://go.dev/doc/effective_go) and the
[Go code review comments](https://go.dev/wiki/CodeReviewComments). The
language-agnostic clean-code principles and the code-smell catalogue live in
[clean-code.md](clean-code.md).

## Formatting

- **Run `gofmt` (or `go fmt`).** Do not hand-format. Indentation is tabs; line
  length is unlimited; `gofmt` aligns struct fields and comments for you.
- **`goimports`** over `gofmt` — it also manages the import block. Configure
  your editor to run it on save.
- If the output of `gofmt` looks wrong, rearrange your code rather than
  working around the tool.

## Naming

Good naming is most of Go's readability. From
[Effective Go](https://go.dev/doc/effective_go) and the
[Go code review comments](https://go.dev/wiki/CodeReviewComments):

- **Package names** are short, lowercase, single word where possible
  (`http`, `z21server`, `dccbus`). No `snake_case`, no `camelCase`, no
  `util`/`common`/`helpers` — these signal a grab-bag with no cohesion. The
  package name is part of the identifier the caller types, so prefer
  `dccbus.Client`, not `dccbus.DccBusClient`.
- **Exported identifiers** use `CamelCase`; unexported use `camelCase`.
- **Acronyms** keep their case: ` ServeHTTP`, `XMLID`, `Z21Address` — pick a
  convention and apply it consistently.
- **Getters** do not start with `Get`; a getter for `owner` is `Owner()`.
  Setters *do* use the `Set` prefix: `SetOwner()`.
- **Interface names** usually describe one method: `Reader`, `Closer`,
  `CommandStation`. A capability interface with one method is the most
  reusable kind.
- **Receiver names** are short, consistent across methods, and never `this`
  or `self`. For `CommandStation` use `cs` in every method.
- **Shadowing** — do not name a variable the same as a package or a control
  flow builtin (`range`, `type`); it confuses readers and tooling.

## Packages

- **One package per directory, one directory per package.** A package's files
  share visibility; splitting cohesive types across directories forces
  exported identifiers where none are needed.
- **Cohesion over size.** Prefer a few well-named packages over many tiny
  ones. A package should cover one concept end-to-end (e.g. `z21server`:
  packets, server loop, track control) rather than one type each.
- **Avoid cycles.** Go forbids import cycles; if you feel one coming, the
  boundary is in the wrong place — extract a shared small package or define an
  interface in the consuming package.
- **Package comments.** Every package should have a `// Package foo ...`
  comment, ideally in a `doc.go` file, that says what the package is for in one
  or two sentences.

## Interfaces

- **Define interfaces at the point of use, not the point of implementation.**
  The consumer knows which methods it needs; let it declare the smallest
  interface that satisfies those needs. A `LocoStore` interface belongs next to
  the code that needs a store, not next to the SQLite implementation.
- **Accept interfaces, return structs.** This is the canonical Go API rule.
  It keeps the call site flexible (any implementation that satisfies the
  interface) while the constructor commits to one concrete type.
- **Keep interfaces small.** `io.Reader` has one method for a reason. Big
  interfaces are a smell — split them or use composition
  (`io.ReadWriteCloser`).
- **Do not declare an interface just to mock.** A concrete struct is testable
  with a fake or by faking its collaborators. Introduce an interface when
  there is a real second implementation or a testing seam you actually use.

## Functions and methods

- **Functions over methods when there is no state.** A free function
  `ParseAddress(s string) (Address, error)` is clearer than a method on a
  stateless type.
- **Value receivers vs pointer receivers.** Choose by the rules: pointer
  receiver if the method mutates, the value is large, or the type is
  inherently a handle (`*Client`, `*Server`). Be consistent within a type —
  mixing is a smell.
- **Multiple return values with error last.** `func Get(id int) (*Loco, error)`.
- **Named returns** are for documentation and naked `return` only in short
  functions; do not use them to declare locals at the top of a 200-line
  function.
- **Defer** for cleanup (`mu.Unlock()`, `rows.Close()`, `wg.Done()`). Defer
  runs on return, including panics, which is usually what you want for
  resource release.

## Error handling

- **Errors are values.** Treat them as part of the return contract, not as
  exceptions.
- **Always check errors.** `_ = doSomething()` is acceptable only in `defer`
  cleanup or tests where the error is genuinely irrelevant. Otherwise: check
  it, wrap it, return it.
- **Wrap with context** using `fmt.Errorf("z21: read handshake: %w", err)`.
  The `%w` verb preserves the error chain for `errors.Is` / `errors.As`.
- **Sentinel errors** (`ErrNotFound`, `ErrNotPaired`) are fine for the small
  set of conditions callers branch on. Define them as package-level `var`
  values, not stringly-typed comparisons.
- **Custom error types** when callers need structured data
  (`type TimeoutError struct{ ... }`). Implement `Is`/`As` accordingly.
- **Do not log-and-return.** Either handle the error (log it, act on it) or
  return it up the stack — not both. Logging at every layer duplicates noise.

## Concurrency

- **Share memory by communicating; do not communicate by sharing memory.**
  Prefer channels over mutex-guarded fields when passing ownership or
  sequencing work.
- **`sync.Mutex` is fine** for protecting a small piece of state; reach for
  channels when you are coordinating *work* between goroutines.
- **Goroutines must have a lifecycle.** Every `go func` should have a clear
  owner who cancels it (`context.Context`) and a clear point where it ends.
  Leaked goroutines hold references and prevent GC.
- **Always pair `wg.Add(1)` with `defer wg.Done()`** at the top of the
  goroutine.
- **Close channels from the sender side**, once, after all sends. Receiving
  from a closed channel yields the zero value forever; sending panics.
- **`context.Context` is the first parameter** of any function that does I/O
  or may block. Plumb it through; respect `ctx.Done()`.

## Composition over inheritance

Go has no inheritance. Use **struct embedding** to compose behaviour and
**interfaces** to abstract over it. Embedding promotes the inner type's
methods, which is the Go equivalent of "is-a" — but it is forwarding, not
subclassing, and you cannot override the promoted method on the outer type.

## Comments

Comments document *why*, not *what*. The code already says what.

- Comments on exported identifiers are read by `go doc` and pkg.go.dev; write
  them as complete sentences starting with the identifier name:
  `// Loco represents a...`
- Avoid redundant comments (`// GetLoco returns the loco`). If the name and
  signature already say it, delete the comment.
- `// TODO(name): ...` to attribute follow-ups; revisit them in cleanup
  passes.

---
*Sources: [Effective Go](https://go.dev/doc/effective_go), [Go code review comments](https://go.dev/wiki/CodeReviewComments). Clean-code principles and the code-smell catalogue live in [clean-code.md](clean-code.md).*
