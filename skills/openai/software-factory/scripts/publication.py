"""Recoverable GitHub publication using inspected targets and exact body files."""

import json
from pathlib import Path

from git_ops import command, git
from storage import FactoryError, save
from workflow import current


def gh(cwd, *args):
    return command(cwd, ["gh", *args])


def target(run):
    request = run["request"]
    cwd = run["identity"]["worktree"]
    remote = request.get("remote", "origin")
    branch = run["identity"]["branch"]
    base = request.get("pr_base", request["base"])
    if any(not isinstance(x, str) or not x or x.startswith("-") for x in (remote, branch, base)):
        raise FactoryError("Invalid publication target.")
    if branch == base:
        raise FactoryError("Feature and PR base branches must differ.")
    url = git(cwd, "remote", "get-url", "--push", remote)
    # Ask GitHub to resolve exactly the selected remote rather than gh's default remote.
    repo = json.loads(gh(cwd, "repo", "view", url, "--json", "nameWithOwner"))["nameWithOwner"]
    if request.get("repository") != repo:
        raise FactoryError("Resolved remote repository differs from the authorized repository.")
    return cwd, remote, branch, base, repo


def inspect_pr(cwd, repo, branch, base):
    prs = json.loads(gh(cwd, "pr", "list", "--repo", repo, "--state", "open", "--head", branch,
                        "--base", base, "--json", "number,url,headRefOid,isDraft,body"))
    if len(prs) > 1:
        raise FactoryError("Multiple matching PRs require target reconciliation.")
    return prs[0] if prs else None


def publish(root, run, payload):
    if run["phase"] != "publish" or not run["publication_eligible"]:
        raise FactoryError("Publication is not eligible.")
    if run["request"]["authorization"].get("delivery") is not True:
        raise FactoryError("Delivery authorization was revoked.")
    observed = current(run)
    if run["pending"] and observed != run.get("reviewed"):
        cwd, remote, branch, base, repo = target(run)
        pr = inspect_pr(cwd, repo, branch, base)
        remote_head = git(cwd, "ls-remote", remote, "refs/heads/" + branch)
        run["history"].append({"event": "publication_reconciled", "pending": run["pending"],
                               "remote_head": remote_head, "pr": pr})
        run["pending"] = None
        run["publication_input"] = None
        if pr and remote_head and remote_head.split()[0] == run["reviewed"]["head"]:
            run["published"] = True
            run["pr"] = pr
        from workflow import reconcile
        reconcile(run)
        save(root, run)
        return
    if observed != run.get("reviewed") and not (run["round"] == 3 and not run["gate"] and run["blocker"]):
        raise FactoryError("Review evidence changed; reconcile before publication.")
    if not observed["clean"]:
        raise FactoryError("Commit or preserve working changes before publication.")
    if payload.get("outgoing_scope_verified") is not True:
        raise FactoryError("Inspect outgoing commits and record that they belong to the task.")
    cwd, remote, branch, base, repo = target(run)
    marker = f"<!-- software-factory:{run['id']} -->"
    directory = Path(root) / "state" / run["id"]
    # Inputs are persisted before remote operations so an interrupted attempt is recoverable.
    if run.get("publication_input"):
        if payload.get("refresh_inspected_input") is True:
            if not payload.get("title") or not payload.get("body") or "existing_body" not in payload:
                raise FactoryError("Refreshing publication input requires the newly inspected body and complete intended text.")
            run["history"].append({"event": "publication_input_replaced", "previous": run["publication_input"]})
            run["publication_input"] = payload
        else:
            payload = run["publication_input"]
    else:
        if not payload.get("title") or not payload.get("body"):
            raise FactoryError("Publication requires an inspected PR title and body.")
        run["publication_input"] = payload
    if not run["gate"]:
        disclosure = "\n\nLocal review gate failed. This PR is not ready for merge.\n"
        disclosure += "\n".join(f"- {f['id']}: {f['severity']}, {f['disposition']}. {f['impact']}" for f in run["findings"])
        disclosure += "\n" + (run["blocker"] or "The three fix rounds are exhausted.")
    else:
        disclosure = ""
    pr = inspect_pr(cwd, repo, branch, base)
    if pr and payload.get("existing_body") != pr["body"] and pr["body"] != payload["body"] + disclosure:
        raise FactoryError("Existing PR body changed or was not inspected; preserve its human content before updating.")
    run["pending"] = {"action": "publish", "head": observed["head"], "repository": repo,
                      "branch": branch, "base": base}
    save(root, run)
    # Fetch the base and feature destination without advancing local branches.
    git(cwd, "fetch", remote, base)
    fetched_base = git(cwd, "rev-parse", "FETCH_HEAD")
    if fetched_base != observed["base"]:
        raise FactoryError("Remote base differs from reviewed base; reconcile evidence before retrying.")
    remote_head = git(cwd, "ls-remote", remote, "refs/heads/" + branch)
    if remote_head and remote_head.split()[0] != observed["head"]:
        git(cwd, "fetch", remote, branch)
        ancestor = command(cwd, ["git", "merge-base", "FETCH_HEAD", observed["head"]])
        if ancestor != git(cwd, "rev-parse", "FETCH_HEAD"):
            raise FactoryError("Remote branch has new work; reconcile it before publishing.")
    if not remote_head or remote_head.split()[0] != observed["head"]:
        git(cwd, "push", "--set-upstream", remote, f"HEAD:refs/heads/{branch}")
    if git(cwd, "ls-remote", remote, "refs/heads/" + branch).split()[0] != observed["head"]:
        raise FactoryError("Remote head does not match the intended commit.")
    body_path = directory / "pr-body.md"
    body_path.write_text(payload["body"] + disclosure, encoding="utf-8")
    pr = inspect_pr(cwd, repo, branch, base)
    if pr:
        if pr["body"] not in (payload.get("existing_body"), payload["body"] + disclosure):
            raise FactoryError("PR body changed during publication; inspect and preserve its new content before retrying.")
        gh(cwd, "pr", "edit", str(pr["number"]), "--repo", repo, "--title", payload["title"], "--body-file", str(body_path))
    else:
        gh(cwd, "pr", "create", "--repo", repo, "--head", branch, "--base", base,
           "--title", payload["title"], "--body-file", str(body_path))
    pr = inspect_pr(cwd, repo, branch, base)
    if not pr:
        raise FactoryError("PR creation is not yet visible; inspect before retrying.")
    run["pr"] = pr
    run["published"] = True
    save(root, run)
    # Server-side pagination prevents duplicate comments when a PR has a long conversation.
    pages = gh(cwd, "api", "--paginate", "--slurp", f"repos/{repo}/issues/{pr['number']}/comments")
    comments = [comment for page in json.loads(pages) for comment in page]
    matches = [c for c in comments if marker in c["body"]]
    if len(matches) > 1:
        raise FactoryError("Multiple factory summary comments require reconciliation.")
    summary = marker + "\n# Factory review\n\n" + ("Local gate passed." if run["gate"] else "Local gate failed. Not ready for merge.")
    summary += f"\n\nHead: {observed['head']}\nBase: {observed['base']}\n"
    summary += "\nRoles: " + json.dumps(run["request"].get("roles", {})) + "\n"
    for event in run["history"]:
        if event.get("phase") == "review" and "score" in event:
            evidence = event.get("snapshot", {})
            summary += f"\n- Round {event.get('round', 'legacy')}: score {event['score']}/5 at {evidence.get('head', 'unknown')}, base {evidence.get('base', 'unknown')}. {event.get('summary', 'Legacy evidence incomplete.')}\n"
            summary += json.dumps({"findings": event.get("findings", []), "checks": event.get("checks", []),
                                   "evidence_limits": event.get("evidence_limits", "Legacy evidence incomplete.")}, ensure_ascii=False) + "\n"
    # The parent must omit private context from submitted summaries and evidence.
    comment_file = directory / "comment.json"
    comment_file.write_text(json.dumps({"body": summary}), encoding="utf-8")
    endpoint = f"repos/{repo}/issues/comments/{matches[0]['id']}" if matches else f"repos/{repo}/issues/{pr['number']}/comments"
    response = json.loads(gh(cwd, "api", endpoint, "--method", "PATCH" if matches else "POST", "--input", str(comment_file)))
    run["comment_id"] = response["id"]
    run["pending"] = None
    run["phase"] = "github"
    run["revision"] += 1
    save(root, run)


def github_checks(root, run):
    if run["phase"] not in ("github", "done") or not run["published"]:
        raise FactoryError("No published PR is ready for GitHub verification.")
    cwd, remote, branch, base, repo = target(run)
    pr = json.loads(gh(cwd, "pr", "view", str(run["pr"]["number"]), "--repo", repo,
                       "--json", "headRefOid,baseRefOid,mergeStateStatus,mergeable,reviewDecision,statusCheckRollup,url"))
    run["github"] = pr
    checks = pr["statusCheckRollup"] or []
    green = all(c.get("conclusion") in ("SUCCESS", "NEUTRAL", "SKIPPED") or c.get("state") == "SUCCESS" for c in checks)
    run["ready"] = bool(run["gate"] and pr["headRefOid"] == run["reviewed"]["head"]
                        and pr["baseRefOid"] == run["reviewed"]["base"] and current(run) == run["reviewed"]
                        and green and pr["mergeable"] == "MERGEABLE" and pr["mergeStateStatus"] == "CLEAN"
                        and pr["reviewDecision"] not in ("CHANGES_REQUESTED", "REVIEW_REQUIRED"))
    run["phase"] = "done"
    run["history"].append({"event": "github", "ready": run["ready"], "evidence": pr})
    run["revision"] += 1
    save(root, run)
