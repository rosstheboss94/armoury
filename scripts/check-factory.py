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
import factory
import git_ops
import install
import publication
import storage
import workflow
import workspace
import tasks


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

    def task(self, name="plan-implement", **extra):
        request = dict(self.request, workflow=name, modifiers=[],
                       authorization={"source": "User selected workflow", "edits": True,
                                      "delivery": name in ("deliver", "plan-deliver")})
        request.update(extra)
        return tasks.start(self.root, request)

    def task_action(self, task, action, **extra):
        with storage.locked(self.root):
            return tasks.command(self.root, action, {"task_id": task["task_id"], **extra})

    def test_catalog_and_all_existing_routes(self):
        expected = {"scout": [("specflow", "analyze")], "plan": [("specflow", "shape"), ("specflow", "build")],
                    "implement": [("specflow", "implement")], "review": [("tldr", "review")],
                    "fix": [("tldr", "fix")], "deliver": [("tldr", "deliver")]}
        expected["plan-implement"] = expected["plan"] + expected["implement"]
        expected["plan-deliver"] = expected["plan"] + [("specflow", "implement")]
        before = set(self.root.rglob("*"))
        book = tasks.catalog()
        self.assertEqual(set(book["workflows"]), set(expected))
        for name, sequence in expected.items():
            self.assertEqual([(s["operation"], s["mode"]) for s in book["workflows"][name]["stages"]], sequence)
        for operation, modes in workflow.MODES.items():
            for mode in modes:
                self.assertEqual(workflow.route({"task": "Scoped operation", "operation": operation, "mode": mode})["mode"], mode)
        self.assertEqual(before, set(self.root.rglob("*")))

    def test_combined_task_idempotent_and_local(self):
        task = self.task()
        with self.assertRaises(storage.FactoryError):
            self.task_action(task, "task-advance", stage="implement")
        self.task_action(task, "task-advance", stage="shape", skip_reason="Intent already scoped")
        for stage in ("build", "implement"):
            first = self.task_action(task, "task-next")["assignment"]
            self.assertEqual(first["run_id"], self.task_action(task, "task-next")["assignment"]["run_id"])
            run = storage.read_json(storage.run_path(self.root, first["run_id"]))
            self.assertFalse(run["route"]["delivery"])
            self.assertFalse(run["request"]["authorization"]["delivery"])
            workflow.accept(run, self.result(run))
            storage.save(self.root, run)
            state = self.task_action(task, "task-advance", stage=stage)
            self.assertEqual(state, self.task_action(task, "task-advance", stage=stage))
        self.assertIsNone(state["current"])
        self.assertEqual(len({storage.read_json(p)["session_id"] for p in (self.root / "state").glob("*/run.json")}), 1)

    def test_task_checks_and_observation_boundaries(self):
        task = self.task("scout")
        assignment = self.task_action(task, "task-next")["assignment"]
        run = storage.read_json(storage.run_path(self.root, assignment["run_id"]))
        self.assertFalse(run["request"]["authorization"]["edits"])
        (self.project / "product.txt").write_text("unexpected")
        with self.assertRaises(storage.FactoryError):
            workflow.accept(run, self.result(run))
        (self.project / "product.txt").write_text("initial\n", encoding="utf-8")
        workflow.accept(run, self.result(run, checks=[]))
        storage.save(self.root, run)
        self.assertTrue(self.task_action(task, "task-status")["blockers"])
        with self.assertRaises(storage.FactoryError):
            self.task_action(task, "task-advance", stage="scout")

    def test_tasks_without_git_or_initial_commit(self):
        for unborn in (False, True):
            project = Path(self.temporary.name) / str(unborn)
            project.mkdir()
            if unborn:
                git_ops.git(project, "init", "-b", "main")
            root = install.install(SOURCE, project)
            for name in ("scout", "plan", "review"):
                task = tasks.start(root, {"workflow": name, "task": "Inspect or specify", "worktree": str(project),
                                          "authorization": {"source": "User request", "edits": True},
                                          "required_checks": [], "no_checks_reason": "Observation fixture"})
                result = tasks.command(root, "task-next", {"task_id": task["task_id"]})
                self.assertEqual(result["assignment"]["snapshot"]["git"], "unavailable")
            with self.assertRaises(storage.FactoryError):
                tasks.start(root, {"workflow": "deliver", "task": "Deliver", "worktree": str(project),
                                  "authorization": {"source": "User request", "edits": True, "delivery": True},
                                  "required_checks": [], "no_checks_reason": "Fixture"})

    def test_task_resume_ambiguity_restrictions_and_missing_history(self):
        task = self.task("implement")
        self.task("review")
        self.assertTrue(tasks.command(self.root, "task-status", {})["selection_required"])
        run_id = self.task_action(task, "task-next")["assignment"]["run_id"]
        state = self.task_action(task, "task-resume", authorization={"edits": False})
        self.assertEqual(state["current"]["run_id"], run_id)
        run = storage.read_json(storage.run_path(self.root, run_id))
        self.assertFalse(run["request"]["authorization"]["edits"])
        (self.root / "SKILL.md").write_text("Changed instructions")
        with self.assertRaises(storage.FactoryError):
            self.task_action(task, "task-resume")
        self.task_action(task, "task-resume", instructions_reconciled=True)
        storage.run_path(self.root, run_id).unlink()
        with self.assertRaises(storage.FactoryError):
            self.task_action(task, "task-resume")
        with self.assertRaises(storage.FactoryError):
            self.task_action(task, "task-next")

    def test_task_fix_resume_keeps_review_budget(self):
        task = self.task("fix")
        run_id = self.task_action(task, "task-next")["assignment"]["run_id"]
        run = storage.read_json(storage.run_path(self.root, run_id))
        workflow.accept(run, self.result(run))
        workflow.accept(run, self.result(run, score=2))
        workflow.begin_fix(run)
        storage.save(self.root, run)
        self.task_action(task, "task-resume")
        assignment = self.task_action(task, "task-next")["assignment"]
        self.assertEqual((assignment["run_id"], assignment["round"]), (run_id, 1))

    def test_every_workflow_stopping_point_and_interrupted_delivery(self):
        for name in tasks.catalog()["workflows"]:
            with self.subTest(workflow=name):
                task = self.task(name)
                for stage in task["stages"]:
                    run_id = self.task_action(task, "task-next")["assignment"]["run_id"]
                    self.task_action(task, "task-resume")
                    run = storage.read_json(storage.run_path(self.root, run_id))
                    workflow.accept(run, self.result(run))
                    if run["phase"] == "commit":
                        factory.commit(self.root, run, {})
                    if run["phase"] == "review":
                        workflow.accept(run, self.result(run))
                    storage.save(self.root, run)
                    if name in ("deliver", "plan-deliver") and stage["id"] == "deliver":
                        self.assertEqual(run["phase"], "publish")
                        run["pending"] = {"action": "publish", "fixture": True}
                        storage.save(self.root, run)
                        self.task_action(task, "task-resume")
                        resumed = self.task_action(task, "task-next")["assignment"]
                        self.assertEqual((resumed["run_id"], resumed["round"], resumed["pending"]), (run_id, 0, run["pending"]))
                        # Publication itself is covered with mocked GitHub below.
                        run.update(pending=None, published=True, phase="done", ready=False)
                        storage.save(self.root, run)
                    else:
                        self.assertEqual(run["phase"], "done")
                        self.assertFalse(run["published"])
                        with self.assertRaises(storage.FactoryError):
                            factory.commit(self.root, run, {})
                    state = self.task_action(task, "task-advance", stage=stage["id"])
                self.assertIsNone(state["current"])

    def test_task_crash_recovery_and_lock(self):
        task = self.task("implement")
        real_write = tasks.write_json
        def interrupted(path, value):
            if value.get("stages", [{}])[0].get("status") == "active":
                raise OSError("Interrupted after saving run")
            return real_write(path, value)
        with patch.object(tasks, "write_json", side_effect=interrupted):
            with self.assertRaises(OSError):
                self.task_action(task, "task-next")
        saved = list((self.root / "state").glob("*/run.json"))
        self.assertEqual(len(saved), 1)
        resumed = self.task_action(task, "task-next")
        self.assertEqual(resumed["assignment"]["run_id"], storage.read_json(saved[0])["id"])
        with storage.locked(self.root):
            with self.assertRaises(storage.FactoryError):
                self.task_action(task, "task-next")

    def test_run_restrictions_carry_to_future_stages(self):
        task = self.task("plan-implement", modifiers=["auto"])
        run_id = self.task_action(task, "task-next")["assignment"]["run_id"]
        run = storage.read_json(storage.run_path(self.root, run_id))
        workflow.accept(run, self.result(run))
        workflow.restrict(run, {"authorization": {"edits": False}, "revoke_auto": True})
        storage.save(self.root, run)
        self.task_action(task, "task-advance", stage="shape")
        with self.assertRaises(storage.FactoryError):
            self.task_action(task, "task-next")
        saved = storage.read_json(tasks.path(self.root, task["task_id"]))
        self.assertFalse(saved["authorization"]["edits"])
        self.assertEqual(saved["modifiers"], [])

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
