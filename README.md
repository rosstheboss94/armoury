# Armoury

Armoury is a library of reusable skills for coding agents. Skills describe
workflows that can travel between projects.

## Skills

| Skill | Purpose |
| --- | --- |
| [code-structure](skills/openai/code-structure/SKILL.md) | Structure service code and modules. |
| [specflow](skills/openai/specflow/SKILL.md) | Shape, specify, audit, and implement changes. |
| [tldr](skills/openai/tldr/SKILL.md) | Pull, push, manage PRs, and review code adversarially. |
| [unslop](skills/openai/unslop/SKILL.md) | Remove generic AI writing. |

Links above open the OpenAI versions. Equivalent Claude versions live in
[skills/claude](skills/claude/). OpenAI uses `$skill-name`; Claude uses
`/skill-name`. Each `SKILL.md` documents its modes and requirements.

Use `specflow implement <task>` for feature additions and bug fixes. Add the
`tldr` modifier to request delivery through a GitHub PR. The `auto` modifier
allows in-scope decisions and artifact approval; it does not itself authorize
publication. See [Specflow modifiers](skills/openai/specflow/references/modifiers.md).

Specflow and Tldr require Unslop. Install `design-delivery` to get all three,
or include `unslop` when selecting those skills individually. Installers do not
resolve dependencies automatically.

## Install

Requirements are PowerShell for the `.ps1` script, or Bash 4 or newer with
standard Unix tools for the `.sh` script. The target project directory must exist.

Run an installer without arguments to choose a model, skills or collections,
and the target project, then confirm the copy:

```powershell
.\scripts\install-skills.ps1
```

```bash
bash ./scripts/install-skills.sh
```

Supply all three values to skip prompts:

```powershell
.\scripts\install-skills.ps1 claude all C:\path\to\project
.\scripts\install-skills.ps1 openai code-structure,unslop C:\path\to\project
.\scripts\install-skills.ps1 openai collection:design-delivery C:\path\to\project
```

```bash
bash ./scripts/install-skills.sh --model claude --skills all --project /path/to/project
bash ./scripts/install-skills.sh --model openai --skills code-structure,unslop --project /path/to/project
bash ./scripts/install-skills.sh --model openai --skills collection:design-delivery --project /path/to/project
```

Quote paths that contain spaces. Bash converts Windows paths under Git Bash or
WSL. Selections accept names, menu numbers, and comma-separated combinations.
Use `all` or `0` to select every active skill. Duplicate selections are copied once.

| Model | Destination |
| --- | --- |
| OpenAI | `<project>/.agents/skills/` |
| Claude | `<project>/.claude/skills/` |

Installers overwrite matching files and retain other existing files. They do
not remove stale files from earlier installations. Archived skills are excluded.

## Collections

| Collection | Skills |
| --- | --- |
| [architecture](collections/architecture/collection.yaml) | `code-structure` |
| [design-delivery](collections/design-delivery/collection.yaml) | `specflow`, `tldr`, `unslop` |
| [review-and-challenge](collections/review-and-challenge/collection.yaml) | `tldr`, `unslop` |

Collections group skills for installation. Their members are copied as separate
skill directories. Combine `collection:<name>` with individual skill names as
needed.

Manifests use this simple YAML format. Keep descriptions on one line and list
unquoted skill names under `skills`:

```yaml
name: collection-name
description: What this collection helps you do.
skills:
  - skill-name
```

The name must match the collection directory. Members must be unique, exist in
both model directories, and cover every active skill across the collections.

## Contribute

Each active skill lives at `skills/<model>/<skill-name>/SKILL.md`. Its YAML
frontmatter contains `name` and `description`. Keep detailed guidance in linked
`references/` files. OpenAI copies may include `agents/openai.yaml` metadata.

Read [AGENTS.md](AGENTS.md) before editing. Add or update both model versions in
the same change, keep their behavior equivalent, and update collection
memberships. Check the existing library and any `archived/` skills before adding
a workflow. Move retired skills to `archived/`.

Keep `AGENTS.md` and `CLAUDE.md` identical. After installer changes, run:

```text
python scripts/check-installers.py
```

The checks use temporary projects and require Python 3, PowerShell, and Bash 4
or newer. Armoury has no package build or runtime service.
