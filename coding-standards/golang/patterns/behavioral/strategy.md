# Strategy

> Defines a family of algorithms, encapsulates each one, and makes them
> interchangeable.
>
> — [Refactoring Guru: Strategy](https://refactoring.guru/design-patterns/strategy)

Part of [Behavioral patterns](README.md).

## When it applies

- You select an algorithm at runtime (a smoothing strategy, a packing policy).
- You want to avoid a big `switch` over "how to do X" inside one type.

## Go form

A **function value** is the smallest Strategy. Use an interface only when the
strategy carries state or needs several methods.

```go
package speedcurve

// Function-value strategy.
type Curve func(throttle float64) int

func Linear(throttle float64) int      { return int(throttle * 127) }
func Logarithmic(throttle float64) int { return int(math.Log1p(throttle*9) / math.Log(10) * 127) }

type Cab struct {
    curve Curve
}

func (c *Cab) SetThrottle(t float64) int { return c.curve(t) }

// Cab{curve: speedcurve.Logarithmic}.SetThrottle(0.5)
```

## Avoid

- An interface with one method named `Execute`/`Do` — a function type is
  clearer and cheaper.
- Strategy objects that secretly share mutable state — strategies should be
  stateless or own their state privately.

## Related

- [State](state.md) — same delegation shape, but State transitions between
  strategies itself over the object's lifetime.
- [Functional Options](../creational/functional-options.md) — a function value
  selecting behaviour, used at construction time.

---
*Source: [Refactoring Guru — Strategy](https://refactoring.guru/design-patterns/strategy).*
