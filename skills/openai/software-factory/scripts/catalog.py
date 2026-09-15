"""Code-owned Specflow and Tldr workflow catalog, menu, and invocation parser."""

from workflow import route
from storage import FactoryError

WORKFLOWS = (
    {
        "operation": "specflow", "mode": "shape",
        "description": "Clarify an idea and optionally write a brief.",
        "reference": "references/specflow/shape.md",
        "modifiers": ("auto",), "edits": True, "delivery": False,
        "git": False, "readonly": False,
    },
    {
        "operation": "specflow", "mode": "analyze",
        "description": "Record how the project works, its requirements, and unknowns.",
        "reference": "references/specflow/analyze.md",
        "modifiers": ("auto",), "edits": True, "delivery": False,
        "git": False, "readonly": False,
    },
    {
        "operation": "specflow", "mode": "build",
        "description": "Draft or update intended-state specifications.",
        "reference": "references/specflow/build.md",
        "modifiers": ("auto",), "edits": True, "delivery": False,
        "git": False, "readonly": False,
    },
    {
        "operation": "specflow", "mode": "probe",
        "description": "Resolve assumptions and apply approved answers to specs.",
        "reference": "references/specflow/probe.md",
        "modifiers": ("auto",), "edits": True, "delivery": False,
        "git": False, "readonly": False,
    },
    {
        "operation": "specflow", "mode": "audit",
        "description": "Check specification consistency without changing files.",
        "reference": "references/specflow/audit.md",
        "modifiers": ("auto",), "edits": False, "delivery": False,
        "git": False, "readonly": True,
    },
    {
        "operation": "specflow", "mode": "implement",
        "description": "Implement a feature or bug fix in the project.",
        "reference": "references/specflow/implement.md",
        "modifiers": ("auto", "tldr"), "edits": True, "delivery": False,
        "git": True, "readonly": False,
    },
    {
        "operation": "tldr", "mode": "pull",
        "description": "Fast-forward the current branch from its remote.",
        "reference": "references/tldr/delivery.md",
        "modifiers": (), "edits": False, "delivery": False,
        "git": True, "readonly": False,
    },
    {
        "operation": "tldr", "mode": "push",
        "description": "Push the current branch to its remote.",
        "reference": "references/tldr/delivery.md",
        "modifiers": (), "edits": False, "delivery": False,
        "git": True, "readonly": False,
    },
    {
        "operation": "tldr", "mode": "pr",
        "description": "Create or update a pull request without delivery review.",
        "reference": "references/tldr/delivery.md",
        "modifiers": (), "edits": False, "delivery": False,
        "git": True, "readonly": False,
    },
    {
        "operation": "tldr", "mode": "review",
        "description": "Review a change adversarially without editing files.",
        "reference": "references/tldr/review.md",
        "modifiers": (), "edits": False, "delivery": False,
        "git": False, "readonly": True,
    },
    {
        "operation": "tldr", "mode": "fix",
        "description": "Apply authorized review fixes with a bounded review budget.",
        "reference": "references/tldr/review.md",
        "modifiers": (), "edits": True, "delivery": False,
        "git": True, "readonly": False,
    },
    {
        "operation": "tldr", "mode": "deliver",
        "description": "Implement as needed and deliver a pull request.",
        "reference": "references/tldr/delivery.md",
        "modifiers": (), "edits": True, "delivery": True,
        "git": True, "readonly": False,
    },
)

MENU_TRIGGERS = {"", "software-factory", "show factory workflows", "factory workflows", "menu"}


def invocation(entry):
    return entry["operation"] + " " + entry["mode"]


def find(operation, mode):
    return next((entry for entry in WORKFLOWS if entry["operation"] == operation and entry["mode"] == mode), None)


def workflows():
    return [{**entry, "invocation": invocation(entry)} for entry in WORKFLOWS]


def menu():
    rows = [f"| `{invocation(entry)}` | {entry['description']} |" for entry in WORKFLOWS]
    markdown = "\n".join([
        "| Workflow | Use it to |",
        "| --- | --- |",
        *rows,
        "",
        "Start work with `specflow analyze: explain this app` or `tldr review: review the settings changes`.",
        "Code Structure and Unslop stay available through their existing operation syntax.",
    ])
    return {"markdown": markdown, "workflows": workflows()}


def _unknown():
    return {"error": "Unknown workflow.", "menu": menu()["markdown"],
            "workflows": [invocation(entry) for entry in WORKFLOWS]}


def parse(text):
    raw = text.strip() if isinstance(text, str) else ""
    if raw.lower() in MENU_TRIGGERS:
        return menu()
    rest = raw
    lowered = rest.lower()
    if lowered.startswith("software-factory "):
        rest = rest[17:].strip()
    if ":" in rest:
        head, task = rest.split(":", 1)
        head, task = head.strip(), task.strip()
    else:
        head, task = rest.strip(), ""
    tokens = head.split()
    if not tokens:
        return menu()
    operation = tokens[0].lower()
    if operation not in ("specflow", "tldr"):
        return _unknown()
    modifiers, mode = [], None
    for token in tokens[1:]:
        value = token.lower()
        if value in ("auto", "tldr", "tdlr"):
            modifiers.append(value)
        elif mode is None:
            mode = value
        else:
            return _unknown()
    if mode is None:
        return {"error": "Choose a workflow mode.", "menu": menu()["markdown"], "operation": operation}
    entry = find(operation, mode)
    if entry is None:
        return _unknown()
    try:
        selected = route({"operation": operation, "mode": mode, "modifiers": modifiers,
                          "task": task or "pending"})
    except FactoryError as exc:
        return {"error": str(exc), "menu": menu()["markdown"], "workflows": [invocation(item) for item in WORKFLOWS]}
    if not task:
        return {"error": "A scoped task is required.", "operation": operation, "mode": mode,
                "modifiers": selected["modifiers"], "needs": "task", "workflow": invocation(entry)}
    return {**selected, "task": task, "selected": True, "workflow": invocation(entry),
            "catalog": {**entry, "invocation": invocation(entry)}}


def template(payload):
    if not isinstance(payload, dict):
        raise FactoryError("Command input must be a JSON object.")
    operation, mode = payload.get("operation"), payload.get("mode")
    entry = find(operation, mode)
    if entry is None:
        raise FactoryError("Unknown workflow.")
    modifiers = payload.get("modifiers", [])
    selected = route({"operation": operation, "mode": mode, "modifiers": modifiers,
                      "task": payload.get("task") or "Scoped factory task"})
    authorization = {"source": payload.get("source") or "User selected " + invocation(entry)}
    if entry["edits"] or selected["mode"] in ("implement", "refactor", "fix", "deliver", "build", "shape", "analyze", "probe"):
        authorization["edits"] = True
    if selected["delivery"] or entry["delivery"]:
        authorization["delivery"] = True
    if selected["mode"] in ("pull", "push", "pr"):
        authorization[selected["mode"]] = True
    request = {"operation": operation, "mode": mode, "modifiers": selected["modifiers"],
               "task": payload.get("task", ""), "selected": True,
               "worktree": payload.get("worktree", ""),
               "authorization": authorization, "required_checks": payload.get("required_checks", []),
               "reference": entry["reference"]}
    if payload.get("task"):
        request["task"] = payload["task"]
    if not request["required_checks"]:
        request["no_checks_reason"] = payload.get("no_checks_reason", "")
    if payload.get("observation"):
        request["observation"] = payload["observation"]
    elif not entry["git"]:
        request["observation"] = "git"
    if payload.get("session_id"):
        request["session_id"] = payload["session_id"]
    if selected["readonly"]:
        request["save_authorized"] = True
    return request
