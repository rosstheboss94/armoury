"""Behavioral tests for the factory using isolated repositories and mocked GitHub."""

import copy
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "skills/openai/software-factory"
sys.path.insert(0, str(SOURCE / "scripts"))
import catalog
import factory
import git_ops
import install
import observation
import publication
import storage
import workflow
import workspace


class FactoryChecks(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="factory checks ")
        self.addCleanup(self.temporary.cleanup)
        self.project = Path(self.temporary.name) / "project"
        self.project.mkdir()
        git_ops.git(self.project, "init", "-b", "main")
        git_ops.git(self.project, "config", "user.name", "Factory Tests")
        git_ops.git(self.project, "config", "user.email", "factory@example.invalid")
        (self.project / "product.txt").write_text("initial\n", encoding="utf-8")
        git_ops.git(self.project, "add", "product.txt")
        git_ops.git(self.project, "commit", "-m", "initial")
        self.root = install.install(SOURCE, self.project)
        self.request = {"operation": "specflow", "mode": "implement", "modifiers": ["auto", "tldr"],
                        "task": "Implement approved behavior", "worktree": str(self.project), "branch": "main", "base": "main",
                        "authorization": {"source": "User requested auto tldr implement", "edits": True, "delivery": True},
                        "required_checks": ["tests"], "roles": {"editor": "editor", "reviewer": "reviewer"}}

    def run_state(self):
        return workflow.start(self.request)

    def save_run(self, run):
        with storage.locked(self.root):
            observation.attach(self.root, run)
            storage.save(self.root, run)
        return run

    def test_catalog_menu_parse_and_discovery_writes_nothing(self):
        before = {p: p.read_bytes() for p in self.root.rglob("*") if p.is_file()}
        book = catalog.workflows()
        self.assertEqual(len(book), 12)
        self.assertEqual({(w["operation"], w["mode"]) for w in book},
                         {(op, mode) for op in ("specflow", "tldr") for mode in workflow.MODES[op]})
        markdown = catalog.menu()["markdown"]
        self.assertIn("| Workflow | Use it to |", markdown)
        for entry in book:
            self.assertIn("`" + entry["invocation"] + "`", markdown)
            self.assertTrue((SOURCE / entry["reference"]).is_file())
        parsed = catalog.parse("specflow analyze: explain this app and suggest three useful features")
        self.assertEqual((parsed["operation"], parsed["mode"], parsed["selected"]), ("specflow", "analyze", True))
        colon = catalog.parse("specflow implement: add dark mode: keep contrast")
        self.assertEqual(colon["task"], "add dark mode: keep contrast")
        self.assertEqual(catalog.parse("specflow auto tldr implement: ship it")["modifiers"], ["auto", "tldr"])
        missing = catalog.parse("tldr review")
        self.assertEqual(missing["needs"], "task")
        unknown = catalog.parse("scout this app")
        self.assertIn("Unknown workflow", unknown["error"])
        self.assertIn("specflow analyze", unknown["workflows"])
        self.assertIn("specflow analyze", catalog.parse("")["markdown"])
        from io import StringIO
        with patch("sys.stdout", StringIO()):
            self.assertEqual(factory.main(["menu", "--root", str(self.root)]), 0)
        self.assertEqual(before, {p: p.read_bytes() for p in self.root.rglob("*") if p.is_file()})
        for operation, modes in workflow.MODES.items():
            for mode in modes:
                self.assertEqual(workflow.route({"task": "Scoped operation", "operation": operation, "mode": mode})["mode"], mode)

    def test_selected_workflows_record_sessions(self):
        parsed = catalog.parse("tldr review: review the settings changes")
        request = catalog.template({**parsed, "worktree": str(self.project), "task": parsed["task"],
                                    "required_checks": [], "no_checks_reason": "Review fixture"})
        request.update(branch="main", base="main", roles=self.request["roles"])
        run = self.save_run(workflow.start(request))
        self.assertTrue(run["session_id"])
        related = dict(request, session_id=run["session_id"], task="review the follow-up")
        reused = self.save_run(workflow.start(related))
        self.assertEqual(reused["session_id"], run["session_id"])
        other = self.save_run(workflow.start(dict(request, task="a new review task")))
        self.assertNotEqual(other["session_id"], run["session_id"])
        with self.assertRaises(storage.FactoryError):
            factory.commit(self.root, run, {})

    def test_filesystem_observation_rejects_git_delivery(self):
        project = Path(self.temporary.name) / "plain"
        project.mkdir()
        root = install.install(SOURCE, project)
        request = catalog.template({"operation": "specflow", "mode": "analyze", "task": "explain this app",
                                    "worktree": str(project), "observation": "filesystem",
                                    "required_checks": [], "no_checks_reason": "No git history"})
        run = workflow.start(request)
        self.assertEqual(run["initial"]["git"], "unavailable")
        with storage.locked(root):
            observation.attach(root, run)
            storage.save(root, run)
        workflow.accept(run, {**{k: workflow.assignment(run)[k] for k in ("run_id", "revision", "phase", "snapshot")},
                              "status": "complete", "summary": "Recorded analysis",
                              "checks": [{"name": "none", "status": "unavailable", "evidence": "No git checks"}]})
        self.assertEqual(run["phase"], "done")
        deliver = catalog.template({"operation": "tldr", "mode": "deliver", "task": "Deliver",
                                    "worktree": str(project), "observation": "filesystem",
                                    "required_checks": [], "no_checks_reason": "Fixture"})
        with self.assertRaises(storage.FactoryError):
            workflow.start(deliver)

    def test_full_skill_at_discovery_path(self):
        entry = self.project / '.agents/skills/software-factory/SKILL.md'
        self.assertEqual(entry.read_bytes(), (SOURCE / 'SKILL.md').read_bytes())
        entry.write_text('User customization')
        install.install(SOURCE, self.project)
        self.assertEqual(entry.read_bytes(), (SOURCE / 'SKILL.md').read_bytes())

    def result(self, run, **extra):
        result = {key: value for key, value in workflow.assignment(run).items() if key in ("run_id", "revision", "phase", "snapshot")}
        result.update(status="complete", summary="Verified approved behavior", progress=True,
                      checks=[{"name": "tests", "status": "pass", "evidence": "Executed fixture test command"}])
        if run["phase"] == "review":
            result.update(reviewer="reviewer", score=4, findings=[], evidence_limits="Fixture scope only")
        result.update(extra)
        return result

    def review_state(self):
        run = self.run_state()
        workflow.accept(run, self.result(run))
        factory.commit(self.root, run, {})
        self.assertEqual(run["phase"], "review")
        return run

    def test_route_readonly_creates_nothing(self):
        before = set(self.root.rglob("*"))
        request = {"operation": "tldr", "mode": "review", "task": "Review only"}
        self.assertTrue(workflow.route(request)["readonly"])
        with self.assertRaises(storage.FactoryError):
            workflow.start(request)
        self.assertEqual(before, set(self.root.rglob("*")))

    def test_modifiers(self):
        self.request["modifiers"] = ["tdlr", "auto"]
        self.assertEqual(workflow.route(self.request)["modifiers"], ["tldr", "auto"])
        self.request["mode"] = "audit"
        with self.assertRaises(storage.FactoryError):
            workflow.start(self.request)

    def test_implementation_does_not_deliver(self):
        self.request["modifiers"] = []
        self.request["authorization"]["delivery"] = False
        run = self.run_state()
        workflow.accept(run, self.result(run))
        self.assertEqual(run["phase"], "done")
        with self.assertRaises(storage.FactoryError):
            factory.commit(self.root, run, {})
        with self.assertRaises(storage.FactoryError):
            publication.publish(self.root, run, {})

    def test_initial_pass_and_required_evidence(self):
        run = self.review_state()
        workflow.accept(run, self.result(run))
        self.assertTrue(run["gate"])
        self.assertEqual(run["round"], 0)
        self.assertEqual(run["phase"], "publish")
        other = self.review_state()
        workflow.accept(other, self.result(other, checks=[]))
        self.assertFalse(other["gate"])

    def test_round_cap_and_interrupted_round(self):
        run = self.review_state()
        workflow.accept(run, self.result(run, score=3))
        for number in range(1, 4):
            workflow.begin_fix(run)
            (self.project / "product.txt").write_text(f"fix {number}\n", encoding="utf-8")
            workflow.reconcile(run)
            workflow.reconcile(run)
            self.assertEqual(run["phase"], "work")
            self.assertEqual(run["round"], number)
            workflow.accept(run, self.result(run))
            factory.commit(self.root, run, {"files": ["product.txt"], "message": f"fix {number}", "scope_verified": True})
            workflow.reconcile(run)
            self.assertEqual(run["round"], number)
            workflow.accept(run, self.result(run, score=3))
        self.assertTrue(run["publication_eligible"])
        self.assertFalse(run["gate"])
        with self.assertRaises(storage.FactoryError):
            workflow.begin_fix(run)

    def test_drift_and_revocation(self):
        run = self.review_state()
        workflow.accept(run, self.result(run))
        (self.root / "specs").mkdir()
        (self.root / "specs/requirement.md").write_text("Changed intent", encoding="utf-8")
        workflow.reconcile(run)
        self.assertFalse(run["gate"])
        self.assertEqual(run["round"], 1)
        workflow.reconcile(run)
        self.assertEqual(run["round"], 1)
        workflow.restrict(run, {"authorization": {"delivery": False}, "revoke_auto": True})
        self.assertNotIn("auto", run["request"]["modifiers"])
        with self.assertRaises(storage.FactoryError):
            publication.publish(self.root, run, {})

    def test_stale_result_and_review_identity(self):
        run = self.review_state()
        result = self.result(run)
        (self.project / "product.txt").write_text("unexpected", encoding="utf-8")
        with self.assertRaises(storage.FactoryError):
            workflow.accept(run, result)
        run["request"]["roles"]["reviewer"] = "editor"
        with self.assertRaises(storage.FactoryError):
            workflow.accept(run, self.result(run, reviewer="editor"))

    def test_saved_standalone_review_drift_does_not_restart(self):
        self.request.update(operation="tldr", mode="review", modifiers=[], save_authorized=True)
        run = self.run_state()
        workflow.accept(run, self.result(run))
        (self.project / "product.txt").write_text("later work", encoding="utf-8")
        workflow.reconcile(run)
        self.assertEqual(run["phase"], "done")
        self.assertEqual(run["round"], 0)
        self.assertFalse(run["gate"])

    def test_legacy_import_keeps_rounds_and_published_state(self):
        source = self.root / "state/legacy/delivery.md"
        source.parent.mkdir(parents=True)
        source.write_text("Round 2 completed. Review incomplete.", encoding="utf-8")
        payload = {"request": self.request, "legacy_files": ["state/legacy/delivery.md"],
                   "reconstruction_evidence": "Existing record documents two completed rounds", "round": 2,
                   "phase": "publish", "history": [{"phase": "review", "score": 3, "summary": "Legacy record"}]}
        run = workflow.import_legacy(self.root, payload)
        self.assertEqual(run["round"], 3)
        self.assertEqual(run["phase"], "review")
        payload.update(published=True, pr={"number": 5})
        published = workflow.import_legacy(self.root, payload)
        self.assertEqual(published["phase"], "done")
        self.assertTrue(published["published"])
        self.assertEqual(published["round"], 2)
        storage.save(self.root, run)
        with self.assertRaises(storage.FactoryError):
            workflow.import_legacy(self.root, payload)

    def test_pending_publication_drift_can_recover(self):
        run = self.review_state()
        workflow.accept(run, self.result(run))
        run["pending"] = {"action": "publish", "head": run["reviewed"]["head"]}
        (self.project / "product.txt").write_text("later change", encoding="utf-8")
        with patch.object(publication, "target", return_value=(str(self.project), "origin", "feature", "main", "owner/repo")), patch.object(publication, "inspect_pr", return_value=None), patch.object(publication, "git", return_value=""):
            publication.publish(self.root, run, {})
        self.assertIsNone(run["pending"])
        self.assertEqual(run["phase"], "review")
        self.assertEqual(run["round"], 1)
        # Fresh evidence can now be accepted instead of deadlocking on pending state.
        workflow.accept(run, self.result(run, score=3))

    def test_state_writes_do_not_change_product_snapshot(self):
        before = git_ops.snapshot(self.project, "main")
        storage.save(self.root, self.run_state())
        self.assertEqual(before, git_ops.snapshot(self.project, "main"))
        self.assertTrue(before["clean"])

    def test_scoped_commit_preserves_unrelated_staging(self):
        (self.project / "unrelated.txt").write_text("user change", encoding="utf-8")
        git_ops.git(self.project, "add", "unrelated.txt")
        head = git_ops.git(self.project, "rev-parse", "HEAD")
        with self.assertRaises(storage.FactoryError):
            git_ops.scoped_commit(self.project, ["product.txt"], "feature", head)
        self.assertEqual(git_ops.git(self.project, "diff", "--cached", "--name-only"), "unrelated.txt")

    def test_shared_visibility_and_cleanup(self):
        worktree = Path(self.temporary.name) / "feature"
        workspace.prepare(self.root, {"project": str(self.project), "worktree": str(worktree), "branch": "feature", "base": "main"})
        link = worktree / workspace.RELATIVE
        # Ensure temporary cleanup does not traverse a junction on older Python versions.
        self.addCleanup(lambda: workspace.unlink(link) if workspace.is_link(link) else None)
        self.assertEqual(link.resolve(), self.root.resolve())
        (self.root / "specs").mkdir()
        (self.root / "specs/record.md").write_text("shared", encoding="utf-8")
        self.assertEqual((link / "specs/record.md").read_text(), "shared")
        self.assertTrue(git_ops.snapshot(worktree, "main")["clean"])
        workspace.cleanup(self.root, {"project": str(self.project), "worktree": str(worktree), "cleanup_authorized": True,
                                      "commits_preserved": True, "preservation_evidence": "Feature HEAD equals initial main HEAD"})
        self.assertFalse(worktree.exists())
        self.assertTrue((self.root / "specs/record.md").exists())

    def test_migration_preserves_conflicts(self):
        (self.project / "specs").mkdir()
        (self.project / "specs/index.md").write_text("original records", encoding="utf-8")
        workspace.migrate(self.root, self.project)
        self.assertEqual((self.root / "specs/index.md").read_text(), "original records")
        (self.project / "specs").mkdir()
        (self.project / "specs/index.md").write_text("competing records", encoding="utf-8")
        with self.assertRaises(storage.FactoryError):
            workspace.migrate(self.root, self.project)
        self.assertEqual((self.project / "specs/index.md").read_text(), "competing records")

    def test_migration_rejects_external_target(self):
        outside = Path(self.temporary.name) / "outside-specs"
        outside.mkdir()
        (outside / "record.md").write_text("external", encoding="utf-8")
        link = self.root / "specs"
        workspace.make_link(link, outside)
        self.addCleanup(lambda: workspace.unlink(link) if workspace.is_link(link) else None)
        with self.assertRaises(storage.FactoryError):
            workspace.migrate(self.root, self.project)
        self.assertEqual((outside / "record.md").read_text(), "external")

    def test_install_retains_state_and_rejects_link_collision(self):
        storage.save(self.root, self.run_state())
        before = set((self.root / "state").rglob("*"))
        install.install(SOURCE, self.project)
        self.assertEqual(before, set((self.root / "state").rglob("*")))
        outside = Path(self.temporary.name) / "outside"
        outside.mkdir()
        destination = self.root / "new-link"
        workspace.make_link(destination, outside)
        self.addCleanup(lambda: workspace.unlink(destination) if workspace.is_link(destination) else None)
        # Unrelated local links are retained; package destination collisions are rejected.
        install.install(SOURCE, self.project)
        self.assertTrue(workspace.is_link(destination))

    def test_publication_retry_reuses_pr_and_comment(self):
        run = self.review_state()
        workflow.accept(run, self.result(run))
        state = {"pr": None, "comments": [], "creates": 0, "comment_posts": 0}
        repo = "owner/repo"
        def fake_git(cwd, *args):
            if args[0] == "fetch": return ""
            if args == ("rev-parse", "FETCH_HEAD"): return run["reviewed"]["base"]
            if args[0] == "ls-remote": return run["reviewed"]["head"] + "\trefs/heads/feature"
            self.fail(f"Unexpected Git write: {args}")
        def fake_gh(cwd, *args):
            if args[:2] == ("pr", "list"): return json.dumps([state["pr"]] if state["pr"] else [])
            if args[:2] == ("pr", "create"):
                state["creates"] += 1
                state["pr"] = {"number": 1, "url": "https://example.invalid/pr/1", "body": "Feature body"}
                return state["pr"]["url"]
            if args[:2] == ("pr", "edit"): return ""
            if args[:3] == ("api", "--paginate", "--slurp"): return json.dumps([state["comments"]])
            if args[0] == "api":
                body = json.loads(Path(args[-1]).read_text())["body"]
                comment = {"id": 77, "body": body}
                if args[3] == "POST": state["comment_posts"] += 1
                state["comments"] = [comment]
                return json.dumps(comment)
            self.fail(f"Unexpected GitHub call: {args}")
        with patch.object(publication, "target", return_value=(str(self.project), "origin", "feature", "main", repo)), patch.object(publication, "git", side_effect=fake_git), patch.object(publication, "gh", side_effect=fake_gh):
            payload = {"title": "Feature", "body": "Feature body", "outgoing_scope_verified": True}
            publication.publish(self.root, run, payload)
            run["phase"] = "publish"  # Simulate loss of the final local save after the remote comment succeeded.
            publication.publish(self.root, run, payload)
        self.assertEqual(state["creates"], 1)
        self.assertEqual(state["comment_posts"], 1)


if __name__ == "__main__":
    unittest.main(verbosity=2)
