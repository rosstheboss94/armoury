# Implementation

Use Implement for features and bug fixes under the entrypoint's authorization
rules. Inspect relevant specifications and repository evidence directly;
Analyze is needed only for a broader onboarding record.

## Feature worktree

For a Git repository, create or reuse a dedicated feature worktree before
implementation edits or checks that write artifacts. An implementation request
authorizes this local setup. Without a delivery request, it does not authorize
commits, pushes, or PRs; the `tldr` modifier explicitly requests later delivery.
An explicit user choice of checkout takes precedence. For a project without
Git, use the requested directory without initializing a repository.

Read the bundled [Tldr entrypoint](../tldr/overview.md) and
[Workspace](../workspace.md) for setup, existing changes, resumption, and cleanup.
This preparation does not start delivery. Use the controller's `prepare`
command for a dedicated feature worktree, or the user's explicit checkout.
The shared factory contains specifications and state; implementation and build
outputs belong to the feature worktree.

If work already exists in the original checkout, transfer only the selected
feature changes, including needed untracked files, and verify the destination
against the source. Preserve the originals and staging. Ask when mixed changes
cannot be separated safely. Do not copy ignored secrets or generated outputs.

Use the feature worktree as the explicit working directory for implementation,
related specification edits, and checks. Verify the path and branch before
mutations. Worktrees share Git references and may share external services;
avoid modifying the base branch or shared state outside the task. Record the
worktree path, branch, and original checkout in the conversation or existing
checkpoint and retain them across modes. If setup is blocked, report the blocker
instead of silently editing the main checkout.

Keep the worktree until cleanup is requested. Before removing it, verify its
resolved path, confirm no staged, unstaged, or untracked work remains, and check
that commits are merged or durably preserved. Retain it if any work could be
lost. Do not force removal or infer permission to delete its branch.

## Workflow

1. Establish the requested result and observable acceptance behavior. Read the
   affected specifications, code, tests, configuration, and interfaces. For a
   bug, establish expected versus observed behavior, reproduce it when feasible,
   and investigate its cause. If reproduction is blocked, record the limit and
   use the narrowest available evidence.
2. Settle consequential uncertainty through Probe. Discuss new component or
   contract design when approved intent or delegated choices do not settle its
   responsibilities and interfaces. With `auto`, choose recommendations or
   reversible assumptions under [Modifiers](modifiers.md) instead of asking
   for routine decisions. Carry existing approvals forward.
3. Use Build when durable intent needs drafting or development. Probe may apply
   clear approved decisions directly. Record durable decisions before dependent
   implementation. A fix restoring documented behavior needs no specification
   edit; a small feature with clear acceptance and no durable design or contract
   decision may also proceed without one.
4. Explain the approach and relevant checks briefly, then implement the scoped
   change. Follow repository practices and, when useful, one installed Armoury
   engineering skill for the main stack. Specflow adds no separate engineering
   checklist or routine draft approval.
5. Run checks appropriate to the change and fix in-scope failures. For bugs,
   add or strengthen a regression check that demonstrates the defect and its
   correction when feasible; report any verification limit. Separate existing
   failures from those caused by the change.
6. Review the result against acceptance behavior. Sync affected specifications
   when final behavior changes or clarifies accepted intent, and recheck their
   links and verification effects. Report the outcome, changed areas, checks,
   and remaining work in proportion to the task.

When expected behavior cannot be established, settle that choice before the
fix. Do not silently redefine intent to match an implementation. Audit is
optional when requested or when a focused coverage or consistency review helps.

## Delivery handoff

The `tldr` modifier, including its `tdlr` alias, is an explicit delivery request.
After implementation completes, continue into Tldr automatically without another
approval. With `auto`, retain the delegated decision rules through review fixes.
If implementation is blocked, preserve the pending handoff for resumption.

When the user requests delivery, use the bundled Tldr workflow when available
and read its entrypoint. Carry forward scope, acceptance behavior, relevant
specification records and decisions, changed areas, checks and their limits,
unresolved findings, and existing authorization. Use the conversation or an
existing checkpoint; a separate handoff document is not required.

Carry active modifiers, their source and scope, delegated decisions, and
explicit assumptions into Tldr's local progress record. Use the bundled delivery controller and preserve blockers in its state.

Pass the feature worktree path, branch, and original checkout as local context.
Continue review fixes in that same worktree and include these details in an
existing checkpoint when saving state. Do not put local paths in public PR text.

Tldr creates a local progress record in shared Git metadata, commits locally,
and always runs an initial adversarial review. It allows at most three local
fix-and-review rounds afterward. It pushes and creates or updates a regular PR
only when the local gate passes or all three fix rounds complete. An exhausted
result may publish with failed review, which must be stated explicitly.
Required GitHub checks determine final readiness after publication. Tldr does
not merge or enable auto-merge. Point an existing checkpoint to its local
progress record under Tldr's linking rules instead of duplicating review history.
An implementation request without `tldr` or another delivery instruction does
not authorize this delivery workflow.

When Tldr returns a finding, use Probe for unresolved intent, Build for needed
specification development, and Implement for approved fixes. Audit remains
read-only. Carry the same scope, decisions, approvals, finding identifiers,
local progress record, any existing PR,
and completed round count across handoffs. Return the fix and verification
evidence to Tldr without restarting its review budget. Do not rewrite acceptance
criteria merely to make a review pass.

## Resume interrupted work

Use [Artifact model](artifact-model.md) for checkpoint content and preservation.
Update an existing implementation context through the final state. Ordinary
one-session tasks do not need a separate context or report file.
Retain normalized modifiers and pending delivery state under Modifiers. Apply
later user restrictions before resuming; do not ask again for retained approval.
Verify the saved worktree still exists and matches its recorded branch and local
changes before resuming. If it is missing, reconcile surviving commits and
saved changes before recreating it. Do not assume uncommitted work survived.
