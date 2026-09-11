# Git and PR delivery

## Establish the target

Read repository instructions and inspect the working tree, staged changes,
current branch, upstream, remotes, and existing PRs. Establish which changes
belong to the requested feature, including any commits already ahead of the
target. Do not stage unrelated files or publish unrelated commits. If changes
cannot be separated safely, ask about the affected scope.

Prefer Git for local operations and the GitHub CLI for GitHub operations. Use
an available GitHub connector when suitable. Check authentication and tool
availability; report missing access without installing tools or changing account
configuration unless requested. Do not expose credentials in diagnostics.

Use a feature branch for delivery. Preserve an existing suitable branch;
otherwise choose a descriptive name under repository conventions and check for
collisions. Target the user-specified base, then the repository's established
base, otherwise `main`. Verify that the target exists before publishing. If
multiple remotes or PRs remain plausible after inspecting upstream and repository
evidence, ask which target to use.

## Isolate the work

Before editing or running checks that write build artifacts, inspect registered
worktrees, their branches, and local changes. Reuse the dedicated worktree for
this feature when its scope and ownership match. Otherwise create a feature
worktree from the verified feature commit or base. Follow the project's location
convention; otherwise use a sibling directory named `<repo>-<feature>`. Verify
the resolved path is unused. Do not overwrite a directory, commandeer another
task's worktree, or force a branch into a second checkout.

If the feature branch is already checked out in the original checkout, leave
that checkout intact. Create a distinct feature branch from its verified head
for the new worktree when no existing PR requires the original branch. If an
existing PR or ambiguous ownership makes this unsuitable, ask which worktree or
branch to use. Do not silently replace the PR's branch or switch the user's
checkout. An explicit user instruction to use a particular checkout takes
precedence over the default.

For feature changes already in the original checkout, inspect staged, unstaged,
and untracked content. Transfer only the selected feature changes into the
worktree, preserving binary changes and deletions where applicable. Verify the
destination diff and required untracked files against the source before
continuing. Leave source changes and staging intact; do not stash, reset, or
clean them away. Ask if mixed changes cannot be separated safely. Do not copy
the entire checkout, ignored secrets, or build outputs as a transfer shortcut.

Run implementation, tests, review fixes, commits, and pushes with the feature
worktree as the explicit working directory. Verify its path and branch before
mutations, including after a handoff. Keep build outputs there and inspect
project setup before using tools that write to shared paths. Worktrees share
Git objects and references; they do not isolate branch mutations or external
services. Do not advance `main` or the base branch as part of feature delivery.

Record the local worktree path, branch, and original checkout in the
[local progress record](progress.md). Carry them across Specflow handoffs and resumptions.
Local machine paths need not appear in the public PR comment.

Keep the worktree through review and manual merge. Remove it only when cleanup
is requested. Before removal, verify its resolved path and registration, confirm
it has no staged, unstaged, or untracked work, and verify that its commits are
merged or otherwise durably preserved. Account for squash merges using PR and
content evidence. If any work could be lost, retain it and report why. Use Git's
worktree removal without force; deleting a branch needs its own requested scope.

## Pull and push

Fetch and inspect before pulling or reconciling branches. Fast-forward when
possible. For divergence, follow the repository's established merge or rebase
policy within existing authorization. If no policy settles a consequential
history change, ask. Do not auto-stash unrelated work or overwrite conflicting
edits. Resolve conflicts only where approved intent determines the result.

A push request pushes the requested branch and commits; it does not imply new
commits, a PR, or a review. Inspect the outgoing range and destination first.
A rejected push calls for fresh inspection, not an automatic force-push.

Standalone pull or push acts on the requested branch and checkout. It does not
require a new worktree or authorize switching the original checkout. Delivery
synchronization runs in the feature worktree under the isolation rules above.

## Deliver a feature

1. Create or resume [Local progress](progress.md). Establish acceptance behavior
   and run the relevant local checks. Assign preparation edits or in-scope
   failures to the editor under
   [Agent roles and models](../SKILL.md#agent-roles-and-models). The editor returns
   changed areas, check evidence, and unresolved issues before the parent
   commits. Separate pre-existing failures from new ones. An unresolved
   required failure still prevents readiness. Report unavailable
   required validation rather than silently skipping it.
2. The parent inspects the editor's result and exact staged diff, then commits
   the feature changes. Preserve existing commits when no new commit is needed.
   Do not create empty commits just to follow the sequence.
3. Run the initial adversarial [Review](review.md) on the local commit. A passing
   initial review satisfies the minimum of one review. Otherwise run up to three
   local editor-to-reviewer fix rounds, saving results in the progress record.
   Do not push or update PRs during this loop, including when a PR already exists.
4. Publish only after the local gate passes or all three fix rounds complete.
   If work stops earlier, save the blocker and next action locally. Recheck the
   target branch and remote state before publishing. Changed head or base
   commits invalidate a saved pass and require reconciliation under Local progress.
5. Push the feature branch to the verified remote and establish its upstream
   when needed. Confirm the remote head matches the intended commit. Record
   the attempt and outcome so retries do not repeat completed work.
6. Reuse an open PR matching the repository, head, and base, or create a regular
   PR. For an existing draft, preserve its state unless the request authorizes
   changing it. Follow the PR template. Lead with the problem and resulting
   behavior, then include acceptance, checks and their limits, and relevant
   specification links. Preserve unrelated human-authored PR content. If rounds
   exhausted without passing, clearly state that the local gate failed and list
   unresolved findings, scores, and verification limits. Keep the title and
   description aligned with the final implementation. Publish the review-summary
   comment from the local record and save the PR and comment identifiers there.
7. Inspect required GitHub checks and current PR mergeability. Checks requiring
   a push or PR were pending publication, not prerequisites for creating the PR.
   Pending checks are pending, not passing; unavailable check evidence is a
   limit. A conflict
   or unmet repository requirement prevents readiness. Do not bypass branch
   protection or claim that an agent score satisfies required human approvals.
8. Recheck the remote head and base before reporting the final readiness result.
   Save GitHub outcomes in the local record. Post-publication failures do not
   restart an exhausted loop or trigger a fresh automatic delivery loop. Report
   the failure and needed follow-up without claiming readiness.
   Leave merging to the user, even when all checks and reviews pass.

When submitting multiline PR text, use structured arguments or an exact body
file supported by the CLI. Do not interpolate review text into shell code.

## Resume and recover

Before retrying a write after a timeout or interruption, inspect remote state.
The commit, push, PR, or comment may already exist. Reuse the existing artifacts
instead of creating duplicates. Never push over new remote work without review.

Resume from [Local progress](progress.md), reconciling any existing PR,
conversation, and Specflow checkpoint. PR creation is not required to resume.
Locate the recorded worktree and confirm its branch and local changes before
resuming. If it is missing, reconcile the surviving branch, remote, and saved
changes before recreating it; do not assume uncommitted work was preserved.
Reconcile saved scope, authorization, completed rounds, findings, checks, role
assignments, and observed model settings against current evidence.
Reuse available role agents or restore their context in replacements under the
entrypoint's model selection rules. Do not reset the three-round budget on resumption.
If progress cannot be reconstructed, report the uncertainty before more fixes.

Any change to the reviewed head or base invalidates the saved readiness result.
Review the updated diff and rerun affected checks before restoring it. Changes
from another actor require fresh scope inspection; do not overwrite them.
