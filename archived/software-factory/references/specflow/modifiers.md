# Invocation modifiers

These modifiers guide the agent and are validated by the controller.
Recognize `auto` and `tldr` before the mode in either order. Normalize `tdlr` to
`tldr`. Keep the task text after the mode intact. If a mode or task is missing,
resolve the missing task without inventing a feature or delivery target.

## Auto decisions and artifacts

`auto` delegates product and design choices within the requested scope. Inspect
evidence, choose the supported recommendation, record its rationale, and approve
and apply the resulting artifacts without another approval question. This
delegation applies to questions that would otherwise go through Probe. It does
not require creating optional artifacts that the task does not need.

When no recommendation is sufficiently supported, choose a reversible working
assumption where feasible. Record what is assumed, why it is workable, what
depends on it, and how to validate or revisit it. Approval to proceed under an
assumption does not turn it into an observed fact or a passing test result.

Use the artifact model's existing statuses and owners. Record accepted choices
as decisions made by the agent under the user's `auto` delegation, not as
answers personally supplied by the user. Keep uncertain factual claims labeled
as assumptions or inference. Existing explicit requirements and decisions
still constrain recommendations; do not silently override them.

Continue independent work when blocked. Ask only when no workable assumption
exists, required access or facts cannot be obtained, or proceeding would exceed
the requested scope. Report consequential choices as progress, not as approval
requests. Do not relax acceptance criteria to hide a defect or evidence gap.

Mode boundaries still apply. `auto audit` remains read-only, recording any
recommendations or assumptions in its response. `auto analyze` does not write
intended-state specifications. Shape's brief remains optional. `auto` alone
does not authorize Git commits, pushes, PRs, deployments, destructive actions,
or merging. It does not turn a non-implementation task into implementation.

## Tldr delivery

`tldr implement` explicitly requests implementation followed by Tldr's complete
delivery workflow. Complete the implementation and relevant checks in its
feature worktree, then run the bundled Tldr workflow in the same worktree.
Reading Tldr's setup guidance before implementation does not start delivery.
Do not ask for a second approval to start delivery. The modifier
authorizes Tldr's local commits, progress record, bounded review fixes, and
publication under its own rules; merging remains manual.

If implementation blocks before completion, preserve the pending handoff and
continue independent work. Resume delivery once implementation completes.
Missing Tldr does not prevent otherwise feasible implementation: finish the
authorized implementation, report delivery blocked, and retain that pending
step. Do not invent a replacement workflow or claim delivery ran.

`tldr` is valid only with Implement. For another mode, explain the unsupported
combination and ask which mode or delivery task was intended before starting
work. Do not silently drop the modifier or upgrade the task to implementation
or publication. Ordinary requests for implementation remain implementation-only
unless delivery was separately requested.

## Combined delegation and resumption

Carry normalized modifiers, their source, scope, accepted decisions, assumptions,
and pending delivery state through mode transitions and any existing checkpoint.
They remain active for the same task, including resumption and Tldr review fixes.
Do not carry them into an unrelated task. Later user instructions may narrow or
revoke them; reconcile saved state against those instructions before acting.
Revoking `auto` stops future delegated choices. Previously accepted decisions
remain accepted unless the user also withdraws or changes them; preserve history.

With `auto tldr implement`, pass the delegation and its limits into Tldr's
local progress record. Tldr's editor can use Specflow's delegated decisions and
assumption rules for in-scope fixes. This does not waive independent adversarial
review, checks, scoring, publication conditions, or round limits. An unresolved
assumption needed to establish correctness can still block readiness.
