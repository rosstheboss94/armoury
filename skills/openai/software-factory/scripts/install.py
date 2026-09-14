"""Install factory-owned files without replacing project records or discovery configuration."""

import argparse
import os
import shutil
import sys
from pathlib import Path

from storage import FactoryError
from factory_paths import RELATIVE
from workspace import is_link, validate_parents


def install(source, project):
    source = Path(source).resolve()
    project = Path(project).resolve()
    if not project.is_dir() or not (source / "SKILL.md").is_file():
        raise FactoryError("Source skill and target project must exist.")
    validate_parents(project)
    target = project / RELATIVE
    if is_link(target):
        raise FactoryError("Install into the canonical checkout, not a linked feature worktree.")
    # Preflight all destinations before copying any package files.
    files = []
    originals = []
    excluded = {"__pycache__", "node_modules", "dist", ".venv", ".pytest_cache", ".runtime"}
    for directory, folders, names in os.walk(source):
        folders[:] = [name for name in folders if name not in excluded and not (Path(directory) == source and name in ("specs", "state"))]
        for name in folders:
            if is_link(Path(directory) / name):
                raise FactoryError(f"Package directories must not be links: {Path(directory) / name}")
        originals.extend(Path(directory) / name for name in names)
    for original in originals:
        relative = original.relative_to(source)
        if relative.parts[0] in ("specs", "state", ".runtime") or any(p in ("__pycache__", "node_modules", "dist", ".venv", ".pytest_cache") for p in relative.parts) or original.suffix == ".pyc":
            continue
        if is_link(original):
            raise FactoryError(f"Package files must not be links: {original}")
        if original.is_file():
            destination = target / relative
            if any(is_link(p) for p in [destination, *destination.parents] if p != project.parent):
                raise FactoryError(f"Linked destination requires reconciliation: {destination}")
            if destination.exists() and not destination.is_file():
                raise FactoryError(f"Destination is not a file: {destination}")
            files.append((original, destination))
    for original, destination in files:
        destination.parent.mkdir(parents=True, exist_ok=True)
        if original != destination:
            shutil.copy2(original, destination)
    return target


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--project", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        print(f"Installed software-factory -> {install(args.source, args.project)}")
        return 0
    except (FactoryError, OSError) as exc:
        print(str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
