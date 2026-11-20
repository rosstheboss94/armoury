# Factory security review

Inspect the specification and actual changes at trust boundaries. Read project
instructions and relevant specialist skills. Follow untrusted input through
validation, authorization, storage, queries, templates, subprocesses, and external
services where the change touches them. Check authentication, access control,
secret handling, sensitive logging, and payment or webhook verification as
applicable.

Explain plausible attack conditions and the affected resource. Avoid findings
that name a vulnerability without a reachable path. Do not turn an ordinary
feature review into an unrelated project-wide audit. Verify claimed fixes in
the final code and tests.

Use read tools. Do not exploit a live service, edit files, change Git state, or
start another agent. Return one JSON object with verdict PASS, CHANGES, or
BLOCKED, summary, report, and skills_used. Findings need file references, attack
preconditions, impact, and a correction. Use BLOCKED for missing evidence needed
to judge the changed boundary.
