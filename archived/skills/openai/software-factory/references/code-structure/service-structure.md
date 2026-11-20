# Service structure

## Default layout for a new service

The names below describe responsibilities. Adapt file extensions, visibility,
package declarations, and test locations to the language and framework. Each
leaf can be a file or a package, depending on its size. Split a growing module by
coherent responsibility rather than by an arbitrary file-length limit.

```text
src/
  bootstrap                 Creates dependencies and registers handlers
  orders/
    public                  Operations and types available to other features
    handlers                HTTP, message, or CLI translation as needed
    services                Order workflows and transaction coordination
    models                  Order domain types and rules
    repositories            Order persistence and record mapping
    adapters/               External integrations owned by orders, if needed
  billing/
    public                  Billing operations available to other features
    handlers
    services
    models
    repositories
  shared/                   Only established responsibilities used by both
tests/
  orders/                   Service, handler, and repository tests
  billing/
```

This is an example, not a list of mandatory files. A feature that computes a quote
without storage needs no repository. A feature called only by another feature
needs no transport handler. A package export or language visibility declaration
can provide the public interface without a separate `public` file.

In an existing service with top-level `handlers/`, `services/`, and `repositories/`,
keep that layout. Place order handling, workflows, and persistence in their
respective existing packages. Do not move them into `orders/` solely to match this
example.

## Calls and imports

Within a feature, the usual call path is:

```text
handler -> service -> repository
                  -> external adapter
```

Domain models and rules do not import those outer components. Handlers and
repositories may map boundary representations to domain types. Bootstrap creates
and supplies concrete repositories and adapters to services, then services to
handlers. Use ordinary constructors or functions unless the project already needs
a dependency container.

For a small service, a concrete repository dependency can be sufficient. When an
interface is needed to isolate infrastructure or substitute a dependency in tests,
define it near the consuming service contract and implement it in the repository
or adapter. Do not make domain code import an infrastructure module to obtain an
interface. The call path and the direction of source imports can differ here.

Cross-feature calls go through the owning feature's public operation:

```text
orders.services -> billing.public -> billing.services
```

Expose an operation such as `reserve_credit` with the types callers need. Do not
re-export repositories or all internal modules. Keep persistence records and SDK
types out of the public operation's contract.

If billing also needs to call orders, inspect the workflow before adding the
reverse dependency. Move coordination to an application workflow that calls both
public interfaces when that matches ownership. Otherwise propose a boundary
change. Do not hide the cycle with deferred imports or move feature logic into
`shared/` to bypass it.

## Ownership examples

| Code or behavior | Owner |
| --- | --- |
| Parse a request and translate an application error to an HTTP response | Handler |
| Decide whether an order can be cancelled | Order service or order domain model |
| Coordinate an order update and its local database transaction | Service, using the project's transaction mechanism |
| Query order rows and map them to order types | Repository |
| Translate a shipping SDK response into the feature's result type | Shipping adapter owned by the consuming feature |
| Store a reusable value type required by two features | A shared package only after confirming common meaning and ownership |

The service decides the transactional unit. Repositories participate using the
existing transaction mechanism rather than independently committing each step
of a multi-write workflow. Do not invent a new transaction framework to enforce
this rule. External API calls are not rolled back by a database transaction;
preserve the project's failure handling and flag missing behavior when relevant.

Keep request-shape validation in handlers and business validation in services or
domain rules so non-HTTP callers cannot bypass it. Translate errors at the boundary
that understands their representation. A service returns or raises an application
error rather than selecting an HTTP status code.

## Boundary mistakes and checks

- A handler queries the database before calling the service. Move persistence
  behind the repository and let the service coordinate the workflow.
- An order service imports billing's private repository. Call a billing public
  operation that owns the behavior; keep billing data access within billing.
- A repository decides whether a customer qualifies for a discount. Move that
  policy to the owning service or domain rule and leave the query in the repository.
- A generic `utils` package accumulates order policies. Return those policies to
  orders; extract only responsibilities with demonstrated shared use.
- A feature has empty handler or repository modules. Omit unused layers until
  their responsibilities exist.

Use the project's import or architecture checks when available. Otherwise inspect
the affected import paths for private access and cycles. Service tests exercise
business decisions and failures without requiring transport objects. Handler tests
check translation and delegation. Repository integration tests check real query,
mapping, and transaction behavior using the project's test database setup.
