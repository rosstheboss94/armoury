"""Atomic local records and exclusive access to shared factory state."""

import json
import os
import uuid
from contextlib import contextmanager
from pathlib import Path


class FactoryError(Exception):
    pass


def read_json(path):
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        raise FactoryError(f"Cannot read JSON at {path}: {exc}") from exc


def write_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + "." + uuid.uuid4().hex + ".tmp")
    try:
        temporary.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def run_path(root, identifier):
    try:
        if str(uuid.UUID(identifier)) != identifier:
            raise ValueError()
    except (ValueError, AttributeError):
        raise FactoryError("Run identifier must be a canonical UUID.")
    root = Path(root).resolve()
    path = root / "state" / identifier / "run.json"
    if not path.resolve().is_relative_to(root):
        raise FactoryError("State must remain inside the canonical factory.")
    return path


@contextmanager
def locked(root):
    directory = Path(root) / "state"
    if not directory.resolve().is_relative_to(Path(root).resolve()):
        raise FactoryError("State must remain inside the canonical factory.")
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / ".lock"
    try:
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError:
        raise FactoryError("Factory state is locked. Inspect its recorded PID before recovering a stale lock.")
    try:
        with os.fdopen(fd, "w") as stream:
            stream.write(str(os.getpid()))
        yield
    finally:
        path.unlink()


def save(root, run):
    path = run_path(root, run["id"])
    write_json(path, run)
    # JSON owns recovery. Markdown is a readable view rebuilt on the next save.
    lines = ["# Delivery progress", "", f"Run: {run['id']}",
             f"Task: {run['request']['task']}", f"Phase: {run['phase']}",
             f"Review round: {run['round']}", f"Blocked: {run.get('blocker', '')}", "",
             "## History", ""]
    lines.extend("- " + json.dumps(item, ensure_ascii=False) for item in run["history"])
    path.with_name("progress.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
