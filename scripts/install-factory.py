"""Install selected Armoury skills into a project."""

import argparse
import os
import re
import shutil
import stat
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DESTINATION = Path(".agents/skills")
EXCLUDED_DIR_NAMES = {"__pycache__", "node_modules", "dist", ".venv", ".pytest_cache", ".runtime"}
PRESERVED_ROOT_DIRS = {"specs", "state"}


class InstallError(Exception):
    pass


def is_link(path):
    try:
        info = path.lstat()
        return stat.S_ISLNK(info.st_mode) or bool(getattr(info, "st_file_attributes", 0) & 1024)
    except FileNotFoundError:
        return False


def skill_names(model):
    names = []
    root = ROOT / "skills" / model
    if not root.is_dir():
        raise InstallError(f"Unknown model: {model}")
    for path in sorted(root.iterdir()):
        if path.is_dir() and (path / "SKILL.md").is_file():
            names.append(path.name)
    return names


def collections():
    found = {}
    for manifest in sorted((ROOT / "collections").glob("*/collection.yaml")):
        text = manifest.read_text(encoding="utf-8")
        name = None
        for line in text.splitlines():
            if line.startswith("name:"):
                name = line.split(":", 1)[1].strip()
                break
        members = re.findall(r"^  - ([a-z0-9-]+)$", text, re.MULTILINE)
        if name:
            found[name] = members
    return found


def resolve(model, selection):
    available = skill_names(model)
    catalog = collections()
    chosen = []
    seen = set()
    tokens = [token.strip().lower() for token in selection.split(",") if token.strip()]
    if not tokens:
        raise InstallError("Select at least one skill, all, 0, a number, or collection:<name>.")
    for token in tokens:
        if token in ("all", "0"):
            names = available
        elif token.isdigit():
            index = int(token)
            if index < 1 or index > len(available):
                raise InstallError(f"Unknown skill number: {token}")
            names = [available[index - 1]]
        elif token.startswith("collection:"):
            name = token.split(":", 1)[1]
            if name not in catalog:
                raise InstallError(f"Unknown collection: {name}")
            names = catalog[name]
        elif token in available:
            names = [token]
        else:
            raise InstallError(f"Unknown skill: {token}")
        for name in names:
            if name not in available:
                raise InstallError(f"Unknown skill: {name}")
            if name not in seen:
                seen.add(name)
                chosen.append(name)
    return chosen


def validate_parents(project):
    project = Path(project).resolve()
    relatives = [*reversed(DESTINATION.parents[:-1]), DESTINATION]
    for relative in relatives:
        parent = project / relative
        if is_link(parent) or (parent.exists() and not parent.is_dir()):
            raise InstallError(f"The project's {relative.as_posix()} must be a physical directory.")


def packaged_files(source):
    files = []
    source = Path(source)
    for directory, folders, names in os.walk(source):
        current = Path(directory)
        skipped = set(EXCLUDED_DIR_NAMES)
        if current == source:
            skipped |= PRESERVED_ROOT_DIRS
        folders[:] = [name for name in folders if name not in skipped]
        for name in folders:
            if is_link(current / name):
                raise InstallError(f"Package directories must not be links: {current / name}")
        for name in names:
            original = current / name
            relative = original.relative_to(source)
            if relative.parts[0] in PRESERVED_ROOT_DIRS or any(part in EXCLUDED_DIR_NAMES for part in relative.parts) or original.suffix == ".pyc":
                continue
            if is_link(original):
                raise InstallError(f"Package files must not be links: {original}")
            if original.is_file():
                files.append(original)
    return files


def install(model, names, project):
    project = Path(project).resolve()
    if not project.is_dir():
        raise InstallError("The target project directory must exist.")
    validate_parents(project)
    planned = []
    for name in names:
        source = (ROOT / "skills" / model / name).resolve()
        if not (source / "SKILL.md").is_file():
            raise InstallError(f"The source {name} package is missing SKILL.md.")
        target = project / DESTINATION / name
        if is_link(target):
            raise InstallError("Install into the canonical checkout, not a linked feature worktree.")
        for original in packaged_files(source):
            destination = target / original.relative_to(source)
            if any(is_link(path) for path in [destination, *destination.parents] if path != project.parent):
                raise InstallError(f"Linked destination requires reconciliation: {destination}")
            if destination.exists() and not destination.is_file():
                raise InstallError(f"Destination is not a file: {destination}")
            planned.append((original, destination))
    for original, destination in planned:
        destination.parent.mkdir(parents=True, exist_ok=True)
        if original != destination:
            shutil.copy2(original, destination)
    return project / DESTINATION


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", choices=("openai", "claude"), type=str.lower)
    parser.add_argument("--skills", help="skill name, all, 0, a 1-based number, or collection:<name>")
    parser.add_argument("--project")
    args = parser.parse_args(argv)
    interactive = not all((args.model, args.skills, args.project))
    try:
        model = args.model or input("Model [openai/claude]: ").strip().lower()
        if model not in ("openai", "claude"):
            parser.error("Select openai or claude.")
        selection = args.skills or input("Skill [software-factory]: ").strip() or "software-factory"
        project = args.project or input("Project root: ").strip()
        names = resolve(model, selection)
        if not Path(project).is_dir():
            parser.error("The target project directory must exist.")
        label = ", ".join(names)
        if interactive and input(f"Install {model} {label} into {project}? [Y/n]: ").strip().lower() in ("n", "no"):
            print("Cancelled.")
            return 0
        destination = install(model, names, project)
        print(f"Installed {label} -> {destination}")
        return 0
    except (InstallError, EOFError, OSError) as exc:
        print(str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
