# Facade

> Provides a simplified interface to a complex subsystem.
>
> — [Refactoring Guru: Facade](https://refactoring.guru/design-patterns/facade)

Part of [Structural patterns](README.md).

## When it applies

- A subsystem has many collaborating types and callers only need a handful of
  operations.
- You want to hide internal structure behind a stable API so the subsystem can
  evolve freely.

## Go form

A facade is usually a single struct with a few methods that orchestrate the
subsystem's internal types. It is the natural shape of a "service" in Go.

```go
package lease

// The facade hides: LocoStore, UserRepository, AuditLog, Policy engine.
type Service struct {
    locos  LocoStore
    users  UserStore
    audit  AuditLog
    policy Policy
}

// Lend is one operation that callers care about; internally it coordinates
// four collaborators.
func (s *Service) Lend(ctx context.Context, locoID, userID int) (Lease, error) {
    l, err := s.locos.Get(ctx, locoID)
    if err != nil {
        return Lease{}, err
    }
    u, err := s.users.Get(ctx, userID)
    if err != nil {
        return Lease{}, err
    }
    if err := s.policy.CanLend(u, l); err != nil {
        return Lease{}, err
    }
    lease := Lease{Loco: l, User: u, Start: time.Now()}
    s.audit.Append(ctx, "lend", lease)
    return lease, nil
}
```

## Avoid

- A facade that grows into a god object with 40 methods. Split into multiple
  focused facades (an "Additional Facade" per the Refactoring Guru article).
  This is [Single Responsibility](../solid.md#s--single-responsibility-principle)
  applied to the facade itself.
- Bypassing the facade from inside the subsystem "just this once" — that
  breaks the encapsulation the facade was providing.

## Related

- [Adapter](adapter.md) — adapts one incompatible interface; a Facade defines
  a new, simpler one over many types.

---
*Source: [Refactoring Guru — Facade](https://refactoring.guru/design-patterns/facade).*
