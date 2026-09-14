---
name: code-structure
description: Design, implement, refactor, and review module and package organization inside a service. Use when deciding where code belongs, separating handlers, services, and repositories, defining feature interfaces, or correcting dependency boundaries. Covers internal code structure, not distributed service topology or deployment.
---

# Code structure

Organize code inside a service around business features with defined layer
responsibilities. Apply these rules across languages using the project's own
module, package, and framework conventions.

## Inspect the project first

Read applicable repository instructions, architecture decisions, domain terms,
package manifests, entrypoints, imports, and relevant tests. Identify the current
layout, public interfaces, dependency wiring, and transaction conventions.

Existing project layouts take precedence over the default feature layout. Apply
responsibility rules within that layout. If established behavior or architecture
conflicts with these rules, explain the concrete problem and propose a scoped
change. Do not silently reorganize code or override an accepted decision.

## Assign ownership and dependencies

- For a new service, group packages by business feature, such as orders or billing.
  Keep each feature's implementation together and expose a small public interface.
- Handlers translate transport input and output, validate request shape, and call
  services. Keep business rules and persistence queries out of handlers.
- Services own business workflows, business validation, and transaction boundaries.
  Keep reusable domain rules in feature-owned domain types or functions when needed.
  Repositories own persistence queries and mapping to and from stored records.
- Create a layer only when the feature needs its responsibility. Fixed roles do
  not require empty files, a class per operation, or an interface per class.
- Direct calls from handlers to services and from services to repositories.
  Repositories must not call handlers or services. Keep domain logic independent
  of transport and persistence implementations. Wire concrete dependencies at
  application startup using existing project mechanisms.
- Keep domain types with their owning feature. When wire formats or stored records
  differ, keep their representations and conversion with the handler or repository.
  Do not expose framework request objects or database sessions as domain contracts.
- Access another feature through its public interface. Do not import its private
  implementation or reach into its repositories. Keep dependencies acyclic.
- Put external integration adapters in the feature that owns their use. Services
  call them through focused operations; keep vendor SDK details inside adapters.
- Share code only when multiple features need the same responsibility and ownership
  is clear. Similar-looking code alone does not justify a shared package. Shared
  packages must not import their consuming features.
- Keep tests associated with their feature, following the project's test layout.
  Test service behavior separately from handler translation and repository integration.

Read [service structure](references/service-structure.md) when proposing a package
tree, placing code across layers, or diagnosing a boundary violation. It provides
an annotated layout and concrete examples of allowed and misplaced dependencies.

## Apply the requested mode

- For design or advice, stay read-only. Propose a package tree, responsibilities,
  public feature operations, and dependency direction grounded in the project.
  Explain any departure from the default and any unresolved architectural conflict.
- For implementation or refactoring, change only authorized code. Preserve public
  behavior unless the task changes it. Update affected imports and dependency
  wiring, and use existing language-specific checks and relevant tests.
- For review, stay read-only. Report concrete violations with file locations,
  consequences, and scoped fixes. Do not report a different folder naming convention
  as a defect without a responsibility or dependency problem.

Verify that dependencies remain acyclic, callers use public feature interfaces,
and business workflows do not depend on transport objects. For changed behavior,
exercise the relevant service path and affected handler or persistence boundary.
Report what changed or what is proposed, the checks performed, and any remaining
conflict. Do not require an architecture document or generate templates as a side
effect of applying this skill.
