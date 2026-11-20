# Local delivery progress

## Location and ownership

Before the initial delivery review, the controller creates or resumes one run
at `<factory-root>/state/<delivery-id>/run.json`. The identifier is a UUID.
JSON owns recovery; `progress.md` in the same directory is a readable view.
The parent uses controller commands to update state and supplies relevant
context to agents. Do not edit saved scores, phase state, or round counts.

Find existing runs by their saved identifier, branch, worktree, and scope.
Reconcile ambiguous matches before starting another run. Imported legacy
Markdown lives under `state/legacy/`; reconstruct its history before resuming,
without restarting a used review budget.

These local records stay outside commits and PR diffs. The shared factory
survives feature worktree removal. It is not a remote backup. See
[Controller](../controller.md) and [Workspace](../workspace.md).

## Record content

Use concise Markdown with a current-state section and a compact round history.
Retain the information needed to resume:

- Delivery identifier, repository and remote target, feature and base branches,
  feature worktree, original checkout, and relevant Specflow record links.
- Canonical local specifications path, linked worktrees, link type, and the
  latest link verification result when shared specifications are in use.
- Requested scope, acceptance criteria, decisions, and established authorization.
- Active Specflow modifiers, their delegation source and scope, explicit
  assumptions and validation needs, and pending handoff state. Retain these
  through review fixes and resumption, applying later user restrictions first.
- Current and reviewed head/base commits, required local checks and their
  results, and GitHub checks pending publication or observed afterward.
- Editor and reviewer assignments, requested and observed model/effort settings,
  fallback limits, and findings with identifiers, severity, evidence,
  dispositions, and closure conditions.
- Initial review and each fix round, including its score, reviewed commits,
  checks, and whether the round started or completed. Retain completed counts
  and remaining budget; an interrupted round is resumed, not counted twice.
  A round completes when its review result is recorded, including a result
  showing no progress. An interrupted attempt without that result stays started.
- Whether the local gate passed, rounds exhausted, or work blocked early, plus
  the exact blocker and next action. Record publication eligibility separately
  from final PR readiness.
- Publication attempts and results, remote head, PR URL/number, review-summary
  comment identifier, and final GitHub checks and mergeability when available.

Update after each review, fix round, interruption, and publication attempt.
Save pending operations before external writes and reconcile their result
afterward. Preserve prior round outcomes when updating current state. Avoid
credentials, unnecessary logs, and copied specifications.

## Resume and publish

This record is the canonical delivery history. Reconcile it with actual local
and remote Git state, the conversation, and any existing PR before acting.
Saved authorization does not grant new scope. A missing or corrupt record is
not permission to restart the round budget; reconstruct supported history from
available evidence or report the gap. Confirm the worktree and branch still
match, and inspect uncommitted work before continuing.

A changed head or base invalidates its passing result. Obtain review of the
current change before claiming success. Record invalidated reviews as history,
not as current evidence, and retain the existing fix-round budget. Before
publication, re-review after a completed round consumes the next numbered round
from the same three-round budget, even for base-only drift with no edits. An
interrupted round resumes at its existing number against reconciled evidence.
Do not repeat round 0 or add unnumbered reviews to evade the cap. After
publication, drift invalidates readiness and is reported for follow-up rather
than starting automatic re-review. If all rounds
are exhausted, publication may still proceed, but mark changed or unreviewed
content and the failed readiness gate explicitly.

Publish only after the local gate passes or all three fix rounds complete.
Early stopping for stalled progress, decisions, or access issues saves a blocker
locally without automatically publishing. Once eligible, the parent derives
the PR review summary from this record, omitting local machine paths and private
context. A failed publication or comment update remains pending in this file;
inspect remote state before retrying to prevent duplicate artifacts.

An existing Specflow checkpoint points to this local record instead of copying
its round history. In tracked checkpoint text, record the delivery identifier
and factory-relative location rather than an absolute machine path. A checkpoint
link is local context, not a promise that the record exists in another clone.

Standalone read-only review stays file-free unless saving is requested.
Standalone fixes also do not imply Git publication or a mandatory delivery
record; keep their existing local authorization and round limits.
