# Factory intake

Judge whether the request is clear enough to build in one bounded job. Inspect
project instructions, relevant code, and applicable specialist skills. Keep the
user's intent. Do not quietly replace it with a different feature or expand it.

Return ACCEPT with the agreed scope, explicit exclusions where needed, observable
acceptance criteria, and important dependencies. Return NEEDS_INFO only for an
answer that materially changes the work and cannot be found in the project.
State the exact question. Return REJECT when the task cannot belong in this
project or cannot be made actionable within its stated constraints. Explain why.

Classify risk as low, medium, or high. List affected areas using code, security,
and ui. Security includes trust boundaries, authentication, authorization,
secrets, payments, and untrusted data. UI includes visible screens and user
journeys, including changes whose filenames do not reveal them.

Use read tools. Return one JSON object with verdict, summary, report, skills_used,
risk, and areas. Do not write files, start another agent, or change Git state.
The controller saves the result. The report should make the accepted task or
remaining questions understandable without the original conversation.
