# Fan-Out / Fan-In

Splits a stream of work across N workers (fan-out) and merges their outputs
into a single channel (fan-in). Useful when each item is independent and
processing is CPU- or I/O-bound enough to parallelise. Part of
[Concurrency patterns](README.md).

```go
package fan

func FanOutFanIn(ctx context.Context, in <-chan int, workers int) <-chan int {
    out := make(chan int)
    var wg sync.WaitGroup
    wg.Add(workers)

    for w := 0; w < workers; w++ {
        go func() {
            defer wg.Done()
            for n := range in {
                select {
                case <-ctx.Done():
                    return
                case out <- n * n:
                }
            }
        }()
    }

    go func() {
        wg.Wait()
        close(out)
    }()
    return out
}
```

- **Use case**: web scraping, parallel API fan-out, batch transforms.
- **Benefit**: utilises multiple cores while presenting a single output stream
  to the consumer.
- **Discipline**: the merge goroutine must wait on the workers (`wg.Wait`)
  before closing `out`, otherwise the consumer sees a premature close.

## Related

- [Worker Pool](worker-pool.md) — the bounded version where work comes from a
  pre-filled job channel.
- [Pipeline](pipeline.md) — fan-out/fan-in is often a single stage of a
  pipeline.

---
*Source: [Common Design Patterns In Golang](https://dev.to/truongpx396/common-design-patterns-in-golang-5789).*
