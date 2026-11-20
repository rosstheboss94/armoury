
# Specflow

## Choose a mode

Recognize optional `auto` and `tldr` modifiers before the mode, in either order.
Accept `tdlr` as an alias for `tldr`. Read [Modifiers](modifiers.md)
when either is present or retained in the current task's saved context.

- `software-factory specflow auto <mode> <task>` delegates recommended in-scope decisions and
  artifact approval, using explicit reversible assumptions when needed.
- `software-factory specflow tldr implement <feature>` requests implementation followed by
  automatic Tldr delivery without another handoff approval.
- `software-factory specflow auto tldr implement <feature>` combines both behaviors.

The `tldr` modifier applies only to Implement. Explain incompatible combinations
without silently starting implementation. Without modifiers, use the existing
workflow. Modifier words inside the task description are not invocation flags.

If the user invokes `software-factory specflow` without a task, offer these modes and ask for
the job. Otherwise select the mode that fits and begin.

- [Shape](shape.md) clarifies an idea, optionally in a brief.
- [Analyze](analyze.md) onboards an existing project by
  recording current behavior, broad requirements, unknowns, and evidence.
- [Build](build.md) drafts and develops specifications
  from approved intent and relevant repository evidence.
- [Probe](probe.md) resolves assumptions and findings,
  and applies clear approved answers to affected specifications.
- [Audit](audit.md) checks consistency, coverage, and
  readiness without changing files.
- [Implement](implement.md) carries out a feature or bug fix.
  Select it for an implementation request.

Read the reference for each mode used. Read [Artifact model](artifact-model.md)
when reading or writing specification records. It owns labels, statuses, layout,
navigation, decision ownership, and history rules.

Every specification `index.md` is a router: a title and a bullet list of links
with short reading guidance. Keep substantive content in named records. When
editing specifications, normalize existing indexes under the artifact model's
migration rules.

Use only the modes the task needs. Build and Implement inspect their own
relevant evidence; Analyze is not a prerequisite for an existing project.
Probe may apply an answer directly without switching to Build. Use Build when
specifications need drafting or further development.

## Shared principles

Follow project terminology and useful document conventions. Apply the factory's [Unslop](../unslop.md) guidance to prose. Keep observed behavior separate from
approved intent, label inference and uncertainty, and attach evidence to
consequential claims. Record conflicting sources instead of silently choosing one.

After a decision or edit, recheck affected records and dependencies for
consistency, links, and verification effects. Return to Probe only when new
evidence or unresolved uncertainty warrants it.

Scale updates and final results to the task. Explain the result, supporting
evidence, changes, checks and their limits, and unresolved work when relevant.
Omit empty sections, mode histories, and repeated queues. Save enough context
to resume interrupted work using the artifact model's checkpoint rules.

## Authorization

Authorization and delegated choices carry across mode transitions. A clear
user-approved decision authorizes its in-scope specification changes. Do not
ask again solely because the mode changed. Discuss consequential new design
choices when existing decisions or delegation do not settle them. Ask only
about the unclear scope or meaning, and continue independent work.

- Shape may write an optional brief within the request.
- Analyze may write analysis documents, but not intended-state specifications.
- Build may create or update intended-state specifications within scope.
- Probe may record decisions and apply their clear approved effects to
  specifications, including during standalone use. Keep partial or unapproved
  answers provisional.
- Audit is read-only. Report needed corrections unless the user authorizes
  another mode to apply them.
- Implement alone may change product code and related repository files needed
  for the requested outcome. An implementation request authorizes ordinary
  in-scope edits and checks without another write approval.

Use active `auto` delegation to settle in-scope choices under Modifiers. Pause
affected work for choices that remain unresolved, conflicting intent,
material scope expansion, or destructive actions beyond the authorization.
No mode may commit, publish, deploy, migrate live data, or cause another
external effect unless the user requested it. Existing authorization remains valid.

For requested Git/GitHub delivery or adversarial code review, use the bundled
[Tldr workflow](../tldr/overview.md). Implement's delivery handoff describes the
shared context. Implementation alone does not start delivery. The `tldr`
modifier explicitly requests delivery and leaves merging to the user.
