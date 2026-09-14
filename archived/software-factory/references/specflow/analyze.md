# Project analysis

Use Analyze to onboard an existing project and preserve a reusable account of
its behavior, broad requirements, unknowns, and verification. Scoped inspection
inside Build, Implement, or Audit does not require Analyze artifacts.

## Inspect the project

Identify the product boundary, relevant packages or services, entry points,
documentation, and excluded areas. Trace representative workflows through their
owners, interfaces, state, dependencies, and failure behavior. Inspect the tests,
configuration, schemas, and runtime evidence that establish those claims. Use
history when current evidence cannot explain consequential intent.

Distinguish observed behavior, approved requirements, inference, and unresolved
questions using [Artifact model](artifact-model.md). Attach exact sources and
record conflicts. State evidence limits, such as a mocked dependency or an
uninspected service, instead of extending a local result to the whole system.

## Preserve the analysis

Use the artifact model's analysis layout or equivalent project records:

- Current state describes the inspected boundary, responsibilities, workflows,
  interfaces, state, and relevant operating behavior.
- Broad requirements record capabilities and constraints backed by accepted
  intent. Observed behavior alone does not establish a requirement.
- Assumptions and decisions retain unknowns, conflicts, decision sources, and
  the work they affect.
- Verification maps behavior and requirements to existing checks or explicit
  gaps, with what each check establishes and its limits.

Link the records for navigation. Analyze is sufficient when a reader can tell
what happens now, what is required, what remains unknown, and how it is checked.
Report material gaps without requiring every unknown to be resolved.
