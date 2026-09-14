"""Project identity, feature sessions, and recorded context. Call writers under locked()."""

import hashlib
import uuid
from datetime import datetime, timezone
from pathlib import Path

from factory_paths import project_directory
from storage import FactoryError, read_json, write_json


def now():
    return datetime.now(timezone.utc).isoformat()


def contained(directory, name):
    directory = Path(directory).resolve()
    path = (directory / name).resolve()
    if not path.is_relative_to(directory) or path == directory:
        raise FactoryError("Requested file must stay within its record directory.")
    return path


def project(root):
    root = Path(root).resolve()
    path = root / "state/project.json"
    if path.exists():
        return read_json(path)
    record = {"version": 1, "id": str(uuid.uuid4()), "name": project_directory(root).name,
              "factory": str(root), "created_at": now()}
    write_json(path, record)
    return record


def session(root, payload):
    identifier = payload.get("session_id")
    if identifier:
        try:
            identifier = str(uuid.UUID(identifier))
        except ValueError as exc:
            raise FactoryError("Invalid session identifier.") from exc
        return read_json(Path(root) / "state/sessions" / (identifier + ".json"))
    if not payload.get("task"):
        raise FactoryError("A session needs a task.")
    record = {"version": 1, "id": str(uuid.uuid4()), "project_id": project(root)["id"],
              "task": payload["task"], "goal": payload.get("goal", payload["task"]), "created_at": now()}
    write_json(Path(root) / "state/sessions" / (record["id"] + ".json"), record)
    return record


def attach(root, run):
    run["project_id"] = project(root)["id"]
    run["session_id"] = session(root, run["request"])["id"]
    run["observation_version"] = 1
    run["created_at"] = now()
    run["events"] = []
    run["attempts"] = []
    run["observed_history"] = len(run["history"])
    if run["history"]:
        run["historical_observation_unavailable"] = True


def event(run, kind, **data):
    item = {"version": 1, "id": str(uuid.uuid4()), "at": now(), "kind": kind,
            "attempt_id": run.get("active_attempt"), **data}
    run["events"].append(item)
    run["updated_at"] = item["at"]


def observe(run):
    """Capture transitions at each atomic save without reconstructing old timing."""
    if not run.get("observation_version"):
        return
    if run.get("pending") != run.get("observed_pending"):
        event(run, "controller_operation", operation=run.get("pending"), status="pending" if run.get("pending") else "settled")
        import copy
        run["observed_pending"] = copy.deepcopy(run.get("pending"))
    attempts = run["attempts"]
    active = next((a for a in attempts if a["id"] == run.get("active_attempt")), None)
    changed = active and (active["phase"], active["round"]) != (run["phase"], run["round"])
    if active and (changed or run.get("blocker")) and not active.get("ended_at"):
        active.update(ended_at=now(), status="blocked" if run.get("blocker") else "complete")
        event(run, "phase_finished", status=active["status"])
    if run["phase"] != "done" and (active is None or changed):
        role = "reviewer" if run["phase"] == "review" else "editor" if run["phase"] == "work" else "controller"
        roles = run["request"].get("roles", {})
        active = {"id": str(uuid.uuid4()), "phase": run["phase"], "round": run["round"],
                  "role": role, "started_at": now(), "ended_at": None, "status": "started",
                  "requested_model": roles.get(role + "_requested"), "observed_model": roles.get(role + "_observed"),
                  "assignment": {"task": run["request"]["task"], "checks": run["request"]["required_checks"],
                                 "authorization": run["request"]["authorization"]}}
        attempts.append(active)
        run["active_attempt"] = active["id"]
        event(run, "phase_started", assignment=active["assignment"])
    seen = run.get("observed_history", 0)
    for item in run["history"][seen:]:
        # Results refer to the attempt that preceded a transition.
        previous = attempts[-2] if changed and len(attempts) > 1 and run["phase"] != "done" else active
        event(run, "result" if "status" in item else "controller_operation",
              attempt_id=previous["id"] if previous else None, evidence=item)
    run["observed_history"] = len(run["history"])


def resume(run):
    if not run.get("observation_version") or run["phase"] == "done":
        return
    active = next((a for a in run["attempts"] if a["id"] == run.get("active_attempt")), None)
    if active and not active.get("ended_at"):
        # No last-seen timestamp is a reliable interruption time.
        active["status"] = "interrupted"
        active["interruption_observed_at"] = now()
        event(run, "interruption_observed")
    run["active_attempt"] = None


def context_read(root, run, payload):
    if not run.get("active_attempt") or run["phase"] == "done":
        raise FactoryError("Context capture requires a monitored phase attempt.")
    role = payload.get("role")
    if not isinstance(role, str) or not role.strip():
        raise FactoryError("Name the consuming role.")
    root = Path(root).resolve()
    if not (root / "specs").resolve().is_relative_to(root) or not (root / "state/snapshots").resolve().is_relative_to(root):
        raise FactoryError("Specification and snapshot directories must stay inside the factory.")
    path = contained(root / "specs", payload["file"])
    if path.suffix.lower() != ".md":
        raise FactoryError("Context files must be Markdown specifications.")
    content = path.read_text(encoding="utf-8")
    digest = hashlib.sha256(content.encode("utf-8")).hexdigest()
    snapshot = contained(Path(root) / "state/snapshots", digest + ".json")
    if not snapshot.exists():
        write_json(snapshot, {"hash": digest, "content": content})
    elif read_json(snapshot).get("content") != content:
        raise FactoryError("Existing snapshot failed its content integrity check.")
    event(run, "context_supplied", file=path.relative_to(Path(root).resolve() / "specs").as_posix(),
          hash=digest, role=role, evidence_label="Context supplied to the agent")
    return {"content": content, **run["events"][-1]}
