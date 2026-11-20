# Guided configuration host evidence

This fixture is input data for actual host sessions. It contains no configuration
editor or expected transcript. Run each journey through the changed factory
skill in a disposable Git project. Use a fresh fixture for each numbered row,
except when the row specifies sequential responses. Exercise each available
host and record any explicitly waived host run as untested. The builder cannot
launch those hosts or nested agents.

## Issue #4 verification handoff

The user waived actual Claude-host testing for issue #4 because Claude is not
installed. Do not require installation or substitute Grok for the frozen Codex
runner. Keep the paired skill instructions equivalent and verify repository
parity. That check establishes matching instructions, not Claude-host behavior.

The controller's `host-evidence-summary.md` reports actual Codex interactions
in job `20261120211735-91aba23f33`, under `host/turn01` through `host/turn04`.
Those artifacts include event logs and before/after JSON. The summary reports
the current runner, all three choices, the dependent-removal warning, and an
unanswered prompt without writes. It also reports a read-only refusal and,
after write access returned, an explicit `grok` selection that changed only the
builder runner and removed its model, reasoning, and executable. Builder
timeout and unrelated settings survived. The reported frozen-config hash
matches the source fixture. This is partial evidence for cases 1 and 2 and
frozen-config preservation. It does not establish the other journeys or actual
future-job creation.

The host owns the remaining Codex interactions, full native factory suites,
current gate, and independent reviews. Attach its actual transcripts, fixture
diffs, no-write comparisons, and future-job evidence to the review handoff.
The builder's focused repository checks do not replace those runs. Mark Claude
host behavior untested with the user waiver, and mark unobserved Codex journeys
pending until the host supplies evidence. The builder must not launch nested
agents or edit job records to fill these gaps.

## Prepare each project

Create a new temporary directory outside any real project's `factory` directory.
Initialize a local Git repository with branch `main`. Copy this directory's
`config.json` to `<fixture>/factory/config.json`. Use a native file copy, never
evaluate the JSON as shell code. Point the host explicitly at the changed
`skills/<model>/factory/SKILL.md` and its references. Do not overwrite installed
skills. Keep the fixture's original bytes for comparisons.

For edit journeys, create a sentinel at
`factory/jobs/existing/config.json` containing the original fixture config,
`factory/jobs/existing/checks.ps1` containing `exit 0`, and
`factory/jobs/existing/job.state` containing `stage=build`. These are frozen-file
sentinels, not evidence of a real created job. Hash them before and after each
journey. Place a separate sentinel at `factory/checks.ps1` too. None may change.

Capture the initial config bytes, actual conversation including every prompt and
response, host tool calls and writes, final config bytes, and a config diff.
For no-write cases compare bytes, not just parsed JSON. For writes compare
parsed values as well, so serialization changes do not conceal lost data.
Store evidence outside the fixture config and job directories. Label each run
with host, skill path, source revision or diff, and case number. A case without
an observed host interaction remains unverified.

## Journeys and assertions

| Case | Actual host inputs and actions | Check after the interaction |
| --- | --- | --- |
| 1 | Invoke `factory config`, then `factory config default.runner`. Leave the prompt unanswered and end the session. | Inspection lists editable paths. Runner prompt shows stored `codex` and all of `codex`, `claude`, `grok`. Config and sentinels remain byte-identical. |
| 2 | Request `roles.builder.runner`, submit `grok`. | Prompt warns about provider field removals. Only builder runner changes and builder model, reasoning, executable disappear. Builder timeout, sibling roles, extensions, lists, and sentinels survive. |
| 3 | Request `default.runner`, submit `codex`. Then request it again and submit `claude`. | Same-runner selection retains provider fields. Changed runner removes only default model, reasoning, executable. Stored role profiles stay unchanged. |
| 4 | Request `default.timeout_seconds`, submit `1.5`, `0`, `86401`, `true`, then `60`. Request `max_rounds`, submit `101`, then `4`. | Each invalid response explains its constraint and writes nothing. Valid responses store integers. Also exercise concurrency bounds 1 and 100, and rejection of 0 and 101. |
| 5 | Inspect `roles.review-ui.model` and cancel. Set `default.model` to `fixture-model`, then `null`. Set `roles.review-ui.model` to `null`. | Absent role model initially inherits `fixture-default`. Explicit null means CLI default and remains a property. No invented model choices. Only selected fields change. |
| 6 | Request `skills.roots`, submit malformed `[`, then `["ok", 3]`, then `["fixture path with spaces", "café/技能"]`, then `[]`. | Invalid arrays write nothing. Strings survive exactly and the final value is an empty array. Exercise a one-element array too, which must remain an array. |
| 7 | Request `unknown`, `roles.typo.model`, `version`, and `default`. Request `default.runner` and submit `other`, then empty text, then `cancel`. | Each unsupported key or value gives supported examples or permitted values. No writes for any action. Empty text does not select a default. |
| 8 | Set `default.model` with the JSON string literal below. Set `default.executable` to the same literal. | Decoded strings match exactly. No command runs and no `CONFIG_EXECUTED` file appears. Executable validation must not invoke it. |
| 9 | Request `roles.builder.reasoning`, submit `clear`. Request `roles.builder.executable`, submit `clear`. | Each prompt explains inheritance after removal, including provider reset. Only the selected properties disappear. For a same-provider inheritance case repeat on `roles.review-ui.reasoning` after assigning a value. |
| 10 | Open a `max_rounds` prompt. Through a separate file tool change only `extension.concurrent` to `"keep me"`. Then answer `4`. | Host detects changed source, shows new state, requests a fresh response, and does not overwrite the intervening edit. Cancel that new prompt and verify the external edit is the only change. Repeat with a fresh explicit response to verify safe save. |
| 11 | Use separate fixtures with missing config, malformed JSON, version 1, and a host-enforced unwritable config. Request inspection and a key edit. | Actionable failure, no initialization, migration, repair, or replacement. Missing config must not create `factory/`. |
| 12 | Request `base_branch`, submit an invalid branch such as `bad..branch`, then `feature/config-demo`. | Invalid response writes nothing. Valid name stores literally without creating or switching a branch. |

Use this JSON string literal for case 8. It is data for the host prompt, not a
shell command. Submit it through text input without shell interpolation.

```json
"fixture \"quoted\" café $(touch CONFIG_EXECUTED); & echo marker `literal`"
```

Also exercise clearing default reasoning and executable, null list members,
objects instead of arrays, whitespace-only strings, and a literal JSON string
`"cancel"` for a model. Clarify ambiguous text without writes. Verify no-write
cases using hashes taken immediately before the response under test.

## Future-job freeze evidence

The host must also use the existing native workflow in an offline disposable
project with a local bare origin. Commit its initial fixture setup and provide
meaningful native checks for a small tracked test file. Create an actual first
job through the documented `create` workflow and freeze its effective config
using native file tools as required by the skill. Snapshot its frozen config,
checks, state, and limit bytes.

Through the actual host interaction change project `max_rounds` to 4 and
`default.timeout_seconds` to 60. Verify the first job's saved files remain
byte-identical. Resolve the updated effective config and create a second job
through the same native workflow, passing the updated limit. Confirm its
frozen config has the new timeout and its saved limit is 4. Keep the original
project checks unchanged. Sentinel checks alone do not establish this journey.

Keep this offline. Use local Git remotes and existing external-command mocks
where needed. Do not invoke issue creation, comments, push, or PR delivery.
Do not dispatch a configured fixture executable. Record the exact native
commands and saved files, rather than infer a freeze from config editing alone.

## Review handoff

Text is the changed UI. Supply actual text transcripts and fixture diffs to UI,
UX, code, and security reviewers. Dashboard screenshots do not demonstrate this
interaction. If a choice widget appears, record its actual options, text-input
route, empty response, and cancellation behavior. Mark each host and journey
passed or missing with evidence paths. Repository parity checks prove matching
instructions, not host compliance. A separate editor's tests cannot fill that gap.
