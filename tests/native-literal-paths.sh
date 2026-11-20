#!/usr/bin/env bash
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
# An optional source root lets the same assertions check a disposable predecessor.
helpers=${1:-$repo}
temporary=$(mktemp -d)
cleanup() {
    local code=$?
    if (( code != 0 )); then
        printf 'Literal-path regression failed, exit %s.\n' "$code" >&2
        find "$temporary" -name stderr.log -type f -exec tail -n 12 {} \; >&2
    fi
    rm -rf -- "$temporary"
}
trap cleanup EXIT
fail() { printf 'Literal-path regression failed: %s\n' "$*" >&2; exit 1; }
name=':(literal)README.md'
# MSYS translates the colon to a private-use character on Windows.
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) printf 'SKIP literal-path regression: unsupported Windows filesystem. Run on Unix.\n'; exit 0;;
esac
if ! (printf 'probe\n' > "$temporary/$name") 2>/dev/null; then
    fail 'Unix temporary filesystem rejected the literal filename.'
fi
rm -- "$temporary/$name"
printf 'Runner: %s\nTemporary filesystem: %s\n' "$(uname -sr)" "$temporary"
bash --version | head -n 1
git --version
original_path=$PATH
unset FACTORY_FAKE_SLEEP FACTORY_FAKE_EDIT
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
export GH_CONFIG_DIR="$temporary/gh-config" GH_PROMPT_DISABLED=1
unset GH_TOKEN GITHUB_TOKEN GH_ENTERPRISE_TOKEN GITHUB_ENTERPRISE_TOKEN
native() { bash "$entry" --project "$project" "$@"; }
report() {
    local role=$1 verdict=$2
    printf 'ROLE: %s\n' "$role" > "$temporary/prompt"
    native dispatch --job "$job" --role "$role" --runner codex --model fixture \
        --executable "$mock/agent.sh" --prompt "$temporary/prompt" > "$temporary/dispatch"
    printf 'VERDICT: %s\nAREAS: code\n\nOffline literal-path evidence.\n' "$verdict" > "$temporary/report"
    native accept --job "$job" --role "$role" --file "$temporary/report" >/dev/null
}
for model in openai claude; do
    project="$temporary/$model project"; mock="$temporary/$model bin"
    entry="$helpers/skills/$model/factory/scripts/factory.sh"
    [[ -f "$entry" ]] || fail "Missing $model helper."
    mkdir -p -- "$project" "$mock" "$GH_CONFIG_DIR"
    cp -- "$repo/tests/fixtures/gh" "$mock/gh"
    cp -- "$repo/tests/fixtures/agent.sh" "$mock/agent.sh"
    chmod +x "$mock/gh" "$mock/agent.sh"
    export PATH="$mock:$original_path" FACTORY_FAKE_GH="$mock"
    [[ "$(command -v gh)" == "$mock/gh" ]] || fail 'Controlled GitHub fixture is absent.'
    [[ "$(command -v "$mock/agent.sh")" == "$mock/agent.sh" ]] || fail 'Controlled agent fixture is absent.'
    git init --bare "$temporary/$model remote.git" >/dev/null 2>&1
    git init -b main "$project" >/dev/null
    git -C "$project" config user.name 'Factory fixture'
    git -C "$project" config user.email 'factory@example.invalid'
    git -C "$project" config commit.gpgsign false
    git -C "$project" config core.autocrlf false
    printf 'ordinary baseline\n' > "$project/README.md"
    git -C "$project" add -- README.md
    git -C "$project" commit -m Initial >/dev/null
    git -C "$project" remote add origin "$temporary/$model remote.git"
    git -C "$project" push -u origin main >/dev/null 2>&1
    native init --runner codex --base main >/dev/null
    printf '#!/usr/bin/env bash\nexit 0\n' > "$project/factory/checks.sh"
    printf 'Offline literal filename regression\n' > "$temporary/request"
    job=$(native create --base main --file "$temporary/request" | tail -n 1)
    report intake ACCEPT
    native advance --job "$job" --next spec >/dev/null
    report spec-writer READY
    native advance --job "$job" --next build >/dev/null
    worktree="$project/.worktrees/$job"
    before=$(git -C "$worktree" rev-parse HEAD)
    printf 'literal filename content\nsecond line\n' > "$temporary/expected"
    cp -- "$temporary/expected" "$worktree/$name"
    report builder READY
    native advance --job "$job" --next gate
    native status --job "$job" > "$temporary/status"
    grep -Eq '"stage"[[:space:]]*:[[:space:]]*"gate"' "$temporary/status" || fail "$model did not enter gate."
    after=$(git -C "$worktree" rev-parse HEAD)
    [[ "$after" != "$before" ]] || fail "$model did not create a commit."
    grep -Fxq "COMMIT: $after" "$project/factory/jobs/$job/round-1/builder.md" || fail 'Builder report commit was not updated.'
    found=false
    while IFS= read -r -d '' path; do
        if [[ "$path" == "$name" ]]; then found=true; fi
    done < <(git -C "$worktree" ls-tree -rz --name-only HEAD)
    $found || fail 'The exact literal filename is absent from the committed tree.'
    git -C "$worktree" show "HEAD:$name" > "$temporary/actual"
    cmp -s "$temporary/expected" "$temporary/actual" || fail 'Committed literal content differs.'
    printf 'ordinary baseline\n' > "$temporary/baseline"
    git -C "$worktree" show HEAD:README.md > "$temporary/actual"
    cmp -s "$temporary/baseline" "$temporary/actual" || fail 'Committed ordinary README changed.'
    cmp -s "$temporary/baseline" "$worktree/README.md" || fail 'Working ordinary README changed.'
    [[ -z "$(git -C "$worktree" status --porcelain --untracked-files=all)" ]] || fail 'Resulting worktree is dirty.'
    printf 'PASS %s public build-to-gate, new commit, report commit, exact tree name and content, unchanged README, clean worktree.\n' "$model"
done
