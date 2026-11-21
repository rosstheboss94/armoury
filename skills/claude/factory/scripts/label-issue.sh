#!/usr/bin/env bash
# Update one saved issue so it carries exactly one factory status label.
set -euo pipefail
export LC_ALL=C
project=$1 issue=$2 status=$3 temporary=''
cleanup() {
    if [[ -n "$temporary" ]]; then rm -rf -- "$temporary"; fi
}
trap cleanup EXIT
fail() { printf 'factory label: %s\n' "$*" >&2; exit 1; }
[[ -z "$issue" ]] && exit 0
[[ "$issue" =~ ^[1-9][0-9]*$ ]] || fail 'Pass the issue number saved on this job.'
[[ "$status" == running || "$status" == need-human || "$status" == stopped ]] || fail 'Status must be running, need-human, or stopped.'
command -v gh >/dev/null || fail 'Install GitHub CLI and authenticate with gh auth login.'
temporary=$(mktemp -d "${TMPDIR:-/tmp}/factory-label.XXXXXXXX") || fail 'Cannot create a private temporary directory.'
cd -- "$project"
GH_DEBUG= gh repo view --json nameWithOwner,url --template '{{.nameWithOwner}}{{"\n"}}{{.url}}{{"\n"}}' > "$temporary/context" 2> "$temporary/stderr" || fail "Cannot resolve the repository. Check gh auth login, gh repo view, and project remotes. $(<"$temporary/stderr")"
mapfile -t context < "$temporary/context"
[[ ${#context[@]} == 2 ]] || fail 'GitHub returned an invalid repository context.'
repository=${context[0]%$'\r'} url=${context[1]%$'\r'}
[[ "$repository" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ && "$url" == https://*/"$repository" ]] || fail 'GitHub returned an invalid repository URL.'
hostname=${url#https://}; hostname=${hostname%/"$repository"}
[[ "$hostname" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*(:[0-9]+)?$ ]] || fail 'GitHub returned an invalid repository host.'
endpoint="repos/$repository"
encode() {
    local value=$1 index byte piece encoded=''
    for (( index=0; index<${#value}; index++ )); do printf -v byte '%d' "'${value:index:1}"; printf -v piece '%%%02X' "$byte"; encoded+=$piece; done
    printf '%s' "$encoded"
}
gh_api() {
    GH_DEBUG= gh api --hostname "$hostname" "$@" > "$temporary/stdout" 2> "$temporary/stderr"
}
read_issue() {
    gh_api -X GET "$endpoint/issues/$issue/labels" --template '{{range .}}{{printf "%s\n" .name}}{{end}}' || fail "GitHub label lookup failed. No issue was created. $(<"$temporary/stderr")"
    mapfile -t current < "$temporary/stdout"
    for index in "${!current[@]}"; do current[index]=${current[index]%$'\r'}; done
}
read_issue
encoded=$(encode "$status")
if ! gh_api -X GET "$endpoint/labels/$encoded" --template '{{.name}}'; then
    detail=$(<"$temporary/stderr")
    [[ "$detail" == *404* || "$detail" == *'Not Found'* ]] || fail "GitHub label lookup failed. Existing issue labels were left unchanged. $detail"
    printf '{"name":"%s","color":"ededed"}' "$status" > "$temporary/create.json"
    gh_api -X POST "$endpoint/labels" --input "$temporary/create.json" || fail "GitHub could not create the status label. Existing issue labels were left unchanged. $(<"$temporary/stderr")"
fi
printf '{"labels":["%s"]}' "$status" > "$temporary/add.json"
if ! gh_api -X POST "$endpoint/issues/$issue/labels" --input "$temporary/add.json"; then
    fail "GitHub rejected the status label. Existing issue labels were left unchanged. $(<"$temporary/stderr")"
fi
for other in running need-human stopped; do
    [[ "$other" == "$status" ]] && continue
    present=false
    for name in "${current[@]}"; do [[ "$name" == "$other" ]] && present=true; done
    if $present; then
        gh_api -X DELETE "$endpoint/issues/$issue/labels/$(encode "$other")" || fail "GitHub could not remove the previous status label. $(<"$temporary/stderr")"
    fi
done
read_issue
if (( ${#current[@]} )); then printf '%s\n' "${current[@]}"; fi
