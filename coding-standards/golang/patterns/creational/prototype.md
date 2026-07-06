# Prototype

> Lets you copy existing objects without making your code dependent on their
> classes.
>
> — [Refactoring Guru: Prototype](https://refactoring.guru/design-patterns/prototype)

Part of [Creational patterns](README.md).

## When it applies

- You need a deep copy of a value whose concrete type you do not know (only
  an interface).
- You pre-build expensive templates and clone them per use instead of
  reconstructing from scratch.

## Go form

Go has no built-in `clone()`. Implement a `Clone()` method per type, or use a
generic `Clone[T any]` constraint. For pure data structs, a value copy
(`*cpy = src`) plus explicit cloning of slice/map/pointer fields is enough —
do not reach for `reflect DeepCopy` unless the type graph is truly opaque.

```go
package domain

// Loco is a pure data record; its template fields are copy-on-write.
type Loco struct {
    ID        int
    Name      string
    Address   int
    Functions []Function   // slice — must clone explicitly
    Meta      map[string]string
}

func (l Loco) Clone() Loco {
    cpy := l // copies scalars and the slice/map headers
    if l.Functions != nil {
        cpy.Functions = append([]Function(nil), l.Functions...)
    }
    if l.Meta != nil {
        cpy.Meta = make(map[string]string, len(l.Meta))
        for k, v := range l.Meta {
            cpy.Meta[k] = v
        }
    }
    return cpy
}
```

## Avoid

- Using `Clone` to paper over aliasing bugs — fix the ownership model.
- Cloning types that hold OS resources (`*sql.DB`, `*os.File`); a clone that
  shares the handle is rarely what you want.

## Related

- [Composite](../structural/composite.md) — when the cloned value is a tree,
  `Clone` must recurse over the children.

---
*Source: [Refactoring Guru — Prototype](https://refactoring.guru/design-patterns/prototype).*
