"""Install factory-owned files without replacing project records or discovery configuration."""

import argparse
import shutil
import sys
from pathlib import Path

from storage import FactoryError
from workspace import RELATIVE, is_link


def install(source, project):
    source = Path(source).resolve()
    project = Path(project).resolve()
    if not project.is_dir() or not (source / "SKILL.md").is_file():
        raise FactoryError("Source skill and target project must exist.")
    target = project / RELATIVE
    if is_link(target):
        raise FactoryError("Install into the canonical checkout, not a linked feature worktree.")
    # Preflight all destinations before copying any package files.
    files = []
    for original in source.rglob("*"):
        relative = original.relative_to(source)
        if relative.parts[0] in ("specs", "state") or "__pycache__" in relative.parts or original.suffix == ".pyc":
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
