# Intended-state build

Use Build to draft and develop specifications that implementation and test work
can follow. Follow [Artifact model](artifact-model.md) for navigation, layout,
record ownership, and decision history.

## Develop the specification

1. Read governing intent, accepted decisions, current specifications, and any
   relevant analysis or Probe checkpoint. Inspect affected code, tests,
   configuration, and interfaces directly to fill evidence gaps.
2. Define scoped requirements and scenarios with observable acceptance
   criteria. State where intended behavior keeps or changes existing behavior.
3. Assign responsibilities to components and interactions to contracts.
   Describe the state, interfaces, constraints, and failure behavior needed to
   implement the outcome. Include measurable quality or operational targets
   where acceptance depends on them, using approved sources.
4. Link scenarios to verification. Put details with their canonical owner and
   keep the verification plan thin. Keep every index a router and normalize
   existing specification indexes under the artifact model's migration rules.
5. Resolve consequential uncertainty through Probe, applying active `auto`
   delegation under [Modifiers](modifiers.md). Keep dependent sections
   provisional or blocked until settled; continue independent specification work.

Do not invent policy, guarantees, or a reason for every irrelevant engineering
concern. Local implementation choices may remain delegated within stated
constraints and acceptance criteria. Analysis remains evidence and does not
become target intent merely by being copied.

Probe may already have applied approved decisions. Build develops any remaining
specification work without repeating those edits or seeking the same approval.
When applying an outstanding approved change, update its checkpoint application
state and recheck the affected records under the shared rules.

## Completion

Build is complete for the scoped target when requirements have acceptance and
verification paths, consequential responsibilities and boundaries have owners,
and implementers need not invent behavior or policy. Identify excluded or
blocked records when the target remains partial. A separate Probe pass is not
a completion requirement.
