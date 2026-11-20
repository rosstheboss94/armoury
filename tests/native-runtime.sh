#!/usr/bin/env bash
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
powershell=$(command -v pwsh || command -v powershell.exe || command -v powershell || true)
[[ -n "$powershell" ]] || { printf 'Runtime checks require PowerShell and Bash.\n' >&2; exit 1; }
temporary=$(mktemp -d)
cleanup() {
    code=$?
    if (( code != 0 )); then
        while IFS= read -r -d '' log; do printf '\n%s\n' "$log" >&2; tail -n 12 "$log" >&2; done < <(find "$temporary" -type f \( -name stderr.log -o -name command.txt \) -print0)
    fi
    rm -rf -- "$temporary"
}
trap cleanup EXIT
fail() { printf 'Native runtime check failed: %s\n' "$*" >&2; exit 1; }
native() {
    if [[ "$engine" == bash ]]; then bash "$entry" --project "$project" "$@"
    else
        local action=$1; shift; local arguments=()
        while (( $# )); do
            case "$1" in
                --base) arguments+=(-Base "$2");; --runner) arguments+=(-Runner "$2");; --file) arguments+=(-File "$2");;
                --job) arguments+=(-Job "$2");; --role) arguments+=(-Role "$2");; --prompt) arguments+=(-Prompt "$2");;
                --next) arguments+=(-Next "$2");; --executable) arguments+=(-Executable "$2");; --model) arguments+=(-Model "$2");;
                --timeout) arguments+=(-TimeoutSeconds "$2");; --limit) arguments+=(-Limit "$2");;
                *) fail "Unmapped test option $1";;
            esac; shift 2
        done
        "$powershell" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$entry" "$action" -ProjectPath "$project" "${arguments[@]}"
    fi
}
report() {
    local selected=$1 verdict=$2
    printf 'ROLE: %s\n' "$selected" > "$temporary/prompt"
    native dispatch --job "$job" --role "$selected" --runner codex --model 'fixture-model' --executable "$agent" --prompt "$temporary/prompt" > "$temporary/dispatch"
    printf 'VERDICT: %s\nAREAS: code\n\nOffline fixture evidence.\n' "$verdict" > "$temporary/report"
    native accept --job "$job" --role "$selected" --file "$temporary/report"
}
original_path=$PATH
engines=(bash powershell)
[[ "${1:-}" != --powershell ]] || engines=(powershell)
[[ "${1:-}" != --bash ]] || engines=(bash)
for engine in "${engines[@]}"; do
    project="$temporary/$engine project"; remote="$temporary/$engine remote.git"; mock="$temporary/$engine bin"
    mkdir -p "$project" "$mock"
    cp "$repo/tests/fixtures/agent.sh" "$mock/agent.sh"; cp "$repo/tests/fixtures/agent.ps1" "$mock/agent.ps1"
    if [[ "$engine" == bash ]]; then cp "$repo/tests/fixtures/gh" "$mock/gh"; chmod +x "$mock/gh"
    else cp "$repo/tests/fixtures/gh.ps1" "$mock/gh.ps1"; fi
    chmod +x "$mock/agent.sh"
    export FACTORY_FAKE_GH="$mock"
    export PATH="$mock:$original_path"
    if [[ "$engine" == bash ]]; then [[ "$(command -v gh)" == "$mock/gh" ]] || fail 'The GitHub CLI mock is not active.'; fi
    if [[ "$engine" == powershell ]]; then
        resolved=$("$powershell" -NoProfile -NonInteractive -Command '(Get-Command gh -CommandType Application,ExternalScript | Select-Object -First 1).Source' | tr -d '\r')
        [[ "$resolved" == *gh.ps1 ]] || fail "The PowerShell GitHub CLI mock is not active: $resolved"
    fi
    git init --bare "$remote" >/dev/null 2>&1; git init -b main "$project" >/dev/null
    git -C "$project" config user.name 'Factory fixture'; git -C "$project" config user.email 'factory@example.invalid'
    git -C "$project" config commit.gpgsign false; git -C "$project" config core.autocrlf false
    printf 'before\n' > "$project/app.txt"; git -C "$project" add app.txt; git -C "$project" commit -m Initial >/dev/null
    git -C "$project" remote add origin "$remote"; git -C "$project" push -u origin main >/dev/null 2>&1
    if [[ "$engine" == bash ]]; then entry="$repo/skills/openai/factory/scripts/factory.sh"; agent="$mock/agent.sh"
    else entry="$repo/skills/openai/factory/scripts/factory.ps1"; agent="$mock/agent.ps1"; fi
    native init --runner codex --base main > "$temporary/init"
    printf '#!/usr/bin/env bash\nset -euo pipefail\n[[ -f app.txt ]]\n' > "$project/factory/checks.sh"
    printf '$ErrorActionPreference = "Stop"\nif (-not (Test-Path -LiteralPath "app.txt")) { exit 1 }\nexit 0\n' > "$project/factory/checks.ps1"
    printf 'Improve app <script>unsafe</script>\n' > "$temporary/request"
    job=$(native create --base main --file "$temporary/request" | tail -n 1 | tr -d '\r')
    [[ -f "$project/factory/jobs/$job/job.state" ]] || fail 'Job creation did not return its identifier.'
    printf 'ROLE: intake\n' > "$temporary/prompt"
    for provider in codex claude grok; do
        native dispatch --job "$job" --role intake --runner "$provider" --model 'fixture model with spaces' --executable "$agent" --prompt "$temporary/prompt" > "$temporary/dispatch"
        attempt=$(tail -n 1 "$temporary/dispatch" | tr -d '\r')
        grep -Fxq 'fixture model with spaces' "$attempt/stderr.log" || fail 'Model arguments were changed.'
        case "$provider" in codex) grep -q turn.completed "$attempt/stdout.log";; claude) grep -q is_error "$attempt/stdout.log";; grok) grep -q stopReason "$attempt/stdout.log";; esac || fail 'CLI protocol output was not preserved.'
    done
    export FACTORY_FAKE_SLEEP=4
    if native dispatch --job "$job" --role intake --runner codex --executable "$agent" --prompt "$temporary/prompt" --timeout 1 > "$temporary/error" 2>&1; then fail 'A timed out agent was accepted.'; fi
    unset FACTORY_FAKE_SLEEP
    if [[ "$(cat "$project/factory/jobs/$job/round-0/intake.exit" | tr -d '\r')" != 124 ]]; then cat "$temporary/error" >&2; fail 'Timeout status was not recorded.'; fi
    if native advance --job "$job" --next spec > "$temporary/error" 2>&1; then fail 'Intake gate was bypassed.'; fi
    report intake ACCEPT; native advance --job "$job" --next spec
    report spec-writer READY; native advance --job "$job" --next build
    export FACTORY_FAKE_EDIT=1; report builder READY; unset FACTORY_FAKE_EDIT
    native advance --job "$job" --next gate
    native gate --job "$job" > "$temporary/gate"; grep -q 'GATE: PASS' "$temporary/gate" || fail 'Checks did not pass.'
    native advance --job "$job" --next review
    if native advance --job "$job" --next approve > "$temporary/error" 2>&1; then fail 'Missing review was accepted.'; fi
    report review-code PASS; native advance --job "$job" --next approve
    report approver APPROVE; native advance --job "$job" --next deliver
    native deliver --job "$job"
    native status --job "$job" > "$temporary/status"
    grep -q 'ready' "$temporary/status" || fail 'Delivery did not finish as ready.'
    [[ -f "$mock/ready" ]] || fail 'The PR was not marked ready.'
    grep -q '\\u003cscript' "$project/factory/dashboard.html" || fail 'Dashboard report data is not escaped.'
    [[ "$(cat "$project/app.txt")" == before ]] || fail 'The main checkout was edited.'
    native dispatch --job "$job" --role builder --executable "$agent" --prompt "$temporary/prompt" > "$temporary/error" 2>&1 && fail 'Dispatch ignored the current stage.'
    native feedback --job "$job" --file "$temporary/request"
    report builder READY; native advance --job "$job" --next gate
    native gate --job "$job" > "$temporary/gate"; native advance --job "$job" --next review
    printf 'external change\n' > "$project/.worktrees/$job/app.txt"
    git -C "$project/.worktrees/$job" add app.txt; git -C "$project/.worktrees/$job" commit -m External >/dev/null
    if native advance --job "$job" --next approve > "$temporary/error" 2>&1; then fail 'A stale review was accepted.'; fi
    native advance --job "$job" --next build
    report builder READY; native advance --job "$job" --next gate
    native gate --job "$job" > "$temporary/gate"; native advance --job "$job" --next build
    native status --job "$job" > "$temporary/status"
    grep -q needs-human "$temporary/status" || fail 'Round budget was reset.'
    printf 'Verified %s dispatch, transitions, checks, review gates, delivery, escaping, and budget.\n' "$engine"
done
printf 'Native factory runtime checks passed.\n'
