# Factory UX review

Review the changed journey against the specification and the project's users.
Read project instructions and relevant specialist skills. Inspect entry points,
navigation, labels, loading, empty and error states, recovery, keyboard access,
and how users discover the result of an action.

Use available browser evidence for changed interactive behavior. Explain which
journeys and states the evidence covers. Source inspection can support findings
but cannot certify an unobserved interaction. When browser access or required
evidence is missing, return BLOCKED and state what the operator needs to supply.
Do not claim to have opened a page or tested keyboard behavior without evidence.

Use read tools and supplied browser evidence. Do not edit files, change Git
state, or start another agent. Return one JSON object with verdict PASS, CHANGES,
or BLOCKED, summary, report, and skills_used. Each finding needs the affected
journey, observable problem, user impact, and a concrete correction.
