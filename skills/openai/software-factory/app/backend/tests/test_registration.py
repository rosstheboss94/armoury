"""Project installation, host path mapping, and browser write boundaries."""

import sys
import json
import os
import shutil
import signal
import socket
import subprocess
import uuid
from pathlib import Path
from unittest.mock import patch
from urllib.request import Request, urlopen

import pytest
from fastapi.testclient import TestClient

SOURCE = Path(__file__).resolve().parents[3]
sys.path[:0] = [str(SOURCE / "scripts"), str(SOURCE / "app/backend")]
from registration import ProjectDirectory, Registration, RegistrationConflict, merge, entries
from storage import FactoryError, read_json, write_json, locked
from server import create_app
from records import Records
import dashboard
import install
import docker_dashboard
import workspace as worktrees


def configured(tmp_path, host_path=None):
    workspace = tmp_path / "projects"
    workspace.mkdir()
    registry = tmp_path / "registry"
    directory = ProjectDirectory(host_path or str(workspace), workspace)
    service = Registration(SOURCE, registry, directory)
    return workspace, registry, service


def test_install_register_retry_and_host_controller(tmp_path):
    workspace, registry, service = configured(tmp_path)
    folder = workspace / "Project with spaces"
    folder.mkdir()
    neighbor = folder / '.agents/skills/neighbor/SKILL.md'
    neighbor.parent.mkdir(parents=True)
    neighbor.write_text('Neighbor skill')
    result = service.add(str(folder))
    factory = folder / ".agents/skills/software-factory"
    assert result["installed"] and not result["already_registered"]
    assert result['project']['name'] == folder.name
    assert neighbor.read_text() == 'Neighbor skill'
    assert {p.name for p in (folder / '.agents').iterdir()} == {'skills'}
    assert read_json(factory / "state/project.json")["factory"] == str(factory)
    assert (factory / "scripts/factory_paths.py").is_file()
    assert (factory / "scripts/install.py").is_file()
    original = (factory / "SKILL.md").read_bytes()
    assert original == (SOURCE / 'SKILL.md').read_bytes()
    (factory / 'local.txt').write_text('Local file')
    identity = (factory / 'state/project.json').read_bytes()
    (factory / "specs").mkdir()
    (factory / "specs/local.md").write_text("Keep me")
    repeated = service.add("Project with spaces")
    assert repeated["already_registered"] and not repeated["installed"]
    assert len(read_json(registry / "projects.json")) == 1
    assert (factory / "SKILL.md").read_bytes() == original
    assert (factory / "specs/local.md").read_text() == "Keep me"
    install.install(SOURCE, folder)
    assert (factory / 'local.txt').read_text() == 'Local file'
    assert (factory / 'state/project.json').read_bytes() == identity
    assert neighbor.read_text() == 'Neighbor skill'
    dashboard.register(factory, [folder])
    assert read_json(factory / "state/project.json")["id"] == result["project"]["id"]
    assert Records(SOURCE, registration=service).projects()["items"][0]["available"]


@pytest.mark.parametrize("host_path", ["C:\\Users\\Owner\\Projects", "/home/owner/projects"])
def test_container_mapping_persists_host_paths(tmp_path, host_path):
    workspace, registry, service = configured(tmp_path, host_path)
    (workspace / "Atlas").mkdir()
    result = service.add(str(service.directory.host / "Atlas"))
    assert result["project"]["factory"] == str(service.directory.host / "Atlas" / ".agents" / "skills" / "software-factory")
    assert str(workspace) not in (registry / "projects.json").read_text()
    assert Records(SOURCE, registration=service).projects()["items"][0]["available"]


def test_install_errors_name_the_missing_side(tmp_path):
    with pytest.raises(FactoryError, match="target project directory must exist"):
        install.install(SOURCE, tmp_path / "missing")
    empty = tmp_path / "empty"
    empty.mkdir()
    with pytest.raises(FactoryError, match="missing SKILL.md"):
        install.install(empty, tmp_path)


@pytest.mark.parametrize("path", ["../outside", "missing", "", "C:relative", "/elsewhere"])
def test_invalid_paths_do_not_install(tmp_path, path):
    workspace, registry, service = configured(tmp_path)
    with pytest.raises(FactoryError):
        service.add(path)
    assert list(workspace.iterdir()) == []
    assert not (registry / "projects.json").exists()


def test_legacy_factory_is_registered_without_a_second_install(tmp_path):
    workspace, registry, service = configured(tmp_path)
    folder = workspace / "Atlas"
    folder.mkdir()
    legacy = folder / ".agents/software-factory"
    (legacy / "scripts").mkdir(parents=True)
    (legacy / "SKILL.md").write_text("Legacy factory")
    (legacy / "scripts/install.py").write_text("legacy")
    identity = {"version": 1, "id": str(uuid.uuid4()), "name": "Atlas",
                "factory": str(legacy), "created_at": "2026-09-14T00:00:00+00:00"}
    write_json(legacy / "state/project.json", identity)
    result = service.add("Atlas")
    assert not result["installed"] and result["already_registered"] is False
    assert result["project"]["id"] == identity["id"]
    assert not (folder / ".agents/skills/software-factory").exists()
    assert (legacy / "SKILL.md").read_text() == "Legacy factory"
    assert read_json(registry / "projects.json")[0]["id"] == identity["id"]
    dashboard.register(legacy, [folder])
    saved = read_json(legacy / "state/dashboard/projects.json")[0]
    assert saved["id"] == identity["id"]
    assert saved["factory"] == str(legacy.resolve())


def test_registry_keeps_one_row_per_project(tmp_path):
    workspace, registry, service = configured(tmp_path)
    (workspace / "Atlas").mkdir()
    (workspace / "Beacon").mkdir()
    first = service.add("Atlas")
    factory = workspace / "Atlas/.agents/skills/software-factory"
    live = read_json(registry / "projects.json")[0]
    stale = {"id": str(uuid.uuid4()), "factory": str(factory), "name": "Atlas",
             "created_at": "2020-01-01T00:00:00+00:00"}
    write_json(registry / "projects.json", [stale, live])
    assert len(entries(registry)) == 1
    assert entries(registry)[0]["id"] == first["project"]["id"]
    repeated = service.add("Atlas")
    listed = read_json(registry / "projects.json")
    assert len(listed) == 1
    assert listed[0]["id"] == first["project"]["id"]
    assert listed[0]["id"] == read_json(factory / "state/project.json")["id"]
    assert not repeated["installed"]
    service.add("Beacon")
    assert {p["name"] for p in read_json(registry / "projects.json")} == {"Atlas", "Beacon"}
    old_id = first["project"]["id"]
    shutil.rmtree(factory)
    reinstalled = service.add("Atlas")
    listed = read_json(registry / "projects.json")
    atlas = next(p for p in listed if p["name"] == "Atlas")
    assert reinstalled["installed"]
    assert atlas["id"] != old_id
    assert atlas["id"] == reinstalled["project"]["id"]
    assert len([p for p in listed if p["name"] == "Atlas"]) == 1
    assert len(listed) == 2


def test_legacy_then_canonical_is_one_registry_row(tmp_path):
    workspace, registry, service = configured(tmp_path)
    folder = workspace / "Atlas"
    folder.mkdir()
    legacy = folder / ".agents/software-factory"
    (legacy / "scripts").mkdir(parents=True)
    (legacy / "SKILL.md").write_text("Legacy factory")
    (legacy / "scripts/install.py").write_text("legacy")
    write_json(legacy / "state/project.json", {"version": 1, "id": str(uuid.uuid4()), "name": "Atlas",
                                               "factory": str(legacy), "created_at": "2026-01-01T00:00:00+00:00"})
    service.add("Atlas")
    install.install(SOURCE, folder)
    result = service.add("Atlas")
    listed = read_json(registry / "projects.json")
    canonical = folder / ".agents/skills/software-factory"
    assert len(listed) == 1
    assert listed[0]["id"] == read_json(canonical / "state/project.json")["id"]
    assert listed[0]["id"] == result["project"]["id"]


def test_install_failure_is_not_registered_and_staging_is_removed(tmp_path):
    workspace, registry, service = configured(tmp_path)
    folder = workspace / "Atlas"
    folder.mkdir()
    with patch("registration.install", side_effect=OSError("disk full")):
        with pytest.raises(OSError):
            service.add("Atlas")
    assert not (folder / ".agents/skills/software-factory").exists()
    assert list((folder / ".agents/skills").iterdir()) == []
    assert not (registry / "projects.json").exists()
    assert service.add("Atlas")["installed"]


def test_incomplete_install_and_concurrent_lock(tmp_path):
    workspace, registry, service = configured(tmp_path)
    target = workspace / "Atlas/.agents/skills/software-factory"
    target.mkdir(parents=True)
    (target / "custom.txt").write_text("Preserve")
    with pytest.raises(RegistrationConflict, match="incomplete"):
        service.add("Atlas")
    assert (target / "custom.txt").read_text() == "Preserve"
    with locked(registry), pytest.raises(FactoryError, match="locked"):
        service.add("Atlas")


def test_factory_links_and_escape(tmp_path):
    workspace, registry, service = configured(tmp_path)
    (workspace / "canonical").mkdir()
    service.add("canonical")
    link = workspace / "feature/.agents/skills/software-factory"
    link.parent.mkdir(parents=True)
    try:
        link.symlink_to(workspace / "canonical/.agents/skills/software-factory", target_is_directory=True)
    except OSError:
        pytest.skip("Directory links require OS permission")
    assert service.add("feature")["already_registered"]
    outside = tmp_path / "outside"
    outside.mkdir()
    (workspace / "escape").symlink_to(outside, target_is_directory=True)
    with pytest.raises(FactoryError, match="inside"):
        service.add("escape")
    assert list(outside.iterdir()) == []


def test_http_registration_and_restart(tmp_path):
    workspace, registry, service = configured(tmp_path)
    (workspace / "Atlas").mkdir()
    def client():
        return TestClient(create_app(SOURCE, projects_directory=str(workspace), registry_directory=registry))
    http = client()
    settings = http.get("/api/project-registration").json()
    headers = {"origin": "http://testserver", "x-factory-token": settings["token"]}
    assert http.post("/api/projects", json={"path": "Atlas"}).status_code == 403
    assert http.post("/api/projects", json={"path": "Atlas"}, headers={**headers, "origin": "https://evil.example"}).status_code == 403
    assert http.post("/api/projects", content="path=Atlas", headers=headers).status_code == 415
    assert http.post("/api/projects", json={"path": 1}, headers=headers).status_code == 400
    assert http.post("/api/projects", json={"path": "Atlas"}, headers=headers).status_code == 200
    assert http.post("/api/projects", json={"path": "Atlas"}, headers=headers).json()["already_registered"]
    restarted = client()
    assert restarted.get("/api/projects").json()["items"][0]["name"] == "Atlas"
    assert restarted.post("/api/projects", json={"path": "Atlas"}, headers=headers).status_code == 403
    assert http.delete("/api/projects").status_code == 405


def test_unconfigured_dashboard_only_offers_setup(tmp_path):
    http = TestClient(create_app(tmp_path))
    settings = http.get("/api/project-registration").json()
    assert not settings["available"]
    assert http.post("/api/projects", json={"path": "Atlas"}, headers={"origin": "http://testserver", "x-factory-token": settings["token"]}).status_code == 409


def write_auth(http):
    token = http.get("/api/project-registration").json()["token"]
    return {"origin": "http://testserver", "x-factory-token": token}


def test_http_removal_auth_repeat_unavailable_host_and_lock(tmp_path):
    workspace, registry, service = configured(tmp_path)
    host_project = workspace / "Host"
    host_project.mkdir()
    host = install.install(SOURCE, host_project)
    service.add("Host")
    neighbor = workspace / "Beacon"
    neighbor.mkdir()
    beacon = service.add("Beacon")["project"]
    factory = neighbor / ".agents/skills/software-factory"
    (factory / "keep.txt").write_text("retain")
    identity = (factory / "state/project.json").read_bytes()
    def client():
        return TestClient(create_app(SOURCE, projects_directory=str(workspace), registry_directory=registry, single_factory=host))
    http = client()
    headers = write_auth(http)
    host_id = read_json(host / "state/project.json")["id"]
    beacon_id = beacon["id"]
    assert http.delete(f"/api/projects/{beacon_id}").status_code == 403
    assert http.delete(f"/api/projects/{beacon_id}", headers={**headers, "origin": "https://evil.example"}).status_code == 403
    assert http.delete(f"/api/projects/{uuid.uuid4()}", headers=headers).status_code == 404
    with patch("registration.write_json", side_effect=PermissionError):
        assert http.delete(f"/api/projects/{beacon_id}", headers=headers).status_code == 403
    neighbor.rename(workspace / "missing-beacon")
    listing = http.get("/api/projects").json()["items"]
    assert any(p["id"] == beacon_id and not p["available"] for p in listing)
    assert http.delete(f"/api/projects/{beacon_id}", headers=headers).status_code == 204
    assert http.delete(f"/api/projects/{beacon_id}", headers=headers).status_code == 204
    assert all(p["id"] != beacon_id for p in http.get("/api/projects").json()["items"])
    assert http.get(f"/api/projects/{beacon_id}/sessions").status_code == 404
    assert (workspace / "missing-beacon/.agents/skills/software-factory/keep.txt").read_text() == "retain"
    assert (workspace / "missing-beacon/.agents/skills/software-factory/state/project.json").read_bytes() == identity
    assert any(p["id"] == beacon_id for p in read_json(registry / "projects.json"))
    assert beacon_id in read_json(registry / "removed-projects.json")
    other = tmp_path / "other-dashboard"
    dashboard.register(other, [host])
    assert any(p["id"] == host_id for p in Records(other).projects()["items"])
    with locked(registry):
        assert http.delete(f"/api/projects/{host_id}", headers=headers).status_code == 409
    assert http.delete(f"/api/projects/{host_id}", headers=headers).status_code == 204
    assert http.get("/api/projects").json()["items"] == []
    assert http.get(f"/api/projects/{host_id}/sessions").status_code == 404
    assert any(p["id"] == host_id for p in Records(other).projects()["items"])
    restarted = client()
    assert restarted.get("/api/projects").json()["items"] == []


def test_add_and_explicit_registration_restore_removed_identity(tmp_path):
    workspace, registry, service = configured(tmp_path)
    (workspace / "Atlas").mkdir()
    added = service.add("Atlas")
    pid = added["project"]["id"]
    identity = (workspace / "Atlas/.agents/skills/software-factory/state/project.json").read_bytes()
    http = TestClient(create_app(SOURCE, projects_directory=str(workspace), registry_directory=registry))
    headers = write_auth(http)
    assert http.delete(f"/api/projects/{pid}", headers=headers).status_code == 204
    merge(registry, [added["project"]])
    assert http.get("/api/projects").json()["items"] == []
    restored = http.post("/api/projects", json={"path": "Atlas"}, headers=headers).json()
    assert restored["project"]["id"] == pid
    assert not restored["already_registered"]
    assert restored["project"]["name"] == "Atlas"
    listing = http.get("/api/projects").json()["items"]
    assert len(listing) == 1 and listing[0]["id"] == pid
    assert pid not in read_json(registry / "removed-projects.json")
    assert (workspace / "Atlas/.agents/skills/software-factory/state/project.json").read_bytes() == identity
    assert http.delete(f"/api/projects/{pid}", headers=headers).status_code == 204
    merge(registry, [added["project"]], restore=True)
    assert http.get("/api/projects").json()["items"][0]["id"] == pid


def test_removal_without_projects_directory_and_stale_sources(tmp_path):
    host_project = tmp_path / "Host"
    host_project.mkdir()
    host = install.install(SOURCE, host_project)
    dashboard.register(host, [host])
    pid = read_json(host / "state/project.json")["id"]
    http = TestClient(create_app(host))
    headers = write_auth(http)
    assert not http.get("/api/project-registration").json()["available"]
    assert http.delete(f"/api/projects/{pid}", headers=headers).status_code == 204
    assert http.get("/api/projects").json()["items"] == []
    dashboard.register(host, [host])
    assert Records(host).projects()["items"] == []
    config = {"projects": [{**read_json(host / "state/project.json"), "factory": str(host), "mount": str(host)}]}
    stale = Records(host, config, registration=Registration(SOURCE, host / "state/dashboard"))
    assert stale.projects()["items"] == []
    with pytest.raises(FactoryError, match="not registered"):
        stale.root(pid)
    discovered = Records(SOURCE, single_factory=host, registration=Registration(SOURCE, host / "state/dashboard"))
    assert discovered.projects()["items"] == []
    dashboard.register(host, [host], restore=True)
    assert Records(host).projects()["items"][0]["id"] == pid


def test_compose_preserves_host_outside_projects_directory(tmp_path):
    workspace, registry, service = configured(tmp_path)
    host_project = tmp_path / "Host outside workspace"
    host_project.mkdir()
    host = install.install(SOURCE, host_project)
    dashboard.register(host, [host])
    service = Registration(SOURCE, host / "state/dashboard", service.directory)
    records = Records(SOURCE, single_factory=host, registration=service)
    listing = records.projects()["items"]
    assert len(listing) == 1 and listing[0]["available"]


@pytest.mark.parametrize("mode", ["native", "docker", "compose"])
def test_live_registration(tmp_path, mode):
    if mode != "native" and os.environ.get("FACTORY_DOCKER_TESTS") != "1":
        pytest.skip("Set FACTORY_DOCKER_TESTS=1 to exercise Docker")
    workspace = tmp_path / "Projects with spaces"
    workspace.mkdir()
    host_project = workspace / "Host"
    host_project.mkdir()
    host = install.install(SOURCE, host_project)
    dashboard.register(host, [host])
    target = workspace / "Added project"
    target.mkdir()
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        port = probe.getsockname()[1]
    compose_name = "factory-registration-" + uuid.uuid4().hex[:12]
    environment = dict(os.environ, FACTORY_PROJECTS_DIRECTORY=str(workspace), FACTORY_DIRECTORY=str(host), FACTORY_PORT=str(port))
    if os.name != "nt":
        environment["FACTORY_USER"] = f"{os.getuid()}:{os.getgid()}"
    compose = ["docker", "compose", "-p", compose_name, "-f", str(host / "compose.yaml")]
    address = f"http://127.0.0.1:{port}"
    native_pid = None
    def request(path, payload=None, token=None):
        headers = {"Origin": address}
        if token:
            headers.update({"Content-Type": "application/json", "X-Factory-Token": token})
        with urlopen(Request(address + path, data=json.dumps(payload).encode() if payload else None, headers=headers), timeout=30) as response:
            return json.load(response)
    try:
        if mode == "native":
            address = dashboard.launch(host, port, False, False, projects_directory=str(workspace))
            native_pid = read_json(host / "state/dashboard/server.json")["pid"]
        elif mode == "docker":
            address = docker_dashboard.control(host, port, False, projects_directory=str(workspace))["address"]
        else:
            result = subprocess.run([*compose, "up", "--build", "-d", "--wait"], env=environment, capture_output=True, text=True, timeout=600)
            assert result.returncode == 0, result.stdout + result.stderr
        before = request("/api/identity")
        token = request("/api/project-registration")["token"]
        added = request("/api/projects", {"path": str(target)}, token)
        assert added["installed"]
        assert request("/api/projects", {"path": "Added project"}, token)["already_registered"]
        listing = request("/api/projects")["items"]
        assert len(listing) == 2 and all(p["available"] for p in listing)
        assert request("/api/identity") == before
        installed = target / ".agents/skills/software-factory"
        assert read_json(installed / "state/project.json")["factory"] == str(installed)
        assert (installed / "references/dashboard.md").is_file()
        assert (installed / "scripts/factory.py").is_file()
        assert not (installed / "app/frontend/dist").exists()
        dashboard.register(host, [installed])
        assert len(read_json(host / "state/dashboard/projects.json")) == 2
        if mode == "docker":
            docker_dashboard.control(host, action="stop")
            address = docker_dashboard.control(host, port, False, projects_directory=str(workspace))["address"]
        elif mode == "compose":
            subprocess.run([*compose, "restart"], env=environment, check=True, capture_output=True)
            subprocess.run([*compose, "up", "-d", "--wait"], env=environment, check=True, capture_output=True)
        assert len(request("/api/projects")["items"]) == 2
    finally:
        if native_pid:
            os.kill(native_pid, signal.SIGTERM)
        elif mode == "docker":
            docker_dashboard.control(host, action="stop")
        elif mode == "compose":
            subprocess.run([*compose, "down", "--volumes"], env=environment, capture_output=True, timeout=60)


@pytest.mark.parametrize("mode", ["native", "docker", "compose"])
def test_live_removal(tmp_path, mode):
    if mode != "native" and os.environ.get("FACTORY_DOCKER_TESTS") != "1":
        pytest.skip("Set FACTORY_DOCKER_TESTS=1 to exercise Docker")
    workspace = tmp_path / "Projects"
    workspace.mkdir()
    host_project = workspace / "Host"
    host_project.mkdir()
    host = install.install(SOURCE, host_project)
    dashboard.register(host, [host])
    target = workspace / "Beacon"
    target.mkdir()
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        port = probe.getsockname()[1]
    compose_name = "factory-removal-" + uuid.uuid4().hex[:12]
    environment = dict(os.environ, FACTORY_PROJECTS_DIRECTORY=str(workspace), FACTORY_DIRECTORY=str(host), FACTORY_PORT=str(port))
    if os.name != "nt":
        environment["FACTORY_USER"] = f"{os.getuid()}:{os.getgid()}"
    compose = ["docker", "compose", "-p", compose_name, "-f", str(host / "compose.yaml")]
    address = f"http://127.0.0.1:{port}"
    native_pid = None
    def request(path, payload=None, token=None, method=None):
        headers = {"Origin": address}
        data = json.dumps(payload).encode() if payload is not None else None
        if token:
            headers["X-Factory-Token"] = token
            if data is not None:
                headers["Content-Type"] = "application/json"
        req = Request(address + path, data=data, headers=headers, method=method or ("POST" if data is not None else "GET"))
        with urlopen(req, timeout=30) as response:
            if response.status == 204:
                return None
            return json.load(response)
    try:
        if mode == "native":
            address = dashboard.launch(host, port, False, False, projects_directory=str(workspace))
            native_pid = read_json(host / "state/dashboard/server.json")["pid"]
        elif mode == "docker":
            address = docker_dashboard.control(host, port, False, projects_directory=str(workspace))["address"]
        else:
            result = subprocess.run([*compose, "up", "--build", "-d", "--wait"], env=environment, capture_output=True, text=True, timeout=600)
            assert result.returncode == 0, result.stdout + result.stderr
        token = request("/api/project-registration")["token"]
        added = request("/api/projects", {"path": str(target)}, token)
        pid = added["project"]["id"]
        keep = target / ".agents/skills/software-factory/state/project.json"
        identity = keep.read_bytes()
        request(f"/api/projects/{pid}", token=token, method="DELETE")
        assert all(p["id"] != pid for p in request("/api/projects")["items"])
        host_id = read_json(host / "state/project.json")["id"]
        request(f"/api/projects/{host_id}", token=token, method="DELETE")
        assert request("/api/projects")["items"] == []
        if mode == "native":
            os.kill(native_pid, signal.SIGTERM)
            native_pid = None
            dashboard.register(host, [host])
            address = dashboard.launch(host, port, False, False, projects_directory=str(workspace))
            native_pid = read_json(host / "state/dashboard/server.json")["pid"]
        elif mode == "docker":
            docker_dashboard.control(host, action="stop")
            dashboard.register(host, [host])
            address = docker_dashboard.control(host, port, False, projects_directory=str(workspace))["address"]
        else:
            subprocess.run([*compose, "restart"], env=environment, check=True, capture_output=True)
            subprocess.run([*compose, "up", "-d", "--wait"], env=environment, check=True, capture_output=True)
        token = request("/api/project-registration")["token"]
        assert request("/api/projects")["items"] == []
        restored = request("/api/projects", {"path": "Beacon"}, token)
        assert restored["project"]["id"] == pid
        assert keep.read_bytes() == identity
        dashboard.register(host, [host], restore=True)
        if mode == "docker":
            docker_dashboard.control(host, action="stop")
            address = docker_dashboard.control(host, port, False, projects_directory=str(workspace))["address"]
        listing = request("/api/projects")["items"]
        assert {p["id"] for p in listing} == {pid, host_id}
    finally:
        if native_pid:
            os.kill(native_pid, signal.SIGTERM)
        elif mode == "docker":
            docker_dashboard.control(host, action="stop")
        elif mode == "compose":
            subprocess.run([*compose, "down", "--volumes"], env=environment, capture_output=True, timeout=60)


@pytest.mark.parametrize('parent', ['.agents', '.agents/skills'])
@pytest.mark.parametrize('redirected', [False, True])
def test_install_parents_are_physical_directories(tmp_path, parent, redirected):
    workspace, registry, service = configured(tmp_path)
    folder = workspace / 'Atlas'
    folder.mkdir()
    destination = folder / parent
    destination.parent.mkdir(parents=True, exist_ok=True)
    outside = workspace / 'other'
    outside.mkdir()
    if redirected:
        worktrees.make_link(destination, outside)
    else:
        destination.write_text('Preserve')
    try:
        with pytest.raises(RegistrationConflict, match='physical directory'):
            service.add('Atlas')
        with pytest.raises((FactoryError, OSError)):
            install.install(SOURCE, folder)
        assert list(outside.iterdir()) == []
        assert not (registry / 'projects.json').exists()
    finally:
        if redirected:
            worktrees.unlink(destination)
