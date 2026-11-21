---
name: factory
description: Run resumable software jobs from chat or labeled GitHub issues through specification, isolated builds, checks, reviews, and ready pull requests. Configure each step to use Codex, Claude, or Grok CLI models.
---

# Factory

The host agent orchestrates this workflow. Native PowerShell or Bash helpers own
job records, worktrees, checks, transition gates, commits, and PR delivery. Use
the installed skill directly from any project's Git root. No separate language
runtime or JSON parser is required by the factory.

Apply [Writing](references/writing.md) to prose and read the project's rules.
Preserve user changes, approved scope, and existing authorization.

## Choose the operation

Accept the host's skill syntax or a plain request to use the factory. A freeform
task selects `start`. A bare invocation shows the operations without writing
records. Status queries and ordinary questions remain read-only.

| Operation | Behavior |
| --- | --- |
| `factory init` | Set up this project's settings and checks |
| `factory add <idea>` | Create one labeled GitHub issue and return its URL |
| `factory start <task>` | Run a new chat task through the pipeline |
| `factory run [issue]` | Process labeled issues or one selected issue |
| `factory status [job]` | Read saved state and blockers |
| `factory resume <job>` | Reconcile evidence and continue interrupted work |
| `factory feedback <job> <text>` | Record the user's answer or feedback and continue |
| `factory config [key]` | Inspect defaults or guide an edit for future jobs |
| `factory dashboard` | Generate and open the local read-only board |

`start`, `run`, and `feedback` request the complete pipeline, including commits,
pushing the job branch, and creating or updating its PR. Explain this endpoint
when introducing the factory. Never merge or deploy. Model selection does not
grant additional permissions.

## Set up the project

Read [Runtime](references/runtime.md) for native helper commands. Resolve the
project root from the session's working directory with `git rev-parse
--show-toplevel`. Resolve the helper from this installed skill, not the project.
Select PowerShell on Windows or Bash on systems using Bash. Do not introduce
another runtime or execute retired helpers from `archived/`.

Route `add` before first-use setup. Follow [Issue creation](references/add.md).
Write the exact idea to an exclusively created UTF-8 temporary file without a
BOM, pass that path as a literal argument to the helper, and remove only that
owned input file afterward. Report the returned URL and say the issue is queued
for a later run. `add` authorizes issue creation and does not start a build.

Route `config` before first-use setup too. Follow
[Guided configuration](references/config-edit.md) for both bare inspection and
`config <key>`. Show the current value and all permitted choices for a finite
setting, or request typed input with its constraints. Wait for an explicit valid
response before saving. Inspection, cancellation, and unanswered prompts write
nothing. Use native file tools, preserve unrelated settings and frozen jobs,
and report that saved changes apply to future jobs. This operation starts no
pipeline and needs no GitHub access.

On first use for a pipeline task, initialize `factory/config.json`, inspect repository
instructions, manifests, and CI, and write meaningful native project checks.
Choose the invoking host's CLI unless the user selected another. Preserve
existing settings. Continue the original task after setup. Ask only for a
necessary choice that project evidence cannot settle. Never require the user to
run setup commands manually.

Read [Configuration](references/config.md) for profiles and project checks. The
host reads JSON through its file tools, applies role and job overrides, and
prepares prompts. Helpers receive resolved arguments. They never evaluate a
config file as shell code. Project settings and job history stay in the project.
The global package stays in the user's skill directory.

## Run the pipeline

Read [Workflow and records](references/workflow.md) before starting work.

```text
Intake -> Specification -> Build -> Checks -> Reviews -> Approval -> Ready PR
                            ^                    |
                            +------ Rework ------+
```

The host dispatches each role through its selected CLI. It does not perform an
assigned role itself or invent missing review evidence. Use the independent
factory role skills from the installed collection, with bundled role references
as a fallback. Discover relevant project and host skills through their catalogs.
Load only applicable guidance and record the skill names used by each role.

The helpers create jobs, freeze settings and checks, manage isolated branches,
validate transitions, and retain the build budget. They enforce checks before
review, all required current reviews before approval, and the reviewed commit
before delivery. Code review always runs. Add security, UX, and UI reviews when
the task or actual changes require them. Missing required visual evidence blocks
a review. Never change records directly to bypass a helper refusal.

The host normalizes provider JSON into the documented report format using native
file tools, then submits reports through `accept`. Read the actual result,
including error and completion fields. Successful process exit alone does not
prove the role completed. Do not manufacture a passing verdict from logs.

## Resume and finish

Reconcile the worktree, current commit, saved reports, dispatch locks, and PR
before resuming. Never duplicate a live child process. A stale lock requires
inspection of its recorded owner and child before removal. Keep previous rounds
and feedback. Changed commits require fresh checks and reviews within the
remaining budget. Exhausted jobs need a linked successor.

Report the job's state, checks, review outcome, blocker, and PR link. Distinguish
ready for a human merge from merged. Report missing runners, permissions, or
evidence without silently changing providers. When the frozen job config stores
JSON true for `vibe`, re-dispatch one eligible `needs-human` role with the blocker
text and require one allowed verdict. A second stop still waits. `needs-info`
still requires the person's words through `feedback`. A missing `vibe` value,
any stored value other than JSON true, round-budget exhaustion, a runner failure,
merge, and deploy also wait. Do not invent that answer during resume.

The dashboard is a self-contained HTML snapshot refreshed by recorded operations.
Open the printed file path in the available browser. It needs no HTTP server.

## Design reference

This skill follows the stage-based approach of
[ZazenCodes software factory v2](https://github.com/zazencodes/zazencodes-season-3/tree/main/src/software-factory-claude-code-v2).
The role instructions, native helpers, and dashboard in this version are new.
