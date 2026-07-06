# Project layout

This page describes the reference directory structure for a Go service or
library in the BigFred ecosystem. It is based on the community
[golang-standards/project-layout](https://github.com/golang-standards/project-layout/blob/master/README.md)
README, with two important caveats taken from that document itself:

> This is **NOT an official standard defined by the core Go dev team**. It is a
> set of common historical and emerging project layout patterns in the Go
> ecosystem.

> If you are building a PoC or a simple project for yourself this layout is
> overkill. Start with a single `main.go` and `go.mod`. Introduce structure as
> the project grows and the root gets busy.

In other words: **the layout exists to communicate intent**, not to be applied
verbatim. Adopt a directory only when it earns its place.

## Reference structure

```
project-root/
├── cmd/                       # main applications (one dir per binary)
│   └── myapp/
│       └── main.go            # small: wire dependencies, run
├── internal/                  # private application/library code (compiler-enforced)
│   ├── app/                   # application-specific code (not reusable)
│   │   └── myapp/
│   └── pkg/                   # internal shared helpers
├── pkg/                       # public library code ok for external import
│   └── mypubliclib/
├── api/                       # OpenAPI / JSON schema / proto definitions
├── web/                       # web app assets, SPA, server-side templates
├── configs/                   # config templates / defaults
├── scripts/                   # build / install / analysis scripts
├── build/                     # packaging and CI
│   ├── package/               # OS packages, containers, AMIs
│   └── ci/                    # CI configs
├── deployments/               # IaaS / PaaS / orchestration (compose, k8s, terraform)
├── test/                      # external test apps and test data
├── docs/                      # design and user documentation
├── tools/                     # supporting tools (may import internal/ and pkg/)
├── examples/                  # examples for apps / public libraries
├── third_party/               # forked code, external helpers
├── githooks/                  # git hooks
├── assets/                    # images, logos and other repo assets
├── vendor/                    # vendored dependencies (go mod vendor)
├── go.mod
├── go.sum
├── Makefile
└── README.md
```

### Directories you should not have

**Do not add a top-level `src/` directory.** It is a Java-ism and conflates
with the `$GOPATH/src` workspace directory. With modules (Go 1.11+) the
project lives wherever it lives; a `src/` folder only confuses tooling.

## Directory-by-directory guidance

### `/cmd` — main applications

One subdirectory per binary, named after the executable. Keep `main.go`
trivial: parse flags/env, assemble dependencies, call `Run`. Real logic lives
in `internal/` or `pkg/`.

BigFred example — `bigfred/cmd/`:

```
cmd/
├── server/        # the bigfred hub server
├── loco/          # the loco CLI
├── dcc-bus/       # dcc-bus tooling
├── z21pairing/    # Z21 pairing helper
├── remotes/
├── otel/
├── loadtest/
└── contract/      # contract tests
```

### `/internal` — private code

Enforced by the Go compiler: packages under `internal/` can only be imported
by code rooted at the parent of `internal/`. Use it for anything you do not
want other modules to depend on. You may nest `internal/` at any level.

Optional sub-structure:

- `internal/app/myapp/` — application code specific to one binary.
- `internal/pkg/` — shared internal helpers used by several apps but not
  intended for external consumption.

BigFred keeps the bulk of its code under `pkgs/bigfred/` (see below); treat
that path as the project's `internal` boundary.

### `/pkg` — public library code

Code other projects are allowed to import. Think twice before putting
anything here — once a package is under `pkg/` you are implicitly promising a
stable API. Prefer `internal/` unless there is a concrete external consumer.

BigFred uses `pkgs/` (note the plural, a project-specific convention) for
cross-binary shared code:

```
pkgs/
├── bigfred/      # domain, server, dcc-bus, z21pairing, ...
├── loco/
└── rb/
```

This is a deliberate deviation from the reference layout; document your own
deviations the same way.

### `/vendor` — dependencies

Produced by `go mod vendor`. Commit it for binaries that must build offline or
with reproducible deps; do **not** commit it for libraries. Since Go 1.14 the
`-mod=vendor` flag is on by default when `vendor/` is present.

### `/api` — protocol definitions

OpenAPI specs, JSON schemas, `.proto` files. BigFred keeps gRPC/protobuf
definitions under `specs/bigfred/protos/` in the docs repo and generates Go
from them — the principle is the same: protocols live in one owned place,
separate from implementation.

### `/configs`, `/scripts`, `/build`, `/deployments`, `/test`, `/docs`, `/tools`, `/examples`, `/third_party`, `/githooks`, `/assets`

Use these as described in the reference layout. They are optional. A few
rules of thumb:

- **`/scripts`** keeps the root `Makefile` small — move build/install/analysis
  scripts there and call them from the Makefile.
- **`/test`** is for *external* test apps and test data, not for `_test.go`
  files (those stay next to the code they test). Go ignores directories
  starting with `.` or `_`, and `test/data` is ignored by `go build`.
- **`/tools`** may import from `internal/` and `pkg/` — useful for codegen
  helpers, migration runners, etc.

## Module layout — the official view

The core Go team's guidance ([Organizing a Go module](https://go.dev/doc/modules/layout))
can be summarised as:

- A module is a single unit of versioning. Keep related code together; split
  into separate modules only when you need independent versioning.
- `internal/` is the mechanism for privacy; use it liberally.
- Prefer fewer, larger packages over many tiny ones when the types are
  cohesive — it reduces churn across package boundaries.
- Program constructors (`NewX`) belong in the same package as `X`.

## Choosing where a new package goes

| Question | If yes |
| --- | --- |
| Is it the entry point of a binary? | `cmd/<binary>/` |
| Should external modules be able to import it? | `pkg/<lib>/` (or public path) |
| Is it shared inside this repo only? | `internal/pkg/` or `pkgs/<lib>/` |
| Is it specific to one app? | `internal/app/<app>/` |
| Is it generated protocol/API definitions? | `api/` |
| Is it test data / external test harness? | `test/` |

## Checklist for review

- `cmd/*/main.go` is small and free of business logic.
- Anything that should not be imported externally is under `internal/` (or
  the project's documented equivalent).
- No top-level `src/` directory.
- `vendor/` is either fully committed or absent — never partial.
- Each package has a `doc.go` or a leading package comment explaining its
  purpose.
- Build/install scripts live in `scripts/` and are invoked from the Makefile,
  not inlined into CI YAML.

---
*Source: [golang-standards/project-layout](https://github.com/golang-standards/project-layout/blob/master/README.md), [Organizing a Go module](https://go.dev/doc/modules/layout).*
