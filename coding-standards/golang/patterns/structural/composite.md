# Composite

> Lets you compose objects into tree structures and work with them as if they
> were individual objects.
>
> — [Refactoring Guru: Composite](https://refactoring.guru/design-patterns/composite)

Part of [Structural patterns](README.md).

## When it applies

- Your domain is naturally a tree (a layout of track blocks, a function group
  with sub-groups, a menu of items).
- You want to treat a single element and a group uniformly through one
  interface.

## Go form

One interface, two implementations: a **leaf** and a **composite** that holds
a slice of the interface and delegates each method to its children.

```go
package functions

// A function group is either a single decoder function or a group of groups.
type Function interface {
    Enabled() bool
    Activate() error
}

// Leaf
type Single struct {
    Name    string
    Address int
    on      bool
}

func (s *Single) Enabled() bool   { return true }
func (s *Single) Activate() error { s.on = true; return nil }

// Composite
type Group struct {
    Label string
    items []Function
}

func (g *Group) Add(f Function)          { g.items = append(g.items, f) }
func (g *Group) Enabled() bool {
    for _, f := range g.items {
        if f.Enabled() {
            return true
        }
    }
    return false
}
func (g *Group) Activate() error {
    for _, f := range g.items {
        if err := f.Activate(); err != nil {
            return err
        }
    }
    return nil
}
```

A caller does not care whether it holds a `Single` or a `Group`; both are
`Function`.

## Avoid

- Adding type-switches on "is this a leaf or a composite?" in client code —
  that defeats the pattern. Push the behaviour into the interface.
- Composite trees with parent back-references and circular activation — model
  them carefully or use the [Visitor](../behavioral/visitor.md) pattern.

## Related

- [Visitor](../behavioral/visitor.md) — expresses operations over a Composite
  tree without adding a method to each node.
- [Prototype](../creational/prototype.md) — cloning a Composite requires
  recursing over the children.

---
*Source: [Refactoring Guru — Composite](https://refactoring.guru/design-patterns/composite).*
