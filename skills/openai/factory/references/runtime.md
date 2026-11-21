# Runtime

Use PowerShell 5.1 or newer, or Bash 4 or newer with standard Unix file tools.
Jobs also need Git, an authenticated GitHub CLI, and the selected agent CLIs.
The factory does not require Python, Node, jq, or a background service. A target
project may have its own build tools, which its checks still need.

## Install once

Run either native installer from a downloaded Armoury checkout:

```powershell
.\scripts\install-factory.ps1 -Model openai
```

```sh
bash scripts/install-factory.sh --model openai
```

Use `claude` for the Claude variant. User scope is the default. OpenAI packages
go in `~/.agents/skills`, which Codex and Grok discover. Claude packages go in
`~/.claude/skills`. The installer copies all nine skills and their resources.
The downloaded repo is not needed afterward. Differing existing files are
reported before copying. Identical installs are repeatable.

If the user skills directory is a junction or symbolic link to a shared library,
keep the link. Install into its existing physical target with
`-SkillsPath <directory>` in PowerShell or `--skills-path <directory>` in Bash.
Use this option without scope or project options. Links inside installed skills
remain blocked. Existing differing files still require a separate backup before
replacement.

For a project-only install, use `-ProjectPath <root>` in PowerShell or
`--project <root>` in Bash. Explicit `-Scope project` or `--scope project` without
a path chooses the current directory. Installation changes no project rules,
GitHub settings, or machine-wide PATH.

Open an agent at a project's Git root and invoke `$factory start <task>` in
Codex or `/factory start <task>` in Claude or Grok. The skill handles first-use
setup. Open a new session if the current one has not discovered the new skill.

## Native helper interface

The host chooses the native helper and supplies resolved paths and arguments.
Examples below use placeholders for paths, not commands for the user to type.

```powershell
& <skill-dir>/scripts/factory.ps1 init -ProjectPath <root> -Runner codex
& <skill-dir>/scripts/factory.ps1 create -ProjectPath <root> -Base main -File <task-file>
& <skill-dir>/scripts/factory.ps1 label -ProjectPath <root> -Issue <number> -Status running
& <skill-dir>/scripts/factory.ps1 dispatch -ProjectPath <root> -Job <id> -Role builder -Runner grok -Prompt <prompt-file>
```

```sh
bash <skill-dir>/scripts/factory.sh --project <root> init --runner codex
bash <skill-dir>/scripts/factory.sh --project <root> create --base main --file <task-file>
bash <skill-dir>/scripts/factory.sh --project <root> label --issue <number> --status running
bash <skill-dir>/scripts/factory.sh --project <root> dispatch --job <id> --role builder --runner grok --prompt <prompt-file>
```

Both helpers provide the same operations. PowerShell uses named parameters and
Bash uses lowercase `--` options.

| Helper action | Required information |
| --- | --- |
| `init` | Runner, optional base branch |
| `add` | Exact UTF-8 idea file, optional label, returns the created issue URL |
| `label` | Saved issue number and one status name: `running`, `need-human`, or `stopped` |
| `create` | Request file, base branch, resolved limit and concurrency |
| `queue` | Optional queue label, returns paginated GitHub issue JSON |
| `status` | Optional job, returns saved JSON summaries |
| `skills` | Lists project and user skill entrypoints |
| `prepare` | Job, reconciles its isolated branch and worktree |
| `dispatch` | Job, role, runner, prompt, optional model, reasoning, executable, timeout |
| `accept` | Job, role, normalized Markdown report file |
| `gate` | Job, optional check timeout |
| `advance` | Job, next stage, optional blocker report file |
| `feedback` | Job, real feedback file, optional recovery stage |
| `deliver` | Job with current approval and reviews |
| `dashboard` | Regenerates the local board and prints its file path |

Use `-Next` or `--next` for stage changes. PowerShell's timeout parameter is
`-TimeoutSeconds`; Bash uses `--timeout`. Defaults are three concurrent jobs,
three build rounds, and 1,800 seconds per dispatch or check. `create` freezes
`-Limit` or `--limit` and the effective config. A new role or provider assignment
comes from the frozen profile or an explicit job override, not a silent fallback.

## Agent execution

The host prepares a prompt file containing the role guide, project instructions,
request, acceptance criteria, current commit, relevant reports, and the catalog
of applicable skills. It explicitly forbids writes by review roles, edits outside
the worktree, changes to factory controls, nested agents, and Git delivery.

Helpers invoke `codex exec --json`, `claude -p --output-format json`, or Grok's
prompt-file mode. They use argument arrays, preserve CLI permissions, and never
enable approval bypasses. Read roles use restricted tools or a read-only sandbox.
Each attempt saves its prompt, stdout, stderr, requested model, exit status, and
starting commit. The host extracts the final result from that provider's JSON,
checks completion and error fields, and submits the normalized report.

A missing CLI, denied operation, nonzero exit, timeout, malformed result, or
missing evidence blocks the affected stage. Preserve the attempt and use
`advance` to record `needs-human`. The host does not treat an empty response or
unfinished turn as success.

## Dashboard and recovery

Every state save regenerates `factory/dashboard.html`. It contains job summaries
and reports as escaped JSON, with inline CSS and JavaScript. Open the file
locally. Choose Refresh jobs to load the latest saved snapshot. The page does not
reload on a timer, so reading and keyboard navigation continue until you refresh.
Refresh restores the button focus and scroll position when browser session storage
is available. Report dialogs show the job and report name and return focus to
their opening button when closed. Resolved blockers remain in report history and
leave the active summary after feedback resumes work.
Recorded operations update the saved snapshot. No HTTP server or additional runtime
is needed. Reports render as text, not HTML. Raw logs and config stay outside
the board. Usage and cost remain unknown unless the host has actual CLI evidence.

Directory locks record the owning shell and process. Dispatches and checks also
record the child process. Normal completion releases the lock. A crash leaves
it for inspection. The host must verify that both owner and child stopped before
removing that exact lock directory. Never remove an unknown live process or reset
a job's budget to recover it.

Retired implementations and their tests live under `archived/`. They are history,
not a fallback execution path or part of the installed package.
