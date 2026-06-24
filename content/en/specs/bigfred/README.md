# BigFred – Web Application Architecture Plan

This document describes the proposed architecture for a web application that
controls model railroad locomotives. It builds on top of the existing
`pkgs/loco` and `pkgs/rb` packages (Go core), which already provide a clean
`LocoApp` controller layer, a `Station` interface (Z21, LocoNet) and SQLite
access via `modernc.org/sqlite` (pure Go, `CGO_ENABLED=0`).

The architecture is split across multiple files under
[`./architecture/`](./architecture/). For an orientation read start at
the [architecture index](./architecture/README.md); for a specific
topic, jump directly to one of the sections below.

Section numbering used in the prose (`§3a.4`, `§4.5`, `§7b.1`, …) is
preserved verbatim in the headings of the split files, so existing
cross-references inside the text still work via `Ctrl+F`.

On the Go server, responsibilities are split across three packages under
`pkgs/bigfred/server/`: **`http`** (and **`ws`**) terminate transport and
authentication; **`service`** owns validation, orchestration, and
permission checks via **`security`**; see
[§3.1 Backend layer responsibilities](./architecture/04-repository-layout.md#31-backend-layer-responsibilities).

## [Terminology](./architecture/00-terminology.md)

## [Goals](./architecture/01-goals.md)

## [Technology Stack](./architecture/02-tech-stack.md)

## [High-Level Architecture](./architecture/03-high-level-architecture.md)

## [Repository Layout](./architecture/04-repository-layout.md)

## [Domain Model (REL — Data Mapper)](./architecture/05-domain-model/README.md)

## [Communication Protocol (REST + WebSocket)](./architecture/06-communication-protocol/README.md)

## [Backend Components](./architecture/07-backend-components.md)

## [Frontend Components](./architecture/08-frontend-components.md)

## [Cross-Cutting Concerns](./architecture/09-cross-cutting.md)

## [Internationalization (i18n)](./architecture/09a-i18n.md)

## [Authentication, Roles & Authorization](./architecture/10-authn-authz/README.md)

## [API Keys & Built-in MCP Server](./architecture/11-api-keys-and-mcp.md)

## [Makefile Additions](./architecture/12-makefile.md)

## [Delivery Order (Milestones)](./architecture/13-delivery-order.md)

## [Acceptance Criteria](./architecture/14-acceptance-criteria/README.md)

## [Process Supervisor (Supervisord)](./architecture/15-supervisord/README.md)

## [DCC Bus Daemon (`dcc-bus`)](./architecture/16-dcc-bus/README.md)

Task-scoped implementation plans live under [`./plans/`](./plans/):

## [M5 – Interlocking view, radio & takeover](./plans/m5-interlocking-radio-takeover.md)

## [M5.1 – Train announcements panel](./plans/train-announcements-panel.md)
