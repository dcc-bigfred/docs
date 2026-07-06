# Singleton

> Ensures a single instance of a type exists across the application.
>
> — [Refactoring Guru: Singleton](https://refactoring.guru/design-patterns/singleton)

Part of [Creational patterns](README.md).

## When it applies

Rarely. Legitimate uses: a process-wide logger, a metrics registry, a cache
that *must* be unique. Most "I need one of these" cases are better served by
constructing one instance in `main` and injecting it (see
[Dependency Injection](../design-principles.md#dependency-injection-di)) —
that keeps the type testable and avoids hidden global state.

## Go form

`sync.Once` is the correct primitive — it is race-free and lets you return an
error from the one-time init.

```go
package log

import "sync"

type Logger struct{ /* … */ }

var (
    instance *Logger
    once     sync.Once
    initErr  error
)

func Default() (*Logger, error) {
    once.Do(func() {
        instance, initErr = newLoggerFromEnv()
    })
    return instance, initErr
}
```

## Avoid

- Package-level `var DB = openDB()` — untestable, hides errors, races on
  first use.
- Singletons that hold mutable business state. A singleton logger is fine; a
  singleton "current layout" is a bug farm.

## Related

- [Dependency Injection](../design-principles.md#dependency-injection-di) —
  the usual better answer to "I need one of these".

---
*Source: [Refactoring Guru — Singleton](https://refactoring.guru/design-patterns/singleton).*
