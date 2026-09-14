"""Command entrypoint for the project-local software factory."""

import argparse
import json
import sys
from pathlib import Path

import publication
import workflow
import workspace
from git_ops import git, scoped_commit
from storage import FactoryError, locked, read_json, run_path, save


def load_input(path):
    if path == "-":
        return json.load(sys.stdin)
    return read_json(path) if path else {}


def commit(root, run, payload):
    if run["phase"] != "commit" or run["request"]["authorization"].get("delivery") is not True:
        raise FactoryError("A local delivery commit is not authorized in this phase.")
    observed = workflow.current(run)
    cwd = run["identity"]["worktree"]
    if run["pending"]:
        pending = run["pending"]
        if pending["action"] != "commit":
            raise FactoryError("Reconcile the pending operation first.")
        if observed["head"] != pending["head"]:
            parents = git(cwd, "show", "-s", "--format=%P", "HEAD")
            message = git(cwd, "show", "-s", "--format=%B", "HEAD")
            changed = set(git(cwd, "diff", "--name-only", "-z", pending["head"], "HEAD").split("\0")) - {""}
            if parents != pending["head"] or message.strip() != pending["message"].strip() or not changed.issubset(set(pending["files"])):
                raise FactoryError("HEAD changed unexpectedly during commit; reconcile without repeating the write.")
            run["history"].append({"event": "commit_recovered", "head": observed["head"]})
            run["pending"] = None
            run["phase"] = "review"
            run["revision"] += 1
            save(root, run)
            return
        payload = pending
    if observed["clean"]:
        head = observed["head"]
    else:
        if payload.get("scope_verified") is not True:
            raise FactoryError("Inspect the exact staged scope before committing.")
        run["pending"] = {"action": "commit", "head": observed["head"],
                          "files": payload.get("files", []), "message": payload.get("message", ""),
                          "scope_verified": True}
        save(root, run)
        head = scoped_commit(cwd, payload.get("files", []), payload.get("message", ""), observed["head"])
    run["pending"] = None
    run["history"].append({"event": "commit", "head": head})
    run["phase"] = "review"
    run["revision"] += 1
    save(root, run)


def standalone_git(root, run, payload):
    if run["phase"] != "git":
        raise FactoryError("This is not a standalone Git operation.")
    mode = run["route"]["mode"]
    if run["request"]["authorization"].get(mode) is not True or payload.get("scope_verified") is not True:
        raise FactoryError("Record the requested Git operation and inspected scope.")
    workflow.current(run)
    cwd = run["identity"]["worktree"]
    remote = run["request"].get("remote", "origin")
    branch = run["identity"]["branch"]
    if remote.startswith("-"):
        raise FactoryError("Invalid remote.")
    if mode == "pull":
        if not workflow.current(run)["clean"]:
            raise FactoryError("Preserve local changes before pulling.")
        git(cwd, "fetch", remote, branch)
        run["pending"] = {"action": "pull", "target": git(cwd, "rev-parse", "FETCH_HEAD")}
        save(root, run)
        git(cwd, "merge", "--ff-only", run["pending"]["target"])
    elif mode == "push":
        run["pending"] = {"action": "push", "head": git(cwd, "rev-parse", "HEAD")}
        save(root, run)
        remote_head = git(cwd, "ls-remote", remote, "refs/heads/" + branch)
        if not remote_head or remote_head.split()[0] != run["pending"]["head"]:
            git(cwd, "push", "--set-upstream", remote, f"HEAD:refs/heads/{branch}")
    else:
        cwd, remote, branch, base, repo = publication.target(run)
        pr = publication.inspect_pr(cwd, repo, branch, base)
        if pr and payload.get("existing_body") != pr["body"] and payload.get("body") != pr["body"]:
            raise FactoryError("Inspect and preserve existing PR content before updating it.")
        if not payload.get("title") or not payload.get("body"):
            raise FactoryError("Provide the requested PR title and body.")
        body = Path(root) / "state" / run["id"] / "pr-body.md"
        body.write_text(payload["body"], encoding="utf-8")
        run["pending"] = {"action": "pr", "repository": repo, "branch": branch, "base": base}
        save(root, run)
        if pr:
            publication.gh(cwd, "pr", "edit", str(pr["number"]), "--repo", repo,
                           "--title", payload["title"], "--body-file", str(body))
        else:
            publication.gh(cwd, "pr", "create", "--repo", repo, "--head", branch, "--base", base,
                           "--title", payload["title"], "--body-file", str(body))
        run["pr"] = publication.inspect_pr(cwd, repo, branch, base)
    run["pending"] = None
    run["phase"] = "done"
    run["revision"] += 1
    run["history"].append({"event": mode, "head": git(cwd, "rev-parse", "HEAD")})
    save(root, run)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("route", "start", "import", "next", "accept", "fix", "commit", "publish", "github", "git", "resume", "restrict", "prepare", "share", "migrate", "cleanup", "verify"))
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--input", help="JSON input file, or - for stdin")
    parser.add_argument("--run", help="Saved workflow UUID")
    args = parser.parse_args(argv)
    root = args.root.resolve()
    try:
        payload = load_input(args.input)
        if not isinstance(payload, dict):
            raise FactoryError("Command input must be a JSON object.")
        if args.command == "route":
            output = workflow.route(payload)
        elif args.command == "next":
            output = workflow.assignment(read_json(run_path(root, args.run)))
        elif args.command == "verify":
            output = workspace.verify(root, payload["project"])
        else:
            validated = workflow.start(payload) if args.command == "start" else None
            with locked(root):
                if args.command in ("prepare", "share", "migrate", "cleanup"):
                    if args.command in ("prepare", "cleanup"):
                        output = getattr(workspace, args.command)(root, payload)
                    else:
                        output = getattr(workspace, args.command)(root, payload["project"])
                elif args.command in ("start", "import"):
                    # Validate before creating a run directory.
                    run = validated if args.command == "start" else workflow.import_legacy(root, payload)
                    if run["route"]["mode"] in ("implement", "refactor", "fix", "deliver"):
                        workspace.verify(root, run["identity"]["worktree"])
                    save(root, run)
                    output = workflow.assignment(run)
                else:
                    run = read_json(run_path(root, args.run))
                    if args.command == "accept":
                        workflow.accept(run, payload)
                    elif args.command == "fix":
                        workflow.begin_fix(run)
                    elif args.command == "resume":
                        workspace.verify(root, run["identity"]["worktree"])
                        workflow.reconcile(run)
                    elif args.command == "restrict":
                        workflow.restrict(run, payload)
                    elif args.command == "commit":
                        commit(root, run, payload)
                    elif args.command == "git":
                        standalone_git(root, run, payload)
                    elif args.command == "publish":
                        publication.publish(root, run, payload)
                    elif args.command == "github":
                        publication.github_checks(root, run)
                    save(root, run)
                    output = workflow.assignment(run)
        print(json.dumps(output, indent=2))
        return 0
    except (FactoryError, OSError, ValueError, KeyError, TypeError) as exc:
        print(json.dumps({"error": str(exc)}), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
