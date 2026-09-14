"""Prepare, register, and open the local factory dashboard."""

import argparse
import hashlib
from http.client import HTTPException
import json
import os
import shutil
import socket
import subprocess
import sys
import time
import uuid
import venv
import webbrowser
from pathlib import Path
from urllib.request import urlopen

from factory_paths import existing_factory
from observation import project
from storage import FactoryError, locked, read_json, write_json
from registration import merge, ProjectDirectory


def register(host, roots, restore=False):
    entries = []
    for value in roots:
        root = Path(value).resolve()
        if not (root / "SKILL.md").is_file():
            found = existing_factory(root)
            root = found.resolve() if found is not None else root
        if not (root / "SKILL.md").is_file():
            raise FactoryError(f"No installed factory at {value}")
        with locked(root):
            record = project(root)
        entries.append({**record, "factory": str(root)})
    merge(Path(host) / "state/dashboard", entries, restore=restore)


def identity(port):
    try:
        with urlopen(f"http://127.0.0.1:{port}/api/identity", timeout=1) as response:
            return json.load(response)
    except (OSError, ValueError, HTTPException):
        return None


def prepare(root):
    runtime = root / ".runtime"
    environment = runtime / "python"
    python = environment / ("Scripts/python.exe" if os.name == "nt" else "bin/python")
    if not python.exists():
        venv.create(environment, with_pip=True)
    lock = root / "app/backend/requirements.lock"
    digest = hashlib.sha256(lock.read_bytes()).hexdigest()
    marker = runtime / "dependencies.json"
    if not marker.exists() or read_json(marker).get("hash") != digest:
        subprocess.run([str(python), "-m", "pip", "install", "-r", str(lock)], check=True)
        write_json(marker, {"hash": digest})
    frontend = root / "app/frontend"
    sources = sorted(p for p in frontend.rglob("*") if p.is_file() and not set(p.relative_to(frontend).parts) & {"node_modules", "dist"})
    digest = hashlib.sha256(b"".join(p.relative_to(frontend).as_posix().encode() + p.read_bytes() for p in sources)).hexdigest()
    marker = runtime / "frontend.json"
    if not (frontend / "dist/index.html").exists() or not marker.exists() or read_json(marker).get("hash") != digest:
        npm = shutil.which("npm.cmd" if os.name == "nt" else "npm")
        if not npm:
            raise FactoryError("Node.js and npm are required to build the dashboard.")
        subprocess.run([npm, "ci", "--no-audit", "--no-fund"], cwd=frontend, check=True)
        subprocess.run([npm, "run", "build"], cwd=frontend, check=True)
        write_json(marker, {"hash": digest})
    return python


def launch(root, port=4601, open_browser=True, prepare_assets=True, projects_directory=None):
    root = Path(root).resolve()
    metadata = root / "state/dashboard/server.json"
    saved = read_json(metadata) if metadata.exists() else {}
    if saved.get("port"):
        found = identity(saved["port"])
        if found == {"application": "software-factory-dashboard", "version": 1, "host": str(root), "token": saved.get("token")} and saved.get("projects_directory") == projects_directory:
            address = f"http://127.0.0.1:{saved['port']}"
            if open_browser:
                webbrowser.open(address)
            return address
    python = prepare(root) if prepare_assets else Path(sys.executable)
    environment = dict(os.environ, FACTORY_DASHBOARD_ROOT=str(root), FACTORY_DASHBOARD_TOKEN=str(uuid.uuid4()))
    environment["FACTORY_PROJECTS_DIRECTORY"] = projects_directory or ""
    runtime = root / ".runtime"
    runtime.mkdir(exist_ok=True)
    for candidate in range(port, min(port + 100, 65536)):
        with socket.socket() as probe:
            try:
                probe.bind(("127.0.0.1", candidate))
            except OSError:
                continue
        with (runtime / "dashboard.log").open("ab") as log:
            process = subprocess.Popen([str(python), "-m", "uvicorn", "server:app", "--app-dir", str(root / "app/backend"),
                                        "--host", "127.0.0.1", "--port", str(candidate)],
                                       env=environment, stdout=log, stderr=log, stdin=subprocess.DEVNULL,
                                       creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0,
                                       start_new_session=os.name != "nt")
        for _ in range(60):
            found = identity(candidate)
            if found and found.get("token") == environment["FACTORY_DASHBOARD_TOKEN"] and found.get("host") == str(root):
                with locked(root):
                    write_json(metadata, {"port": candidate, "pid": process.pid, "token": found["token"], "projects_directory": projects_directory})
                address = f"http://127.0.0.1:{candidate}"
                if open_browser:
                    webbrowser.open(address)
                return address
            if process.poll() is not None:
                break
            time.sleep(0.1)
        if process.poll() is None:
            process.terminate()
            process.wait(timeout=10)
        raise FactoryError(f"Dashboard failed to start. Inspect {runtime / 'dashboard.log'}")
    raise FactoryError("No available dashboard port.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--project", action="append", default=[])
    parser.add_argument("--projects-directory", default=os.environ.get("FACTORY_PROJECTS_DIRECTORY"))
    parser.add_argument("--port", type=int, default=4601)
    parser.add_argument("--no-open", action="store_true")
    parser.add_argument("--runtime", choices=("docker", "native"), default="docker")
    lifecycle = parser.add_mutually_exclusive_group()
    lifecycle.add_argument("--status", action="store_true")
    lifecycle.add_argument("--stop", action="store_true")
    args = parser.parse_args()
    try:
        if not 1024 <= args.port <= 65535:
            raise FactoryError("Port must be between 1024 and 65535.")
        root = args.root.resolve()
        projects_directory = str(ProjectDirectory(args.projects_directory).local) if args.projects_directory else None
        if args.status or args.stop:
            if args.runtime != "docker":
                raise FactoryError("--status and --stop manage Docker dashboards only.")
            from docker_dashboard import control
            print(json.dumps(control(root, action="stop" if args.stop else "status")))
            return 0
        if args.runtime == "docker":
            from docker_dashboard import preflight, control
            preflight()
        register(root, args.project or [root], restore=bool(args.project))
        output = control(root, args.port, not args.no_open, projects_directory=projects_directory) if args.runtime == "docker" else {"address": launch(root, args.port, not args.no_open, projects_directory=projects_directory)}
        print(json.dumps(output))
    except (FactoryError, OSError, subprocess.SubprocessError) as exc:
        print(json.dumps({"error": str(exc)}), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
