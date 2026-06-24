## 7a. Authentication, Roles & Authorization

This section turns the functional goals about users, roles, leases and
interlockings into concrete code-level rules.

## [Login + PIN](./01-login-pin.md)

## [Effective roles](./02-effective-roles.md)

`effective(user, layout)` computation.

## [Domain Policy Layer (`pkgs/bigfred/server/security`)](./03-security-policy-layer.md)

`*SecurityContext` per aggregate.

## [Middleware – using the policies](./04-middleware.md)

## [Permission matrix](./05-permission-matrix.md)

## [Session reconciliation on WS connect](./06-session-reconciliation.md)

## [Sudo elevation – temporary `admin` / `signalman` via the layout PIN](./07-sudo-elevation.md)
