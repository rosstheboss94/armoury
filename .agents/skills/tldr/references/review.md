# Adversarial code review

## Establish evidence

Identify the review boundary and record the exact head and base commits. For
local uncommitted review, identify the working diff as well and state that the
result cannot certify a later commit without reconciliation. Read the relevant
implementation, callers, tests, acceptance criteria, and governing decisions.

Try to disprove that the change meets its requirements. Look for concrete
failure paths, regressions, and missing verification. Do not invent defects to
fill a quota or treat stylistic preferences as correctness findings.

Use the repository severity scheme, mapped to these blocking meanings when
needed. Critical means immediate security, safety, or irreversible-data risk.
High means an acceptance blocker or major contract violation. Medium means a
meaningful nonblocking weakness. Low means a local minor issue.

## Independent review

Use the reviewer role and model selection rules in
[Agent roles and models](../SKILL.md#agent-roles-and-models). Give the reviewer
the task, scope, head and base, current diff, relevant specifications, and
verification evidence. It may inspect surrounding code and run relevant
non-mutating checks. It must not edit files, post feedback, or perform Git
mutations. Supply the scoring rubric without suggesting a score to reproduce.

The reviewer covers correctness, regressions, acceptance behavior, failure
paths, security, and verification gaps. Ask for its score under the rubric,
supporting evidence, actionable findings, and verification limits. The editor
must not review or approve its own changes in place of this reviewer.

Give the reviewer the feature worktree path and require it to use that path for
delivery reviews. The editor must finish its work and checks before the parent
commits the intended change locally for review. Pause writes to reviewed
files while review runs, and coordinate checks that write build outputs. If the
head, base, or reviewed files change, reconcile the evidence and review again.
Standalone read-only review may inspect the requested checkout without creating
a worktree. Before authorized fixes begin, apply Delivery's
[worktree rules](delivery.md#isolate-the-work).

Use the entrypoint's disclosed single-agent fallback only when delegation is
unavailable or prohibited. An unavailable preferred model instead uses a
separate reviewer on the parent's current model.

## Findings and scoring

Each finding needs a stable identifier, severity, exact source location,
expected and observed behavior, impact, supporting evidence, and a closure
condition. Preserve existing identifiers and use Specflow labels where already
assigned. Distinguish demonstrated defects from hypotheses requiring a check.

Verify reported findings. Record each as open, fixed with evidence, rejected
with evidence, or deferred with a reason. A deferred critical or high finding
still blocks passing. Ask the reviewer to reassess disputed findings using the
new evidence; the coordinator must not silently override that reviewer's score.
If disagreement remains unresolved, report it and stop affected work.

| Score | Evidence-based meaning |
| --- | --- |
| 1 | Fundamental failure or critical defect |
| 2 | Major defects or high-severity findings |
| 3 | Meaningful unresolved defects or insufficient verification |
| 4 | Acceptance behavior verified, with only nonblocking findings |
| 5 | No actionable findings within the reviewed scope, with strong verification |

A score describes reviewed evidence, not a guarantee. The reviewer must give
at least 4/5. No unresolved critical or high finding may
remain, and required local checks must pass for the current head. Missing required
evidence prevents passing even if the numerical score is high. Report
nonblocking findings and residual uncertainty even on a passing result.

This is the local review gate. Checks that need a push or PR remain pending
publication. After publication, required GitHub checks and repository merge
requirements also govern final readiness. Do not claim those checks passed
based on local evidence alone.

## Fix loop

Always run an initial adversarial review and label it round 0. Its score comes
from the reviewer, not an editor or parent estimate. A passing round 0 satisfies
the minimum review requirement and needs no additional pass. During delivery,
create [Local progress](progress.md) before this review and save its result.
Allow at most three subsequent fix-and-review rounds, numbered 1 through 3.
Standalone review reports findings
without starting this loop unless fixes were requested. Standalone fixes use
the same round count and cap but remain local. Requesting fixes alone does not
authorize commits, pushes, PR updates, or review publication. Review the updated
working diff and identify its base and uncommitted state in the report; perform
Git/GitHub writes only within separately established authorization.

For each round, the parent verifies findings and assigns approved in-scope
fixes to the editor. Give it the findings, closure conditions, accepted intent,
worktree path, and completed round count. The editor applies fixes, runs affected
checks, and returns its evidence and unresolved issues. The parent inspects the
result. During delivery, it commits changed content locally before requesting
a fresh review. For evidence-only closure with no file changes, retain the same
head and provide the new check evidence without an empty commit. For standalone
fixes, request review of the updated local diff unless publication is authorized.
The reviewer checks both finding closure and regressions introduced by the
fixes. Keep prior findings and dispositions available for this reassessment.
Reuse the editor and reviewer where possible; if either must be replaced,
transfer the same scope, decisions, evidence, and remaining round budget.
An unchanged commit does not justify a higher score without new evidence.

During delivery, the parent records each round's start, result, findings, and
checks in Local progress. Do not push commits or update a PR during these rounds.

Use [Specflow handoff](specflow.md) if the fix depends on specifications or an
intent decision. Do not change acceptance criteria to make a failed review pass.

Stop local fixes when the gate passes, three fix rounds finish, a round makes
no verifiable progress toward closure, or further work needs user input, access, or expanded
authorization. Report the exact blocker and next action. Do not keep editing
just to consume the budget. Pending external checks require no additional fix
round unless their results require a code change. For delivery, a passing local
gate or three completed fix rounds permits publication under
[Delivery](delivery.md#deliver-a-feature). Publish an exhausted result even if
it failed the gate, clearly reporting that it is not ready for merge. An earlier
stop remains local unless the user separately requests publication. Standalone
review and fixes never gain publication authorization from round exhaustion.

## PR and chat report

During the local loop, save review history in [Local progress](progress.md).
Once delivery reaches its publication boundary, create or update one clearly
identified Tldr review-summary comment on the PR from that record. Keep a
compact history of round numbers, head and base commits, reviewer scores,
finding dispositions, and executed check results.
State current readiness, remaining blockers, nonblocking findings, and any
single-agent fallback. Include requested and observed role settings and any
model or effort fallback, marking unverified settings as unknown. Link detailed
evidence instead of copying long logs.

Locate the saved comment before updating it. Edit only the known Tldr summary
created for this workflow, preserving other comments and human feedback. If
publication is blocked, retain the report in chat and report the failed update;
do not claim that the PR record is current. Do not submit a formal GitHub
approval as a substitute for this summary or for the user's manual merge.

For standalone review, keep output in chat unless publication was requested.
On delivery interruption, update the local record, including the completed
round count and next action. The PR summary is a published report, not the
canonical resume record. For standalone work, use chat or an explicitly
requested saved report.
