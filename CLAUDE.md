# Armoury repository instructions

Armoury is a shared library of reusable skills for coding agents.

## Writing and skill changes

- Before responding or creating or editing files, read and apply the active
  `unslop` skill. Apply it to all human-authored text, including progress updates,
  plans, documentation, comments, and examples. Preserve code, structured data,
  generated content, quoted sources, and required syntax where prose rules do
  not fit.
- Read the relevant `SKILL.md` before changing a skill.
- Keep portable instructions in `SKILL.md` and detailed guidance in `references/`.
- Preserve existing skill names and project terminology.
- Move retired skills to `archived/`. Do not silently delete them.
- For roadmap work, follow the roadmap lifecycle reference, preserve closed
  history, and create linked successors for new scope.

## Model variants

Active skills are direct children of `skills/openai/` and `skills/claude/`.
Add, update, rename, or retire both versions in the same change. Keep their
behavior equivalent. Limit platform differences to invocation syntax and
metadata, such as OpenAI's `agents/openai.yaml`, which Claude copies omit.
Keep `archived/` separate from both active sets.

Before finishing a skill change, verify that both model directories have the
same skill names and valid `SKILL.md` files with matching `name` and equivalent
`description` frontmatter. Check that platform differences are intentional.

## Collections

Collections live in `collections/<collection-name>/collection.yaml` and group
skills for installation. Keep active skill directories flat so agents can
discover each skill independently.

Every active skill must belong to at least one collection. Collection members
must exist in both model directories. Update memberships in the same change
when adding, renaming, archiving, or removing skills.

## Repository maintenance

Keep `AGENTS.md` and `CLAUDE.md` identical. Update both in the same operation.
Only introduce platform-specific instructions when the behavior cannot be shared.

Run `python scripts/check-installers.py` after changing either installer script.
The checks require Python 3, PowerShell, and Bash 4 or newer.
