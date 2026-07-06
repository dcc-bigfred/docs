# Chain of Responsibility

> Passes a request along a chain of handlers until one handles it.
>
> — [Refactoring Guru: Chain of Responsibility](https://refactoring.guru/design-patterns/chain-of-responsibility)

Part of [Behavioral patterns](README.md).

## When it applies

- A request may be handled by any of several handlers, in order.
- HTTP middleware: logging → auth → rate limit → handler.

## Go form

The `http.Handler` middleware chain *is* Chain of Responsibility. The generic
form is a slice of handlers consulted in order, or nested function decorators.

```go
package dccbus

type Handler func(ctx context.Context, pkt Packet) error

// Link handlers so the first non-nil result wins.
func Link(handlers ...Handler) Handler {
    return func(ctx context.Context, pkt Packet) error {
        for _, h := range handlers {
            if h == nil {
                continue
            }
            if err := h(ctx, pkt); err != nil {
                return err // or: continue to next per your semantics
            }
        }
        return nil
    }
}
```

The classic "each handler either handles or forwards" semantics map to
middleware functions that call `next` only when they did not handle the
request.

## Avoid

- Chains where every handler runs on every request regardless — that is just a
  loop, not a chain.
- Chains built ad-hoc in many places; centralise construction so the order is
  visible and testable.

## Related

- [Decorator](../structural/decorator.md) — HTTP middleware is both at once:
  each layer Decorates the next and forms a Chain of Responsibility.

---
*Source: [Refactoring Guru — Chain of Responsibility](https://refactoring.guru/design-patterns/chain-of-responsibility).*
