# Artifact model

Use the project's terms and coherent document structure. The layout below is
the fallback. Keep evidence and intended state distinguishable, even when they
share a file. Each record has one canonical owner; other records link to it.

## Labels and status

Preserve existing labels. Otherwise use these prefixes, adding a descriptive
suffix when needed to avoid ambiguity:

| Label | Record |
| --- | --- |
| `REQ` | Required behavior or constraint |
| `SCN` | Concrete behavior and expected result |
| `CMP` | Owner of a system responsibility |
| `CTR` | Agreement across a boundary |
| `ASM` | Claim that still needs a decision |
| `DEC` | Accepted answer, rejection, or deliberate deferral |
| `FND` | Evidenced gap, conflict, or risk |
| `TST` | Current or planned verification |

The usual behavior chain is `REQ -> SCN -> TST`. Components own work,
contracts constrain interactions, decisions settle assumptions, and findings
record gaps.

Use project statuses when equivalent. Otherwise use `observed` for current
evidence, `intended` for approved target behavior, `inferred` for interpretation,
`unresolved` for missing information or pending decisions, `proposed` for wording
awaiting approval, `accepted` for approved current intent, and `superseded` for
replaced records. Observed behavior does not automatically become intended.
Connect conflicts through findings and decisions.

For active `auto` delegation, follow [Modifiers](modifiers.md). Accepted
decisions identify the invocation as the delegation source and the agent as
the decision-maker, retaining rationale and verification effects. An accepted
decision to proceed under a reversible assumption does not mark the underlying
claim as observed or verified. Preserve its uncertainty and validation needs.

A consequential record retains its label, statement, status, source, evidence
or rationale, affected records, and relevant verification effects or unresolved
questions. A finding also needs severity, disposition, and a closure condition.
Use links such as `derived-from`, `depends-on`, `constrains`, `implements`,
`verifies`, `contradicts`, `supersedes`, and `blocked-by`, pointing to stable
labels or exact sources. Do not add fields already conveyed by the format.

## Layout and navigation

```text
.agents/skills/software-factory/specs/
|-- index.md
|-- decisions/
|   |-- index.md
|   `-- <decision-name>.md
|-- analysis/
|   |-- current-state.md
|   |-- decisions.md
|   |-- requirements.md
|   |-- verification.md
|   `-- probes/<topic>.md
|-- requirements/
|   |-- index.md
|   |-- scope.md
|   `-- req-<requirement>/
|       |-- index.md
|       |-- requirement.md
|       |-- decisions.md
|       `-- scn-<scenario>.md
|-- design/
|   |-- index.md
|   |-- overview.md
|   |-- components/cmp-<component>.md
|   |-- contracts/ctr-<contract>.md
|   `-- shared/<concern>.md
`-- verification.md
```

Create artifacts as needed, without empty placeholders. Analysis files hold
current-state evidence, broad sourced requirements, unknowns and decision
sources, and existing verification. They do not replace intended-state records.

Read `.agents/skills/software-factory/specs/index.md` first when it exists, then follow the task's route and
links to governing decisions and affected records. Every specification
`index.md`, at any depth, contains only a title and a bullet list of links with
short reading guidance. Link descriptions tell readers what to find or when to
read it; they do not restate rules, decisions, evidence, or current status.
This applies to root, requirement, design, decision, and analysis indexes.

Keep the intended-state root index limited to these routes:

- `requirements/index.md` for behavior, scenarios, and acceptance criteria.
- `design/index.md` for ownership, interfaces, contracts, and dependencies.
- `verification.md` for test planning, acceptance checks, and readiness.
- `decisions/index.md` for decisions shared across owners, only when it exists.

An analysis-only index routes to analysis records. Put the inspected boundary
and evidence limits in `analysis/current-state.md` or the relevant analysis
record. Once intended-state routes exist, link supporting analysis and
checkpoints from the nearest relevant record or subordinate index.

For example, a requirement index routes to its content without summarizing
the required behavior:

```markdown
# REQ-execution

- [Requirement](requirement.md): read scope, constraints and dependencies.
- [Signal fill](scn-signal-fill.md): follow the scenario and acceptance criteria.
- [Decisions](decisions.md): read governing decisions and their rationale.
```

## Existing index migration

When authorized work edits specifications, normalize all specification indexes
in the project, including those outside the immediate feature. Build, Probe and
Implement apply this across analysis and intended-state specifications when
editing intended-state records. Analyze normalizes analysis indexes only.
Audit reports needed migrations without editing. A code-only change or an
optional Shape brief does not trigger a specification migration.

Move substantive index content to its canonical owner before replacing it
with routing links. Preserve useful existing owner filenames; use the fallback
names below when no suitable record exists. Preserve labels, approval state,
sources, evidence and history. Combine duplicates without losing unique meaning.
Keep conflicting statements and record the conflict instead of choosing new
intent during a structural move.

Update incoming links, including heading fragments, and relative links within
moved content. Links used as evidence or authority must target the owning record,
not its router. Check that every moved statement remains reachable and all
affected links resolve. Create supporting documents only when they have content
to own; do not add empty files or routers.

## Specification ownership

The requirements index routes to requirements and shared scope when present.
Use `requirements/scope.md` for shared product scope, actors,
vocabulary and exclusions that have no single requirement owner. Keep behavior,
invariants and state machines with their governing requirements.

Each `REQ` has a lowercase folder derived from its label. Its `requirement.md`
owns the statement, scope, constraints, dependencies, status, and links to
scenarios, design, decisions, assumptions, and findings. Its index routes to
that record, scenarios and decisions. Requirements own measurable quality and
operational expectations where acceptance needs them.

Each `SCN` has one canonical lowercase file with its owning requirement,
preconditions, trigger, expected result, applicable failures and boundary cases,
acceptance criteria, and concrete `TST` cases. Link relevant evidence, design,
and other affected requirements. Link shared scenarios instead of copying them.
Keep the root verification plan thin, mapping `TST` records to scenarios,
requirements, intended test layer or evidence, status, and blockers. Detailed
conditions stay in scenarios.

The design index routes to design records. Use `design/overview.md` for shared
architecture scope and dependencies when needed. Keep detailed design, status
and blockers with their governing records. Each independently owned component
has a `CMP` file with responsibilities, exclusions, state, interfaces,
dependencies, lifecycle, and applicable failure, recovery, security, and
operational duties.

Each independently owned or versioned boundary has a `CTR` file covering its
participants, authority, shape, invariants, and applicable sequencing, validation,
compatibility, error, retry, and idempotency rules. Do not split by endpoint or
field unless ownership or versioning requires it. Link authoritative schemas
or other sources and add only the ownership, constraints, mappings, or gaps
needed by the specification.

Use shared design files only for consequential concerns spanning owners. Name
responsibility, enforcement, affected records, decisions, and verification.

## Decision ownership and history

Give each `DEC` one canonical owner:

- Requirement decisions belong in `requirements/<req-name>/decisions.md`, one
  register per requirement with decisions. Link individual entries from
  `requirement.md` and affected scenarios; the index routes to the register.
- Component and contract decisions belong in the component or contract file
  that governs the behavior, even when several requirements are affected.
- Decisions spanning owners without one governing owner belong in
  `decisions/<decision-name>.md`. Create the shared directory and its small
  index only when such decisions exist.

Use stable headings or anchors. Keep sources, approval status, rationale, and
supersession history with the decision. Analysis decision records and Probe
checkpoints preserve evidence and answers; they do not substitute for canonical
accepted intent.

Do not renumber records for neat ordering. Mark retired records superseded or
withdrawn and link successors where applicable. Give changed meanings new labels
and record their relationship. When moving decisions, preserve labels and
history, update incoming links including fragments, and retain remaining content
in the old register. Never erase conflicting accepted intent without a decision.

## Checkpoints

Save a checkpoint when the user asks, work pauses or blocks, or unresolved state
would otherwise be lost. Reuse the project's record convention. The fallback
for Probe is `.agents/skills/software-factory/specs/analysis/probes/<topic>.md`; for implementation it is
`.agents/skills/software-factory/specs/specflow/implementation-context.md`. Link from the nearest relevant
record or subordinate index. A completed short exchange whose decisions and
effects are recorded does not need a separate report.

Keep enough to resume: scope and acceptance, evidence and limits, decisions and
answers, approval and application state, changed records, checks and outcomes,
unresolved items and dependencies, completed work, and the next action. Include
only relevant content. A saved queue retains dispositions and priorities;
terminal updates need not repeat it.

On resuming, reconcile the checkpoint with current evidence and records. Preserve
saved labels, answers, approvals, dispositions, and existing wave numbers.
Update current state without discarding decisions or completed history. Mark
completion when done. A pending proposal remains provisional until approved;
an approved decision may still be awaiting application.

For a related legacy task, read and continue using
`.agents/skills/software-factory/specs/spec-manager/implementation-context.md`. Preserve its goal, evidence,
module design, decisions, changes, checks, and completed work. An old
`awaiting-approval` status does not override clear current authorization.
Delete an implementation context only on an explicit reset request, targeting
that file alone and reporting whether version control can recover it.
