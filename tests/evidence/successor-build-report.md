# Successor build report

Verdict: READY

The implementation correction is complete. The host reran both full factory
checks with process-termination permission and reports exit 0 for both commands.
`host-round2-factory-powershell.txt` and `host-round2-factory-bash.txt` record
passing native runtime checks and the full issue suite, including the redirected
UTF-8 regression. These current host passes supersede the round-2 timeout
permission failures. Both current installer checks also pass. Existing host
browser evidence applies to the unchanged dashboard assets. No builder commit
was created because Git delivery belongs to the controller.
This report carries forward the host evidence. The initial environment blocker
was superseded by those host runs. The later helper gate exposed a separate
test-decoding defect, addressed in round 2 below.

## Changes

Restored the reviewed predecessor using the requested binary diff and git apply.
Removed the owned transfer patch after successful application. The restored tree
comparison found no missing predecessor paths. The existing host metadata change
under `.agents/skills/unslop/agents/openai.yaml` was preserved.

Both issue helpers resolve GitHub CLI once and invoke executables through
ProcessStartInfo with explicit argument quoting and UseShellExecute=false.
They preserve the working directory, decode UTF-8, drain stdout and stderr
concurrently, keep response parsing separate from diagnostics, dispose the
process, and restore GH_DEBUG and console encoding. Script fixtures retain their
existing route.

Added a compiled offline gh.exe fixture, explicit fixture selection, binary
argument capture, full argument-array assertions, and probes of the production
functions. Both model copies pass empty arguments, Unicode, quotes, backslashes
before quotes, trailing backslashes, and spaces. The predecessor binder fails
the same executable probe with exit 92. Failure probes verify environment
restoration. Large simultaneous output streams test draining, and successful
stderr stays out of response parsing.

## Round 2 redirected UTF-8 correction

The round-1 helper gate failed at `native / post-reject lost UTF-8 stderr`.
Read the frozen check and installed `Run-Check` implementation without changing
either. `Run-Check` starts Windows PowerShell with redirected output and error
streams. The issue test's own `Run` function also redirects both streams, but
left their encodings implicit. Under the gate's inherited OEM encoding it read
the helper's UTF-8 diagnostic with the wrong decoder. Interactive host runs
inherited UTF-8 and hid that test defect. The compiled fixture emits UTF-8, and
the production `Gh` function already decodes both native streams explicitly.

Set both test ProcessStartInfo stream encodings to the existing strict UTF-8
decoder. No assertion, fixture diagnostic, product helper, installed helper,
or frozen control changed. Added eight public-route executable cases covering
both models, code pages 437 and 1252, and rejected and uncertain submissions.
Each retains full argument, payload, cleanup, single-creation, diagnostic, and
recovery assertions. The new redirected runner forces an OEM parent and uses
the installed helper's redirected-process pattern. Required factory checks run
this regression before the full issue suite.

`round-2-reproduction.txt` records the original full-suite failure with exit 1.
`round-2-focused-before.txt` records the focused regression with the implicit
decoder restored in an owned temporary test copy, also exit 1. Only the decoder
assignment was removed for that comparison. The temporary copy was removed.
`round-2-focused-after.txt` records all eight cases passing with exit 0 on
Windows PowerShell 5.1.26100.9818. This establishes the failure and correction
under equivalent redirected execution. The test change adds no runtime
dependency. The UI assets and both production issue helpers retain their
previous hashes, so the host's rendered evidence remains valid.

The directly invoked `bash tests/add-issue.sh` also passes with observed exit 0
in `round-2-add-issue.txt`. It runs the eight redirected cases, then 39 script
cases, 39 Bash cases, and 47 executable cases. Both model quote probes pass,
and the predecessor binder still fails with exit 92 as required. No assertion
was removed. The actual rejected-submission stderr retains `café` and remains
separate from the 70000-byte stdout stream. The fixture is unchanged.

## Acceptance criteria and evidence

1. Exact executable arguments pass on Windows PowerShell 5.1.26100.9818.
   `round-2-add-issue.txt` records both model probes, 39 PowerShell script cases,
   39 Bash cases, 47 executable cases, and eight additional redirected cases.
   Executable cases include the public Claude route, both complete templates,
   enterprise host, literal custom label, and paths containing spaces. The
   executable rejects malformed argument arrays and has no forwarding path.
2. Original issue behavior passes the retained 117 cases, with the new encoding
   cases also passing. Complete decoded payloads,
   title cutoffs, unchanged input bytes, pinned targets, label verification,
   creation count, and URL-only success are asserted.
3. Failure and local-effect cases pass. Transcripts include success, preflight
   rejection, and uncertain submission. Tests assert no retry, recovery guidance,
   helper-owned cleanup, unchanged caller files and Git state, and no setup in
   initialized or uninitialized projects.
4. Host dashboard capture passed in Edge 157.0.4341.60 at 1280x900 and 500x900.
   `successor-ui/keyboard-log.json` records separate Tab, Enter, PageDown,
   Escape, and Close journeys at each width. The report has scrollHeight 3822
   and clientHeight 495. PageDown moves scrollTop from 0 to 3327. The saved
   `*-later-content.png` files show the initially hidden final marker, and
   `*-close-after-scroll.png` shows reachable Close. Both dismissal paths return
   visible focus to the initiating button. Empty and populated boards, long
   identifiers, and a long blocker are captured. There are 18 PNGs on disk.
   The builder inspected eight, including `narrow-later-content.png`,
   `desktop-close-after-scroll.png`, `narrow-empty.png`, `narrow-populated.png`,
   `desktop-escape-focus-return.png`, `narrow-close-focus-return.png`,
   `narrow-dialog.png`, and `desktop-report-start.png`. No defect was observed.
   Generated sample pages match the current template and assets exactly. The
   host will record the delivered commit and identical asset hashes after its
   commit. The capture log accurately identifies working tree assets.
5. Prior dashboard corrections remain unchanged and synchronized. Native
   regressions passed for blocker history, control escaping, delivery arguments,
   and Unicode stdin. The fresh browser log confirms literal script display,
   refresh suppression while the dialog is open, and explicit reload with focus
   on Refresh jobs. At 500px explicit refresh retains scrollY 100. The ready
   card has no active blocker and retains its resolved-blocker report control.
6. Both current installer checks pass with observed exit 0. The host reran both
   full factory commands with process-termination permission and reports exit 0
   for each. `host-round2-factory-powershell.txt` and
   `host-round2-factory-bash.txt` record passing library, synchronization,
   installer, native regression, workflow, delivery, and budget checks. Each
   reaches the redirected OEM-parent regression and the full issue suite,
   including both model probes, 39 PowerShell script cases, 39 Bash cases,
   47 executable cases, and eight additional redirected cases. The logs retain
   PowerShell NativeCommandError wrappers around expected Git stderr, followed
   by the passing runtime and issue results. The host's reported command exits
   are 0. Earlier access-denied timeout failures and the failed WSL attempt
   remain historical environment evidence. No timeout assertion or control
   changed, and this reassessment reran no checks.
7. Library checks and both synchronization checks passed. Active skill names,
   frontmatter, collection membership, and platform metadata checks passed.
   AGENTS.md and CLAUDE.md are identical. `successor-validation.txt` records
   matching helper hashes and verification of all 128 archived source blobs.
   Active helpers and checks introduce no Python, Node, or jq requirement.
   Node is used only by the optional evidence capture. Tracked diff checks and
   whitespace checks of successor source files passed. `round-2-validation.txt`
   records the current synchronization, library, scope, and hash checks.
8. Fresh independent reviews, approval, the builder commit, and PR delivery remain
   controller work. No commit, push, PR, merge, deployment, nested agent, main
   checkout edit, job-record edit, installed-skill edit, or product factory
   configuration edit was performed.

## Required check logs

| Command | Exit | Log |
| --- | --- | --- |
| powershell -NoProfile -File scripts/check-factory.ps1 | 0, host-reported | host-round2-factory-powershell.txt |
| bash scripts/check-factory.sh | 0, host-reported, Git Bash | host-round2-factory-bash.txt |
| powershell -NoProfile -File scripts/check-installers.ps1 | 0 | round-2-check-installers-powershell.txt |
| bash scripts/check-installers.sh | 0 | round-2-check-installers-bash.txt |
| powershell -NoProfile -File tests/add-issue-redirected.ps1 | 0 | round-2-focused-after.txt |
| bash tests/add-issue.sh | 0 | round-2-add-issue.txt |

Bash commands used Git for Windows Bash. Git commands used process-local
safe.directory configuration because the sandbox identity differs from the
worktree owner. No global Git configuration changed.

`host-check-factory-bash.txt` is the failed host WSL attempt and does not replace
the Git Bash result. Earlier failed logs remain as history. The saved issue
transcripts replace the synthetic 70000-byte diagnostic run with
`[70000 diagnostic bytes]`. Actual exit codes, request counts, actionable
diagnostics, and recovery guidance remain intact. New round-2 transcripts use
UTF-8 text. No test assertion was weakened.

## Prior findings

The round-3 code quoting finding is fixed and covered by the executable tests.
Earlier native and dashboard corrections were preserved. Host captures now
supply the missing UI-1, UI-2, and UX-4 evidence for fresh independent review.
This builder report does not declare those reviews passed. Earlier security
PASS is not a successor review. Round 2 fixes the test runner's redirected UTF-8
decoding and adds regression cases. Production helpers, archives, paired skill
files, and captured dashboard assets remain unchanged from
`bfb41aac844edd7382a1133068bc811506391c32`. The existing UI hashes were rechecked,
and the two long-report screenshots were re-inspected. No UI defect was found.

The current host passes resolve the remaining builder environment blocker.
No builder acceptance gap or product decision remains. This final reassessment
changes only this report and preserves existing product code, tests, evidence,
and prior findings. The previous BLOCKED report remains in the controller's
round-2 history. Independent reviews, approval, asset-to-commit recording,
and Git delivery remain controller work. READY here means ready for those
controller gates, not an approved or delivered PR.

Automatic approval review rejected cleanup of the temporary ignored browser
profile with the reason "blocked by policy". The ignored profile remains
untouched. Cleanup is unnecessary, and no alternate deletion method was
attempted.

Skills used this round: factory, factory-builder, unslop.
