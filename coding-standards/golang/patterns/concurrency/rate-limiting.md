# Rate Limiting

Paces operations so downstream systems are not overwhelmed. Use
`time.Ticker` for simple "N per second" limits, or `golang.org/x/time/rate`
for token-bucket limits with burst. Part of [Concurrency patterns](README.md).

```go
package ratelimit

// One operation every `interval`.
func Paced(ctx context.Context, interval time.Duration, work func() error) error {
    ticker := time.NewTicker(interval)
    defer ticker.Stop()
    for {
        select {
        case <-ctx.Done():
            return ctx.Err()
        case <-ticker.C:
            if err := work(); err != nil {
                return err
            }
        }
    }
}
```

```go
// Token bucket: 5 ops/sec, burst of 2.
import "golang.org/x/time/rate"

limiter := rate.NewLimiter(5, 2)
if err := limiter.Wait(ctx); err != nil {
    return err
}
doWork()
```

- **Use case**: API rate limiting, protecting a Z21 command station from
  command floods, polling loops.
- **Benefit**: steady, controlled throughput.
- **Discipline**: pick the right primitive — `time.Ticker` is fixed-rate;
  `x/time/rate` allows bursts and is the right choice for most production
  limits.

---
*Source: [Common Design Patterns In Golang](https://dev.to/truongpx396/common-design-patterns-in-golang-5789).*
