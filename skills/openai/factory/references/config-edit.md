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
| `vibe` | Exactly `true`, `1`, `on`, `false`, `0`, or `off`. The match is case-sensitive. `true`, `1`, and `on` save JSON true. `false`, `0`, and `off` save JSON false. Any other input leaves the file unchanged, including empty text, `yes`, `no`, and uppercase copies. When the key is absent, say it is absent and treated as off. |
| `default.runner` | Exactly `codex`, `claude`, or `grok`. |
| `default.model` | For `codex` and `claude`, a nonempty model identifier string, or explicit JSON `null` to use the selected CLI's default. For `grok`, JSON `null` or an id from the listing in [Grok model and reasoning listings](#grok-model-and-reasoning-listings). |
| `default.reasoning` | For `codex` and `claude`, a nonempty runner-specific string, or explicit `clear` to remove the optional assignment. For `grok`, `clear` or an id from the reasoning listing in that section. |
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
For a Grok model or reasoning edit, follow
[Grok model and reasoning listings](#grok-model-and-reasoning-listings).
Keep unsupported provider settings subject to the existing dispatch checks.
Store an executable literally without executing it for validation. The guide
does not run an executable merely to validate the executable field.

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

## Grok model and reasoning listings

This section applies while `factory config` edits one of these keys and the
effective runner for that profile is `grok`.

- `default.model`
- `default.reasoning`
- `roles.<role>.model`
- `roles.<role>.reasoning`

The effective runner follows the existing profile rules. A role with no stored
runner uses `default.runner`. Codex and Claude do not query a CLI catalog.
Model and reasoning edits for `codex` and `claude` stay as they are. A nonempty
string is enough. Those edits do not run `grok models`. JSON `null` still means
the selected CLI's default model. `clear` still removes optional reasoning.

Show the current stored value first. Then say which executable is running and
which models command it is running, `grok models` or `<stored-executable> models`.
If that models command does not finish, name it, say that it did not finish,
and say that `factory/config.json` is unchanged. Write nothing.

After the models command returns, a model edit with a readable id list shows
those ids and asks for a model value. That is the only case that asks for a
model value.

A reasoning edit does not ask for a model value. It shows reasoning-effort ids
from that output when the output includes them for the resolved model. When it
does not, the host names the executable and the documented reasoning command
before waiting. The documented command is the non-interactive form that
`grok models --help` on the installed CLI documents for one model's
reasoning-effort ids, with that model id passed. Do not invent a flag the help
text does not document. If the installed CLI documents no such listing, write
nothing.

A failed or unfinished models command names that command, says
`factory/config.json` is unchanged, and does not ask for a value. Failure
includes a missing executable, a failed process, empty output, or output the
host cannot read ids from. The host does not guess an id and does not fall back
to any nonempty string for that Grok edit.

After the documented reasoning command returns, show the reasoning ids, the
empty menu, or the failure. If that reasoning command does not finish, name it,
say that it did not finish, and say that `factory/config.json` is unchanged.
Write nothing.

### Model ids

Run the installed Grok CLI as `grok models` when the profile has no executable
override. When the profile stores an executable, run that executable with the
same `models` argument, because dispatch will use that executable. Do not add
flags that filter, sort, or rank.

The selectable values are the model ids in that CLI output, in that order. The
same stdout always produces the same lines. Show one line per id. A default
marker from the CLI may sit beside an id. The marker is not part of the stored
value. Display names are selectable only when the CLI uses that exact string as
the id.

Do not hardcode ids. Names such as `grok-4.7` illustrate a listing. They are
not a catalog in the skill.

The user may still submit JSON `null`, which keeps today's meaning. The
selected CLI uses its own default model. `null` does not need to appear in the
listing.

### Reasoning-effort ids

Reasoning-effort ids come from that same CLI for one model.

1. Resolve the model id first.
2. If `grok models` output already includes reasoning-effort ids for that model, use those ids from that output. Do not run a second command.
3. If it does not, name the executable and the documented reasoning command before waiting on it. Run the non-interactive form that `grok models --help` on the installed CLI documents for one model's reasoning-effort ids, and pass that model id. Do not invent a flag the help text does not document. After that command returns, show the reasoning ids, the empty menu, or the failure. If that command does not finish, name it, say that it did not finish, and say that `factory/config.json` is unchanged. Write nothing.
4. If the installed CLI documents no reasoning listing, stop before saving a new reasoning id. Tell the user that `grok models --help` documents no reasoning listing, that a new reasoning id cannot be saved, and that `factory/config.json` is unchanged. Accept `cancel` to leave.

The model id is the profile's effective model when that value is a nonempty
string and that string is in the model listing just read. When the effective
model is JSON `null`, use the single model id that `grok models` marks as the
CLI default. If that listing marks no default, or marks more than one, stop.
Tell the user there is no single CLI default, that a new reasoning id cannot
be saved, and that `factory/config.json` is unchanged. Accept `cancel` to leave.

If the effective model string is absent from the model listing, do not query
reasoning under a different id. Name the key being edited and the stored model
string. Say that model is not a listed id, that a listed model has to be saved
before reasoning ids can be listed, and that `factory/config.json` is unchanged.
Accept `cancel` to leave.

Render reasoning-effort ids in CLI order, one line per id, with the same
stability rule as model ids. The existing `clear` control still removes an
optional reasoning assignment. `clear` does not need to appear in the listing.
Explain the inheritance that `clear` will produce before accepting it.

A reasoning command that starts, exits zero, and returns output the host can
read, with zero reasoning ids, is an empty menu. Say the menu is empty. Explain
the inheritance `clear` will produce. Accept only `clear` or `cancel`. Any other
string is absent from that menu. Ask again or accept `cancel`.

### What may be saved

Save a Grok model only when the response is JSON `null` or an id from the
listing just shown. Save a Grok reasoning value only when the response is
`clear` or an id from the reasoning listing just shown. Store that id exactly,
including case.

A shorthand that is not in the listing is explained. The host asks again. It
does not substitute another id. `4.7` is not stored as `grok-4.7` unless the
user submits `grok-4.7` and that id was listed.

Existing input rules stay. Wait for an explicit response. Empty input, cancel,
and an unanswered prompt write nothing. A string equal to a control word such
as `cancel`, `null`, or `clear` still uses one JSON string literal when the
user wants that literal stored, and only if that literal is a listed id.

Invalid input is not replaced with a default. The host explains the constraint
and offers another response or cancellation.

### Failure

If the Grok executable cannot start, the process exits nonzero, or the host
cannot read the output, the host writes nothing and does not guess an id. It
reports the failure and leaves `factory/config.json` byte for byte unchanged.
It does not fall back to accepting any nonempty string for that Grok edit. A
model listing that returns no ids is this same failure. A reasoning command
that exits zero with zero ids is the empty menu above, and that menu is still
open for `clear` or `cancel`.

A failed listing does not change other keys, frozen job files, or checks.

No new timeout setting is added. If the models command does not finish, name
`grok models` or `<stored-executable> models`, say that it did not finish, and
say that `factory/config.json` is unchanged. If the documented reasoning
command does not finish, name that command, say that it did not finish, and
say that `factory/config.json` is unchanged. Write nothing.

Dispatch still passes the stored model and reasoning strings through. It does
not alias, rewrite, or replace them. Existing stored values, including `4.7`,
stay until a later config edit stores a listed id. This operation does not
migrate them and does not edit project config.

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
