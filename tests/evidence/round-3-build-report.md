# Round 3 build report

Verdict: READY

Both round-2 code findings are fixed in matching OpenAI and Claude helpers.
Focused verification passes on Windows PowerShell 5.1.26100.9818 and Git for
Windows Bash. The controller must run the authoritative helper gate and full
Bash check after its commit. This report does not claim those current full
checks or fresh reviews have passed.

## Changes and findings

The dashboard now replaces placeholders in a single pass over the original
template. Replacement values never enter another substitution pass. Requests
and saved reports retain all three literal placeholder strings, including
`__FACTORY_SCRIPT__`, and their dashboard JSON parses and round trips exactly.
The template, stylesheet, and browser script are unchanged.

The PowerShell build transition reads both changed and untracked paths through
Git's NUL-delimited output. The native runner returns raw UTF-8 stdout for these
calls without trimming or appending stderr. Staging uses `--literal-pathspecs`
and separate quoted arguments. It retains Unicode, quotes, embedded newlines,
and pathspec characters as filename data. Existing default native output
handling remains in effect for other operations.

The regression fixture exercises the public build-to-gate transition with
`core.quotePath=true`. It modifies a tracked accented filename and creates an
untracked filename containing Chinese text and an emoji. Both names contain
brackets. Assertions verify a clean worktree and the exact committed contents
under each original filename. Unix fixtures also include quote and newline
filenames. Windows rejects those names, so the current Windows run explicitly
skips those two filesystem cases. No Unix execution is claimed.

Requests and builder reports include all three dashboard placeholder tokens.
The fixture parses the generated JSON and compares the complete artifact text.
The standard regression launcher now exercises both model variants. Existing
control-character, blocker-history, delivery-argument, diagnostic, exit-code,
and Unicode-stdin assertions remain intact and pass.

## Acceptance evidence

| Requirement | Current evidence |
| --- | --- |
| Both code findings, matching variants | `round-3-focused-openai.txt` and `round-3-focused-claude.txt`, both exit 0. Each runs the PowerShell and Bash public routes, including placeholder round trips and modified/untracked Unicode staging. |
| Preserve issue behavior | Issue helpers and fixtures are unchanged. `round-3-issue-focused.txt`, exit 0, covers both executable argument probes and eight redirected rejected or uncertain submission cases, with exact payloads, request counts, recovery, and cleanup. |
| Preserve dashboard design | All three asset hashes in both model directories match the host's job `visual-manifest.json`. Existing `successor-ui/keyboard-log.json` and 18 screenshots remain applicable at 1280x900 and 500x900. No new browser capture ran. |
| Preserve native migration and paired library | `round-3-library.txt`, exit 0, verifies skill names, frontmatter, collections, paired files, identical repository instructions, and absence of active Python files. `round-3-paired.txt`, exit 0, records the PowerShell synchronization check. No archive, installer, metadata, or issue helper changed. |
| Scope and syntax | `git diff --check` and `bash -n tests/native-regressions.sh` pass. Changes are confined to the two matching helpers, focused regressions, their launcher, and brief evidence files. |
| Full checks and delivery | Controller work after commit. The known process-termination permission failure prevents authoritative full-suite execution in this builder sandbox. Neither full factory suite was rerun. Earlier host full-suite and installer passes remain historical evidence in `successor-build-report.md`. |

Commands for the focused logs were `powershell -NoProfile -File
tests/native-regressions.ps1`, the same command with `-Model claude`,
`powershell -NoProfile -File tests/add-issue-redirected.ps1`,
`bash tests/check-library.sh`, and `powershell -NoProfile -File
scripts/sync-factory.ps1 -Check`. Bash is Git for Windows Bash. Git ownership
exceptions used process-local environment configuration only. Logs are short
UTF-8 files and record observed exits.

Round-2 security, UI, and UX reviews passed without blocking findings. Their
implementation and rendered evidence were preserved. Both code findings now
have focused regressions. Fresh reviews must assess the controller's resulting
commit. No actual job records, frozen controls, installed helpers, or main
checkout files changed. No agent was started and no Git delivery occurred.
Fixture commits and mock delivery stayed inside owned temporary repositories.

Skills used: factory, factory-builder, unslop.
