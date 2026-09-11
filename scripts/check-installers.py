"""Check repository consistency and both installers using temporary projects."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
POWERSHELL = shutil.which('pwsh') or shutil.which('powershell')
GIT_BASH = Path(os.environ.get('ProgramFiles', 'C:/Program Files')) / 'Git/bin/bash.exe'
BASH = str(GIT_BASH) if GIT_BASH.is_file() else shutil.which('bash')


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

    def test_bash_syntax(self):
        subprocess.run([BASH, '-n', './scripts/install-skills.sh'], cwd=ROOT, check=True)

    def test_installations(self):
        all_names = {p.name for p in (ROOT / 'skills/openai').iterdir() if p.is_dir()}
        selections = {
            'all': all_names,
            ' all ,unslop': all_names,
            '0': all_names,
            'UNSLOP': {'unslop'},
            '1': {'code-structure'},
            'collection:architecture': {'code-structure'},
            'collection:design-delivery,unslop': {'specflow', 'tldr', 'unslop'},
            'COLLECTION:review-and-challenge,tldr': {'tldr', 'unslop'},
        }
        for shell in ('powershell', 'bash'):
            for model in ('openai', 'claude'):
                for selection, expected in selections.items():
                    with self.subTest(shell=shell, model=model, selection=selection):
                        with tempfile.TemporaryDirectory(prefix='armoury checks ') as temporary:
                            project = Path(temporary)
                            destination = project / ('.agents' if model == 'openai' else '.claude') / 'skills'
                            self.run_installer(shell, model, selection, project)
                            self.assertEqual({p.name for p in destination.iterdir()}, expected)
                            for name in expected:
                                source = ROOT / 'skills' / model / name
                                for original in source.rglob('*'):
                                    if original.is_file():
                                        self.assertEqual(original.read_bytes(), (destination / name / original.relative_to(source)).read_bytes())
                            retained = destination / next(iter(expected)) / 'local.txt'
                            retained.write_text('keep me', encoding='utf-8')
                            self.run_installer(shell, model, selection, project)
                            self.assertEqual(retained.read_text(encoding='utf-8'), 'keep me')

    def test_invalid_selections(self):
        for shell in ('powershell', 'bash'):
            for selection in ('unknown', 'collection:unknown', '999', ', ,'):
                with self.subTest(shell=shell, selection=selection):
                    with tempfile.TemporaryDirectory(prefix='armoury checks ') as temporary:
                        project = Path(temporary)
                        self.run_installer(shell, 'openai', selection, project, success=False)
                        self.assertEqual(list(project.iterdir()), [])


if __name__ == '__main__':
    unittest.main(verbosity=2)
