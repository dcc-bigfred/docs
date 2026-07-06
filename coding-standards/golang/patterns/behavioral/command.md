# Command

> Turns a request into a stand-alone object containing all information about
> the request.
>
> — [Refactoring Guru: Command](https://refactoring.guru/design-patterns/command)

Part of [Behavioral patterns](README.md).

## When it applies

- You queue, schedule or send requests across goroutines/processes.
- You need undo/redo.
- A UI element (button, menu) must trigger arbitrary operations without
  knowing them.

## Go form

For a single action, a `func() error` *is* a command. Reach for the explicit
interface only when you need undo, metadata, or polymorphic dispatch.

```go
package dccbus

type Command interface {
    Execute(ctx context.Context) error
    Undo(ctx context.Context) error
}

type setSpeedCmd struct {
    cs    CommandStation
    addr  int
    prev  int
    speed int
}

func NewSetSpeed(cs CommandStation, addr, speed int) Command {
    return &setSpeedCmd{cs: cs, addr: addr, speed: speed}
}

func (c *setSpeedCmd) Execute(ctx context.Context) error {
    prev, err := c.cs.CurrentSpeed(ctx, c.addr)
    if err != nil {
        return err
    }
    c.prev = prev
    return c.cs.SetSpeed(ctx, c.addr, c.speed)
}

func (c *setSpeedCmd) Undo(ctx context.Context) error {
    return c.cs.SetSpeed(ctx, c.addr, c.prev)
}
```

A `CommandHistory` is just a stack of `Command`; pushing after a successful
`Execute` and popping on undo is exactly the Refactoring Guru example
translated to Go.

## Avoid

- A `Command` interface with only `Execute()` and no undo/queueing — replace
  with a plain function value.
- Commands that capture the *whole* receiver by value when they only need a
  few fields; keep them small for queueing/serialisation.

## Related

- [Strategy](strategy.md) — a Strategy picks *how* to do one job; a Command
  encapsulates *one request* so it can be queued or undone.

---
*Source: [Refactoring Guru — Command](https://refactoring.guru/design-patterns/command).*
