"""Shared project-local installation layout. No factory module dependencies."""

from pathlib import Path, PurePosixPath, PureWindowsPath


RELATIVE = Path(".agents/skills/software-factory")
LEGACY_RELATIVE = Path(".agents/software-factory")


def _pure(factory):
    text = str(factory)
    return PureWindowsPath(text) if PureWindowsPath(text).drive else PurePosixPath(text.replace("\\", "/"))


def _under(factory, relative):
    parts = relative.parts
    tail = factory.parts[-len(parts):] if len(factory.parts) >= len(parts) else ()
    return tuple(part.casefold() for part in tail) == tuple(part.casefold() for part in parts)


def project_directory(factory):
    """Return the project containing an installed factory."""
    factory = Path(factory).resolve()
    path = _pure(factory)
    for relative in (RELATIVE, LEGACY_RELATIVE):
        if _under(path, relative):
            return Path(path.parents[len(relative.parts) - 1])
    return Path(path.parents[len(RELATIVE.parts) - 1])


def project_key(factory):
    """Case-insensitive project folder key for canonical and legacy factory paths."""
    path = _pure(factory)
    for relative in (RELATIVE, LEGACY_RELATIVE):
        if _under(path, relative):
            folder = path.parents[len(relative.parts) - 1]
            break
    else:
        folder = path.parents[len(RELATIVE.parts) - 1] if len(path.parts) > len(RELATIVE.parts) else path
    return str(folder).replace("\\", "/").casefold()


def existing_factory(project):
    """Return the canonical or legacy factory path if either is present."""
    project = Path(project)
    for relative in (RELATIVE, LEGACY_RELATIVE):
        path = project / relative
        if path.exists() or path.is_symlink():
            return path
    return None
