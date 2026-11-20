#!/usr/bin/env bash
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
powershell=$(command -v powershell.exe || command -v pwsh || command -v powershell || true)
[[ -n "$powershell" ]] || { printf 'Native regressions require PowerShell and Bash.\n' >&2; exit 1; }
bash_path=$(command -v bash)
if command -v cygpath >/dev/null; then bash_path=$(cygpath -w "$bash_path"); fi
for model in openai claude; do
    "$powershell" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$repo/tests/native-regressions.ps1" -Bash "$bash_path" -Model "$model"
done
