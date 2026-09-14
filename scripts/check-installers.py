"""Check repository consistency and both installers using temporary projects."""

import os
import re
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import sys


ROOT = Path(__file__).resolve().parents[1]
POWERSHELL = shutil.which('pwsh') or shutil.which('powershell')
GIT_BASH = Path(os.environ.get('ProgramFiles', 'C:/Program Files')) / 'Git/bin/bash.exe'
BASH = str(GIT_BASH) if GIT_BASH.is_file() else shutil.which('bash')
OPENAI_DASHBOARD_ONLY = False
if '--openai-dashboard-only' in sys.argv:
    sys.argv.remove('--openai-dashboard-only')
DASHBOARD_DIFFERENCES = {'SKILL.md', '.gitignore', '.dockerignore', 'compose.yaml', 'references/dashboard.md', 'references/controller.md',
                         'references/workspace.md', 'scripts/factory.py', 'scripts/workflow.py',
                         'scripts/storage.py', 'scripts/install.py', 'scripts/observation.py', 'scripts/dashboard.py', 'scripts/docker_dashboard.py',
                         'scripts/tasks.py', 'scripts/catalog.json', 'scripts/discovery.py', 'scripts/workspace.py', 'scripts/git_ops.py', 'references/workflows.md',
                         'references/tldr/progress.md', 'references/tldr/review.md', 'references/specflow/analyze.md'}


def packaged_files(source):
    for directory, folders, names in os.walk(source):
        folders[:] = [n for n in folders if n not in {'node_modules', 'dist', '.runtime', '__pycache__', '.pytest_cache', '.venv', 'state', 'specs'}]
        for name in names:
            if not name.endswith('.pyc'):
                yield Path(directory) / name


class InstallerChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not POWERSHELL or not BASH:
            raise RuntimeError('Checks require PowerShell and Bash 4 or newer.')

    def run_installer(self, shell, model, selection, project, success=True):
        if shell == 'powershell':
            command = [POWERSHELL, '-NoProfile', '-ExecutionPolicy', 'Bypass',
                       '-File', str(ROOT / 'scripts/install-skills.ps1'),
                       model, selection, str(project)]
        else:
            command = [BASH, './scripts/install-skills.sh', '--model', model,
                       '--skills', selection, '--project', str(project)]
        result = subprocess.run(command, cwd=ROOT, input='', text=True,
                                capture_output=True, timeout=30)
        self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
        return result

    def test_repository(self):
        self.assertEqual((ROOT / 'AGENTS.md').read_bytes(), (ROOT / 'CLAUDE.md').read_bytes())
        names = {}
        for model in ('openai', 'claude'):
            names[model] = {p.name for p in (ROOT / 'skills' / model).iterdir() if p.is_dir()}
        self.assertEqual(names['openai'], names['claude'])
        for name in names['openai']:
            frontmatter = []
            for model in names:
                content = (ROOT / 'skills' / model / name / 'SKILL.md').read_text(encoding='utf-8')
                self.assertTrue(content.startswith('---\n'))
                fields = dict(line.split(':', 1) for line in content.split('---', 2)[1].strip().splitlines())
                self.assertEqual(fields['name'].strip(), name)
                self.assertTrue(fields['description'].strip())
                frontmatter.append(fields)
            self.assertEqual(frontmatter[0], frontmatter[1])
        self.assertEqual(names['openai'], {'software-factory'})
        members = set()
        for manifest in (ROOT / 'collections').glob('*/collection.yaml'):
            entries = re.findall(r'^  - ([a-z0-9-]+)$', manifest.read_text(), re.MULTILINE)
            self.assertEqual(len(entries), len(set(entries)))
            self.assertTrue(set(entries) <= names['openai'])
            members.update(entries)
        self.assertEqual(members, names['openai'])
        for original in packaged_files(ROOT / 'skills/openai/software-factory'):
            counterpart = ROOT / 'skills/claude/software-factory' / original.relative_to(ROOT / 'skills/openai/software-factory')
            relative = original.relative_to(ROOT / 'skills/openai/software-factory').as_posix()
            if not (OPENAI_DASHBOARD_ONLY and (relative.startswith('app/') or relative in DASHBOARD_DIFFERENCES)):
                self.assertEqual(original.read_bytes(), counterpart.read_bytes(), str(original))
            if original.suffix == '.md':
                prose = re.sub(r'```[^\n]*\n.*?```', '', original.read_text(encoding='utf-8'), flags=re.DOTALL)
                for target in re.findall(r'\]\(([^)]+)\)', prose):
                    path = target.split('#', 1)[0]
                    if not path or '://' in path or '<' in path:
                        continue
                    self.assertTrue((original.parent / path).exists(), f'{original}: {target}')

    def test_bash_syntax(self):
        subprocess.run([BASH, '-n', './scripts/install-skills.sh'], cwd=ROOT, check=True)

    def test_installations(self):
        all_names = {p.name for p in (ROOT / 'skills/openai').iterdir() if p.is_dir()}
        selections = {
            'all': all_names,
            ' all ,software-factory': all_names,
            '0': all_names,
            'SOFTWARE-FACTORY': {'software-factory'},
            '1': {'software-factory'},
            'collection:software-factory': {'software-factory'},
            'COLLECTION:software-factory,software-factory': {'software-factory'},
        }
        for shell in ('powershell', 'bash'):
            for model in ('openai', 'claude'):
                for selection, expected in selections.items():
                    with self.subTest(shell=shell, model=model, selection=selection):
                        with tempfile.TemporaryDirectory(prefix='armoury checks ') as temporary:
                            project = Path(temporary)
                            destination = project / '.agents/skills'
                            neighbor = destination / 'neighbor/SKILL.md'
                            neighbor.parent.mkdir(parents=True)
                            neighbor.write_text('Neighbor skill', encoding='utf-8')
                            self.run_installer(shell, model, selection, project)
                            self.assertEqual({p.name for p in destination.iterdir()}, expected | {'neighbor'})
                            for name in expected:
                                source = ROOT / 'skills' / model / name
                                for original in packaged_files(source):
                                    self.assertEqual(original.read_bytes(), (destination / name / original.relative_to(source)).read_bytes())
                                if model == 'openai':
                                    self.assertFalse((destination / name / '.runtime').exists())
                                    self.assertFalse((destination / name / 'app/frontend/node_modules').exists())
                            retained = destination / next(iter(expected)) / 'local.txt'
                            retained.write_text('keep me', encoding='utf-8')
                            records = destination / 'software-factory' / 'specs' / 'index.md'
                            records.parent.mkdir(exist_ok=True)
                            records.write_text('existing records', encoding='utf-8')
                            state = destination / 'software-factory/state/project.json'
                            state.parent.mkdir(exist_ok=True)
                            state.write_text('{"name": "Keep"}')
                            self.run_installer(shell, model, selection, project)
                            self.assertEqual(state.read_text(), '{"name": "Keep"}')
                            self.assertEqual(retained.read_text(encoding='utf-8'), 'keep me')
                            self.assertEqual(records.read_text(encoding='utf-8'), 'existing records')
                            self.assertEqual({p.name for p in project.iterdir()}, {'.agents'})
                            self.assertEqual({p.name for p in (project / '.agents').iterdir()}, {'skills'})
                            self.assertEqual(neighbor.read_text(), 'Neighbor skill')
                            self.assertEqual((destination / 'software-factory/SKILL.md').read_bytes(),
                                             (ROOT / 'skills' / model / 'software-factory/SKILL.md').read_bytes())
                            self.assertFalse((project / '.claude').exists())

    def test_redirected_installation_parents(self):
        sys.path.insert(0, str(ROOT / 'skills/openai/software-factory/scripts'))
        import workspace
        for shell in ('powershell', 'bash'):
            for model in ('openai', 'claude'):
                for relative in ('.agents', '.agents/skills'):
                    with self.subTest(shell=shell, model=model, parent=relative):
                        with tempfile.TemporaryDirectory(prefix='armoury parents ') as temporary:
                            project = Path(temporary) / 'project'
                            outside = Path(temporary) / 'outside'
                            project.mkdir()
                            outside.mkdir()
                            link = project / relative
                            workspace.make_link(link, outside)
                            try:
                                self.run_installer(shell, model, 'all', project, success=False)
                                self.assertEqual(list(outside.iterdir()), [])
                            finally:
                                workspace.unlink(link)

    def test_invalid_selections(self):
        for shell in ('powershell', 'bash'):
            for selection in ('unknown', 'collection:unknown', '999', ', ,', 'tldr', 'unslop'):
                with self.subTest(shell=shell, selection=selection):
                    with tempfile.TemporaryDirectory(prefix='armoury checks ') as temporary:
                        project = Path(temporary)
                        self.run_installer(shell, 'openai', selection, project, success=False)
                        self.assertEqual(list(project.iterdir()), [])


if __name__ == '__main__':
    unittest.main(verbosity=2)
