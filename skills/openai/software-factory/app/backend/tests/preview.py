"""Create labeled local fixtures for browser verification. Never use product records."""

import json
import shutil
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

SOURCE = Path(__file__).resolve().parents[3]
sys.path[:0] = [str(SOURCE / "scripts"), str(SOURCE / "app/backend"), str(Path(__file__).parent)]
from test_dashboard import new_run
from storage import locked, save
import dashboard
import install
import observation


def main():
    location = SOURCE / ".runtime/browser-preview"
    roots = []
    for name in ("Preview Atlas", "Preview Beacon"):
        project = location / name
        project.mkdir(parents=True, exist_ok=True)
        roots.append(install.install(SOURCE, project))
    host = roots[0]
    shutil.copytree(SOURCE / "app/frontend/dist", host / "app/frontend/dist", dirs_exist_ok=True)
    for root in roots:
        spec = root / "specs/design.md"
        spec.parent.mkdir(exist_ok=True)
        spec.write_text("# Dashboard preview fixture\n\nCaptured specification for browser verification.\n\n- Project isolation\n- Immutable context\n", encoding="utf-8")
        run = new_run(root)
        run["request"]["task"] = "Preview fixture: implement search and review the change"
        with locked(root):
            observation.context_read(root, run, {"file": "design.md", "role": "editor"})
            save(root, run)
            for phase, number in (("commit", 0), ("review", 0), ("fix", 0), ("work", 1), ("commit", 1), ("review", 1), ("publish", 1), ("github", 1), ("done", 1)):
                run["history"].append({"event": "preview_fixture", "status": "complete", "summary": "Synthetic browser verification evidence", "checks": [{"name": "unit", "status": "pass", "evidence": "Preview only"}]})
                run.update(phase=phase, round=number)
                save(root, run)
            start = datetime(2026, 9, 13, 10, 0, tzinfo=timezone.utc)
            for index, attempt in enumerate(run["attempts"]):
                attempt["started_at"] = (start + timedelta(seconds=index * 45)).isoformat()
                attempt["ended_at"] = (start + timedelta(seconds=(index + 1) * 45)).isoformat()
            run.update(gate=True, publication_eligible=True, ready=True, reviewed={"evidence": "Preview fixture"})
            save(root, run)
        new_run(root, run["session_id"])
        blocked = new_run(root)
        blocked["blocker"] = "Preview fixture: required check is unavailable"
        with locked(root):
            save(root, blocked)
        spec.write_text("# Current preview specification\n\nThis version differs from the captured content.\n", encoding="utf-8")
    dashboard.register(host, roots)
    address = dashboard.launch(host, open_browser=False, prepare_assets=False)
    print(json.dumps({"address": address, "host": str(host)}))


if __name__ == "__main__":
    main()
