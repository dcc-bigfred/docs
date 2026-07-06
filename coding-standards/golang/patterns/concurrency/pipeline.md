# Pipeline

A series of stages, each reading from the previous stage's channel and
writing to the next. Stages run concurrently and buffer through channels.
Part of [Concurrency patterns](README.md).

```go
package pipeline

func Generate(ctx context.Context, nums ...int) <-chan int {
    out := make(chan int)
    go func() {
        defer close(out)
        for _, n := range nums {
            select {
            case out <- n:
            case <-ctx.Done():
                return
            }
        }
    }()
    return out
}

func Square(ctx context.Context, in <-chan int) <-chan int {
    out := make(chan int)
    go func() {
        defer close(out)
        for n := range in {
            select {
            case out <- n * n:
            case <-ctx.Done():
                return
            }
        }
    }()
    return out
}

// in <- Generate(ctx, 1,2,3); sq <- Square(ctx, in)
```

- **Use case**: ETL, streaming transformations, multi-stage data processing.
- **Benefit**: each stage scales independently; clear separation of concerns.
- **Discipline**: every stage must respect `ctx.Done()` and close its output
  channel on exit, or the pipeline deadlocks. For backpressure, give channels
  small bounded buffers (or none).

## Related

- [Fan-Out / Fan-In](fan-out-fan-in.md) — a parallel stage inside a pipeline.

---
*Source: [Common Design Patterns In Golang](https://dev.to/truongpx396/common-design-patterns-in-golang-5789).*
