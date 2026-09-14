"""Host-side Docker lifecycle. Uses only the Python standard library."""

import hashlib
import json
import os
import socket
import shutil
import subprocess
import time
import uuid
import webbrowser
from pathlib import Path

from storage import FactoryError, locked, read_json, write_json
from registration import ProjectDirectory

LABEL = "org.armoury.dashboard.host"


def docker(*arguments, check=True):
    try:
        result = subprocess.run(["docker", *arguments], capture_output=True, text=True, timeout=900)
    except FileNotFoundError as exc:
        raise FactoryError("Docker is required. Install Docker Desktop or Docker Engine with Compose.") from exc
    if check and result.returncode:
        raise FactoryError(f"Docker {' '.join(arguments[:2])} failed: {result.stderr.strip() or result.stdout.strip()}")
    return result


def preflight():
    if docker("info", "--format", "{{.OSType}}").stdout.strip() != "linux":
        raise FactoryError("Switch Docker to Linux containers.")
    docker("compose", "version")
    endpoint = os.environ.get("DOCKER_HOST") if not os.environ.get("DOCKER_CONTEXT") else None
    if not endpoint:
        context = json.loads(docker("context", "inspect").stdout)[0]
        endpoint = context["Endpoints"]["docker"]["Host"]
    if not endpoint.startswith(("unix://", "npipe://")):
        raise FactoryError("Dashboard mounts require a local Docker engine. Select a local Docker context.")


def build_inputs(root):
    excluded = {"state", "specs", ".runtime", "node_modules", "dist", "__pycache__", ".pytest_cache", ".venv", ".git"}
    paths = []
    for directory, folders, names in os.walk(root):
        folders[:] = [name for name in folders if name not in excluded]
        if Path(directory) == root:
            folders[:] = [name for name in folders if name in {"app", "scripts", "references", "agents"}]
        for name in names:
            path = Path(directory) / name
            if Path(directory) == root and name not in {"SKILL.md", "compose.yaml", ".gitignore", ".dockerignore"}:
                continue
            if path.is_symlink():
                raise FactoryError("Dashboard package files must not be links.")
            if path.suffix != ".pyc":
                paths.append(path)
    return sorted(paths)


def fingerprint(root):
    digest = hashlib.sha256()
    for path in build_inputs(root):
        digest.update(path.relative_to(root).as_posix().encode() + b"\0" + path.read_bytes())
    return digest.hexdigest()


def inspect(name, owner):
    result = docker("container", "inspect", name, check=False)
    if result.returncode:
        if "No such" in result.stderr:
            return None
        raise FactoryError(result.stderr)
    record = json.loads(result.stdout)[0]
    if record["Config"].get("Labels", {}).get(LABEL) != owner:
        raise FactoryError("Container name belongs to another application. It will not be replaced.")
    return record


def configuration(root, digest, projects_directory=None):
    entries = read_json(root / "state/dashboard/projects.json")
    projects, mounts = [], []
    for entry in entries:
        identifier = str(uuid.UUID(entry["id"]))
        path = Path(entry["factory"]).resolve()
        available = path.is_dir() and (path / "state/project.json").is_file()
        target = "/projects/" + identifier
        projects.append({**entry, "mount": target if available else None})
        if available:
            mounts.append({"type": "bind", "source": str(path), "target": target,
                           "read_only": True, "bind": {"create_host_path": False}})
    value = {"version": 1, "host": str(root), "fingerprint": digest, "projects": projects}
    if projects_directory:
        directory = ProjectDirectory(projects_directory)
        registry = root / "state/dashboard"
        value.update(projects_directory=str(directory.host), projects_mount="/workspace", registry_directory="/registry")
        mounts.extend([
            {"type": "bind", "source": str(directory.local), "target": "/workspace", "read_only": False, "bind": {"create_host_path": False}},
            {"type": "bind", "source": str(registry), "target": "/registry", "read_only": False, "bind": {"create_host_path": False}},
        ])
    revision = hashlib.sha256(json.dumps([value, mounts], sort_keys=True).encode()).hexdigest()
    return value, mounts, revision


def mounts_match(record, mounts):
    def normalized(source):
        value = source.replace("\\", "/").rstrip("/")
        if os.name == "nt":
            for prefix in ("/run/desktop/mnt/host/", "/host_mnt/"):
                if value.startswith(prefix):
                    value = value[len(prefix)] + ":" + value[len(prefix) + 1:]
            value = value.lower()
        return value
    actual = {m["Destination"]: (normalized(m["Source"]), m["RW"]) for m in record.get("Mounts", []) if m["Type"] == "bind"}
    desired = {m["target"]: (normalized(m["source"]), not m["read_only"]) for m in mounts}
    return actual == desired and record["HostConfig"].get("ReadonlyRootfs") is True


def control(root, port=4601, open_browser=True, action="start", projects_directory=None):
    from dashboard import identity
    root = Path(root).resolve()
    preflight()
    owner = hashlib.sha256(str(root).encode()).hexdigest()
    name = "software-factory-" + owner[:16]
    runtime = root / ".runtime/docker-dashboard"
    with locked(runtime):
        record = inspect(name, owner)
        if action == "stop":
            if record:
                docker("container", "rm", "--force", record["Id"])
            network = docker("network", "inspect", name + "_default", check=False)
            if network.returncode == 0:
                entry = json.loads(network.stdout)[0]
                if entry.get("Labels", {}).get("com.docker.compose.project") == name:
                    docker("network", "rm", entry["Id"])
            return {"status": "stopped", "container": name}
        if action == "status":
            return {"status": record["State"]["Status"] if record else "absent", "container": name,
                    "health": record["State"].get("Health", {}).get("Status") if record else None}
        digest = fingerprint(root)
        config, mounts, revision = configuration(root, digest, projects_directory)
        mounts.append({"type": "bind", "source": str(runtime), "target": "/etc/factory-dashboard",
                       "read_only": True, "bind": {"create_host_path": False}})
        image = "software-factory-dashboard:" + digest[:24]
        image_record = docker("image", "inspect", image, check=False)
        if image_record.returncode:
            print("Building dashboard image inside Docker...", flush=True)
            # Send only declared package inputs, even if the installed tree has local files.
            context = runtime / "build-context" / digest
            for source in build_inputs(root):
                destination = context / source.relative_to(root)
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source, destination)
            built = docker("build", "--file", str(context / "app/Dockerfile"), "--tag", image, str(context), check=False)
            (runtime / "build.log").write_text(built.stdout + built.stderr, encoding="utf-8")
            if built.returncode:
                raise FactoryError(f"Dashboard image build failed. See {runtime / 'build.log'}: {built.stderr[-2000:]}")
            image_record = docker("image", "inspect", image)
        image_id = json.loads(image_record.stdout)[0]["Id"]
        metadata_path = root / "state/dashboard/docker-server.json"
        saved = read_json(metadata_path) if metadata_path.exists() else {}
        if record and record["Image"] == image_id and record["Config"]["Labels"].get("org.armoury.dashboard.config") == revision:
            found = identity(saved.get("port", 0))
            bindings = record["HostConfig"].get("PortBindings", {}).get("4601/tcp")
            correct_port = bindings == [{"HostIp": "127.0.0.1", "HostPort": str(saved.get("port"))}]
            if mounts_match(record, mounts) and correct_port and record["State"].get("Health", {}).get("Status") == "healthy" and found == saved.get("identity") and found and found.get("fingerprint") == digest:
                address = f"http://127.0.0.1:{saved['port']}"
                if open_browser:
                    webbrowser.open(address)
                return {"address": address, "container": name, "reused": True}
        if record:
            docker("container", "rm", "--force", record["Id"])
        write_json(runtime / "runtime.json", config)
        token = str(uuid.uuid4())
        service = {"image": image, "container_name": name, "read_only": True,
                   "tmpfs": ["/tmp"], "cap_drop": ["ALL"], "security_opt": ["no-new-privileges:true"],
                   "volumes": mounts, "environment": {"FACTORY_DASHBOARD_CONFIG": "/etc/factory-dashboard/runtime.json", "FACTORY_DASHBOARD_TOKEN": token},
                   "labels": {LABEL: owner, "org.armoury.dashboard.config": revision},
                   "logging": {"driver": "json-file", "options": {"max-size": "5m", "max-file": "2"}}}
        if os.name != "nt" and os.uname().sysname == "Linux":
            service["user"] = f"{os.getuid()}:{os.getgid()}"
        compose_path = runtime / "compose.json"
        for candidate in range(port, min(port + 100, 65536)):
            with socket.socket() as probe:
                try:
                    probe.bind(("127.0.0.1", candidate))
                except OSError:
                    continue
            service["ports"] = [{"target": 4601, "published": str(candidate), "host_ip": "127.0.0.1", "protocol": "tcp"}]
            write_json(compose_path, {"name": name, "services": {"dashboard": service}})
            launched = docker("compose", "-f", str(compose_path), "up", "-d", check=False)
            if launched.returncode:
                if "port is already allocated" in launched.stderr or "address already in use" in launched.stderr:
                    collision = inspect(name, owner)
                    if collision:
                        docker("container", "rm", "--force", collision["Id"])
                    continue
                raise FactoryError(f"Dashboard container failed to start: {launched.stderr}")
            expected = {"application": "software-factory-dashboard", "version": 1, "host": str(root),
                        "token": token, "runtime": "docker", "fingerprint": digest}
            for _ in range(45):
                found = identity(candidate)
                current = inspect(name, owner)
                if current and current["State"].get("Health", {}).get("Status") == "healthy" and found == expected:
                    with locked(root):
                        write_json(metadata_path, {"port": candidate, "container_id": current["Id"], "identity": expected})
                    address = f"http://127.0.0.1:{candidate}"
                    if open_browser:
                        webbrowser.open(address)
                    return {"address": address, "container": name, "reused": False}
                if not current or not current["State"]["Running"]:
                    break
                time.sleep(1)
            logs = docker("logs", "--tail", "50", name, check=False)
            raise FactoryError(f"Dashboard failed its health check: {logs.stdout}{logs.stderr}")
        raise FactoryError("No available dashboard port.")
