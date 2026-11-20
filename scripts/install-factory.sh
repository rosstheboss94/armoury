#!/usr/bin/env bash
set -euo pipefail

fail() { printf 'install-factory: %s\n' "$*" >&2; exit 1; }
usage() {
    printf '%s\n' \
        'Usage: bash scripts/install-factory.sh --model openai|claude [--scope user|project] [--project PATH] [--skills-path PATH]' \
        'Default scope: user, or project when --project is supplied.'
}

(( BASH_VERSINFO[0] >= 4 )) || fail 'Bash 4 or newer is required.'
factory_model=''
factory_scope=''
factory_project=''
factory_skills_path=''
factory_scope_explicit=''
while (( $# )); do
    case "$1" in
        --model|--scope|--project|--skills-path)
            (( $# >= 2 )) && [[ -n "$2" ]] || fail "Missing value for $1"
            case "$1" in
                --model) factory_model=$2 ;;
                --scope) factory_scope=$2; factory_scope_explicit=yes ;;
                --project) factory_project=$2 ;;
                --skills-path) factory_skills_path=$2 ;;
            esac
            shift 2
            ;;
        -h|--help) usage; exit 0 ;;
        *) fail "Unknown argument: $1" ;;
    esac
done
[[ "$factory_model" == openai || "$factory_model" == claude ]] || fail '--model must be openai or claude.'
if [[ -z "$factory_scope" ]]; then
    if [[ -n "$factory_project" ]]; then factory_scope=project; else factory_scope=user; fi
fi
[[ "$factory_scope" == user || "$factory_scope" == project ]] || fail '--scope must be user or project.'
if [[ "$factory_scope" == user && -n "$factory_project" ]]; then
    fail 'Use --project only with project scope.'
fi
if [[ "$factory_scope" == user ]]; then
    [[ -n "${HOME:-}" ]] || fail 'Cannot determine the user home directory.'
    factory_install_root=$HOME
else
    factory_install_root=${factory_project:-$PWD}
fi
[[ -d "$factory_install_root" ]] || fail "The target directory does not exist: $factory_install_root"
factory_install_root=$(cd -- "$factory_install_root" && pwd -P)
factory_repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
if [[ "$factory_model" == openai ]]; then factory_vendor=.agents; else factory_vendor=.claude; fi
factory_destination="$factory_install_root/$factory_vendor/skills"
if [[ -n "$factory_skills_path" ]]; then
    [[ -z "$factory_scope_explicit" && -z "$factory_project" ]] || fail 'Use --skills-path without --scope or --project.'
    [[ -d "$factory_skills_path" && ! -L "$factory_skills_path" ]] || fail 'Use --skills-path with an existing physical skills directory, not a link.'
    factory_install_root=$(cd -- "$factory_skills_path" && pwd -P)
    factory_destination=$factory_install_root
fi
factory_members=()
while IFS= read -r line || [[ -n "$line" ]]; do
    line=${line%$'\r'}
    if [[ "$line" =~ ^[[:space:]]*-[[:space:]]+([a-z0-9][a-z0-9-]*)[[:space:]]*$ ]]; then
        factory_members+=("${BASH_REMATCH[1]}")
    fi
done < "$factory_repo/collections/factory/collection.yaml"
(( ${#factory_members[@]} )) || fail 'The factory collection has no members.'

check_target() {
    local target=$1 candidate=$1 parent
    while [[ "$candidate" != "$factory_install_root" ]]; do
        [[ ! -L "$candidate" ]] || fail "Refusing a linked installation path: $candidate"
        if [[ "$candidate" != "$target" && -e "$candidate" && ! -d "$candidate" ]]; then
            fail "Installation directory is a file: $candidate"
        fi
        parent=${candidate%/*}
        [[ -n "$parent" && "$parent" != "$candidate" ]] || fail "Installation path escapes its target directory: $target"
        candidate=$parent
    done
}

factory_sources=()
factory_targets=()
for name in "${factory_members[@]}"; do
    source_dir="$factory_repo/skills/$factory_model/$name"
    [[ -f "$source_dir/SKILL.md" ]] || fail "Collection member is missing: $name"
    while IFS= read -r -d '' source_file; do
        [[ ! -L "$source_file" ]] || fail "Refusing a linked package path: $source_file"
        [[ -f "$source_file" ]] || continue
        relative=${source_file#"$source_dir/"}
        target="$factory_destination/$name/$relative"
        check_target "$target"
        if [[ -e "$target" ]]; then
            [[ -f "$target" ]] && cmp -s "$source_file" "$target" || fail "Existing file differs: $target"
        else
            factory_sources+=("$source_file")
            factory_targets+=("$target")
        fi
    done < <(find "$source_dir" -type d -name __pycache__ -prune -o \( -type f -o -type l \) ! -name '*.pyc' -print0)
done

# Check every destination before copying the first file.
for (( index=0; index<${#factory_sources[@]}; index++ )); do
    source_file=${factory_sources[index]}
    target=${factory_targets[index]}
    check_target "$target"
    mkdir -p -- "${target%/*}"
    cp -pn "$source_file" "$target"
    cmp -s "$source_file" "$target" || fail "Existing file differs: $target"
done
printf 'Installed %s files in %s\n' "${#factory_sources[@]}" "$factory_destination"
if [[ "$factory_scope" == user ]]; then
    printf '%s\n' \
        'Open an agent in a project root and invoke $factory in Codex or /factory in Claude or Grok.' \
        'The skill handles first-use setup. Settings and jobs stay in that project.'
fi
