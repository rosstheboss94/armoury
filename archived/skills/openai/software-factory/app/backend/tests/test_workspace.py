"""Installed factory paths, Git protection, and shared worktree lifetime."""

import sys
from pathlib import Path

import pytest

SOURCE = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(SOURCE / "scripts"))
import git_ops
import install
import observation
import workspace
from factory_paths import RELATIVE
from storage import FactoryError


@pytest.fixture
def installed(tmp_path):
    project = tmp_path / "Actual project name"
    project.mkdir()
    git_ops.git(project, "init", "-b", "main")
    git_ops.git(project, "config", "user.name", "Factory tests")
    git_ops.git(project, "config", "user.email", "factory@example.invalid")
    (project / "product.txt").write_text("Initial")
    git_ops.git(project, "add", "product.txt")
    git_ops.git(project, "commit", "-m", "Initial")
    return project, install.install(SOURCE, project)


def test_identity_and_git_scope(installed):
    project, root = installed
    assert root == project / ".agents/skills/software-factory"
    assert observation.project(root)["name"] == project.name
    before = git_ops.snapshot(project, "HEAD")
    assert before["clean"]
    (root / "specs").mkdir()
    (root / "specs/local.md").write_text("Specification")
    after = git_ops.snapshot(project, "HEAD")
    assert after["clean"] and after["specs"] != before["specs"]
    for path in (RELATIVE, RELATIVE / "SKILL.md", RELATIVE / "specs/local.md"):
        with pytest.raises(FactoryError, match="cannot be staged"):
            git_ops.scoped_commit(project, [path.as_posix()], "Factory", after["head"])
    neighbor = project / ".agents/skills/neighbor/SKILL.md"
    neighbor.parent.mkdir()
    neighbor.write_text("Neighbor")
    assert not git_ops.snapshot(project, "HEAD")["clean"]
    git_ops.scoped_commit(project, [neighbor.relative_to(project).as_posix()], "Neighbor", after["head"])
    assert git_ops.snapshot(project, "HEAD")["clean"]
    neighbor.write_text("Changed neighbor")
    assert not git_ops.snapshot(project, "HEAD")["clean"]


def test_shared_worktree_cleanup(installed, tmp_path):
    project, root = installed
    feature = tmp_path / "feature"
    workspace.prepare(root, {"project": project, "worktree": feature, "branch": "feature", "base": "main"})
    link = feature / RELATIVE
    try:
        assert link.resolve() == root
        assert len(workspace.verify(root, project)["linked_worktrees"]) == 2
        (root / "local.txt").write_text("Shared")
        assert (link / "local.txt").read_text() == "Shared"
        assert git_ops.snapshot(feature, "main")["clean"]
        neighbor = feature / ".agents/skills/neighbor/SKILL.md"
        neighbor.parent.mkdir()
        neighbor.write_text("Keep")
        request = {"project": project, "worktree": feature, "cleanup_authorized": True,
                   "commits_preserved": True, "preservation_evidence": "Feature HEAD equals main"}
        with pytest.raises(FactoryError, match="unpreserved"):
            workspace.cleanup(root, request)
        assert neighbor.read_text() == "Keep" and link.resolve() == root
        neighbor.unlink()
        neighbor.parent.rmdir()
        workspace.cleanup(root, request)
        assert not feature.exists()
        assert (root / "local.txt").read_text() == "Shared"
    finally:
        if workspace.is_link(link):
            workspace.unlink(link)


@pytest.mark.parametrize("relative", [".agents", ".agents/skills"])
def test_share_rejects_redirected_parents(installed, tmp_path, relative):
    project, root = installed
    feature = tmp_path / "feature"
    git_ops.git(project, "worktree", "add", "-b", "feature", str(feature), "main")
    outside = tmp_path / "outside"
    outside.mkdir()
    parent = feature / relative
    workspace.make_link(parent, outside)
    try:
        with pytest.raises(FactoryError, match="physical directory"):
            workspace.share(root, project)
        with pytest.raises(FactoryError, match="physical directory"):
            workspace.verify(root, project)
        assert list(outside.iterdir()) == []
    finally:
        workspace.unlink(parent)
