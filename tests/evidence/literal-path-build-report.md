# Literal filename build report

Builder verdict is READY. The Bash correction and regression are implemented.
Host WSL execution passed for both model variants, and the predecessor
comparison failed at the intended clean-worktree check. This resolves the prior
Unix verification blocker. The controller's full gate and fresh reviews remain
separate work after its commit.

## Changes and prior finding

Restored the reviewed change with `git diff --binary --output` between
`369ebf2266fdba617c9e9bf815907c20b9e8aab3` and
`74495223d36ed661cd9c74eb34ac75845ca8b992`, followed by `git apply`.
Deleted the owned patch after successful application. Before the correction,
all 389 restored files matched their predecessor Git blobs byte for byte.
The apply warnings concern preserved historical whitespace in evidence files.

Both `commit_build` copies now stage with `git --literal-pathspecs add`.
The NUL-delimited filename collection, array quoting, conditional commit, clean
worktree check, and builder report update remain intact. This addresses the
round-3 P2 finding in both model variants.

`tests/native-literal-paths.sh` uses public init, create, dispatch, accept, and
advance commands with separate temporary repositories and local bare remotes for
both variants. It checks gate status, a new commit, the builder report commit,
the exact NUL-delimited tree name, complete committed content, unchanged ordinary
README content in the tree and worktree, and a clean result. The controlled
GitHub and agent fixtures must resolve before helper execution. No live service
is involved. The factory check invokes the regression.

The script explicitly skips Windows shells. An initial Git Bash trial showed
that MSYS translates the colon to a private-use character. The exact tree-name
assertion rejected that result. The corrected launcher reports an unsupported
Windows filesystem skip, exit 0. That skip does not satisfy Unix acceptance.

## Acceptance evidence

| Requirement | Result |
| --- | --- |
| Restore reviewed migration and preserve accepted behavior | All 389 predecessor files initially matched Git blobs. Only the paired Bash helpers and factory check entrypoint receive implementation edits after restoration, plus the new regression and evidence. |
| Fix Bash staging in both variants | Both helpers use the same global literal-pathspec option. Library and synchronization checks pass. |
| Actual Unix public transition and predecessor rejection | Host WSL Ubuntu run of `bash tests/native-literal-paths.sh` passed, exit 0, for OpenAI and Claude with Linux `/tmp` fixtures. The predecessor source-root comparison failed, exit 1, at `Build left uncommitted files.` See the host evidence below. The earlier builder sandbox restriction no longer blocks this criterion. |
| Preserve filename and dashboard regressions | `powershell -NoProfile -File tests/native-regressions.ps1` and the same command with `-Model claude` each exit 0. Both PowerShell and Bash routes pass Unicode filenames, literal dashboard placeholders, delivery arguments, diagnostics, Unicode stdin, and blocker history. Quote and newline filename cases explicitly skip on Windows. |
| Preserve executable issue behavior | `powershell -NoProfile -File tests/add-issue-redirected.ps1 -Bash 'C:/Program Files/Git/bin/bash.exe'` exits 0. Both executable probes reject the predecessor binder with exit 92. All eight redirected UTF-8 rejected or uncertain submission cases pass exact arguments, payloads, request counts, recovery, and cleanup. |
| Library and model parity | `bash tests/check-library.sh` and `powershell -NoProfile -File scripts/sync-factory.ps1 -Check` exit 0. These cover all nine skill names, matching frontmatter, collection membership, shared files, identical AGENTS.md and CLAUDE.md, and absence of active Python sources. |
| Syntax and whitespace | `bash -n` passes for both helpers, the factory check, and the new regression. `git diff --check` exits 0. Active Bash files contain no CR bytes. |
| Installer checks | `powershell -NoProfile -File scripts/check-installers.ps1` and `bash scripts/check-installers.sh` each exit 0. Both cover Bash and PowerShell, both models, repeat installs, conflicts, project installs, and explicit skill directories. |
| Current host full gate | Pending controller execution after commit. Neither known blocked full factory suite nor timeout fixture was rerun. |

The shell was Windows PowerShell 5.1.26100.9818. Git Bash was GNU Bash
5.2.12, x86_64-pc-msys, with Git 2.39.0.windows.2. Ownership exceptions were
process-local Git configuration. No global Git configuration was written.

## Preserved visual evidence

Both model copies match the predecessor visual manifest exactly:

| Asset | SHA256 |
| --- | --- |
| dashboard.html | 56D89FABD2960C36295D27DD0ABF0E78DB43E9E255957540A17FE8BB369063AB |
| dashboard.css | 03A50F449302A52B3710EE31693F82774DDB4D4BA7DD1AB7814BFC68F380BB03 |
| dashboard.js | 61DE8AA600460DD794AB7F789F0A7F47F1B4CDBBA6EE04FEE046156819D1391C |

The saved `successor-ui/empty.html` and `populated.html` match the current
template, stylesheet, and browser script exactly after substitution of their
existing sample JSON. All 18 PNGs and `keyboard-log.json` retain predecessor
bytes. Their current SHA256 values are in `literal-path-visual-hashes.json`.

Inspected `successor-ui/narrow-later-content.png` and
`successor-ui/desktop-close-after-scroll.png`. Both show the later marker and
reachable Close control. The existing keyboard log records the 1280x900 and
500x900 journeys, scrolling from 0 to 3327 with scrollHeight 3822 and
clientHeight 495, dismissal, focus return, literal script text, and refresh
behavior. These remain historical host observations associated with unchanged
pages. `capture.log` remains the earlier failed attempt. No screenshot or log
was rewritten and no new browser capture ran.

HEAD remains the assigned base because the builder does not commit. The full
restored implementation is uncommitted. The controller must associate actual
committed asset hashes and clean status with its final commit before review.

## Host Unix evidence

Read the host's saved logs from
`C:/Users/torra/Desktop/Projects/armoury/factory/jobs/20261120163011-d97ddb4cf8/host-unix-literal.log`
and `host-unix-predecessor.log`. These are host observations, not new builder
runs. The host reports candidate exit 0 and predecessor exit 1.

Both logs identify Linux `6.18.58.1-microsoft-standard-WSL2`, GNU Bash
`5.1.16(1)-release`, x86_64-pc-linux-gnu, and Git `2.34.1`. The candidate
fixtures used `/tmp/tmp.9oefBwfJA5`; the predecessor fixtures used
`/tmp/tmp.IMuTZ3WDtz`. These are Linux filesystem fixtures.

The candidate run of `bash tests/native-literal-paths.sh` records PASS for
both OpenAI and Claude. Each public build-to-gate transition created a new
commit, updated the report commit, preserved the exact tree filename and
content, left ordinary README unchanged, and finished with a clean worktree.
The log shows each commit creating `:(literal)README.md`.

The comparison ran the same regression with the reviewed predecessor source
root. It reached the OpenAI public transition and failed with
`factory: Build left uncommitted files.` followed by
`Literal-path regression failed, exit 1.` This is the intended defect detection,
not a runner setup failure. It stopped before the Claude comparison. The logs
include PowerShell NativeCommandError formatting around WSL stderr; the actual
candidate PASS records and host exit status establish the successful result.
The logs do not preserve the complete outer WSL command lines or the optional
predecessor source-root argument, so no exact invocation beyond the regression
command is claimed here.

## Remaining controller verification

After the controller commits, run its normal helper gate, the full Git Bash
factory check, and fresh code, security, UI, and UX reviews against main.
Predecessor passes are historical evidence only.

This reassessment changed only this worktree report. No product or test edits
and no test reruns were needed or performed.

No main checkout, installed skill, job record, factory control, or frozen check
changed. No agent, live issue, delivery, merge, or deployment was started.

Skills used: factory, factory-builder, unslop.
