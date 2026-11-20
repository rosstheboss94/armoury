#!/usr/bin/env bash
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
fail() { printf 'Library check failed: %s\n' "$*" >&2; exit 1; }
cmp -s "$repo/AGENTS.md" "$repo/CLAUDE.md" || fail 'Repository instructions differ.'
openai_names=$(for path in "$repo/skills/openai"/*; do [[ ! -d "$path" ]] || printf '%s\n' "${path##*/}"; done | sort)
claude_names=$(for path in "$repo/skills/claude"/*; do [[ ! -d "$path" ]] || printf '%s\n' "${path##*/}"; done | sort)
[[ "$openai_names" == "$claude_names" ]] || fail 'Model directories have different skill names.'
members=$(sed -n 's/^[[:space:]]*-[[:space:]]*\([a-z0-9-]*\)[[:space:]]*$/\1/p' "$repo"/collections/*/collection.yaml | sort -u)
[[ "$members" == "$openai_names" ]] || fail 'Collection membership does not match the active skills.'
while IFS= read -r name; do
    first="$repo/skills/openai/$name/SKILL.md"; second="$repo/skills/claude/$name/SKILL.md"
    [[ -f "$first" && -f "$second" ]] || fail "Missing SKILL.md for $name"
    [[ "$(head -n 1 "$first")" == --- && "$(head -n 1 "$second")" == --- ]] || fail "Missing frontmatter for $name"
    [[ "$(sed -n 's/^name: //p' "$first" | head -n 1)" == "$name" ]] || fail "Name differs from directory: $name"
    [[ "$(sed -n 's/^name: //p' "$second" | head -n 1)" == "$name" ]] || fail "Claude name differs from directory: $name"
    description=$(sed -n 's/^description: //p' "$first" | head -n 1)
    [[ -n "$description" && "$description" == "$(sed -n 's/^description: //p' "$second" | head -n 1)" ]] || fail "Descriptions differ: $name"
done <<< "$openai_names"
while IFS= read -r -d '' path; do fail "Retired runtime remains active: $path"; done < <(find "$repo/skills" "$repo/scripts" "$repo/tests" -type f \( -name '*.py' -o -name '*.pyc' \) -print0)
bash "$repo/scripts/sync-factory.sh" --check
printf 'Library names, metadata, collections, model copies, and runtime files are valid.\n'
