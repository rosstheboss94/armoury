"""Shared project-local installation layout. No factory module dependencies."""

from pathlib import Path


RELATIVE = Path(".agents/skills/software-factory")


def project_directory(factory):
    """Return the project containing an installed factory."""
    return Path(factory).resolve().parents[len(RELATIVE.parts) - 1]
