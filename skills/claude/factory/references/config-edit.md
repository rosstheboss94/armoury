# Guided configuration

The host handles `factory config` and `factory config <key>` using native file
tools. Resolve the project root as described in SKILL.md. Read
`factory/config.json` as JSON data. Do not call a helper `config` action, run
setup, start a job, contact GitHub, or regenerate the dashboard.

## Inspect and prompt

A bare invocation displays current settings and the editable paths below. It
saves nothing. The user can name a key afterward. Reject unknown paths,
unsupported roles, whole objects, and read-only `version`. Explain the error
with relevant supported examples. Never silently add an arbitrary key.

For a supported key, show its stored value before asking for input. If a role
override is absent, label it absent and show the effective inherited value using
the profile resolution rules in [Configuration](config.md). Explicit
`model: null` means the selected CLI's default model. It differs from an absent
role model that may inherit a configured model.

For a runner, show every choice, `codex`, `claude`, and `grok`, before requesting
a selection. For other keys, request input and explain its type and constraints.
A native choice widget may supplement text input. Keep text input available
and never omit a runner to fit a widget's option limit.

Wait for an explicit response. A displayed default, a preselected option, an
empty response, an unanswered prompt, and elapsed time authorize no write.
Accept `cancel` or an unambiguous request to stop without saving. Treat ambiguous
input as a clarification, not a selection. If the user intends a string equal
to a control word such as `cancel`, ask them to submit a JSON string literal.
Decode that literal once and preserve its contents. Never trim or split string
contents to make input valid.

Validate before writing. Explain the specific constraint on invalid input and
offer another response or cancellation. Never replace invalid input with a
default. The following contract applies to both hosts.

## Editable keys

| Key | Input and constraints |
| --- | --- |
| `base_branch` | Nonempty branch name accepted by Git's existing branch interface. Validate with `git check-ref-format --branch` using a literal argument, without creating or switching a branch. |
| `concurrency` | Integer from 1 through 100. |
| `max_rounds` | Integer from 1 through 100. |
| `default.runner` | Exactly `codex`, `claude`, or `grok`. |
| `default.model` | Nonempty model identifier string, or explicit JSON `null` to use the selected CLI's default. |
| `default.reasoning` | Nonempty runner-specific string, or explicit `clear` to remove the optional assignment. |
| `default.executable` | Nonempty executable name or path, or explicit `clear` to remove the optional assignment. |
| `default.timeout_seconds` | Integer from 1 through 86400. |
| `roles.<role>.<field>` | The same profile fields and constraints as `default`. |
| `skills.roots` | JSON array of nonempty path strings. |
| `skills.include` | JSON array of nonempty skill-name strings. |
| `skills.exclude` | JSON array of nonempty skill-name strings. |

Supported roles are `intake`, `spec-writer`, `builder`, `review-code`,
`review-security`, `review-ux`, `review-ui`, and `approver`. Profile fields are
`runner`, `model`, `reasoning`, `executable`, and `timeout_seconds`.

Reject booleans, fractions, and values outside the bounds for integer fields.
Whitespace-only strings do not count as nonempty. Lists require JSON array
input, including `[]` to clear a list. Reject malformed JSON, null members,
empty strings, objects, and mixed-type arrays. Do not split paths or skill names
on whitespace or commas. Preserve spaces, quotes, Unicode, and shell
metacharacters within strings. They remain data, never shell code.

Model identifiers and reasoning values depend on the installed CLI and account.
Do not invent a fixed list or claim that syntax validation proves availability.
Keep unsupported provider settings subject to the existing dispatch checks.
Store an executable literally without executing it for validation.

## Profile changes

Resolve defaults, then role settings, then explicit job overrides. Editing an
absent role field creates only the necessary role object and selected field.
Do not copy its whole effective profile into the stored role.

An explicit `clear` for reasoning or executable removes that property. Before
accepting it, explain the resulting inheritance. Clearing a role override may
restore a default value, subject to the inherited-provider reset rule. Clearing
a default assignment removes it from defaults. Never store an empty optional
argument or use null as a substitute for removal. Preserve explicit model null.

Before requesting a runner selection, explain that changing it removes that
profile's stored model, reasoning, and executable assignments. Compare against
the previous effective runner for an absent role runner. Remove those dependent
fields only when the runner changes. Preserve timeout and all unrelated fields.
A single-key runner edit supplies no replacement provider fields. Selecting the
same runner must not reset provider fields.

Changing `default.runner` does not rewrite other role profiles. Continue to
clear inherited provider fields during effective resolution when a role changes
runner, unless that override supplies replacements. Never substitute providers
or change this inheritance contract.

## Save or stop

Missing configuration needs initialization, but inspection and key prompts must
not initialize it. Explain how to request `factory init`. Malformed JSON,
unsupported schema versions other than version 2, unreadable files, or denied
writes stop the edit. Report the path and corrective action. Do not repair,
migrate, or replace configuration implicitly.

Retain the source bytes or a digest when presenting the prompt. Before saving,
reread the file and compare with that source. If another edit occurred, discard
the pending write, show the updated state, and request a fresh explicit response.
Never overwrite an intervening edit from a stale snapshot.

Apply only the selected setting and required dependent removals. Preserve
unknown fields, sibling roles, nested values, and array types, including empty
and one-element arrays. Use sufficient serialization depth for all existing
data. Validate the candidate JSON before replacing the file. Use a safe file
replacement supported by the host and check for intervening changes as close to
replacement as possible. If the host cannot protect against concurrent writes,
stop and explain that limitation rather than claim a safe save.

Confirm the saved value and dependent removals by rereading the result. Report
the key, previous stored value or absence, saved value, and dependent changes.
State that changes affect future jobs only. Selecting an already stored value
may report unchanged without rewriting the file.

Do not edit checks, frozen job configuration, job state, existing job limits, or
installed controller skills. Do not change unrelated project settings. The
native job creation workflow still freezes the effective configuration and
checks for each new job as described in [Configuration](config.md).
