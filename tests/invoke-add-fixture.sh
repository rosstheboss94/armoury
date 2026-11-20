#!/usr/bin/env bash
set -euo pipefail
entry=$1 project=$2 input=$3 label=$4 bin=$5 missing=$6
# These are Git Bash's native tool directories on Windows, standard tools elsewhere.
export PATH="$bin:/usr/bin:/bin:/mingw64/bin"
if [[ "$missing" == git ]]; then
    # An explicit failing Git fixture prevents discovery outside this controlled PATH.
    [[ "$(command -v git)" == "$bin/git" ]] || exit 92
fi
if [[ "$missing" == gh ]]; then
    if command -v gh >/dev/null; then printf 'Missing-tool fixture found GitHub CLI.\n' >&2; exit 92; fi
else [[ "$(command -v gh)" == "$bin/gh" ]] || { printf 'Controlled GitHub fixture is not active.\n' >&2; exit 92; }
fi
if [[ "$7" == yes ]]; then bash "$entry" --project "$project" add --file "$input"
else bash "$entry" --project "$project" add --file "$input" --label "$label"
fi
