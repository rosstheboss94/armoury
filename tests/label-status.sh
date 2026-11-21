#!/usr/bin/env bash
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
powershell=$(command -v powershell.exe || command -v pwsh || command -v powershell || true)
[[ -n "$powershell" ]] || { printf 'Status label fixtures require PowerShell and Bash.\n' >&2; exit 1; }
bash_path=$(command -v bash)
if [[ -n "${EXEPATH:-}" && -x "$EXEPATH/bin/bash.exe" ]]; then bash_path=$EXEPATH/bin/bash.exe; fi
if command -v cygpath >/dev/null; then bash_path=$(cygpath -w "$bash_path"); fi
"$powershell" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$repo/tests/label-status.ps1" -Bash "$bash_path"
