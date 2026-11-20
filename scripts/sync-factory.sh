#!/usr/bin/env bash
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
check=false
[[ "${1:-}" != --check ]] || check=true
copy_expected() {
    local source=$1 target=$2
    if [[ -f "$target" ]] && cmp -s "$source" "$target"; then return; fi
    if $check; then printf 'Factory copy differs: %s\n' "$target" >&2; exit 1; fi
    mkdir -p -- "${target%/*}"; cp -p "$source" "$target"
}
for guide in "$repo"/skills/openai/factory/references/roles/*.md; do
    role=${guide##*/}; role=${role%.md}
    source="$repo/skills/openai/factory-$role/SKILL.md"
    [[ -f "$source" ]] || { printf 'Missing role skill: %s\n' "$role" >&2; exit 1; }
    temporary=$(mktemp)
    awk '/^---$/ {count++; print; if(count==2)exit; next} {print}' "$source" > "$temporary"
    printf '\n' >> "$temporary"; cat "$guide" >> "$temporary"
    copy_expected "$temporary" "$source"; rm -f -- "$temporary"
    copy_expected "$source" "$repo/skills/claude/factory-$role/SKILL.md"
done
while IFS= read -r -d '' source; do
    relative=${source#"$repo/skills/openai/factory/"}
    case "$relative" in agents/*) continue;; esac
    copy_expected "$source" "$repo/skills/claude/factory/$relative"
done < <(find "$repo/skills/openai/factory" -type f ! -path '*/__pycache__/*' -print0)
printf 'Factory model copies match.\n'
