# State

> Lets an object alter its behavior when its internal state changes.
>
> — [Refactoring Guru: State](https://refactoring.guru/design-patterns/state)

Part of [Behavioral patterns](README.md).

## When it applies

- An object has a finite number of states and behaves differently in each.
- A type is filling up with `switch state { … }` branches across many
  methods.

## Go form

The context holds a `State` interface and delegates to it. Each concrete state
implements the interface and may swap the context's state to trigger a
transition. Keep a back-reference to the context only if the state needs to
read or change it.

```go
package handset

// A Z21 handset button behaves differently per playback state.
type State interface {
    ClickLock(h *Handset)
    ClickPlay(h *Handset)
    ClickNext(h *Handset)
}

type Handset struct {
    state State
    // …volume, playlist…
}

func (h *Handset) SetState(s State) { h.state = s }

func (h *Handset) ClickLock() { h.state.ClickLock(h) }
func (h *Handset) ClickPlay() { h.state.ClickPlay(h) }
func (h *Handset) ClickNext() { h.state.ClickNext(h) }

type Ready struct{}
func (Ready) ClickLock(h *Handset) { h.SetState(Locked{}) }
func (Ready) ClickPlay(h *Handset) { h.startPlayback(); h.SetState(Playing{}) }
func (Ready) ClickNext(h *Handset) { h.nextSong() }

type Playing struct{}
func (Playing) ClickPlay(h *Handset) { h.stopPlayback(); h.SetState(Ready{}) }
func (Playing) ClickLock(h *Handset) { h.SetState(Locked{}) }
func (Playing) ClickNext(h *Handset) { h.fastForward(5) }

type Locked struct{}
func (Locked) ClickLock(h *Handset) { h.SetState(Ready{}) }
func (Locked) ClickPlay(h *Handset) {} // no-op
func (Locked) ClickNext(h *Handset) {} // no-op
```

## Avoid

- The full pattern for two states with one method each — a single `switch` is
  simpler and [KISS](../design-principles.md)-correct.
- States that mutate shared context fields without a mutex when the context
  is used from multiple goroutines.

## Related

- [Strategy](strategy.md) — same "delegate to an interface" shape, but
  Strategy changes *an algorithm* once, while State changes *behaviour* over a
  lifetime and the object transitions between states itself.

---
*Source: [Refactoring Guru — State](https://refactoring.guru/design-patterns/state).*
