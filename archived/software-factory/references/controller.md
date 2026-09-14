# Controller

Run `python .agents/software-factory/scripts/factory.py <command>` from the
explicit product worktree. `--root` overrides the factory directory for testing.
The active agent reads the returned assignment, performs its authorized work,
and submits evidence. Scripts do not spawn coding agents.

## Requests

Use `--input -` with exact JSON on stdin, or an input file under the factory's
`state/` directory. Keep task text out of shell interpolation. `route` reads a
request and returns its mode without writing files. For file-free tasks, follow
the selected references directly and report in chat.

`start --input <request.json>` creates a saved run. Required request fields:

```json
{
  "operation": "specflow",
  "mode": "implement",
  "modifiers": ["auto", "tldr"],
  "task": "Implement the approved feature and deliver its PR",
  "worktree": "/absolute/project-feature",
  "branch": "feature-name",
  "base": "main",
  "repository": "owner/repository",
  "remote": "origin",
  "pr_base": "main",
  "authorization": {
    "source": "The user's request for auto tldr implement",
    "edits": true,
    "delivery": true
  },
  "required_checks": ["unit tests"],
  "roles": {
    "editor": "editor-agent-id",
    "reviewer": "reviewer-agent-id",
    "editor_requested": "gpt-5.6-luna / xhigh",
    "reviewer_requested": "gpt-5.6-sol / medium",
    "editor_observed": "unknown",
    "reviewer_observed": "unknown"
  }
}
```

Use actual role identifiers and observed model settings. Follow Tldr's model
fallback rules. A single-agent run includes a nonempty `roles.fallback` reason
only when delegation is unavailable or prohibited. Preserve that disclosure.

An empty `required_checks` list requires `no_checks_reason`. Record check names
the project actually requires. Missing checks remain unavailable, never passing.
Standalone saved read-only work requires `save_authorized: true`. Standalone
pull, push, or PR management uses its corresponding authorization key instead
of `delivery`. A request file records existing authority; creating one does not
grant permissions that the user did not give.

The worktree and branch must already match. Use Workspace's setup commands
before implementation. For specification-only work outside Git, follow the
mode reference directly and save authorized records beneath the factory;
Git delivery is unavailable without a repository. There is no requirement to
initialize Git just to shape an idea or edit a specification.

## Assignments and evidence

`next --run <uuid>` returns the current phase, revision, round, scope, roles,
authorization, findings, required checks, and a snapshot of head/base/diff.
It does not write state. Each result submitted through `accept` includes:

- `run_id`, `revision`, and `phase` from the current assignment.
- `status`, either `complete` or `blocked`, and a concrete `summary`.
- `snapshot` from `next` after work and checks finish.
- `checks`, each with `name`, `status`, and `evidence`. Status is `pass`, `fail`,
  `pending`, or `unavailable`.
- For review, `reviewer`, integer `score` from 1 through 5, `evidence_limits`,
  and `findings`. Each finding carries `id`, `severity`, `location`, `expected`,
  `observed`, `impact`, `evidence`, `closure`, and `disposition`.
- For work in a fix round, `progress: true` only with verifiable closure progress
  described in the summary and evidence.

Retain every previous finding with its current disposition. Dispositions are
`open`, `fixed`, `rejected`, or `deferred`. A blocked result preserves the phase
and round for continuation. Submission with a stale revision fails.

Review evidence must refer to the exact reviewed snapshot. The reviewer captures
it before review and confirms it remains unchanged afterward. Do not substitute
a newer snapshot onto an old result. Freeze reviewed product files and coordinate
shared specification writes during review. The controller validates the submitted
structure and Git identity; it cannot prove the agent's reported evidence true.

## Delivery sequence

1. `start` returns `work`. Complete implementation and submit its evidence.
2. The controller returns `commit`. Inspect the diff and run
   `commit --run <uuid> --input <commit.json>`, with `files` as exact relative
   file paths, `message`, and `scope_verified: true`. Clean trees retain HEAD.
3. The controller returns `review`, initially round 0. Assign independent review
   and submit its score, findings, and checks.
4. A failed review returns `fix`. Apply the review reference's stopping rules.
   When another round is justified, `fix --run <uuid>` begins the next numbered
   round. Reuse the same run and role agents.
5. A pass or three completed fix rounds returns `publish`. Run `publish` with
   `title`, `body`, `outgoing_scope_verified: true`, and the inspected
   `existing_body` when updating a PR. Preserve human-authored content. An
   exhausted failure adds a failed-gate disclosure automatically.
6. `github --run <uuid>` inspects the published PR's head, base, checks, and merge
   requirements. Repeat this read when pending checks settle. Report the saved
   `ready` result and evidence limits. The controller never merges.

The publication summary derives from review history. Keep submitted review
summaries and evidence suitable for publication, without secrets or local paths.
Private supporting context belongs in local references, not published fields.
Publication uses exact body files and reconciles the existing PR and its marked
summary comment before retrying. A failed or interrupted publication stays pending.

Standalone `tldr fix` has the same review budget but no commits or publication.
Other non-delivery work finishes after its result. Required failures must be
reported even when the requested operation has finished.

## Resume and restrictions

`resume --run <uuid>` checks current identity and reconciles reviewed evidence.
A changed head/base/diff invalidates a pass. Re-review after a completed round
uses the next numbered round from the existing budget. An unfinished round
retains its number. Post-publication drift reports follow-up without a new loop.

Retry pending `commit` or `publish` through the same command and run. The
controller inspects observed state before repeating a write. Unexpected changes
block recovery. Retain prior outcomes and the exact blocker; never discard the
record to get a fresh budget.

If a human edits a PR while publication is pending, inspect the new body and
preserve it in the intended update. Resubmit complete publication fields with
`refresh_inspected_input: true` and the newly inspected `existing_body`. The
controller retains the former input in history and checks the latest remote
body again before editing.

`restrict --run <uuid>` accepts `authorization` with revoked keys set to false,
and `revoke_auto: true` when applicable. Apply later user restrictions immediately.
New scope or renewed authority requires an explicit user instruction and a
reconciled continuation, never an unrecorded edit to permissions.

The shared state lock serializes controller writes. If interrupted, inspect the
PID in `state/.lock` and confirm the process has stopped before removing that
one stale lock. Do not remove another live run's lock.

Legacy Markdown records do not contain executable assignments. Preserve them
under `state/legacy/` and reconstruct their scope, evidence, phase, and consumed
rounds before resuming. `import --input <continuation.json>` accepts `request`,
`legacy_files` relative to the factory, `reconstruction_evidence`, `round`,
`phase`, `history`, and `findings`. It prevents importing a source twice and
does not grant a fresh review budget. Old passing evidence requires current
review or an explicit exhausted, unready result. Report gaps rather than starting
another round 0. Published legacy work is a follow-up report, not authority to
restart publication; include `published: true` and its `pr` identifiers, preserve
the remote evidence, and report it directly.

## Standalone Git operations

Start `tldr pull`, `tldr push`, or `tldr pr` with its explicit authorization key.
Use `git --run <uuid>` with `scope_verified: true`; PR operations also take the
title/body fields above. These operations neither create a feature worktree nor
run a delivery review. Pull defaults to fast-forward and retains divergence for
reconciliation under the repository's established policy. The parent may perform
an explicitly authorized merge or rebase when needed, then record the evidence
and resume. No automatic stash, force-push, or branch deletion is provided.
