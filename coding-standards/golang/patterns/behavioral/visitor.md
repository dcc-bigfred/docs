# Visitor

> Separates algorithms from the objects on which they operate.
>
> — [Refactoring Guru: Visitor](https://refactoring.guru/design-patterns/visitor)

Part of [Behavioral patterns](README.md).

## When it applies

- A stable hierarchy of element types, but many possible operations over them
  (export to XML, validate, render, collect stats).
- You cannot or do not want to add the operation to each element class.

## Go form

Go has no method overloading by type, so the classic Visitor uses an `accept`
method on each element that calls the matching `VisitX` on the visitor. Use
generics to reduce boilerplate where it helps.

```go
package functions

type Visitor interface {
    VisitSingle(*Single)
    VisitGroup(*Group)
}

type Function interface {
    Accept(v Visitor)
}

// Leaf
type Single struct{ Name string }
func (s *Single) Accept(v Visitor) { v.VisitSingle(s) }

// Composite
type Group struct{ Items []Function }
func (g *Group) Accept(v Visitor) { v.VisitGroup(g) }

// An operation expressed outside the hierarchy.
type EnabledCounter struct{ Count int }
func (c *EnabledCounter) VisitSingle(s *Single) {
    if s.Enabled() { c.Count++ }
}
func (c *EnabledCounter) VisitGroup(g *Group) {
    for _, f := range g.Items {
        f.Accept(c) // recurse uniformly
    }
}
```

## Avoid

- Visitor for a hierarchy that changes often — every new element type forces
  an update to every visitor (the pattern's main drawback). This is the
  [Open/Closed](../solid.md#o--openclosed-principle) trade-off in action:
  Visitor is open for new *operations* but closed against new *elements*.
- Visitor when a plain `range` + type switch reads better; Go's interfaces
  usually let you express the operation as a method on each type, which is
  preferable.

## Related

- [Composite](../structural/composite.md) — the classic element hierarchy
  Visitors walk over.

---
*Source: [Refactoring Guru — Visitor](https://refactoring.guru/design-patterns/visitor).*
