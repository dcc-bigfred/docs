## 3a. Domain Model (REL – Data Mapper)

The multi-user functional goals translate into the following entities.
REL maps these structs onto SQLite tables; the domain types live in
`pkgs/bigfred/server/domain/` and contain **no persistence tags beyond the few
hints REL needs**, so the controller layer (`LocoApp` and the services)
stays free of any ORM imports.

## [Entities](./01-entities.md)

`User`, `Vehicle`, `Train`, `Lease`, `Interlocking`, `CommandStation`, `Layout`, `Function`, `Template`, `Script`, `AuditLog`, …

## [REL repository – Data Mapper in practice](./02-rel-repository.md)

## [Invariants enforced by services + DB constraints](./03-invariants.md)

## [Layout-and-command station addressing rules](./04-layout-command-station-addressing.md)

## [Audit log](./05-audit-log.md)

## [Vehicle functions and template inheritance (copy-on-write)](./06-functions-and-templates.md)

Unified `dcc_functions` table.

## [Server-side scripts (Goja sandbox in a sibling executor process)](./07-scripts.md)

## [Function icon catalogue](./08-function-icon-catalogue.md)

Closed `FunctionIcon` list with Polish labels.
