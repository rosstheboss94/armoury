"""Workflow transitions for the current agent session."""

import copy
import uuid

from git_ops import identity, snapshot
from storage import FactoryError


MODES = {
    "specflow": {"shape", "analyze", "build", "probe", "audit", "implement"},
    "code-structure": {"design", "implement", "refactor", "review"},
    "tldr": {"pull", "push", "pr", "review", "fix", "deliver"},
    "unslop": {"edit"},
}


def route(request):
    operation = request.get("operation")
    mode = request.get("mode")
    if operation not in MODES or mode not in MODES[operation]:
        raise FactoryError("Choose an existing factory operation and mode.")
    if not isinstance(request.get("task"), str) or not request["task"].strip():
        raise FactoryError("A scoped task is required.")
    modifiers = request.get("modifiers", [])
    if not isinstance(modifiers, list) or any(m not in ("auto", "tldr", "tdlr") for m in modifiers):
        raise FactoryError("Modifiers must be auto, tldr, or tdlr.")
    modifiers = list(dict.fromkeys("tldr" if m == "tdlr" else m for m in modifiers))
    if modifiers and operation != "specflow":
        raise FactoryError("Modifiers apply to Specflow requests.")
    if "tldr" in modifiers and mode != "implement":
        raise FactoryError("The delivery modifier applies only to Implement.")
    delivery = operation == "tldr" and mode == "deliver" or "tldr" in modifiers
    readonly = mode in ("design", "audit", "review") or operation == "unslop"
    ref = "references/unslop.md" if operation == "unslop" else f"references/{operation}/overview.md"
    return {"operation": operation, "mode": mode, "modifiers": modifiers,
            "delivery": delivery, "readonly": readonly, "reference": ref}


def start(request):
    selected = route(request)
    if selected["readonly"] and request.get("save_authorized") is not True:
        raise FactoryError("Read-only work stays in chat. Use route without starting a saved run.")
    request = copy.deepcopy(request)
    request["modifiers"] = selected["modifiers"]
    authority = request.get("authorization", {})
    if not isinstance(authority, dict) or not authority.get("source"):
        raise FactoryError("Record the user request supplying authorization.")
    if selected["delivery"] and authority.get("delivery") is not True:
        raise FactoryError("Delivery requires explicit delivery authorization.")
    if not selected["readonly"] and selected["mode"] not in ("pull", "push", "pr") and authority.get("edits") is not True:
        raise FactoryError("Record authorization for in-scope edits.")
    if not isinstance(request.get("required_checks"), list):
        raise FactoryError("List required local check names, or an empty list with a no_checks_reason.")
    if not request["required_checks"] and not request.get("no_checks_reason"):
        raise FactoryError("Explain why no local checks are required.")
    actual = identity(request["worktree"])
    if request.get("branch") != actual["branch"]:
        raise FactoryError("The requested branch does not match the feature worktree.")
    phase = "review" if selected["mode"] == "review" else "work"
    if selected["mode"] in ("pull", "push", "pr"):
        phase = "git"
    return {"version": 1, "id": str(uuid.uuid4()), "request": request,
            "route": selected, "identity": actual, "phase": phase,
            "round": 0, "revision": 0, "history": [], "checks": [],
            "findings": [], "gate": False, "publication_eligible": False,
            "published": False, "blocker": "", "pending": None,
            "initial": snapshot(actual["worktree"], request["base"])}


def current(run):
    actual = identity(run["identity"]["worktree"])
    if actual != run["identity"]:
        raise FactoryError("Worktree path or branch changed; reconcile identity before continuing.")
    return snapshot(actual["worktree"], run["request"]["base"])


def assignment(run):
    observed = current(run)
    return {"run_id": run["id"], "revision": run["revision"], "phase": run["phase"],
            "session_id": run.get("session_id"), "attempt_id": run.get("active_attempt"),
            "round": run["round"], "snapshot": observed, "scope": run["request"]["task"],
            "authorization": run["request"]["authorization"],
            "modifiers": run["request"]["modifiers"], "findings": run["findings"],
            "checks_required": run["request"]["required_checks"],
            "worktree": run["identity"]["worktree"], "blocker": run["blocker"],
            "pending": run["pending"], "roles": run["request"].get("roles", {}),
            **{key: run.get(key) for key in ("gate", "score", "reviewed", "publication_eligible", "ready", "github", "pr")}}


def validate_checks(run, result):
    checks = result.get("checks")
    if not isinstance(checks, list):
        raise FactoryError("Results must include check evidence, even when the list is empty.")
    by_name = {}
    for check in checks:
        if not isinstance(check, dict) or not check.get("name") or check.get("status") not in ("pass", "fail", "pending", "unavailable") or not check.get("evidence"):
            raise FactoryError("Each check needs name, status, and evidence.")
        if check["name"] in by_name:
            raise FactoryError("Duplicate check evidence.")
        by_name[check["name"]] = check
    return all(by_name.get(name, {}).get("status") == "pass" for name in run["request"]["required_checks"])


def accept(run, result):
    if result.get("run_id") != run["id"] or result.get("revision") != run["revision"] or result.get("phase") != run["phase"]:
        raise FactoryError("Result does not match the current assignment.")
    if run["phase"] not in ("work", "review") or run["pending"]:
        raise FactoryError("This phase needs a controller action, not an agent result.")
    if not result.get("summary"):
        raise FactoryError("A result summary is required.")
    result = copy.deepcopy(result)
    result["round"] = run["round"]
    observed = current(run)
    if result.get("snapshot") != observed:
        raise FactoryError("Result evidence does not match the current head, base, or working diff.")
    if result.get("status") not in ("complete", "blocked"):
        raise FactoryError("Result status must be complete or blocked.")
    if result["status"] == "blocked":
        run["blocker"] = result["summary"]
        run["history"].append(copy.deepcopy(result))
        run["revision"] += 1
        return run
    passing_checks = validate_checks(run, result)
    if run["phase"] == "work":
        if run["request"]["authorization"].get("edits") is not True and not run["route"]["readonly"]:
            raise FactoryError("Edit authorization was revoked.")
        if run["round"] and result.get("progress") is not True:
            run["blocker"] = "Fix round made no verifiable progress. Retain the run for follow-up."
            run["history"].append(copy.deepcopy(result))
            run["revision"] += 1
            return run
        run["checks"] = result["checks"]
        if run["route"]["delivery"]:
            run["phase"] = "commit"
        elif run["route"]["mode"] == "fix":
            run["phase"] = "review"
        else:
            run["phase"] = "done"
            run["gate"] = passing_checks
    else:
        score = result.get("score")
        if type(score) is not int or not 1 <= score <= 5:
            raise FactoryError("Review score must be an integer from 1 to 5.")
        roles = run["request"].get("roles", {})
        fallback = roles.get("fallback")
        if not result.get("reviewer") or result["reviewer"] != roles.get("reviewer"):
            raise FactoryError("Review must identify the assigned reviewer.")
        if roles.get("editor") == roles.get("reviewer") and not fallback:
            raise FactoryError("The editor cannot act as its own independent reviewer.")
        if not result.get("evidence_limits"):
            raise FactoryError("Review must state evidence limits, including when none are known.")
        findings = result.get("findings")
        if not isinstance(findings, list):
            raise FactoryError("Review must return findings, even when empty.")
        identifiers = set()
        for finding in findings:
            fields = ("id", "severity", "location", "expected", "observed", "impact", "evidence", "closure", "disposition")
            if not all(finding.get(key) for key in fields):
                raise FactoryError("A finding is missing its evidence or closure condition.")
            if finding["id"] in identifiers or finding["severity"] not in ("critical", "high", "medium", "low") or finding["disposition"] not in ("open", "fixed", "rejected", "deferred"):
                raise FactoryError("Invalid finding identifier, severity, or disposition.")
            identifiers.add(finding["id"])
        if {f["id"] for f in run["findings"]} - identifiers:
            raise FactoryError("Retain prior finding identifiers with their current dispositions.")
        blocking = any(f["severity"] in ("critical", "high") and f["disposition"] not in ("fixed", "rejected") for f in findings)
        run["findings"] = findings
        run["checks"] = result["checks"]
        run["score"] = score
        run["reviewed"] = observed
        run["gate"] = score >= 4 and not blocking and passing_checks and (observed["clean"] or not run["route"]["delivery"])
        if run["route"]["delivery"]:
            run["publication_eligible"] = run["gate"] or run["round"] == 3
            run["phase"] = "publish" if run["publication_eligible"] else "fix"
        elif run["route"]["mode"] == "fix" and not run["gate"] and run["round"] < 3:
            run["phase"] = "fix"
        else:
            run["phase"] = "done"
    run["blocker"] = ""
    run["history"].append(copy.deepcopy(result))
    run["revision"] += 1
    return run


def begin_fix(run):
    if run["phase"] != "fix" or run["round"] >= 3 or run["pending"]:
        raise FactoryError("No further automatic fix round is available.")
    if run["request"]["authorization"].get("edits") is not True:
        raise FactoryError("Fixes are not authorized.")
    run["round"] += 1
    run["phase"] = "work"
    run["revision"] += 1
    run["history"].append({"event": "round_started", "round": run["round"]})


def reconcile(run):
    observed = current(run)
    if "reviewed" not in run or observed == run["reviewed"]:
        return
    if run["pending"] and run["pending"]["action"] == "publish":
        raise FactoryError("Reconcile pending publication through the publish command before reviewing changed evidence.")
    if run["phase"] in ("work", "commit", "review", "fix") and not run["published"]:
        # The current round has not completed. Resume it, never consume another.
        run["gate"] = False
        return
    run["gate"] = False
    run["history"].append({"event": "review_invalidated", "snapshot": observed})
    if run["published"] or not (run["route"]["delivery"] or run["route"]["mode"] == "fix"):
        run["phase"] = "done"
        run["blocker"] = "Published evidence changed; report follow-up without restarting the loop."
    elif run["round"] < 3:
        run["round"] += 1
        run["phase"] = "review"
        run["publication_eligible"] = False
    else:
        run["phase"] = "publish"
        run["publication_eligible"] = True
        run["blocker"] = "Review rounds exhausted; publication must disclose changed or unreviewed content."
    run["revision"] += 1


def restrict(run, changes):
    authority = run["request"]["authorization"]
    for key, value in changes.get("authorization", {}).items():
        if key == "source" or value is not False:
            raise FactoryError("Restriction may only revoke permissions.")
        authority[key] = False
    if changes.get("revoke_auto"):
        run["request"]["modifiers"] = [m for m in run["request"]["modifiers"] if m != "auto"]
    run["history"].append({"event": "restriction", "changes": changes})
    run["revision"] += 1


def import_legacy(root, payload):
    """Reconstruct a saved continuation without manufacturing a new review budget."""
    from pathlib import Path
    from storage import read_json
    root = Path(root).resolve()
    sources = payload.get("legacy_files", [])
    if not sources or not payload.get("reconstruction_evidence"):
        raise FactoryError("Legacy continuation requires source files and reconstruction evidence.")
    resolved = []
    for name in sources:
        path = (root / name).resolve()
        if not path.is_relative_to(root / "state/legacy") or not path.is_file():
            raise FactoryError("Legacy sources must be preserved files under state/legacy.")
        resolved.append(str(path.relative_to(root)))
    for existing in (root / "state").glob("*/run.json"):
        if set(read_json(existing).get("legacy_sources", [])) & set(resolved):
            raise FactoryError("These legacy records already have a continuation; resume that run.")
    number = payload.get("round")
    phase = payload.get("phase")
    if type(number) is not int or not 0 <= number <= 3 or phase not in ("work", "commit", "review", "fix", "publish", "github", "done"):
        raise FactoryError("Reconstruct the existing round and phase explicitly.")
    history = payload.get("history")
    if not isinstance(history, list) or not history or any(not isinstance(item, dict) for item in history):
        raise FactoryError("Preserve legacy review history and evidence gaps explicitly.")
    run = start(payload["request"])
    run.update(legacy_sources=resolved, round=number, phase=phase, history=history,
               findings=payload.get("findings", []), blocker="Legacy review evidence needs reconciliation.")
    if payload.get("published") is True or phase == "github":
        run.update(published=True, phase="done", ready=False, pr=payload.get("pr"),
                   blocker="Published legacy work requires follow-up; do not restart delivery.")
        run["history"].append({"event": "legacy_import", "evidence": payload["reconstruction_evidence"]})
        return run
    # A legacy pass cannot certify the present files without current review evidence.
    if phase in ("publish", "github", "done"):
        if number < 3:
            run["round"] += 1
            run["phase"] = "review"
        else:
            run["phase"] = "publish"
            run["publication_eligible"] = bool(run["route"]["delivery"])
            run["reviewed"] = current(run)
    run["history"].append({"event": "legacy_import", "evidence": payload["reconstruction_evidence"]})
    return run
