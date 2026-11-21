#!/usr/bin/env bash
# Deterministic operations for the host agent's factory workflow.
set -euo pipefail
(( BASH_VERSINFO[0] >= 4 )) || { printf 'Bash 4 or newer is required.\n' >&2; exit 1; }
fail() { printf 'factory: %s\n' "$*" >&2; exit 1; }
package=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
action='' project=$PWD job='' runner=codex model='' reasoning='' executable='' base='' next='' role='' file='' prompt='' reviewers='' label=factory
limit=3 concurrency=3 seconds=1800
declare -A state=()
while (( $# )); do
    case "$1" in
        --project|--job|--runner|--model|--reasoning|--executable|--base|--next|--role|--file|--prompt|--reviewers|--label|--limit|--concurrency|--timeout)
            (( $# >= 2 )) || fail "Missing value for $1"
            case "$1" in
                --project) project=$2;; --job) job=$2;; --runner) runner=$2;; --model) model=$2;;
                --reasoning) reasoning=$2;; --executable) executable=$2;; --base) base=$2;; --next) next=$2;;
                --role) role=$2;; --file) file=$2;; --prompt) prompt=$2;; --reviewers) reviewers=$2;;
                --label) label=$2;; --limit) limit=$2;; --concurrency) concurrency=$2;; --timeout) seconds=$2;;
            esac
            shift 2;;
        -h|--help) printf '%s\n' 'factory.sh --project ROOT ACTION [options]' 'Actions: add init create status queue prepare dispatch accept gate advance feedback deliver dashboard skills'; exit 0;;
        *) [[ -z "$action" ]] || fail "Unexpected argument: $1"; action=$1; shift;;
    esac
done
[[ -n "$action" ]] || fail 'Choose an action. Use --help for the command list.'
[[ "$runner" == codex || "$runner" == claude || "$runner" == grok ]] || fail 'Unknown runner.'
[[ -z "$role" || "$role" =~ ^(intake|spec-writer|builder|review-code|review-security|review-ux|review-ui|approver)$ ]] || fail 'Unknown role.'
for number in "$limit" "$concurrency" "$seconds"; do [[ "$number" =~ ^[1-9][0-9]*$ ]] || fail 'Limits and timeout must be positive integers.'; done
command -v git >/dev/null || fail 'Install Git and run from a Git project.'
project=$(git -C "$project" rev-parse --show-toplevel) || fail 'Run from a Git project.'
project=$(cd -- "$project" && pwd -P)
factory="$project/factory"; jobs="$factory/jobs"
locks=()
cleanup() { for lock in "${locks[@]}"; do rm -f -- "$lock/owner"; rmdir -- "$lock" 2>/dev/null || true; done; }
trap cleanup EXIT
wait_timed() {
    local process_id=$1 started=$SECONDS expired=false
    timed_code=0
    while kill -0 "$process_id" 2>/dev/null; do
        if (( SECONDS - started >= seconds )); then
            expired=true
            kill -TERM -- "-$process_id" 2>/dev/null || kill -TERM "$process_id" 2>/dev/null || true
            sleep 0.1
            kill -KILL -- "-$process_id" 2>/dev/null || kill -KILL "$process_id" 2>/dev/null || true
            break
        fi
        sleep 0.1
    done
    wait "$process_id" || timed_code=$?
    if $expired; then timed_code=124; fi
}
lock_dir() {
    local target=$1 attempt=0
    mkdir -p -- "${target%/*}"
    until mkdir -- "$target" 2>/dev/null; do
        (( attempt += 1 )); (( attempt < 40 )) || fail "Another operation owns $target. Inspect its owner before recovery."
        sleep 0.05
    done
    locks+=("$target")
    printf 'shell=bash\npid=%s\n' "$$" > "$target/owner"
}
json_quote() {
    local value=$1 code character escaped
    value=${value//\\/\\\\}; value=${value//\"/\\\"}
    for (( code=1; code<32; code++ )); do
        printf -v escaped '\\u%04x' "$code"
        printf -v character '%b' "$escaped"
        value=${value//"$character"/"$escaped"}
    done
    value=${value//</\\u003c}
    printf '"%s"' "$value"
}
json_file() {
    local value quoted ended=false
    printf '"'
    while ! $ended; do
        value=''
        IFS= read -r -d '' value || ended=true
        quoted=$(json_quote "$value")
        printf '%s' "${quoted:1:${#quoted}-2}"
        $ended || printf '\\u0000'
    done < "$1"
    printf '"'
}
atomic_copy() { local target=$2 temporary; temporary=$(mktemp "${target}.XXXXXX"); cat -- "$1" > "$temporary"; mv -f -- "$temporary" "$target"; }
load_job() {
    [[ "$job" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]] || fail 'Invalid job identifier.'
    folder="$jobs/$job"
    [[ ! -L "$jobs" && ! -L "$folder" && -f "$folder/job.state" ]] || fail 'Job not found or linked outside its project.'
    state=()
    while IFS=$'\t' read -r key value; do
        [[ "$key" =~ ^[a-z_]+$ ]] || fail 'Invalid state record.'
        state["$key"]=$value
    done < "$folder/job.state"
    [[ "${state[id]}" == "$job" && "${state[worktree]}" == ".worktrees/$job" ]] || fail 'Job belongs to a different project.'
    worktree="$project/${state[worktree]}"
    round="$folder/round-${state[round]}"
}
summary_json() {
    local key separator=''
    printf '{'
    for key in id stage round limit runner base branch base_commit worktree reviewers review_commit pr_url; do
        printf '%s"%s":' "$separator" "$key"; json_quote "${state[$key]:-}"; separator=,
    done
    printf ',"blocker":'; if [[ ( "${state[stage]}" == needs-human || "${state[stage]}" == needs-info ) && -f "$folder/blocker.md" ]]; then json_file "$folder/blocker.md"; else printf 'null'; fi
    printf ',"artifacts":{'; separator=''
    for report in "$folder"/*.md "$folder"/round-*/*.md; do
        [[ -f "$report" && ! -L "$report" ]] || continue
        printf '%s' "$separator"; json_quote "${report#"$folder/"}"; printf ':'; json_file "$report"; separator=,
    done
    printf '}}'
}
dashboard() {
    local data template line other saved_job=${job:-}
    data=$(mktemp "$factory/dashboard-data.XXXXXX")
    printf '[' > "$data"
    local separator=''
    for other in "$jobs"/*/job.state; do
        [[ -f "$other" ]] || continue
        job=${other%/job.state}; job=${job##*/}; load_job
        printf '%s' "$separator" >> "$data"; summary_json >> "$data"; separator=,
    done
    printf ']' >> "$data"
    template=$(mktemp "$factory/dashboard.XXXXXX")
    while IFS= read -r line || [[ -n "$line" ]]; do
        line=${line%$'\r'}
        case "$line" in
            __FACTORY_STYLE__) cat "$package/assets/dashboard.css" >> "$template";;
            __FACTORY_DATA__) cat "$data" >> "$template";;
            __FACTORY_SCRIPT__) cat "$package/assets/dashboard.js" >> "$template";;
            *) printf '%s\n' "$line" >> "$template";;
        esac
    done < "$package/assets/dashboard.html"
    mv -f -- "$template" "$factory/dashboard.html"; rm -f -- "$data"
    job=$saved_job; if [[ -n "$job" ]]; then load_job; fi
}
save_job() {
    local temporary key
    temporary=$(mktemp "$folder/job.state.XXXXXX")
    for key in "${!state[@]}"; do
        [[ "${state[$key]}" != *$'\t'* && "${state[$key]}" != *$'\n'* ]] || fail 'State values cannot contain tabs or newlines.'
        printf '%s\t%s\n' "$key" "${state[$key]}" >> "$temporary"
    done
    mv -f -- "$temporary" "$folder/job.state"
    temporary=$(mktemp "$folder/job.json.XXXXXX"); summary_json > "$temporary"; mv -f -- "$temporary" "$folder/job.json"
    dashboard
}
entered_stage() {
    local stamp from to found=''
    [[ -f "$folder/history.tsv" ]] || fail 'This stop has no recorded entry.'
    while IFS=$'\t' read -r stamp from to || [[ -n "${stamp:-}" ]]; do
        [[ -n "${stamp:-}" ]] || continue
        if [[ "$to" == needs-human && "$from" != needs-human ]]; then found=$from; fi
    done < "$folder/history.tsv"
    [[ -n "$found" ]] || fail 'This stop has no recorded entry.'
    printf '%s\n' "$found"
}
budget_blocker() {
    local text
    [[ -f "$folder/blocker.md" ]] || return 1
    text=$(<"$folder/blocker.md")
    text=${text//$'\r'/}
    text=${text%$'\n'}
    [[ "$text" == 'Build round budget exhausted. Create a successor job.' ]]
}
head_commit() { git -C "$worktree" rev-parse HEAD; }
report_path() {
    case "$role" in intake|spec-writer) printf '%s/%s.md' "$folder" "$role";; *) printf '%s/%s.md' "$round" "$role";; esac
}
proof() {
    local report=$1 verdict=$2 commit=${3:-}
    local selected=${report##*/}; selected=${selected%.md}
    [[ -f "$round/$selected.exit" && "$(<"$round/$selected.exit")" == 0 ]] || return 1
    [[ -f "$report" && "$(head -n 1 "$report")" == "VERDICT: $verdict" ]] || return 1
    [[ -z "$commit" || "$(sed -n '2p' "$report")" == "COMMIT: $commit" ]]
}
prepare() {
    if [[ -d "$worktree" ]]; then
        [[ "$(git -C "$worktree" branch --show-current)" == "${state[branch]}" ]] || fail 'The worktree is on an unexpected branch.'
        return
    fi
    lock_dir "$factory/.workspace.lock"
    git -C "$project" fetch origin "${state[base]}"
    state[base_commit]=$(git -C "$project" rev-parse "origin/${state[base]}")
    mkdir -p -- "$project/.worktrees"
    if git -C "$project" show-ref --verify --quiet "refs/heads/${state[branch]}"; then
        git -C "$project" worktree add "$worktree" "${state[branch]}"
    else
        git -C "$project" worktree add -b "${state[branch]}" "$worktree" "${state[base_commit]}"
    fi
}
commit_build() {
    local path paths=()
    while IFS= read -r -d '' path; do paths+=("$path"); done < <(git -C "$worktree" diff --name-only -z --no-renames HEAD)
    while IFS= read -r -d '' path; do paths+=("$path"); done < <(git -C "$worktree" ls-files --others --exclude-standard -z)
    if (( ${#paths[@]} )); then git -C "$worktree" --literal-pathspecs add -- "${paths[@]}"; fi
    if ! git -C "$worktree" diff --cached --quiet; then git -C "$worktree" commit -m "Factory $job round ${state[round]}"; fi
    [[ -z "$(git -C "$worktree" status --porcelain)" ]] || fail 'Build left uncommitted files.'
}

case "$action" in
add) bash "$package/scripts/add-issue.sh" "$project" "$file" "$label";;
init)
    mkdir -p -- "$factory"; lock_dir "$factory/.config.lock"
    if [[ ! -f "$factory/config.json" ]]; then
        if [[ -z "$base" ]]; then base=$(git -C "$project" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || true); base=${base#origin/}; fi
        [[ -n "$base" ]] || base=$(cd "$project" && gh repo view --json defaultBranchRef --template '{{.defaultBranchRef.name}}')
        git check-ref-format "refs/heads/$base" >/dev/null || fail 'Invalid base branch.'
        printf '{"version":2,"base_branch":' > "$factory/config.json"; json_quote "$base" >> "$factory/config.json"
        printf ',"concurrency":3,"max_rounds":3,"default":{"runner":"%s","model":null,"timeout_seconds":1800},"roles":{},"skills":{"roots":[],"include":[],"exclude":[]}}\n' "$runner" >> "$factory/config.json"
    fi
    for ignore in /factory/jobs/ '/factory/.*.lock/' /factory/dashboard.html /factory/dashboard-data.* /factory/dashboard.* /.worktrees/; do
        grep -Fxq "$ignore" "$project/.gitignore" 2>/dev/null || printf '\n%s\n' "$ignore" >> "$project/.gitignore"
    done
    printf '%s\n' "$factory/config.json";;
queue) (cd "$project" && gh api -X GET --paginate --slurp 'repos/{owner}/{repo}/issues' -f state=open -f per_page=100 -f "labels=$label");;
skills)
    for root in "$project/.agents/skills" "$project/.claude/skills" "$project/.grok/skills" "${HOME:-}/.agents/skills" "${HOME:-}/.claude/skills" "${HOME:-}/.grok/skills"; do
        for entry in "$root"/*/SKILL.md; do [[ ! -f "$entry" ]] || printf '%s\n' "$entry"; done
    done;;
create)
    [[ -f "$file" && -f "$factory/config.json" && -f "$factory/checks.sh" ]] || fail 'Initialize the project and configure checks.sh before creating jobs.'
    lock_dir "$factory/.queue.lock"
    busy=0
    for record in "$jobs"/*/job.state; do
        [[ -f "$record" ]] || continue
        current=$(awk -F '\t' '$1=="stage" {print $2}' "$record")
        case "$current" in ready|merged|rejected|needs-info|needs-human) ;; *) (( busy += 1 ));; esac
    done
    (( busy < concurrency )) || fail 'Concurrency limit reached.'
    [[ -n "$base" ]] || fail 'Pass the base branch from project config.'
    job="$(date -u +%Y%m%d%H%M%S)-$RANDOM$RANDOM"; folder="$jobs/$job"; mkdir -p -- "$folder"
    state=([id]="$job" [stage]=intake [round]=0 [limit]="$limit" [runner]="$runner" [base]="$base" [branch]="factory/$job" [base_commit]='' [worktree]=".worktrees/$job" [reviewers]=review-code [review_commit]='' [pr_url]='')
    cp -- "$file" "$folder/request.md"; cp -- "$factory/config.json" "$folder/config.json"; cp -- "$factory/checks.sh" "$folder/checks.sh"
    [[ ! -f "$factory/checks.ps1" ]] || cp -- "$factory/checks.ps1" "$folder/checks.ps1"
    save_job; printf '%s\n' "$job";;
status)
    if [[ -n "$job" ]]; then load_job; cat "$folder/job.json"; else for record in "$jobs"/*/job.json; do [[ ! -f "$record" ]] || { cat "$record"; printf '\n'; }; done; fi;;
dashboard) mkdir -p -- "$factory"; dashboard; printf '%s\n' "$factory/dashboard.html";;
*)
    load_job
    if [[ "$action" == dispatch ]]; then lock_dir "$folder/.dispatch-$role.lock"; else lock_dir "$folder/.state.lock"; fi
    case "$action" in
    prepare) prepare; save_job;;
    dispatch)
        if [[ "${state[stage]}" == needs-human ]]; then
            budget_blocker && fail 'Build round budget exhausted. Create a successor job.'
            entered=$(entered_stage)
            case "$entered:$role" in
                spec:spec-writer|build:builder|approve:approver) ;;
                review:review-*) [[ " ${state[reviewers]} " == *" $role "* ]] || fail 'Reviewer is not required.';;
                *) fail 'Role does not match the stopped stage.';;
            esac
            [[ -f "$prompt" ]] || fail 'A prepared prompt file is required.'
            case " ${state[retry]:-} " in *" $role "*) fail 'This role was already dispatched for this stop.';; esac
            if [[ -z "${state[retry]:-}" ]]; then state[retry]=$role; else state[retry]+=" $role"; fi
            save_job
        else
            case "${state[stage]}:$role" in intake:intake|spec:spec-writer|build:builder|approve:approver) ;; review:review-*) [[ " ${state[reviewers]} " == *" $role "* ]] || fail 'Reviewer is not required.';; *) fail 'Role does not match the current stage.';; esac
            [[ -f "$prompt" ]] || fail 'A prepared prompt file is required.'
        fi
        [[ -n "$executable" ]] || executable=$runner
        command -v "$executable" >/dev/null || fail "Runner is unavailable: $executable"
        output="$folder/attempts/$(date -u +%Y%m%d%H%M%S)-$role-$RANDOM"; mkdir -p -- "$output"
        cp -- "$prompt" "$output/prompt.md"; cwd=$project; [[ ! -d "$worktree" ]] || cwd=$worktree
        args=(); writable=false; [[ "$role" != builder ]] || writable=true
        case "$runner" in
            codex) args=(-a never exec --json --sandbox read-only --cd "$cwd"); $writable && args=(-a never exec --json --sandbox workspace-write --cd "$cwd"); [[ -z "$reasoning" ]] || args+=(-c "model_reasoning_effort=\"$reasoning\"");;
            claude) args=(-p --output-format json --permission-mode dontAsk --tools Read,Grep,Glob); $writable && args=(-p --output-format json --permission-mode auto --tools Read,Grep,Glob,Edit,Write,Bash); [[ -z "$reasoning" ]] || args+=(--effort "$reasoning");;
            grok) args=(--prompt-file "$output/prompt.md" --output-format json --cwd "$cwd" --permission-mode dontAsk --no-subagents); $writable && args=(--prompt-file "$output/prompt.md" --output-format json --cwd "$cwd" --permission-mode auto --no-subagents); $writable || args+=(--tools read_file,grep,list_dir --deny MCPTool); [[ -z "$reasoning" ]] || args+=(--reasoning-effort "$reasoning");;
        esac
        [[ -z "$model" ]] || args+=(--model "$model"); [[ "$runner" != codex ]] || args+=(-)
        before=$(git -C "$cwd" rev-parse HEAD; git -C "$cwd" status --porcelain; git -C "$cwd" diff; git -C "$cwd" diff --cached)
        mkdir -p -- "$round"; printf '%s\t%s\t%s\n' "$role" "$runner" "$model" > "$round/$role.model"
        printf 'PENDING\n' > "$round/$role.exit"
        cp -- "$round/$role.model" "$output/model.tsv"
        git -C "$cwd" rev-parse HEAD > "$round/$role.commit"
        set -m
        (cd "$cwd" && exec "$executable" "${args[@]}") < "$prompt" > "$output/stdout.log" 2> "$output/stderr.log" & child=$!
        set +m
        printf '%s\n' "$child" > "$folder/.dispatch-$role.lock/child"
        wait_timed "$child"; code=$timed_code
        after=$(git -C "$cwd" rev-parse HEAD; git -C "$cwd" status --porcelain; git -C "$cwd" diff; git -C "$cwd" diff --cached)
        if ! $writable && [[ "$before" != "$after" ]]; then code=1; printf '\nRead-only role changed the checkout.\n' >> "$output/stderr.log"; fi
        rm -f -- "$folder/.dispatch-$role.lock/child"
        printf '%s\n' "$code" > "$round/$role.exit"; printf '%s\n' "$code" > "$output/exit.code"; printf '%s\n' "$output"
        (( code == 0 )) || fail "Runner failed or timed out, exit $code. Inspect $output";;
    accept)
        [[ -f "$file" && -f "$round/$role.exit" && "$(<"$round/$role.exit")" == 0 ]] || fail 'A successful dispatch and a report file are required.'
        expected=$(git -C "$project" rev-parse HEAD); [[ ! -d "$worktree" ]] || expected=$(head_commit)
        [[ -f "$round/$role.commit" && "$(<"$round/$role.commit")" == "$expected" ]] || fail 'The dispatched commit changed before acceptance.'
        verdict=$(head -n 1 "$file")
        case "$role:$verdict" in intake:'VERDICT: ACCEPT'|intake:'VERDICT: NEEDS_INFO'|intake:'VERDICT: REJECT'|spec-writer:'VERDICT: READY'|spec-writer:'VERDICT: BLOCKED'|builder:'VERDICT: READY'|builder:'VERDICT: BLOCKED'|review-*:'VERDICT: PASS'|review-*:'VERDICT: CHANGES'|review-*:'VERDICT: BLOCKED'|approver:'VERDICT: APPROVE'|approver:'VERDICT: ESCALATE') ;; *) fail 'Invalid role verdict.';; esac
        target=$(report_path); mkdir -p -- "${target%/*}"; temporary=$(mktemp "$target.XXXXXX")
        commit=$(git -C "${cwd:-$project}" rev-parse HEAD); [[ ! -d "$worktree" ]] || commit=$(head_commit)
        printf '%s\nCOMMIT: %s\n' "$verdict" "$commit" > "$temporary"; tail -n +2 "$file" >> "$temporary"
        if [[ -f "$target" ]]; then cp -- "$target" "$target.before-$(date -u +%Y%m%d%H%M%S)-$RANDOM"; fi
        mv -f -- "$temporary" "$target"; save_job;;
    gate)
        [[ "${state[stage]}" == gate && -z "$(git -C "$worktree" status --porcelain)" ]] || fail 'Checks require the clean gate-stage worktree.'
        commit=$(head_commit); code=0
        set -m
        (cd "$worktree" && exec bash "$folder/checks.sh") > "$round/checks.log" 2>&1 & child=$!
        set +m
        printf '%s\n' "$child" > "$folder/.state.lock/child"
        wait_timed "$child"; code=$timed_code
        rm -f -- "$folder/.state.lock/child"
        [[ -z "$(git -C "$worktree" status --porcelain)" ]] || code=1
        [[ "$(head_commit)" == "$commit" ]] || code=1
        while IFS= read -r path; do
            case "$path" in factory/config.json|factory/checks.*|.agents/skills/factory*/*|.claude/skills/factory*/*|.grok/skills/factory*/*) code=1;; esac
        done < <(git -C "$worktree" diff --name-only "${state[base_commit]}" HEAD)
        verdict=FAIL; (( code != 0 )) || verdict=PASS
        printf 'GATE: %s\nCOMMIT: %s\n\nCheck exit: %s. See checks.log.\n' "$verdict" "$commit" "$code" > "$round/checks.md"
        if [[ "$verdict" == PASS ]]; then
            state[review_commit]=$commit
            areas=$(cat "$folder/intake.md"; git -C "$worktree" diff --name-only "${state[base_commit]}" HEAD)
            state[reviewers]=review-code
            if [[ "$areas" =~ security|auth|payment|webhook|permission|secret|token|session ]]; then state[reviewers]+=' review-security'; fi
            if [[ "$areas" =~ AREAS:.*ui|\.(tsx|jsx|vue|svelte|html|css|scss) ]]; then state[reviewers]+=' review-ux review-ui'; fi
        fi
        save_job; printf 'GATE: %s\n' "$verdict";;
    advance)
        from=${state[stage]}
        logical=$from
        if [[ "$from" == needs-human && "$next" != needs-human ]]; then
            logical=$(entered_stage)
            state[retry]=''
        fi
        if [[ "$next" == needs-human ]]; then [[ ! -f "$file" ]] || cp -- "$file" "$folder/blocker.md"
        else
            case "$logical:$next" in
                intake:spec) proof "$folder/intake.md" ACCEPT || fail 'Intake has not accepted this job.'; prepare;;
                intake:needs-info) proof "$folder/intake.md" NEEDS_INFO || fail 'Intake has not requested information.';;
                intake:rejected) proof "$folder/intake.md" REJECT || fail 'Intake has not rejected this job.';;
                spec:build) proof "$folder/spec-writer.md" READY || fail 'Specification is not ready.'; state[round]=1;;
                build:gate) proof "$round/builder.md" READY || fail 'Builder is not ready.'; commit_build; sed -i "s/^COMMIT:.*/COMMIT: $(head_commit)/" "$round/builder.md";;
                gate:review) grep -Fxq 'GATE: PASS' "$round/checks.md" && grep -Fxq "COMMIT: $(head_commit)" "$round/checks.md" || fail 'Current checks have not passed.';;
                review:approve) [[ "$(head_commit)" == "${state[review_commit]}" ]] || fail 'Reviewed commit changed.'; for required in ${state[reviewers]}; do proof "$round/$required.md" PASS "$(head_commit)" || fail "Missing current PASS from $required"; done;;
                approve:deliver) [[ "$(head_commit)" == "${state[review_commit]}" ]] || fail 'Reviewed commit changed.'; proof "$round/approver.md" APPROVE "$(head_commit)" || fail 'Current approval is missing.';;
                gate:build|review:build) if (( state[round] >= state[limit] )); then next=needs-human; printf 'Build round budget exhausted. Create a successor job.\n' > "$folder/blocker.md"; else state[round]=$(( state[round]+1 )); fi;;
                *) fail "Illegal transition: $from -> $next";;
            esac
        fi
        printf '%s\t%s\t%s\n' "$(date -u +%FT%TZ)" "$from" "$next" >> "$folder/history.tsv"
        state[stage]=$next; save_job;;
    feedback)
        [[ -f "$file" ]] || fail 'Feedback file is required.'
        case "${state[stage]}" in needs-info) next=intake;; needs-human|ready) [[ -n "$next" ]] || next=build;; *) fail 'The job is not waiting for feedback.';; esac
        [[ "$next" =~ ^(intake|spec|build|gate|review|approve|deliver)$ ]] || fail 'Invalid recovery stage.'
        if [[ "$next" == build ]]; then (( state[round] < state[limit] )) || fail 'Build budget is exhausted.'; state[round]=$(( state[round]+1 )); fi
        cp -- "$file" "$folder/feedback-$(date -u +%Y%m%d%H%M%S)-$RANDOM.md"
        if [[ -f "$folder/blocker.md" ]]; then mv -- "$folder/blocker.md" "$folder/blocker-resolved-$(date -u +%Y%m%d%H%M%S)-$RANDOM.md"; fi
        state[retry]=''
        state[stage]=$next; save_job;;
    deliver)
        [[ "${state[stage]}" == deliver && -z "$(git -C "$worktree" status --porcelain)" && "$(head_commit)" == "${state[review_commit]}" ]] || fail 'Delivery requires the clean reviewed commit.'
        for required in ${state[reviewers]}; do proof "$round/$required.md" PASS "$(head_commit)" || fail 'A required review is missing.'; done
        proof "$round/approver.md" APPROVE "$(head_commit)" || fail 'Approval is missing.'
        git -C "$worktree" push -u origin "${state[branch]}"
        pr=$(cd "$project" && gh pr list --state all --head "${state[branch]}" --json number,url,state,isDraft,headRefOid --template '{{range .}}{{.number}}{{"\t"}}{{.url}}{{"\t"}}{{.state}}{{"\t"}}{{.isDraft}}{{"\t"}}{{.headRefOid}}{{"\n"}}{{end}}')
        if [[ -z "$pr" ]]; then
            [[ -f "$folder/pr-body.md" ]] || cp -- "$folder/spec-writer.md" "$folder/pr-body.md"
            (cd "$project" && gh pr create --draft --base "${state[base]}" --head "${state[branch]}" --title "$(head -n 1 "$folder/request.md")" --body-file "$folder/pr-body.md")
            pr=$(cd "$project" && gh pr list --state open --head "${state[branch]}" --json number,url,state,isDraft,headRefOid --template '{{range .}}{{.number}}{{"\t"}}{{.url}}{{"\t"}}{{.state}}{{"\t"}}{{.isDraft}}{{"\t"}}{{.headRefOid}}{{"\n"}}{{end}}')
        fi
        [[ "$pr" != *$'\n'* ]] || fail 'Several PRs match this branch.'
        IFS=$'\t' read -r number url status draft commit <<< "$pr"
        [[ "$status" == OPEN && "$commit" == "${state[review_commit]}" ]] || fail 'PR state or head differs from the reviewed branch.'
        [[ "$draft" != true ]] || (cd "$project" && gh pr ready "$number")
        state[pr_url]=$url; state[stage]=ready; save_job;;
    *) fail 'Unknown action.';;
    esac;;
esac
