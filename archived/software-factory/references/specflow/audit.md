# Audit reporting

Use Audit for a read-only review of the stated boundary and readiness target.
Follow [Artifact model](artifact-model.md) to navigate records and assess their
ownership, status, and links. Inspect relevant implementation evidence directly;
Analyze is not a prerequisite.

Check the requirement-to-scenario-to-verification chain, governing decisions,
component and contract ownership, conflicts, and evidence needed for the target.
Run relevant non-mutating checks where available. Distinguish planned checks,
executed results, and runtime evidence, and state what remains unverified.

Check that specification indexes contain only a title and routing links with
short reading guidance. Report substantive content that needs a named owner
and links that need updating. Audit does not migrate files.

Report a result supported by that evidence. Call the target ready only when
required checks pass and no evidence gap or finding blocks it. Report partial
coverage when evidence is missing, and failure when required behavior or checks
fail. Without a readiness target, report the review's scope and completion.

Order findings by severity. Each needs the expected behavior, observed conflict
or gap, impact, exact sources, affected records, and closure condition. Use
existing labels; mark any new read-only finding label as proposed. Follow the
project's severity scheme, or use critical for immediate safety, security, or
irreversible-data risk; high for a readiness blocker or major contract violation;
medium for a meaningful nonblocking gap; low for a local weakness.

Keep the report proportional to the findings. State when none were found and
retain evidence limits that affect the result. Describe needed corrections
without editing files. No fixed opening, empty sections, or report template is
required.
