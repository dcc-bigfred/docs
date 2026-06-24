# BigFred – Architecture (split documents)

This folder holds the BigFred architecture proposal, split into one file per
top-level section. The parent file [`../README.md`](../README.md)
is the entry point with the full table of contents.

Section numbering (`§3a.4`, `§7b.1`, …) is preserved in heading text so
cross-references inside the prose still work via `Ctrl+F`. Large sections
that grew beyond ~250 lines are further split into subfolders; each subfolder
carries its own `README.md` with its sub-TOC.

## [Terminology](./00-terminology.md)

## [Goals](./01-goals.md)

## [Technology Stack](./02-tech-stack.md)

## [High-Level Architecture](./03-high-level-architecture.md)

## [Repository Layout](./04-repository-layout.md)

## [Domain Model (REL — Data Mapper)](./05-domain-model/README.md)

## [Communication Protocol (REST + WebSocket)](./06-communication-protocol/README.md)

## [Backend Components](./07-backend-components.md)

## [Frontend Components](./08-frontend-components.md)

## [Cross-Cutting Concerns](./09-cross-cutting.md)

## [Internationalization (i18n)](./09a-i18n.md)

## [Offline-first frontend assets](./09b-offline-assets.md)

Bundled fonts/CSS/JS, no CDN at runtime, `check-offline-bundle` gate.

## [Authentication, Roles & Authorization](./10-authn-authz/README.md)

## [API Keys & Built-in MCP Server](./11-api-keys-and-mcp.md)

## [Makefile Additions](./12-makefile.md)

## [Delivery Order (Milestones)](./13-delivery-order.md)

## [Acceptance Criteria](./14-acceptance-criteria/README.md)

## [Process Supervisor (Supervisord)](./15-supervisord/README.md)

Non-root process groups, Go templates, hot reload, daemon lifecycle.

## [DCC Bus Daemon (`dcc-bus`)](./16-dcc-bus/README.md)

Per-`(layout × command station)` sibling daemon for the throttle data plane;
session-aware, security-policy-driven, Redis-cached.

## [Reliability — reconnect & retry](./17-reliability.md)

WebSocket backoff, command retries, DMS grace, mobile screen wake.
