"""Read registered factory records without invoking the controller or Git."""

import hashlib
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))
from storage import FactoryError, read_json, run_path
from observation import contained
from registration import entries, removed_ids


class Records:
    def __init__(self, host, configuration=None, single_factory=None, registration=None):
        self.host = Path(host).resolve()
        self.configuration = configuration
        self.single_factory = Path(single_factory).resolve() if single_factory else None
        self.registration = registration

    def registry_directory(self):
        if self.registration is not None:
            return self.registration.registry
        return Path(self.host) / "state/dashboard"

    def sources(self):
        if self.registration is not None and self.registration.directory is not None:
            directory = self.registration.directory
            previous = self.configuration["projects"] if self.configuration else []
            merged = {p["id"]: p for p in previous}
            for entry in entries(self.registration.registry):
                try:
                    mapped = str(directory.resolve(entry["factory"]))
                except FactoryError:
                    mapped = next((p.get("mount") for p in previous if p["id"] == entry["id"] and p["factory"] == entry["factory"]), None)
                    if self.configuration is None and self.single_factory is None:
                        mapped = entry["factory"]
                merged[entry["id"]] = {**entry, "mount": mapped}
            if self.single_factory is not None:
                identity = self.single_factory / "state/project.json"
                if identity.exists():
                    entry = read_json(identity)
                    if not merged.get(entry["id"], {}).get("mount"):
                        merged[entry["id"]] = {**entry, "mount": str(self.single_factory)}
            return list(merged.values())
        if self.single_factory is not None:
            path = self.single_factory / "state/project.json"
            if not path.exists():
                return []
            return [{**read_json(path), "mount": str(self.single_factory)}]
        if self.configuration is not None:
            return self.configuration["projects"]
        path = self.host / "state/dashboard/projects.json"
        return read_json(path) if path.exists() else []

    def registry(self):
        hidden = removed_ids(self.registry_directory())
        return [p for p in self.sources() if p["id"] not in hidden]

    def root(self, identifier):
        entry = next((p for p in self.registry() if p["id"] == identifier), None)
        if not entry:
            raise FactoryError("Project is not registered.")
        mapped = self.configuration is not None or self.single_factory is not None or (self.registration is not None and self.registration.directory is not None)
        if mapped and not entry.get("mount"):
            raise FactoryError("Project is unavailable. Rerun the launcher when its directory is accessible.")
        root = Path(entry["mount"] if mapped else entry["factory"]).resolve()
        if not root.is_dir():
            raise FactoryError("Project is unavailable.")
        for directory in ("state", "specs", "state/snapshots", "state/sessions"):
            if not (root / directory).resolve().is_relative_to(root / directory):
                raise FactoryError("Project record directories must stay inside the factory.")
        identity = read_json(root / "state/project.json")
        if identity["id"] != identifier:
            raise FactoryError("Project identity changed.")
        return root

    def workflows(self, identifier):
        root = self.root(identifier)
        runs, errors = [], []
        for path in sorted((root / "state").glob("*/run.json")):
            try:
                if not path.resolve().is_relative_to(root / "state"):
                    raise FactoryError("Linked record leaves the factory state.")
                run = read_json(path)
                if not isinstance(run, dict) or run.get("id") != path.parent.name:
                    raise FactoryError("Malformed workflow identity.")
                run_path(root, run["id"])
                if not isinstance(run.get("request"), dict) or not isinstance(run.get("history"), list):
                    raise FactoryError("Malformed workflow record.")
                if not isinstance(run.get("attempts", []), list) or not isinstance(run.get("events", []), list):
                    raise FactoryError("Malformed observation record.")
                if not isinstance(run["request"].get("task"), str) or not isinstance(run.get("phase"), str):
                    raise FactoryError("Malformed workflow task or phase.")
                for field in ("attempts", "events", "checks", "history"):
                    if not isinstance(run.get(field, []), list) or any(not isinstance(item, dict) for item in run.get(field, [])):
                        raise FactoryError("Malformed workflow evidence.")
                if any(not all(key in a for key in ("id", "phase", "role", "round")) for a in run.get("attempts", [])):
                    raise FactoryError("Malformed phase attempt.")
                if any(not all(isinstance(a[key], str) for key in ("id", "phase", "role")) for a in run.get("attempts", [])):
                    raise FactoryError("Malformed phase identity.")
                if any(not all(key in e for key in ("id", "kind")) for e in run.get("events", [])):
                    raise FactoryError("Malformed event.")
                if any(not isinstance(run.get(key, ""), str) for key in ("created_at", "updated_at")):
                    raise FactoryError("Malformed workflow timestamp.")
                if not isinstance(run.get("identity", {}), dict) or not isinstance(run.get("route", {}), dict):
                    raise FactoryError("Malformed workflow metadata.")
                if "session_id" in run and not isinstance(run["session_id"], str):
                    raise FactoryError("Malformed workflow session.")
                if run.get("observation_version") and run.get("project_id") != identifier:
                    raise FactoryError("Workflow project identity does not match.")
                for event in run.get("events", []):
                    if event["kind"] == "context_supplied" and (not all(isinstance(event.get(key), str) for key in ("file", "hash", "role", "at")) or not re.fullmatch(r"[a-f0-9]{64}", event["hash"])):
                        raise FactoryError("Malformed captured context event.")
                run["legacy"] = not bool(run.get("observation_version"))
                run.setdefault("session_id", "legacy-" + run["id"])
                runs.append(run)
            except (FactoryError, ValueError, TypeError, KeyError) as exc:
                errors.append({"file": path.parent.name, "error": str(exc)})
        return {"items": sorted(runs, key=lambda r: (r.get("created_at", ""), r["id"])), "errors": errors}

    def workflow(self, project_id, identifier):
        run_path(self.root(project_id), identifier)
        run = next((r for r in self.workflows(project_id)["items"] if r["id"] == identifier), None)
        if run is None:
            raise FactoryError("Workflow is missing or malformed.")
        return run

    def sessions(self, identifier):
        root = self.root(identifier)
        result = self.workflows(identifier)
        sessions = {}
        for path in sorted((root / "state/sessions").glob("*.json")):
            try:
                record = read_json(contained(root / "state/sessions", path.name))
                if not isinstance(record, dict) or record["id"] + ".json" != path.name or not isinstance(record.get("task"), str):
                    raise FactoryError("Malformed session.")
                if not isinstance(record.get("created_at", ""), str) or record.get("project_id") != identifier:
                    raise FactoryError("Malformed session metadata.")
                sessions[record["id"]] = {**record, "workflows": []}
            except (FactoryError, KeyError, TypeError) as exc:
                result["errors"].append({"file": path.name, "error": str(exc)})
        for run in result["items"]:
            sid = run["session_id"]
            sessions.setdefault(sid, {"id": sid, "task": run["request"].get("task", "Unavailable"),
                                      "goal": run["request"].get("task", "Unavailable"),
                                      "legacy": run["legacy"], "workflows": []})["workflows"].append(run)
        for item in sessions.values():
            runs = item["workflows"]
            item["status"] = "blocked" if any(r.get("blocker") for r in runs) else "open" if any(r.get("phase") != "done" for r in runs) else "complete" if runs else "empty"
            item["updated_at"] = max((r.get("updated_at", "") for r in runs), default="") or item.get("created_at")
        return {"items": sorted(sessions.values(), key=lambda s: (s.get("created_at", ""), s["id"])), "errors": result["errors"]}

    def projects(self):
        items = []
        for entry in self.registry():
            try:
                sessions = self.sessions(entry["id"])
                runs = [r for s in sessions["items"] for r in s["workflows"]]
                items.append({**entry, "available": True,
                              "active_sessions": sum(s["status"] == "open" for s in sessions["items"]),
                              "blocked_workflows": sum(bool(r.get("blocker")) for r in runs),
                              "updated_at": max((r.get("updated_at", "") for r in runs), default=None),
                              "errors": sessions["errors"]})
            except (FactoryError, OSError, KeyError, TypeError, ValueError) as exc:
                items.append({**entry, "available": False, "error": str(exc)})
        return {"items": items}

    def phase(self, project_id, run_id, attempt_id):
        run = self.workflow(project_id, run_id)
        attempt = next((a for a in run.get("attempts", []) if a["id"] == attempt_id), None)
        if attempt is None:
            raise FactoryError("Phase attempt is unavailable.")
        events = [e for e in run.get("events", []) if e.get("attempt_id") == attempt_id]
        return {**attempt, "events": events, "specs": [e for e in events if e["kind"] == "context_supplied"]}

    def specs(self, project_id):
        root = self.root(project_id) / "specs"
        return {"items": [p.relative_to(root).as_posix() for p in sorted(root.rglob("*.md"))
                          if p.is_file() and p.resolve().is_relative_to(root.resolve())]}

    def current_spec(self, project_id, name):
        path = contained(self.root(project_id) / "specs", name)
        if path.suffix.lower() != ".md":
            raise FactoryError("Only Markdown specifications are available.")
        content = path.read_text(encoding="utf-8")
        return {"file": name, "content": content, "hash": hashlib.sha256(content.encode()).hexdigest()}

    def context(self, project_id, run_id, event_id):
        run = self.workflow(project_id, run_id)
        event = next((e for e in run.get("events", []) if e["id"] == event_id and e["kind"] == "context_supplied"), None)
        if not event or not re.fullmatch(r"[a-f0-9]{64}", event["hash"]):
            raise FactoryError("Captured context is unavailable.")
        snapshot = read_json(contained(self.root(project_id) / "state/snapshots", event["hash"] + ".json"))
        if hashlib.sha256(snapshot["content"].encode()).hexdigest() != event["hash"]:
            raise FactoryError("Snapshot integrity check failed.")
        try:
            current = self.current_spec(project_id, event["file"])
        except (FactoryError, OSError):
            current = None
        return {**event, "content": snapshot["content"], "current": current,
                "changed": current is None or current["hash"] != event["hash"]}
