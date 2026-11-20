# Armoury

Reusable skills for coding agents. The factory runs tasks through specification,
isolated builds, project checks, reviews, and a ready pull request. Each step can
use a configured Codex, Claude, or Grok CLI model.

## Install the factory once

Download or clone this repository. From its root, install for your user with
PowerShell:

```powershell
.\scripts\install-factory.ps1 -Model openai
```

Or use Bash 4 or newer:

```sh
bash scripts/install-factory.sh --model openai
```

This installs the factory and its eight role skills in `~/.agents/skills` for
Codex and Grok. For Claude, use `-Model claude` in PowerShell or `--model claude`
in Bash. The Claude variant installs in `~/.claude/skills`. The copied packages contain
everything they need. You can move or remove the downloaded repository afterward.
Existing differing skills are preserved and reported as conflicts.
Installation and factory operations use native shell tools. No Python runtime is required.

If your user skills directory links to a shared library, keep the link and pass
its existing physical target with `-SkillsPath <directory>` in PowerShell or
`--skills-path <directory>` in Bash. Existing differing files are preserved.

## Run from a project

Open Codex, Claude, or Grok in your project's Git root. Invoke the skill in chat:

```text
$factory start add saved searches
```

Use `/factory start add saved searches` in Claude or Grok. On first use, the
skill handles project setup and selects the project's checks. Configuration and
job history stay in that project. There is no per-project skill installation.

Running factory jobs requires PowerShell or Bash, Git, an authenticated GitHub
CLI, and the agent CLIs you choose. The host agent orchestrates the skills and
native helpers enforce checks and job transitions. Successful jobs stop at a
ready PR for you to merge.

To queue an idea without starting a build, use `$factory add <idea>` in Codex
or `/factory add <idea>` in Claude or Grok. It creates one issue in the project's
GitHub repository with the existing `factory` label, then returns its URL.
It needs no factory setup. The full idea becomes the body. The title uses the
first nonblank line, trimmed and limited to 120 UTF-8 bytes. The helper makes
one creation request and never retries it automatically. See
[issue creation](skills/openai/factory/references/add.md) for file input, custom
labels, failures, and how to check for an existing issue before retrying.

For a project-only install, add `-ProjectPath <project-root>` in PowerShell or
`--project <project-root>` in Bash.
See the [runtime guide](skills/openai/factory/references/runtime.md) for setup and
the [configuration guide](skills/openai/factory/references/config.md) for models,
checks, and optional project skills.

## Repository maintenance

The factory collection contains the core and eight role skills in both model
directories. OpenAI includes agent metadata. Shared instructions, native
scripts, and dashboard assets must match. Run `scripts/sync-factory.ps1` or
`scripts/sync-factory.sh` after changing the OpenAI sources.

Read [AGENTS.md](AGENTS.md) before editing. Validate with both native shells:

```powershell
powershell -NoProfile -File scripts/check-factory.ps1
powershell -NoProfile -File scripts/check-installers.ps1
```

```sh
bash scripts/check-factory.sh
bash scripts/check-installers.sh
```

Checks use temporary repositories and offline GitHub fixtures. They do not
create live issues or PRs. Active tooling requires no Python, Node, or jq.
Retired skills, collections, and scripts remain under `archived/` for history.
