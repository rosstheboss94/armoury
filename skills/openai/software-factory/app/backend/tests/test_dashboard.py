"""Exercise project isolation, immutable context, timing, and read-only HTTP."""

import copy
import json
import socket
import sys
import uuid
import subprocess
from pathlib import Path
from unittest.mock import patch

import pytest
from fastapi.testclient import TestClient

SOURCE = Path(__file__).resolve().parents[3]
sys.path[:0] = [str(SOURCE / "scripts"), str(SOURCE / "app/backend")]
import observation
import dashboard
import factory
import install
import workspace
from storage import locked, save, read_json, write_json, FactoryError
from records import Records
from server import create_app


def new_run(root, sid=None):
    request = {"task": "Build dashboard", "required_checks": ["unit"], "authorization": {"edits": True},
               "roles": {"editor": "agent", "editor_requested": "requested", "editor_observed": "unknown"}}
    if sid:
        request["session_id"] = sid
    run = {"id": str(uuid.uuid4()), "request": request, "phase": "work", "round": 0,
           "history": [], "checks": [], "blocker": "", "pending": None, "route": {"mode": "implement"},
           "identity": {"branch": "main"}, "revision": 0}
    with locked(root):
        observation.attach(root, run)
        save(root, run)
    return run


@pytest.fixture
def factories(tmp_path):
    roots = [tmp_path / name / ".agents/skills/software-factory" for name in ("one", "two")]
    for root in roots:
        root.mkdir(parents=True)
        (root / "SKILL.md").write_text("test")
        (root / "specs").mkdir()
    dashboard.register(roots[0], roots)
    return roots


def test_sessions_projects_and_legacy(factories):
    one, two = factories
    a = new_run(one)
    b = new_run(one, a["session_id"])
    c = new_run(one)
    d = new_run(two)
    legacy = copy.deepcopy(c)
    legacy["id"] = str(uuid.uuid4())
    for key in ("observation_version", "session_id", "events", "attempts", "created_at", "updated_at"):
        legacy.pop(key, None)
    write_json(one / "state" / legacy["id"] / "run.json", legacy)
    records = Records(one)
    groups = records.sessions(a["project_id"])["items"]
    assert len(groups) == 3
    assert len(next(s for s in groups if s["id"] == a["session_id"])["workflows"]) == 2
    old = next(s for s in groups if s.get("legacy"))
    assert old["id"] == "legacy-" + legacy["id"]
    assert not old["workflows"][0].get("created_at")
    with pytest.raises(FactoryError):
        records.workflow(a["project_id"], d["id"])
    dashboard.register(one, [one, one.parent.parent.parent])
    assert len(records.projects()["items"]) == 2


def test_snapshot_change_delete_and_escape(factories, tmp_path):
    root = factories[0]
    run = new_run(root)
    spec = root / "specs/design.md"
    spec.write_text("# Original", encoding="utf-8")
    with locked(root):
        captured = observation.context_read(root, run, {"file": "design.md", "role": "editor"})
        duplicate = observation.context_read(root, run, {"file": "design.md", "role": "reviewer"})
        save(root, run)
    assert captured["hash"] == duplicate["hash"]
    assert len(list((root / "state/snapshots").glob("*.json"))) == 1
    records = Records(root)
    assert records.context(run["project_id"], run["id"], captured["id"])["changed"] is False
    spec.write_text("# Changed", encoding="utf-8")
    result = records.context(run["project_id"], run["id"], captured["id"])
    assert result["content"] == "# Original" and result["changed"]
    spec.unlink()
    assert records.context(run["project_id"], run["id"], captured["id"])["content"] == "# Original"
    with pytest.raises(FactoryError):
        records.current_spec(run["project_id"], "../SKILL.md")
    with pytest.raises(FactoryError):
        observation.context_read(root, run, {"file": str(tmp_path / "outside.md"), "role": "editor"})


def test_attempts_results_resume_and_rounds(factories):
    root = factories[0]
    run = new_run(root)
    first = run["active_attempt"]
    run["history"].append({"status": "complete", "checks": [{"name": "unit", "status": "pass"}]})
    run["phase"] = "commit"
    with locked(root):
        save(root, run)
    assert run["attempts"][0]["ended_at"]
    assert next(e for e in run["events"] if e["kind"] == "result")["attempt_id"] == first
    run["phase"] = "review"
    with locked(root):
        save(root, run)
        observation.resume(run)
        save(root, run)
    assert run["attempts"][-2]["status"] == "interrupted"
    assert run["attempts"][-2]["ended_at"] is None
    assert run["attempts"][-1]["id"] != run["attempts"][-2]["id"]
    run.update(round=1, phase="work")
    with locked(root):
        save(root, run)
    assert run["attempts"][-1]["round"] == 1


def test_readonly_errors_and_malformed_records(factories):
    root, other = factories
    run = new_run(root)
    bad = root / "state" / str(uuid.uuid4()) / "run.json"
    write_json(bad, [])
    client = TestClient(create_app(root))
    prefix = "/api/projects/" + run["project_id"]
    before = {p: p.read_bytes() for p in root.rglob("*") if p.is_file()}
    assert client.get(prefix + "/sessions").json()["errors"]
    assert client.get(prefix + "/workflows/" + run["id"]).status_code == 200
    assert client.post(prefix + "/sessions", json={}).status_code == 405
    assert client.get(prefix + "/spec", params={"file": "../SKILL.md"}).status_code == 404
    assert client.get("/api/projects", headers={"host": "evil.example"}).status_code == 400
    assert client.get("/api/projects", headers={"origin": "https://evil.example"}).status_code == 403
    assert before == {p: p.read_bytes() for p in root.rglob("*") if p.is_file()}
    other.rename(other.with_name("unavailable"))
    projects = client.get("/api/projects").json()["items"]
    assert len(projects) == 2 and not projects[1]["available"]


def test_missing_snapshot_does_not_hide_workflow(factories):
    root = factories[0]
    run = new_run(root)
    (root / "specs/a.md").write_text("A")
    with locked(root):
        captured = observation.context_read(root, run, {"file": "a.md", "role": "editor"})
        save(root, run)
    (root / "state/snapshots" / (captured["hash"] + ".json")).unlink()
    client = TestClient(create_app(root))
    path = f"/api/projects/{run['project_id']}/workflows/{run['id']}"
    assert client.get(path + "/context/" + captured["id"]).status_code == 404
    assert client.get(path).status_code == 200


def test_large_history(factories):
    root = factories[0]
    run = new_run(root)
    for number in range(200):
        run.update(phase="review" if number % 2 else "work", round=number)
        observation.observe(run)
    with locked(root):
        save(root, run)
    assert len(Records(root).workflow(run["project_id"], run["id"])["attempts"]) == 200


def test_server_identity_reuse(factories):
    root = factories[0]
    write_json(root / "state/dashboard/server.json", {"port": 4601, "token": "ours"})
    expected = {"application": "software-factory-dashboard", "version": 1, "host": str(root.resolve()), "token": "ours"}
    with patch.object(dashboard, "identity", return_value=expected), patch.object(dashboard, "prepare") as prepare:
        assert dashboard.launch(root, open_browser=False) == "http://127.0.0.1:4601"
        prepare.assert_not_called()
    with patch.object(dashboard, "identity", return_value={**expected, "token": "foreign"}), patch.object(dashboard, "prepare", side_effect=FactoryError("prepare reached")):
        with pytest.raises(FactoryError, match="prepare reached"):
            dashboard.launch(root, open_browser=False)


def test_real_server_occupied_port_and_reuse(factories):
    root = install.install(SOURCE, factories[0].parent.parent.parent)
    with socket.socket() as occupied:
        occupied.bind(("127.0.0.1", 0))
        occupied.listen()
        port = occupied.getsockname()[1]
        try:
            address = dashboard.launch(root, port=port, open_browser=False, prepare_assets=False)
            chosen = int(address.rsplit(":", 1)[1])
            assert chosen != port
            assert dashboard.identity(chosen)["host"] == str(root.resolve())
            assert dashboard.launch(root, port=port, open_browser=False, prepare_assets=False) == address
        finally:
            metadata = root / "state/dashboard/server.json"
            if metadata.exists():
                pid = read_json(metadata)["pid"]
                if sys.platform == "win32":
                    subprocess.run(["taskkill", "/PID", str(pid), "/F"], capture_output=True, check=True)
                else:
                    import os
                    import signal
                    os.kill(pid, signal.SIGTERM)


def test_controller_start_context_and_file_free_route(factories, capsys):
    root = factories[0]
    request = {"operation": "specflow", "mode": "implement", "task": "Test observed controller",
               "modifiers": [], "worktree": str(root.parent.parent.parent), "branch": "main", "base": "main",
               "authorization": {"source": "Test fixture", "edits": True}, "required_checks": ["unit"]}
    identity = {"worktree": request["worktree"], "branch": "main"}
    observed = {"head": "fixture", "base": "fixture", "diff": "fixture", "clean": True}
    with patch.object(factory, "load_input", return_value=request), patch.object(factory.workflow, "identity", return_value=identity), patch.object(factory.workflow, "snapshot", return_value=observed), patch.object(factory.workspace, "verify"):
        assert factory.main(["start", "--root", str(root)]) == 0
        assignment = json.loads(capsys.readouterr().out)
        assert assignment["attempt_id"] and assignment["session_id"]
        run_id = assignment["run_id"]
        (root / "specs/a.md").write_text("# Captured")
        with patch.object(factory, "load_input", return_value={"file": "a.md", "role": "editor"}):
            assert factory.main(["context-read", "--root", str(root), "--run", run_id]) == 0
            assert json.loads(capsys.readouterr().out)["content"] == "# Captured"
        result = {**assignment, "status": "complete", "summary": "Fixture completed", "checks": [{"name": "unit", "status": "pass", "evidence": "Fixture"}]}
        with patch.object(factory, "load_input", return_value=result):
            assert factory.main(["accept", "--root", str(root), "--run", run_id]) == 0
        saved = read_json(root / "state" / run_id / "run.json")
        assert saved["phase"] == "done"
        assert saved["attempts"][0]["status"] == "complete"
        assert {e["kind"] for e in saved["events"]} >= {"phase_started", "context_supplied", "phase_finished", "result"}
        before = {p: p.read_bytes() for p in root.rglob("*") if p.is_file()}
        assert factory.main(["route", "--root", str(root)]) == 0
        assert before == {p: p.read_bytes() for p in root.rglob("*") if p.is_file()}


def test_reinstall_preserves_snapshot_and_excludes_runtime(factories):
    root = factories[0]
    run = new_run(root)
    (root / "specs/a.md").write_text("# Preserved")
    with locked(root):
        captured = observation.context_read(root, run, {"file": "a.md", "role": "editor"})
        save(root, run)
    install.install(SOURCE, root.parent.parent.parent)
    assert Records(root).context(run["project_id"], run["id"], captured["id"])["content"] == "# Preserved"
    assert (root / "app/frontend/package-lock.json").exists()
    assert (root / "app/backend/requirements.lock").exists()
    assert not (root / ".runtime").exists()
    assert not (root / "app/frontend/node_modules").exists()


@pytest.mark.parametrize("field,value", [("attempts", [{"id":"a", "phase":"work", "role":{}, "round":0}]), ("events", [{"id":"e", "kind":"context_supplied"}]), ("session_id", []), ("created_at", {}), ("checks", [None])])
def test_malformed_workflow_keeps_other_records(factories, field, value):
    root = factories[0]
    good = new_run(root)
    bad = new_run(root)
    bad[field] = value
    write_json(root / "state" / bad["id"] / "run.json", bad)
    response = Records(root).sessions(good["project_id"])
    assert response["errors"]
    assert any(r["id"] == good["id"] for s in response["items"] for r in s["workflows"])


def test_linked_factory_registers_as_one_project(factories, tmp_path):
    root = factories[0]
    linked_project = tmp_path / "feature-worktree"
    link = linked_project / ".agents/skills/software-factory"
    workspace.make_link(link, root)
    try:
        dashboard.register(root, [linked_project, root])
        entries = Records(root).registry()
        assert len(entries) == 2
        assert sum(p["factory"] == str(root.resolve()) for p in entries) == 1
    finally:
        workspace.unlink(link)


def test_snapshot_directory_cannot_escape_factory(factories, tmp_path):
    root = factories[0]
    run = new_run(root)
    outside = tmp_path / "outside"
    outside.mkdir()
    link = root / "state/snapshots"
    workspace.make_link(link, outside)
    try:
        with pytest.raises(FactoryError):
            Records(root).root(run["project_id"])
        with pytest.raises(FactoryError):
            observation.context_read(root, run, {"file": "a.md", "role": "editor"})
    finally:
        workspace.unlink(link)
