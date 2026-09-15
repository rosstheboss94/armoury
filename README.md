# Armoury

Armoury ships one software-factory skill for Codex and Claude. It combines
Code Structure, Specflow, Tldr, and Unslop with Python workflow control.

The factory retains the existing operations: service code organization,
specification shaping and maintenance, implementation, adversarial review,
Git and GitHub delivery, and prose editing. Python tracks phases and review
gates. The current agent performs reasoning and uses its native delegation tools.

## Install

Requirements are Python 3.10 or newer and PowerShell or Bash 4 or newer.
Git is required for worktree operations; GitHub CLI and existing authentication
are required for GitHub delivery. The target project directory must exist.

Run either installer without arguments for interactive selection, or supply:

```powershell
.\scripts\install-skills.ps1 openai software-factory C:\path\to\project
.\scripts\install-skills.ps1 claude all C:\path\to\project
```

```bash
bash ./scripts/install-skills.sh --model openai --skills software-factory --project /path/to/project
bash ./scripts/install-skills.sh --model claude --skills collection:software-factory --project /path/to/project
```

Both models install into `<project>/.agents/skills/software-factory/`. All factory
instructions, scripts, specifications, and state live there. The full `SKILL.md`
occupies the discovery location for both models; there is no forwarding file.

Ask "show factory workflows" to list Specflow and Tldr workflows. Start work
with `specflow analyze: explain this app` or `tldr review: review the change`.
Natural-language requests map to those same names. Only delivery requests
publish a PR.

Existing operation syntax also works:

> Read .agents/skills/software-factory/SKILL.md and use specflow auto tldr implement
> to implement the approved feature and deliver its PR.

Other requests include `specflow shape`, `specflow audit`, `code-structure review`,
`tldr review`, `tldr push`, and `unslop`. These are operations inside one skill,
not separately registered commands. `auto` delegates in-scope decisions;
`tldr implement` authorizes delivery. Ordinary implementation stays local.
Tldr retains its initial review, at most three fix rounds, and manual merging.

The [factory entrypoint](skills/openai/software-factory/SKILL.md) routes to
detailed instructions. [Controller](skills/openai/software-factory/references/controller.md)
documents JSON requests and phase results.
[Workspace](skills/openai/software-factory/references/workspace.md) documents
installation, migration, junctions, symlinks, and cleanup.

Reinstallation updates packaged files while preserving specifications, delivery
state, and unrelated local files. Install updates into the canonical checkout.
Existing standalone installations remain until their removal is requested.

## Shared worktrees

The original checkout holds the physical factory directory. Each feature
worktree points its `.agents/skills/software-factory` directory at that same folder
using a Windows junction or POSIX symlink. Specification edits and delivery
history appear across worktrees immediately. Product edits and build outputs
stay in the feature worktree.

Use the factory's setup commands to create or link worktrees and adopt existing
local specifications. Cleanup removes only a feature worktree's link, preserving
the canonical factory. Conflicting specification trees need reconciliation before
migration. The shared folder is local storage, not a remote backup.

## Repository maintenance

Active packages live at `skills/<model>/software-factory/`.
Both variants include the dashboard and retain the underlying operations.
Use `--projects-directory <parent-folder>` with the dashboard launcher to enable
Add project. Direct Compose accepts `FACTORY_PROJECTS_DIRECTORY` instead.
Retired skills and collections live under `archived/`,
including the original Tldr junction/symlink update.

The [software-factory collection](collections/software-factory/collection.yaml)
contains the single active skill. Installers accept its name, `all`, `0`,
`1`, or `collection:software-factory`. Old standalone names are archived.

Read [AGENTS.md](AGENTS.md) before editing. Preserve the original capabilities
and keep model variants and repository instructions in sync. Validate with:

```text
python scripts/check-installers.py
python scripts/check-factory.py
```

Installer checks require Python, PowerShell, and Bash 4 or newer. Runtime tests
use temporary Git repositories and mocked GitHub responses; they do not publish
PRs. Run the skill validator for both model packages after instruction changes.
