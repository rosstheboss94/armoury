#!/usr/bin/env bash
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
powershell=$(command -v pwsh || command -v powershell.exe || command -v powershell || true)
[[ -n "$powershell" ]] || { printf 'Installer checks require PowerShell and Bash 4 or newer.\n' >&2; exit 1; }
temporary=$(mktemp -d)
# This directory is created by this test and never comes from user input.
trap 'rm -rf -- "$temporary"' EXIT
fail() { printf 'Installer check failed: %s\n' "$*" >&2; exit 1; }
install() {
    local engine=$1 home=$2 model=$3; shift 3
    if [[ "$engine" == bash ]]; then HOME="$home" bash "$repo/scripts/install-factory.sh" --model "$model" "$@"
    else USERPROFILE=$(cygpath -w "$home" 2>/dev/null || printf '%s' "$home") HOME="$home" "$powershell" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$repo/scripts/install-factory.ps1" -Model "$model" "$@"; fi
}
for engine in bash powershell; do
    for model in openai claude; do
        home="$temporary/$engine $model home [copy]"; mkdir -p "$home"
        vendor=.agents; [[ "$model" != claude ]] || vendor=.claude
        install "$engine" "$home" "$model" > "$temporary/result"
        for source in "$repo/skills/$model"/factory*/SKILL.md; do
            name=${source%/SKILL.md}; name=${name##*/}
            cmp -s "$source" "$home/$vendor/skills/$name/SKILL.md" || fail "Incomplete $engine $model install"
        done
        [[ -f "$home/$vendor/skills/factory/scripts/factory.sh" && -f "$home/$vendor/skills/factory/scripts/factory.ps1" ]] || fail 'Native runtime is missing.'
        [[ -z "$(find "$home/$vendor/skills" -name '*.py' -print -quit)" ]] || fail 'Retired runtime was installed.'
        install "$engine" "$home" "$model" > "$temporary/result"
        grep -q 'Installed 0 files' "$temporary/result" || fail 'Repeat install changed files.'
        printf 'User customization\n' > "$home/$vendor/skills/factory/SKILL.md"
        if install "$engine" "$home" "$model" > "$temporary/result" 2>&1; then fail 'A differing skill was overwritten.'; fi
        grep -q 'User customization' "$home/$vendor/skills/factory/SKILL.md" || fail 'Customization was lost.'
        project="$temporary/$engine $model project"; mkdir -p "$project"
        if [[ "$engine" == bash ]]; then install "$engine" "$home" "$model" --project "$project" > "$temporary/result"
        else install "$engine" "$home" "$model" -ProjectPath "$project" > "$temporary/result"; fi
        [[ -f "$project/$vendor/skills/factory/SKILL.md" ]] || fail 'Project install is missing.'
        printf 'Verified %s %s user, repeat, conflict, and project installs.\n' "$engine" "$model"
    done
    home="$temporary/$engine late conflict"; mkdir -p "$home/.agents/skills"
    printf 'blocked\n' > "$home/.agents/skills/factory-approver"
    if install "$engine" "$home" openai > "$temporary/result" 2>&1; then fail 'Directory conflict was ignored.'; fi
    [[ ! -d "$home/.agents/skills/factory" ]] || fail 'Copying started before all conflicts were checked.'
    shared="$temporary/$engine shared skills"; mkdir -p "$shared"
    shared_option=--skills-path
    [[ "$engine" != powershell ]] || shared_option=-SkillsPath
    install "$engine" "$home" openai "$shared_option" "$shared" > "$temporary/result"
    cmp -s "$repo/skills/openai/factory/SKILL.md" "$shared/factory/SKILL.md" || fail 'Explicit skills directory was ignored.'
    install "$engine" "$home" openai "$shared_option" "$shared" > "$temporary/result"
    grep -q 'Installed 0 files' "$temporary/result" || fail 'Repeat explicit install changed files.'
    printf 'Shared customization\n' > "$shared/factory/SKILL.md"
    if install "$engine" "$home" openai "$shared_option" "$shared" > "$temporary/result" 2>&1; then fail 'Explicit install overwrote a customization.'; fi
    grep -q 'Shared customization' "$shared/factory/SKILL.md" || fail 'Shared customization was lost.'
    printf 'Verified %s explicit skills directory and conflict preservation.\n' "$engine"
done
printf 'Native installer checks passed.\n'
