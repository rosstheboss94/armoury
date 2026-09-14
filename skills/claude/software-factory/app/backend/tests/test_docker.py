"""Docker adapter tests, with an opt-in real engine acceptance test."""

import json
import os
import socket
import subprocess
import sys
from pathlib import Path
from unittest.mock import patch
from urllib.request import urlopen

import pytest

SOURCE = Path(__file__).resolve().parents[3]
sys.path[:0] = [str(SOURCE / "scripts"), str(SOURCE / "app/backend")]
import dashboard
import docker_dashboard as runtime
import install
from records import Records
from storage import FactoryError, read_json, write_json


def test_build_inputs_exclude_local_data():
    names = [p.relative_to(SOURCE).as_posix() for p in runtime.build_inputs(SOURCE)]
    assert all(not set(Path(p).parts) & {"state", "specs", ".runtime", "node_modules", "dist"} for p in names)
    assert "app/Dockerfile" in names
    assert "app/frontend/package-lock.json" in names


def test_missing_docker_has_no_native_fallback():
    with patch.object(runtime.subprocess, "run", side_effect=FileNotFoundError), patch.object(dashboard, "prepare") as prepare:
        with pytest.raises(FactoryError, match="Docker is required"):
            runtime.preflight()
        prepare.assert_not_called()


def test_foreign_container_is_not_owned():
    result = subprocess.CompletedProcess([], 0, json.dumps([{"Config": {"Labels": {runtime.LABEL: "other"}}}]), "")
    with patch.object(runtime, "docker", return_value=result):
        with pytest.raises(FactoryError, match="another application"):
            runtime.inspect("test", "owner")


def test_container_paths_preserve_host_display(tmp_path):
    project = tmp_path / "Project with spaces"
    project.mkdir()
    root = install.install(SOURCE, project)
    dashboard.register(root, [root])
    config, mounts, _ = runtime.configuration(root, "fingerprint")
    assert config["projects"][0]["factory"] == str(root)
    assert mounts[0]["read_only"] is True
    assert config["projects"][0]["mount"].startswith("/projects/")
    # Simulate the translated directory in a transport-independent repository test.
    config["projects"][0]["mount"] = str(root)
    assert Records(SOURCE, config).projects()["items"][0]["available"]
    config["projects"][0]["mount"] = None
    assert not Records(SOURCE, config).projects()["items"][0]["available"]


def test_standalone_compose_discovers_identity_after_startup(tmp_path):
    project = tmp_path / "Compose project"
    project.mkdir()
    root = install.install(SOURCE, project)
    records = Records(SOURCE, single_factory=root)
    assert records.projects()["items"] == []
    dashboard.register(root, [root])
    entry = records.projects()["items"][0]
    assert entry["available"]
    assert entry["factory"] == str(root)
    assert (root / "compose.yaml").exists()


@pytest.mark.skipif(os.environ.get("FACTORY_DOCKER_TESTS") != "1", reason="Set FACTORY_DOCKER_TESTS=1 to exercise a local Docker engine")
def test_real_docker_lifecycle(tmp_path):
    roots = []
    for name in ("Docker Atlas", "Docker Beacon"):
        project = tmp_path / name
        project.mkdir()
        root = install.install(SOURCE, project)
        (root / "specs").mkdir()
        (root / "specs/check.md").write_text("# Original", encoding="utf-8")
        roots.append(root)
    host, other = roots
    dashboard.register(host, roots)
    original_records = (host / "state/project.json").read_bytes()
    def get(address, path):
        with urlopen(address + path, timeout=5) as response:
            return json.load(response)
    try:
        with socket.socket() as occupied:
            occupied.bind(("127.0.0.1", 0))
            occupied.listen()
            port = occupied.getsockname()[1]
            started = runtime.control(host, port=port, open_browser=False)
            assert started["address"] != f"http://127.0.0.1:{port}"
        address = started["address"]
        projects = get(address, "/api/projects")["items"]
        assert len(projects) == 2 and all(p["available"] for p in projects)
        with urlopen(address, timeout=5) as response:
            assert b'Software factory' in response.read()
        pid = projects[0]["id"]
        spec_url = f"/api/projects/{pid}/spec?file=check.md"
        assert get(address, spec_url)["content"] == "# Original"
        (host / "specs/check.md").write_text("# Changed", encoding="utf-8")
        assert get(address, spec_url)["content"] == "# Changed"
        attempt = runtime.docker("exec", started["container"], "python", "-c", f"from pathlib import Path; Path('/projects/{pid}/specs/forbidden.md').write_text('x')", check=False)
        assert attempt.returncode != 0
        assert not (host / "specs/forbidden.md").exists()
        clean_image = runtime.docker("run", "--rm", "--entrypoint", "python", "software-factory-dashboard:" + runtime.fingerprint(host)[:24], "-c",
                                     "from pathlib import Path; import shutil; assert not Path('/projects').exists(); assert not Path('/opt/factory/state').exists(); assert not Path('/opt/factory/specs').exists(); assert shutil.which('node') is None")
        assert clean_image.returncode == 0
        assert runtime.control(host, open_browser=False)["reused"]
        assert runtime.control(host, action="status")["health"] == "healthy"
        container_before = read_json(host / "state/dashboard/docker-server.json")["container_id"]
        registry = read_json(host / "state/dashboard/projects.json")
        registry[1]["factory"] = str(tmp_path / "unavailable")
        write_json(host / "state/dashboard/projects.json", registry)
        changed = runtime.control(host, open_browser=False)
        assert not changed["reused"]
        assert read_json(host / "state/dashboard/docker-server.json")["container_id"] != container_before
        assert not get(changed["address"], "/api/projects")["items"][1]["available"]
        image_before = runtime.fingerprint(host)
        source = host / "app/backend/server.py"
        source.write_text(source.read_text(encoding="utf-8") + "\n# Docker rebuild fixture\n", encoding="utf-8")
        assert runtime.fingerprint(host) != image_before
        rebuilt = runtime.control(host, open_browser=False)
        assert not rebuilt["reused"]
        assert get(rebuilt["address"], "/api/identity")["fingerprint"] == runtime.fingerprint(host)
        assert not (host / ".runtime/python").exists()
        assert not (host / "app/frontend/node_modules").exists()
        assert not (host / "app/frontend/dist").exists()
        assert original_records == (host / "state/project.json").read_bytes()
        runtime.control(host, action="stop")
        assert runtime.control(host, action="status")["status"] == "absent"
        restarted = runtime.control(host, open_browser=False)
        assert get(restarted["address"], spec_url)["content"] == "# Changed"
    finally:
        runtime.control(host, action="stop")
