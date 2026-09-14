---
name: software-factory
description: Structure code, shape and maintain specifications, implement changes, review code adversarially, deliver GitHub pull requests, and edit prose through one project-local workflow.
---

# Software factory

Read this file when the user asks to use the project's factory. Installation
lives at `.agents/skills/software-factory/`. The full `SKILL.md` occupies the skill
discovery location alongside the factory package, specifications, and state.

## Route the request

Apply [Unslop](references/unslop.md) to all prose. Keep the requested operation's
scope. A request to implement does not authorize delivery.

- `code-structure`: read [Code structure](references/code-structure/overview.md)
  for design, implementation, refactoring, or review of service internals.
- `specflow`: read [Specflow](references/specflow/overview.md). Preserve Shape,
  Analyze, Build, Probe, Audit, Implement, and the `auto`, `tldr`, and `tdlr`
  modifiers. Delivery modifiers apply only to Implement.
- `tldr`: read [Tldr](references/tldr/overview.md) for pull, push, PR management,
  standalone review, authorized review fixes, or feature delivery.
- `unslop`: apply the writing reference directly to the requested text.

These are operation names within this skill, not separately installed skills.
Natural-language requests route to the same operations. Ask for the operation
and scope only when neither the request nor current work identifies them.
Load Code Structure's guidance during implementation when module ownership or
dependency boundaries are involved. Internal Specflow/Tldr handoffs use these
bundled references, without requiring another installed skill.

## Operate the controller

For "open the factory dashboard", read [Dashboard](references/dashboard.md),
then launch or reuse its local server and open the returned address. The agent
manages feature sessions. Users can register projects with Add project after
configuring a projects directory. A trash control removes a project from this
dashboard and keeps its files and history. Users do not run phase commands.
The dashboard defaults to Docker. Use native mode only when explicitly requested;
never install host application dependencies as a fallback for Docker failure.
For monitored work, obtain specification context through `context-read` and
carry the returned session identifier across related runs and handoffs.

Read [Controller](references/controller.md) before running a workflow and
[Workspace](references/workspace.md) before installation, migration, worktree
setup, or cleanup. These references own executable interfaces and factory paths.
The operation references retain their behavioral rules; interpret their local
records through the factory paths. Report conflicts instead of bypassing a gate.

Python controls phase state, authorized Git steps, and delivery gates. The active
agent supplies reasoning and uses native agent tools. Do not launch Pi, Codex,
or Claude CLI agents. The controller's JSON assignments are work for this session,
not a background agent service. The controller validates evidence structure and
Git identity; the reviewer remains responsible for the truth of its findings.

Read-only advice, audit, review, and prose responses stay in chat unless saving
is requested. Use the controller's file-free `route` command to inspect an
operation. Start a persisted run for implementation, delivery, or explicitly
saved work. Never create a state file just to answer a read-only question.

During Tldr, use its editor and independent reviewer roles, model preferences,
and disclosed fallback. Finish editing before review. Scripts perform commits
and publication only after the agent has inspected the scope and submitted the
corresponding authorization and exact files. Agents must not bypass scripts
to evade controller gates, modify their own recorded scores, or reset rounds.

All factory-owned instructions, specifications, checkpoints, and workflow records
live under this directory. Product source edits remain in the feature worktree.
Every linked worktree shares the whole factory immediately. Coordinate record
edits with other active tasks and never remove the canonical factory during
worktree cleanup. Use factory-relative paths in records and omit local paths
from published PR text.
