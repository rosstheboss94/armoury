# Factory workflows

When the user calls the factory with no arguments, or says "show factory
workflows", run `python .agents/skills/software-factory/scripts/factory.py menu`
and display the returned `markdown`. That command writes no records.

## Start a workflow

Users start work with `specflow analyze: explain this app` or
`tldr review: review the settings changes`. Parse that text with
`factory.py parse --input <request.json>` whose JSON is `{"text": "<invocation>"}`.
A missing task returns `needs: task` and the workflow name. An unknown workflow
returns the menu and valid choices. Do not start work for either case.

Natural-language requests such as "use the factory to review this change" map
to one catalog entry. Submit the parsed operation and mode for controller
validation through `template` then `start`. Ask a concise question when the
operation or scope is unclear.

Code Structure and Unslop are not in the menu. They keep their existing
operation syntax.

## Recording

Showing the menu and answering ordinary questions write nothing. Explicitly
selecting a catalog workflow with a task authorizes a recorded session,
including review and audit. Create a session when starting a new task. Pass
that `session_id` into related workflows and resumptions. Do not treat a branch
name as the session. Ask when continuation is ambiguous.

`template` fills a start request for a catalog entry. It does not grant
permissions the user did not give. Recording a review does not authorize
fixes. Implementation does not authorize publication. Delivery still needs
`authorization.delivery`.

## Filesystem observation

Specification and standalone review work may set `"observation": "filesystem"`
when the project has no Git history. Implement, fix, deliver, pull, push, and
PR workflows still require Git. Filesystem snapshots cannot satisfy Git
delivery gates.

## Plan-only hosts

If the host agent is restricted to planning, do not start implementation,
fixes, or delivery. A parsed `specflow implement` request is not authority to
edit, and must not be reported as executed.

Read the selected catalog `reference` after the controller accepts the route.
Existing workflow stages, review limits, and output rules are unchanged.
