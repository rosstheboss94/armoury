"""Common selection interface for both shell installers."""

import argparse
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", choices=("openai", "claude"), type=str.lower)
    parser.add_argument("--skills", help="software-factory, all, 0, 1, or collection:software-factory")
    parser.add_argument("--project")
    args = parser.parse_args(argv)
    interactive = not all((args.model, args.skills, args.project))
    try:
        model = args.model or input("Model [openai/claude]: ").strip().lower()
        selection = args.skills or input("Skill [software-factory]: ").strip() or "software-factory"
        project = args.project or input("Project root: ").strip()
        tokens = [token.strip().lower() for token in selection.split(",") if token.strip()]
        if model not in ("openai", "claude") or not tokens or any(token not in ("all", "0", "1", "software-factory", "collection:software-factory") for token in tokens):
            parser.error("Select openai or claude and the software-factory skill or collection.")
        if not Path(project).is_dir():
            parser.error("The target project directory must exist.")
        if interactive and input(f"Install {model} software-factory into {project}? [Y/n]: ").strip().lower() in ("n", "no"):
            print("Cancelled.")
            return 0
        source = ROOT / "skills" / model / "software-factory"
        return subprocess.run([sys.executable, str(source / "scripts/install.py"), "--source", str(source), "--project", project]).returncode
    except (EOFError, OSError) as exc:
        print(str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
