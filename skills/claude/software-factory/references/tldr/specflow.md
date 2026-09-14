# Specflow handoff

Tldr owns Git/GitHub delivery and adversarial review of code changes. Specflow
owns specification decisions, specification development, and its implementation
workflow. Its Audit mode remains read-only.

## Receive work

When Specflow hands off delivery, carry forward the feature scope, acceptance
behavior, relevant records and decisions, changed areas, executed checks and
their limits, unresolved findings, and existing authorization. Use the
conversation or an existing implementation checkpoint for the handoff. On
starting delivery, create or resume [Local progress](progress.md), which owns
the review history even when no PR exists yet.

Specflow's `tldr implement` invocation explicitly authorizes this handoff and
delivery. It accepts `tdlr` as an alias. Carry normalized modifiers, their
source and scope, delegated decisions, assumptions, and pending work into the
progress record. Do not ask again solely because implementation finished.

Carry the feature worktree path, branch, and original checkout as local context.
Reuse Specflow's feature worktree under Delivery's [worktree rules](delivery.md#isolate-the-work).
Keep specification updates, implementation fixes, and checks for this feature
in that worktree. A handoff does not authorize returning to the main checkout
or creating a second worktree for the same task.

Before reading or changing local records, apply Delivery's
[shared specification setup](delivery.md#share-local-specifications). Continue
to address records through `<worktree>/.agents/skills/software-factory/specs`; that path resolves to the same
canonical local tree from every registered worktree. Do not replace the link,
copy records between worktrees, or stage the link.

Read the bundled [Specflow entrypoint](../specflow/overview.md) and applicable mode references before
using its modes. When reading or writing specification records, read its
artifact model. Start from the project's specification index and follow only
the relevant routes to requirements, scenarios, contracts, decisions, and
verification. Preserve canonical owners, labels, approval state, and history.

Use the requirements and acceptance scenarios as review evidence. Link relevant
records from the PR and findings without duplicating specifications there.
Observed implementation does not replace approved intent.

## Return findings

- Use Probe for unclear intent, contradictory decisions, or unresolved
  assumptions. Carry clear approved answers forward without asking again.
- Use Build when approved intent needs specification drafting or development.
- Use Implement for approved code fixes and their relevant validation. Return
  to Tldr after the fix, retaining the progress record, any existing PR, review
  findings, and round budget.
- Use Audit only for a requested or useful read-only specification consistency
  or coverage check. Audit does not apply fixes or publish its own results.

During Tldr, assign code fixes to its editor under
[Agent roles and models](overview.md#agent-roles-and-models). The editor reads and
follows the applicable Specflow guidance in the same feature worktree, then
returns evidence to the parent for local commit and independent review. Push
and PR updates wait until the local gate passes or the fix rounds exhaust. A
Specflow handoff does not transfer code editing to the parent or reviewer.
Specflow implementation before Tldr starts remains its own workflow; these role
assignments do not require it to use Tldr's editor.

A delivery request covers fixes within the accepted feature scope. When `auto`
was also delegated, read Specflow's modifier rules and use recommendations or
explicit reversible assumptions for in-scope decisions during review fixes.
Record their provenance and uncertainty without asking again. Without that
delegation, pause consequential new product decisions for user input and
continue independent work. The editor may make delegated in-scope choices and
returns their rationale and effects to the parent, which records them and
coordinates scope. The editor cannot expand the task. Neither modifier
authorizes scope expansion,
acceptance changes that hide defects, fabricated evidence, or waived review
gates. Update specifications only when the authorized change needs it, following
Specflow's artifact and migration rules. Code-only delivery does not trigger
specification restructuring.

Update an existing Specflow checkpoint through the final state when one is in
use. Point to the local progress record under its linking rules instead of
duplicating round history. Preserve unresolved specification findings and
decisions, add the PR link after publication, and distinguish the local gate,
final PR readiness, and the user's later merge.

## Without Specflow

Tldr works without an installed Specflow skill or specification tree. Establish
scope and acceptance from the user and repository evidence. Do not require new
specifications or invent Specflow records as a delivery prerequisite. If records
exist but the skill is unavailable, use them as evidence, preserve their
structure, and ask about unresolved intent rather than inventing a workflow.
