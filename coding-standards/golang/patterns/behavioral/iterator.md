# Iterator

> Lets you traverse elements of a collection without exposing its underlying
> representation.
>
> — [Refactoring Guru: Iterator](https://refactoring.guru/design-patterns/iterator)

Part of [Behavioral patterns](README.md).

## When it applies

- The collection's internal structure (tree, graph, paged result) should not
  leak to callers.
- You want multiple independent traversals of the same collection.

## Go form

The idiomatic Go iterator is a **channel** or — since Go 1.23 — a
**range-over function** (`func(yield func(T) bool)`). Both let the caller
write a plain `for ... range` without knowing the structure.

```go
// Go 1.23+ range-over-function iterator over a layout's track blocks.
func (l *Layout) Blocks(yield func(*Block) bool) {
    for _, b := range l.blocks {
        if !yield(b) {
            return
        }
    }
}

// Caller:
for b := range layout.Blocks {
    render(b)
}
```

For pre-1.23 code, the channel form is the equivalent:

```go
func (l *Layout) Blocks(ctx context.Context) <-chan *Block {
    out := make(chan *Block)
    go func() {
        defer close(out)
        for _, b := range l.blocks {
            select {
            case out <- b:
            case <-ctx.Done():
                return
            }
        }
    }()
    return out
}
```

## Avoid

- A custom `Iterator` interface with `HasNext`/`Next` methods — it is a Java
  import; Go's `range` over a channel or function is shorter and composable.
- Channel iterators without a cancellation path — they leak goroutines if the
  caller stops early. Always accept a `context.Context` or use the
  range-over-function form.

## Related

- [Composite](../structural/composite.md) — iterating a Composite tree is a
  natural Iterator use case (often via a Visitor instead).

---
*Source: [Refactoring Guru — Iterator](https://refactoring.guru/design-patterns/iterator).*
