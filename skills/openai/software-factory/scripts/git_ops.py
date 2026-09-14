"""Scoped Git operations. No shell interpolation or implicit force operations."""

import hashlib
import subprocess
from pathlib import Path

from factory_paths import RELATIVE
from storage import FactoryError


def command(cwd, args):
    result = subprocess.run(args, cwd=cwd, text=True, encoding="utf-8",
                            errors="replace", capture_output=True)
    if result.returncode:
        raise FactoryError(result.stderr.strip() or result.stdout.strip() or f"Command failed: {args[0]}")
    return result.stdout.strip()


def git(cwd, *args):
    return command(cwd, ["git", *args])


def snapshot(cwd, base):
    head = git(cwd, "rev-parse", "HEAD")
    base_commit = git(cwd, "rev-parse", "--verify", base + "^{commit}")
    paths = ("--", ".", f":(exclude){RELATIVE.as_posix()}")
    diff = git(cwd, "diff", "--binary", "HEAD", *paths)
    untracked = git(cwd, "ls-files", "--others", "--exclude-standard", "-z", *paths)
    digest = hashlib.sha256(diff.encode())
    for name in filter(None, untracked.split("\0")):
        path = Path(cwd) / name
        digest.update(name.encode())
        if path.is_symlink():
            digest.update(str(path.readlink()).encode())
        elif path.is_file():
            digest.update(path.read_bytes())
    specs = Path(cwd) / RELATIVE / "specs"
    spec_digest = hashlib.sha256()
    if specs.exists():
        for path in sorted(specs.rglob("*")):
            if path.is_file():
                spec_digest.update(str(path.relative_to(specs)).encode())
                spec_digest.update(path.read_bytes())
    return {"head": head, "base": base_commit, "diff": digest.hexdigest(),
            "specs": spec_digest.hexdigest(),
            "clean": not bool(git(cwd, "status", "--porcelain", *paths))}


def identity(cwd):
    return {"worktree": str(Path(git(cwd, "rev-parse", "--show-toplevel")).resolve()),
            "branch": git(cwd, "symbolic-ref", "--short", "HEAD")}


def scoped_commit(cwd, files, message, expected):
    if git(cwd, "rev-parse", "HEAD") != expected:
        raise FactoryError("HEAD changed before commit; reconcile the work first.")
    if not message.strip() or not files:
        raise FactoryError("Commit requires an inspected file list and message.")
    for name in files:
        path = Path(name)
        if path.is_absolute() or ".." in path.parts or name.startswith("-") or name.startswith(":"):
            raise FactoryError("Commit paths must be literal project-relative paths.")
        if path.parts[:len(RELATIVE.parts)] == RELATIVE.parts:
            raise FactoryError("Factory records cannot be staged as product changes.")
        if (Path(cwd) / path).is_dir():
            raise FactoryError("Commit paths must name files, not directories.")
    staged = set(filter(None, git(cwd, "diff", "--cached", "--name-only", "-z").split("\0")))
    if staged - set(files):
        raise FactoryError("Unrelated staged changes exist. Preserve and reconcile them before committing.")
    git(cwd, "--literal-pathspecs", "add", "--", *files)
    if not git(cwd, "diff", "--cached", "--name-only"):
        return expected
    git(cwd, "commit", "-m", message)
    return git(cwd, "rev-parse", "HEAD")
