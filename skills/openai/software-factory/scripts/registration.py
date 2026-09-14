"""Install and register local projects within an explicitly configured directory."""

import tempfile
import uuid
from pathlib import Path, PurePosixPath, PureWindowsPath

from install import install
from workspace import validate_parents
from factory_paths import RELATIVE, project_directory
from storage import FactoryError, locked, read_json, write_json


class RegistrationConflict(FactoryError):
    pass


class ProjectDirectory:
    def __init__(self, host, local=None):
        self.host = PureWindowsPath(host) if PureWindowsPath(host).drive else PurePosixPath(host)
        if not self.host.is_absolute():
            raise FactoryError("The configured projects directory must be absolute.")
        self.local = Path(local or host).resolve()
        if not self.local.is_dir():
            raise FactoryError("The configured projects directory must exist.")

    def resolve(self, value):
        if not isinstance(value, str) or not value.strip() or "\x00" in value:
            raise FactoryError("Enter a project directory.")
        value = value.strip()
        path = type(self.host)(value)
        if path.is_absolute():
            try:
                path = path.relative_to(self.host)
            except ValueError as exc:
                raise FactoryError("Project must be inside the configured projects directory.") from exc
        elif path.anchor or PureWindowsPath(value).drive:
            raise FactoryError("Enter a relative path or an absolute path inside the projects directory.")
        if ".." in path.parts:
            raise FactoryError("Parent traversal is unavailable. Enter the project path directly.")
        result = (self.local / Path(*path.parts)).resolve()
        if not result.is_relative_to(self.local):
            raise FactoryError("Project links must stay inside the configured projects directory.")
        return result

    def host_path(self, local):
        return str(self.host.joinpath(*Path(local).resolve().relative_to(self.local).parts))


def entries(directory):
    path = Path(directory) / "projects.json"
    value = read_json(path) if path.exists() else []
    if not isinstance(value, list) or any(not isinstance(p, dict) or not all(k in p for k in ("id", "factory")) for p in value):
        raise FactoryError("Malformed project registry.")
    return value


def merge(directory, records):
    with locked(directory):
        merged = {p["id"]: p for p in entries(directory)}
        merged.update({p["id"]: p for p in records})
        write_json(Path(directory) / "projects.json", list(merged.values()))


class Registration:
    def __init__(self, source, registry, directory=None):
        self.source = Path(source)
        self.registry = Path(registry)
        self.directory = directory

    def add(self, value):
        if self.directory is None:
            raise RegistrationConflict("Configure a projects directory before adding projects.")
        folder = self.directory.resolve(value)
        if not folder.is_dir():
            raise FactoryError("The project directory must already exist.")
        target = folder / RELATIVE
        canonical = target.resolve()
        if not canonical.is_relative_to(self.directory.local):
            raise FactoryError("Enter the canonical project path inside the projects directory.")
        # Reject redirected installation parents, even when the link stays in the workspace.
        try:
            validate_parents(folder)
        except FactoryError as exc:
            raise RegistrationConflict(str(exc)) from exc
        installed = False
        with locked(self.registry):
            previous = entries(self.registry)
            if target.exists() or target.is_symlink():
                if not (canonical / "SKILL.md").is_file() or not (canonical / "scripts/install.py").is_file():
                    raise RegistrationConflict("The existing factory is incomplete. Reconcile it before adding this project.")
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                with tempfile.TemporaryDirectory(prefix=".factory-install-", dir=target.parent) as temporary:
                    staged = install(self.source, Path(temporary))
                    if target.exists() or target.is_symlink():
                        raise RegistrationConflict("A factory appeared during installation. Retry adding the project.")
                    staged.rename(target)
                installed = True
            for child in ("state", "specs"):
                if (canonical / child).resolve() != canonical / child:
                    raise RegistrationConflict("Factory records must use physical directories. Enter the canonical project path.")
            with locked(canonical):
                identity_path = canonical / "state/project.json"
                if identity_path.is_symlink():
                    raise RegistrationConflict("Project identity must be a physical file.")
                if identity_path.exists():
                    record = read_json(identity_path)
                    if not isinstance(record, dict) or not all(k in record for k in ("id", "name", "factory")):
                        raise RegistrationConflict("The existing project identity is malformed.")
                    try:
                        uuid.UUID(record["id"])
                    except (ValueError, TypeError, AttributeError) as exc:
                        raise RegistrationConflict("The existing project identity is malformed.") from exc
                else:
                    from observation import now
                    record = {"version": 1, "id": str(uuid.uuid4()), "name": project_directory(canonical).name,
                              "factory": self.directory.host_path(canonical), "created_at": now()}
                    write_json(identity_path, record)
            record = {**record, "factory": self.directory.host_path(canonical)}
            already = any(p["id"] == record["id"] for p in previous)
            merged = {p["id"]: p for p in previous}
            merged[record["id"]] = record
            write_json(self.registry / "projects.json", list(merged.values()))
        return {"project": record, "installed": installed, "already_registered": already}
