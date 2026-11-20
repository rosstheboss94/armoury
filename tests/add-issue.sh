#!/usr/bin/env bash
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
# Prefer the installed Windows 5.1 runner so compatibility cannot pass on 7 alone.
powershell=$(command -v powershell.exe || command -v pwsh || command -v powershell || true)
[[ -n "$powershell" ]] || { printf 'Issue fixtures require PowerShell and Bash.\n' >&2; exit 1; }
bash_path=$(command -v bash)
if command -v cygpath >/dev/null; then bash_path=$(cygpath -w "$bash_path"); fi
if [[ "$powershell" == *powershell.exe ]]; then
    "$powershell" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$repo/tests/add-issue-redirected.ps1" -Bash "$bash_path"
fi
"$powershell" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$repo/tests/add-issue.ps1" -Bash "$bash_path"
