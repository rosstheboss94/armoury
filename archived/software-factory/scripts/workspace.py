"""One physical factory directory, linked into feature worktrees."""

import os
import stat
import subprocess
from pathlib import Path

from git_ops import git, snapshot
from storage import FactoryError


RELATIVE = Path(".agents/software-factory")


def is_link(path):
    try:
        info = path.lstat()
        return stat.S_ISLNK(info.st_mode) or bool(getattr(info, "st_file_attributes", 0) & 1024)
    except FileNotFoundError:
        return False


def registered(project):
    output = git(project, "worktree", "list", "--porcelain", "-z")
    return [Path(field[9:]).resolve() for field in output.split("\0") if field.startswith("worktree ")]


def make_link(link, target):
    link.parent.mkdir(parents=True, exist_ok=True)
    if os.name == "nt":
        env = dict(os.environ, FACTORY_LINK=str(link), FACTORY_TARGET=str(target))
        script = "$ErrorActionPreference='Stop'; New-Item -ItemType Junction -Path $env:FACTORY_LINK -Target $env:FACTORY_TARGET | Out-Null"
        result = subprocess.run(["powershell", "-NoProfile", "-NonInteractive", "-Command", script],
                                capture_output=True, text=True, env=env)
        if result.returncode:
            # Symbolic links support targets for which junction creation is unavailable.
            try:
                os.symlink(target, link, target_is_directory=True)
            except OSError as exc:
                raise FactoryError(f"Cannot link {link}: {result.stderr.strip()}; {exc}") from exc
    else:
        os.symlink(target, link, target_is_directory=True)


def verify(root, project):
    root = Path(root).resolve()
    results = []
    for worktree in registered(project):
        link = worktree / RELATIVE
        if link == root:
            if is_link(link) or not link.is_dir():
                raise FactoryError("Canonical factory must be a physical directory.")
        elif not is_link(link) or link.resolve() != root or not link.is_dir():
            raise FactoryError(f"Factory link is missing or points elsewhere: {link}")
        results.append(str(link))
    return {"canonical": str(root), "linked_worktrees": results}


def share(root, project):
    root = Path(root).resolve()
    worktrees = registered(project)
    if root not in [p / RELATIVE for p in worktrees]:
        raise FactoryError("The canonical factory must belong to a registered checkout.")
    # Complete preflight before changing any worktree.
    for worktree in worktrees:
        link = worktree / RELATIVE
        if link == root:
            continue
        if is_link(link):
            if link.resolve() != root or not link.is_dir():
                raise FactoryError(f"Unexpected factory target: {link}")
        elif link.exists():
            raise FactoryError(f"A physical factory path already exists: {link}")
        if git(worktree, "ls-files", "--", str(RELATIVE)):
            raise FactoryError(f"Tracked factory content prevents linking: {worktree}")
    for worktree in worktrees:
        link = worktree / RELATIVE
        if link != root and not is_link(link):
            make_link(link, root)
    return verify(root, project)


def migrate(root, project):
    """Explicitly adopt one untracked spec tree and legacy delivery records."""
    root = Path(root).resolve()
    common = Path(git(project, "rev-parse", "--path-format=absolute", "--git-common-dir"))
    candidates = [p / "specs" for p in registered(project)] + [common / "tldr/specs"]
    target = root / "specs"
    if is_link(target) or is_link(root / "state") or is_link(root / "state/legacy"):
        raise FactoryError("Canonical specifications and legacy records must be physical directories inside the factory.")
    physical = []
    links = []
    for worktree in registered(project):
        if git(worktree, "ls-files", "--", "specs"):
            raise FactoryError("Tracked specifications require an explicit migration decision.")
    for path in candidates:
        if is_link(path):
            links.append(path)
        elif path.exists():
            if not path.is_dir():
                raise FactoryError(f"Specification path is not a directory: {path}")
            if any(path.iterdir()):
                physical.append(path)
    if target.exists() and any(target.iterdir()):
        physical.append(target)
    if len(physical) > 1:
        raise FactoryError("Competing specification trees exist; reconcile them before migration.")
    source = physical[0] if physical else target
    for link in links:
        if link.resolve() not in (source.resolve(), target.resolve()):
            raise FactoryError(f"Unexpected specification link: {link}")
    records = list((common / "tldr").glob("*.md"))
    for record in records:
        destination = root / "state/legacy" / record.name
        if destination.exists():
            raise FactoryError(f"Existing delivery record requires reconciliation: {destination}")
    if source != target:
        if target.exists():
            target.rmdir()  # Preflight confirmed empty.
        source.rename(target)
    elif physical:
        pass
    # Retire only verified links, never their targets.
    for link in links:
        unlink(link)
    for path in candidates:
        if path.exists() and not any(path.iterdir()):
            path.rmdir()
    if records:
        (root / "state/legacy").mkdir(parents=True, exist_ok=True)
        for record in records:
            record.rename(root / "state/legacy" / record.name)
    return {"specs": str(target), "legacy_records": [r.name for r in records],
            "next": "Reconcile checkpoint links and legacy round history before starting a resumed run."}


def unlink(path):
    if not is_link(path):
        raise FactoryError(f"Refusing to unlink a physical directory: {path}")
    if os.name == "nt" and not path.is_symlink():
        os.rmdir(path)
    else:
        path.unlink()


def prepare(root, request):
    project = Path(request["project"]).resolve()
    target = Path(request["worktree"]).absolute()
    branch = request["branch"]
    base = request["base"]
    git(project, "check-ref-format", "--branch", branch)
    git(project, "rev-parse", "--verify", base + "^{commit}")
    if target.resolve() in registered(project):
        if git(target, "symbolic-ref", "--short", "HEAD") != branch:
            raise FactoryError("Registered worktree belongs to a different branch.")
    else:
        if target.exists() or is_link(target):
            raise FactoryError("New worktree path must be unused.")
        # Git itself rejects a branch checked out elsewhere.
        exists = subprocess.run(["git", "show-ref", "--verify", "--quiet", "refs/heads/" + branch], cwd=project).returncode == 0
        args = ["worktree", "add", str(target), branch] if exists else ["worktree", "add", "-b", branch, str(target), base]
        git(project, *args)
    return share(root, project)


def cleanup(root, request):
    project = Path(request["project"]).resolve()
    target = Path(request["worktree"]).resolve()
    root = Path(root).resolve()
    if request.get("cleanup_authorized") is not True or request.get("commits_preserved") is not True:
        raise FactoryError("Cleanup requires the user's request and verified durable commit evidence.")
    if not request.get("preservation_evidence"):
        raise FactoryError("Record merge or durable preservation evidence before cleanup.")
    if target not in registered(project) or root.is_relative_to(target):
        raise FactoryError("Cannot remove an unregistered worktree or the canonical factory checkout.")
    link = target / RELATIVE
    if not is_link(link) or link.resolve() != root:
        raise FactoryError("Verify the factory link before cleanup.")
    # A POSIX link can appear as untracked. Remove that one status entry only.
    if not snapshot(target, "HEAD")["clean"]:
        raise FactoryError("Worktree contains unpreserved changes.")
    unlink(link)
    try:
        git(project, "worktree", "remove", str(target))
    except FactoryError:
        if target.exists() and not link.exists():
            make_link(link, root)
        raise
    return {"removed_worktree": str(target), "canonical_retained": str(root)}
