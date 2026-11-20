#!/usr/bin/env bash
set -euo pipefail
prompt=''
for ((i=1;i<=$#;i++)); do if [[ "${!i}" == --prompt-file ]]; then ((i+=1)); prompt=$(cat -- "${!i}"); break; fi; done
[[ -n "$prompt" ]] || prompt=$(cat)
if [[ "${FACTORY_FAKE_SLEEP:-0}" != 0 ]]; then sleep "$FACTORY_FAKE_SLEEP"; fi
if [[ "${FACTORY_FAKE_EDIT:-0}" == 1 ]]; then printf 'done\n' > app.txt; fi
printf '%s\n' "$@" >&2
role=$(printf '%s\n' "$prompt" | sed -n 's/^ROLE: //p' | head -n 1)
case "$role" in intake) verdict=ACCEPT;; spec-writer|builder) verdict=READY;; approver) verdict=APPROVE;; *) verdict=PASS;; esac
body="{\"verdict\":\"$verdict\",\"summary\":\"Fixture\",\"report\":\"Offline evidence\",\"skills_used\":[],\"risk\":\"low\",\"areas\":[\"code\"]}"
escaped=${body//\"/\\\"}
if [[ " $* " == *' --prompt-file '* ]]; then printf '{"text":"%s","stopReason":"end_turn","sessionId":"offline"}\n' "$escaped"
elif [[ " $* " == *' exec '* ]]; then
    printf '%s\n' '{"type":"thread.started","thread_id":"offline-fixture"}'
    printf '{"type":"item.completed","item":{"type":"agent_message","text":"%s"}}\n' "$escaped"
    printf '%s\n' '{"type":"turn.completed","usage":{"input_tokens":1,"output_tokens":1}}'
else printf '{"result":"%s","is_error":false,"session_id":"offline"}\n' "$escaped"; fi
