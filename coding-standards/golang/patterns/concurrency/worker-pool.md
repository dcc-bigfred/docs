# Worker Pool

Limits the number of concurrent goroutines working on a queue of jobs. Use it
to bound resource use (CPU, DB connections, in-flight Z21 commands). Part of
[Concurrency patterns](README.md).

```go
package pool

func Run(ctx context.Context, jobs <-chan Job, results chan<- Result, workers int) {
    var wg sync.WaitGroup
    wg.Add(workers)
    for w := 0; w < workers; w++ {
        go func() {
            defer wg.Done()
            for job := range jobs {
                select {
                case <-ctx.Done():
                    return
                case results <- doWork(job):
                }
            }
        }()
    }
    go func() {
        wg.Wait()
        close(results)
    }()
}
```

- **Use case**: bounded batch processing, HTTP request handling, file uploads.
- **Benefit**: controls concurrency; prevents goroutine explosions.
- **Discipline**: the caller closes `jobs` when no more work is coming; the
  pool closes `results` when all workers exit. Plumb a `context.Context` so a
  cancelled run does not leak workers.

## Related

- [Fan-Out / Fan-In](fan-out-fan-in.md) — a Worker Pool is the bounded form
  of fan-out with results merged back.

---
*Source: [Common Design Patterns In Golang](https://dev.to/truongpx396/common-design-patterns-in-golang-5789).*
