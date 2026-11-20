# Configuration

The host reads and edits `factory/config.json` using native file tools. The
helpers do not evaluate config as shell code or require a JSON parser binary.
Keep the settings committable. Preserve existing user settings during setup.

For `factory config` and `factory config <key>`, follow
[Guided configuration](config-edit.md). That reference defines editable paths,
input validation, profile changes, and when an explicit response permits a save.

```json
{
  "version": 2,
  "base_branch": "main",
  "concurrency": 3,
  "max_rounds": 3,
  "default": {"runner": "codex", "model": null, "timeout_seconds": 1800},
  "roles": {
    "builder": {"runner": "claude", "model": "YOUR_CLAUDE_MODEL"},
    "review-code": {"runner": "grok", "model": "YOUR_GROK_MODEL"}
  },
  "skills": {"roots": [], "include": [], "exclude": []}
}
```

## Profiles

Supported role keys are `intake`, `spec-writer`, `builder`, `review-code`,
`review-security`, `review-ux`, `review-ui`, and `approver`. Supported runners
are `codex`, `claude`, and `grok`. Model names come from the installed CLI and
user account. A null model inherits that CLI's default. Never guess a current
model ID. The host records the requested assignment and any reported model.

Resolve default settings, then role settings, then explicit job overrides. When
a runner changes, clear inherited model, reasoning, and executable settings unless
the override supplies replacements. A profile can provide `model`, `reasoning`,
`executable`, and a positive `timeout_seconds`. Missing or unsupported settings
block dispatch. Do not substitute another provider.

Before `create`, save any job overrides in an effective config file, then copy
that file into the new job as its frozen config through native file tools before
dispatch. Keep the original project config unchanged. Pass the resolved base,
round limit, and concurrency to `create`. Helpers enforce those numeric limits.
Later project changes affect future jobs only.

## Checks

The host derives meaningful validation commands from project instructions,
manifests, and CI. Save a native `factory/checks.ps1` or `factory/checks.sh` for
the active shell. The helper requires that file before creating a job and copies
it into the job. Supply both scripts only when both environments are supported.

Bash checks begin with `set -euo pipefail`. PowerShell checks set
`$ErrorActionPreference = 'Stop'` and explicitly exit nonzero after a failed
native command. Checks must be non-interactive, run in the worktree, and must not
rewrite tracked files. Do not generate an empty script or a script that always
succeeds. The gate uses the frozen copy, not a script changed by the builder.

Changes to `factory/config.json`, `factory/checks.*`, or installed factory skills
fail the gate. Product tests may change and remain subject to review. Passing
checks cannot replace missing acceptance or review evidence.

## Specialist skills

The host reads the project's available skill catalog and uses the helper's
`skills` listing when needed. Include `.agents/skills`, `.claude/skills`, and
`.grok/skills`, relevant user skills, and explicit `skills.roots`. Do not scan
credential directories. Load only relevant SKILL.md files and their referenced
guidance. Deduplicate equivalent model copies. Conflicting same-name definitions
need a decision, not a silent preference.

`skills.include` requires named skills in every role. `skills.exclude` removes
named skills from the dispatch catalog. A missing include blocks that role.
Record the actual catalog and `skills_used` in the role's saved report. Skills
cannot expand the job's scope or authorization. Native CLI configuration may
also load its own instructions, hooks, and tools.

## Existing projects

Version 1 settings from the retired runtime may contain check argument arrays.
Preserve their runner choices and keep a dated copy before adapting those checks
into native scripts and updating the config to version 2. Do not delete old job
records. Native helpers use a separate `job.state` format. Create a linked
successor for unfinished old jobs and reuse only evidence for the same commit.
