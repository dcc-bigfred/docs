# Clean code

Clean code is the practical, day-to-day counterpart to the design principles
in [solid.md](solid.md) and [design-principles.md](design-principles.md).
Where SOLID tells you *how to structure* code, clean code tells you *how to
write* the lines inside it. The goal is the same: code that a stranger can
read in one pass and change without fear.

This page distils [Writing efficient Go code — clean code principles, code
smells, and conventions](https://medium.com/@prawiraa.rivan/writing-efficient-go-code-clean-code-principles-code-smells-and-conventions-4117acfc2cb3)
onto the BigFred domain. Go-specific idioms (formatting, naming, interfaces,
concurrency) live in [idiomatic-go.md](idiomatic-go.md); here we keep the
language-agnostic principles and the smell catalogue.

## The clean code principles

### Meaningful names

A name should answer *what*, not *how*. If a reader has to open the body to
guess what a variable holds, the name failed.

- `d` is a bad name for a duration; `handshakeTimeout` is good.
- `data` and `info` are non-names; `pkt` (a DCC packet) and `roster` (the
  locomotive roster) carry meaning.
- Booleans read as predicates: `isPaired`, `hasSensors`, not `pair` or
  `sensor`.
- Consistency: if the codebase says `loco`, do not rename it to `engine` in
  one file — synonyms cost more than they save.

### Small functions, one job

A function does one thing at one level of abstraction. Heuristics:

- **Extract at the dotted depth.** If a function mixes "send a packet"
  (`cs.Send(pkt)`) with "encode the packet bytes" (`binary.Write(...)`), it
  spans two levels — extract the lower one.
- **Few arguments.** Zero is ideal, one or two is fine, three is suspect,
  four usually means a missing type (group them into a `Request` struct).
  Boolean parameters often flag a function doing two things — split it.
- **No flag arguments.** `Render(html bool)` is two functions hiding inside
  one; write `RenderHTML()` and `RenderText()`.
- **Guard clauses over nesting.** Handle the error / empty case early with a
  `return`; keep the happy path at the left margin.

```go
// Smell: deep nesting, mixed levels.
func (s *Service) Lend(locoID, userID int) (*Lease, error) {
    loco, err := s.locos.Get(locoID)
    if err == nil {
        user, err := s.users.Get(userID)
        if err == nil {
            if s.policy.CanLend(user, loco) {
                lease := &Lease{Loco: loco, User: user}
                return lease, nil
            }
            return nil, ErrForbidden
        }
        return nil, err
    }
    return nil, err
}

// Clean: guard clauses, one level of abstraction.
func (s *Service) Lend(locoID, userID int) (*Lease, error) {
    loco, err := s.locos.Get(locoID)
    if err != nil {
        return nil, err
    }
    user, err := s.users.Get(userID)
    if err != nil {
        return nil, err
    }
    if err := s.policy.CanLend(user, loco); err != nil {
        return nil, err
    }
    return &Lease{Loco: loco, User: user}, nil
}
```

### Single level of abstraction per function

Every line inside a function should sit at the same level. If `Lend` calls
`Get` (high level) and then `binary.BigEndian.PutUint16` (low level) in the
same body, the reader jumps between abstractions. Push the low-level line
into a helper named after its intent.

### No hidden side effects

A function called `IsValid` should not write to the database. A function
called `Get` should not mutate the value it returns. If a function has a
side effect, its name or signature should advertise it — or it belongs in a
type whose state it changes.

### Comments explain *why*

Code says *what*; comments say *why*. A comment that restates the code
(`// increment i` next to `i++`) is noise; delete it. A comment that records
a non-obvious constraint (`// Z21 requires the address high byte first`)
earns its keep. See [idiomatic-go.md](idiomatic-go.md#comments) for the Go
doc-comment conventions.

### Error handling is part of the contract

Errors are not exceptional control flow; they are values the caller decides
about. Wrap with context at the layer boundary, check every error, and never
log-and-return — pick one or the other. Full rules in
[idiomatic-go.md](idiomatic-go.md#error-handling).

### Pure where possible

A function with no side effects that depends only on its inputs is trivially
testable and refactorable. Keep parsing, encoding, validation and policy
decisions pure; push the I/O to the edges (handlers, repositories). This is
the [functional-core, imperative-shell](https://www.destroyallsoftware.com/talks/boundaries)
shape, and it lines up with SRP.

## Code smells to reject in review

| Smell | Fix |
| --- | --- |
| Deep nesting (`if` inside `if` inside `for`) | Guard clauses / early return |
| Functions over ~50 lines doing several things | Extract helpers, one level of abstraction |
| Mixing levels of abstraction in one function | Push the low-level step into a named helper |
| Functions with 4+ params or boolean flag params | Group into a struct, or split into two functions |
| Names like `data`, `info`, `temp`, `a`/`b` | Name after meaning (`pkt`, `roster`, `handshakeTimeout`) |
| Interfaces with many methods defined next to the only implementation | Move to consumer, shrink, or delete |
| `interface{}`/`any` where a concrete type works | Use the concrete type or a typed generic |
| Empty interface + type switch | A small interface per case |
| Global mutable state (`var cache = map[...]...`) | Pass it in, guard it, or wrap in a type |
| Functions with hidden side effects | Make the side effect explicit, or extract a pure function |
| Log-and-return (log inside a function that also returns the error) | Either handle it or return it — not both |
| Repeated error wrapping with the same string | Wrap once at the layer boundary |
| Unused parameters / return values | Redesign the signature |
| Comments that restate the code | Delete them; keep only *why* comments |
| Duplicated logic across handlers/repos | Extract the shared step; consider a small interface |

## Tests are clean code too

The smells apply to test code with extra force, because brittle tests block
refactors.

- One assertion concept per test; name the test after the behaviour
  (`TestLend_ForbiddenWhenPolicyDenies`), not the method.
- Build fixtures through helpers, not 40-line struct literals copied per
  test.
- Table-driven tests for inputs that share a path; separate tests for
  genuinely different behaviours.
- Avoid sleeping to wait for async work — use channels, `WaitGroup`, or a
  small fake clock.

## Tooling baseline

Every Go change should pass:

```bash
gofmt -l .           # empty output
go vet ./...
go test ./...
```

Add `staticcheck` and `golangci-lint` in CI for deeper checks, and
`go test -race ./...` for anything touching concurrency. The linters codify
many of the smells above; fix what they flag rather than silencing it.

---
*Source: [Writing efficient Go code — clean code principles, code smells, and conventions](https://medium.com/@prawiraa.rivan/writing-efficient-go-code-clean-code-principles-code-smells-and-conventions-4117acfc2cb3).*
