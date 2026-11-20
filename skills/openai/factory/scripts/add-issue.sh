#!/usr/bin/env bash
# Called by factory.sh after resolving the Git root. No factory setup is needed.
set -euo pipefail
export LC_ALL=C
project=$1 file=$2 label=$3 temporary='' submitted=false recovery=''
cleanup() {
    if [[ -n "$temporary" ]]; then
        rm -f -- "$temporary/payload.json" "$temporary/stderr" "$temporary/context" "$temporary/result"
        rmdir -- "$temporary"
    fi
}
trap cleanup EXIT
fail() {
    printf 'factory add: %s\n' "$*" >&2
    if $submitted; then printf 'Creation may have occurred. Do not blindly retry. %s\n' "$recovery" >&2; fi
    exit 1
}
white() {
    (( ($1 >= 9 && $1 <= 13) || $1 == 32 || $1 == 133 || $1 == 160 || $1 == 5760 ||
       ($1 >= 8192 && $1 <= 8202) || $1 == 8232 || $1 == 8233 || $1 == 8239 || $1 == 8287 || $1 == 12288 ))
}
[[ -n "$file" && -f "$file" && -r "$file" ]] || fail 'Pass --file with a readable UTF-8 idea file, not a directory.'
# Read bytes without command substitution, which would discard trailing newlines.
idea=''; IFS= read -r -d '' idea < "$file" || true
bytes=()
while read -r -a row; do bytes+=("${row[@]}"); done < <(od -An -v -tu1 -- "$file")
candidate='' pending='' title='' chosen=false
for (( index=0; index<${#bytes[@]}; )); do
    byte=${bytes[index]} width=1 point=$byte
    if (( byte >= 194 && byte <= 223 )); then width=2; point=$((byte & 31))
    elif (( byte >= 224 && byte <= 239 )); then width=3; point=$((byte & 15))
    elif (( byte >= 240 && byte <= 244 )); then width=4; point=$((byte & 7))
    elif (( byte >= 128 )); then fail 'Use valid UTF-8 without a BOM.'; fi
    (( index + width <= ${#bytes[@]} )) || fail 'Use valid UTF-8 without a BOM.'
    for (( offset=1; offset<width; offset++ )); do
        next=${bytes[index+offset]}
        (( next >= 128 && next <= 191 )) || fail 'Use valid UTF-8 without a BOM.'
        point=$(( (point << 6) | (next & 63) ))
    done
    (( point != 0 )) || fail 'NUL bytes are not supported in an idea.'
    (( !(index == 0 && point == 65279) && !(width == 2 && point < 128) && !(width == 3 && point < 2048) &&
       !(width == 4 && point < 65536) && !(point >= 55296 && point <= 57343) && point <= 1114111 )) || fail 'Use valid UTF-8 without a BOM.'
    if ! $chosen; then
        character=${idea:index:width}
        if (( point == 10 )); then
            if [[ -n "$candidate" ]]; then chosen=true; else pending=''; fi
        elif white "$point"; then
            if [[ -n "$candidate" ]]; then
                if (( point == 9 )); then pending+=' '; else pending+=$character; fi
            fi
        else candidate+="$pending$character"; pending=''
        fi
    fi
    (( index += width ))
done
[[ -n "$candidate" ]] || fail 'The idea must contain non-whitespace text.'
for (( index=0; index<${#candidate}; )); do
    printf -v byte '%d' "'${candidate:index:1}"
    width=1
    if (( byte >= 240 )); then width=4; elif (( byte >= 224 )); then width=3; elif (( byte >= 194 )); then width=2; fi
    (( index + width <= 120 )) || break
    title+=${candidate:index:width}; (( index += width ))
done
[[ "$label" != *','* && "$label" != *$'\r'* && "$label" != *$'\n'* ]] || fail 'Choose one nonblank label without commas or line breaks.'
# The same White_Space bytes used above, independent of the user's locale.
blank_label=$label
for space in $'\t' $'\v' $'\f' ' ' $'\xc2\x85' $'\xc2\xa0' $'\xe1\x9a\x80' $'\xe2\x80\x80' $'\xe2\x80\x81' $'\xe2\x80\x82' $'\xe2\x80\x83' $'\xe2\x80\x84' $'\xe2\x80\x85' $'\xe2\x80\x86' $'\xe2\x80\x87' $'\xe2\x80\x88' $'\xe2\x80\x89' $'\xe2\x80\x8a' $'\xe2\x80\xa8' $'\xe2\x80\xa9' $'\xe2\x80\xaf' $'\xe2\x81\x9f' $'\xe3\x80\x80'; do blank_label=${blank_label//"$space"/}; done
[[ -n "$blank_label" ]] || fail 'Choose one nonblank label without commas or line breaks.'
command -v gh >/dev/null || fail 'Install GitHub CLI and authenticate with gh auth login.'
temporary=$(mktemp -d "${TMPDIR:-/tmp}/factory-add.XXXXXXXX") || fail 'Cannot create a private temporary directory.'
cd -- "$project"
GH_DEBUG= gh repo view --json nameWithOwner,url --template '{{.nameWithOwner}}{{"\n"}}{{.url}}{{"\n"}}' > "$temporary/context" 2> "$temporary/stderr" || fail "Cannot resolve the repository. Check gh auth login, gh repo view, and project remotes. $(<"$temporary/stderr")"
mapfile -t context < "$temporary/context"
[[ ${#context[@]} == 2 ]] || fail 'GitHub returned an invalid repository context.'
repository=${context[0]%$'\r'} url=${context[1]%$'\r'}
[[ "$repository" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ && "$url" == https://*/"$repository" ]] || fail 'GitHub returned an invalid repository URL.'
hostname=${url#https://}; hostname=${hostname%/"$repository"}
[[ "$hostname" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*(:[0-9]+)?$ ]] || fail 'GitHub returned an invalid repository host.'
endpoint="repos/$repository"
recovery="Inspect recent issues in https://$hostname/$repository/issues, including closed issues, and compare title and body before retrying. A repeated invocation creates a new issue."
encoded=''
for (( index=0; index<${#label}; index++ )); do printf -v byte '%d' "'${label:index:1}"; printf -v piece '%%%02X' "$byte"; encoded+=$piece; done
GH_DEBUG= gh api --hostname "$hostname" -X GET "$endpoint/labels/$encoded" --template '{{.name}}' > /dev/null 2> "$temporary/stderr" || fail "Label lookup failed. Create the label in $repository or select an existing label. $(<"$temporary/stderr")"
quote() {
    local value=$1 code control escaped
    value=${value//\\/\\\\}; value=${value//\"/\\\"}
    for (( code=1; code<32; code++ )); do
        printf -v control '%b' "\\$(printf '%03o' "$code")"
        printf -v escaped '\\u%04x' "$code"
        value=${value//"$control"/"$escaped"}
    done
    printf '"%s"' "$value"
}
{ printf '{"title":'; quote "$title"; printf ',"body":'; quote "$idea"; printf ',"labels":['; quote "$label"; printf ']}'; } > "$temporary/payload.json"
submitted=true
GH_DEBUG= gh api --hostname "$hostname" -X POST "$endpoint/issues" --input "$temporary/payload.json" --template '{{printf "%v\n%s\n" .number .html_url}}{{range .labels}}{{printf "%s\n" .name}}{{end}}' > "$temporary/result" 2> "$temporary/stderr" || fail "GitHub creation failed. Check permissions and the diagnostic: $(<"$temporary/stderr")"
mapfile -t result < "$temporary/result"
for index in "${!result[@]}"; do result[index]=${result[index]%$'\r'}; done
[[ ${#result[@]} -ge 2 && "${result[0]}" =~ ^[1-9][0-9]*$ && "${result[1]}" == "https://$hostname/$repository/issues/${result[0]}" ]] || fail 'GitHub returned an invalid issue result.'
found=false
for returned in "${result[@]:2}"; do if [[ "$returned" == "$label" ]]; then found=true; fi; done
$found || fail "Created issue ${result[1]} lacks the requested label. Correct this existing issue before running the queue."
printf '%s\n' "${result[1]}"
