# Probing assumptions and findings

Use Probe to settle consequential uncertainty, either standalone or within
another mode. Follow [Artifact model](artifact-model.md) for records, decision
owners, and checkpoints.

## Investigate and ask

Find active assumptions and actionable findings through their evidence,
dependency, contradiction, and verification links. Work on prerequisites and
items that block the current target first. Do not reopen settled items without
new evidence. Revisit deferrals only when requested, expired, or blocking the
current target.

Inspect evidence before asking. Reject disproved findings with sources. Current
behavior can settle facts but cannot establish intended policy by itself.
For an assumption, identify the provisional claim and needed decision. For a
finding, identify the evidenced problem and its closure condition.

When `auto` is active, apply [Modifiers](modifiers.md) before asking: choose a
supported recommendation or explicit reversible assumption within delegated
scope, record it, and continue. Ask only for the blockers those rules leave.
Without that delegation, ask one or two related consequential questions at a time. Give enough context,
affected behavior, evidence, and supported options for a decision. Do not repeat
the full queue or ask questions evidence and existing authorization already settle.

## Apply the answer

Turn a clear approved answer into a linked decision at its canonical owner and
apply its in-scope effects to affected specifications. This applies during
standalone Probe as well. No Build transition or second approval is required
solely to record the decision or apply its clear effects.

For a partial answer, record the settled portion separately while preserving
the assumption's label and remaining uncertainty. Apply only effects whose
meaning and scope are clear and approved. Keep dependent unresolved wording
provisional and ask about the missing part. A deferral does not approve a default.

If the answer calls for substantial drafting or specification development,
continue in Build under the same authorization. Documentation corrections
settled by evidence and accepted intent may be applied within authorized scope.
Product defects remain open for Implement; do not claim a fix before verification.
If implementation was already requested, its authorization carries forward.

Recheck affected records and dependencies after applying a decision or edit.
Add newly evidenced assumptions or findings, but do not schedule another full
Probe pass solely because files changed. Continue independent items when one
branch needs unavailable input or work outside scope.

## Checkpoint and completion

Preserve answers, dispositions, approvals, application state, and unresolved
work under the artifact model's checkpoint rules. Distinguish accepted intent
in canonical specifications from pending proposals in the checkpoint.

Probe is complete for its scope when each active item has a disposition and
remaining blockers or deferred work have an owner or next action. Findings may
be resolved after verified correction, rejected with evidence, accepted as risk,
deferred, or routed to other work. Do not describe an open item as resolved.
Report decisions applied and the next unresolved choice without repeating the queue.
