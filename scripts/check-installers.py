"""Check repository consistency and both installers using temporary projects."""

import os
import re
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path
import shutil


ROOT = Path(__file__).resolve().parents[1]
POWERSHELL = shutil.which('pwsh') or shutil.which('powershell')
GIT_BASH = Path(os.environ.get('ProgramFiles', 'C:/Program Files')) / 'Git/bin/bash.exe'
BASH = str(GIT_BASH) if GIT_BASH.is_file() else shutil.which('bash')
FILE_ATTRIBUTE_REPARSE_POINT = 1024


def packaged_files(source):
    for directory, folders, names in os.walk(source):
        folders[:] = [n for n in folders if n not in {'node_modules', 'dist', '.runtime', '__pycache__', '.pytest_cache', '.venv', 'state', 'specs'}]
        for name in names:
            if not name.endswith('.pyc'):
                yield Path(directory) / name


def is_link(path):
    try:
        info = path.lstat()
        return stat.S_ISLNK(info.st_mode) or bool(getattr(info, 'st_file_attributes', 0) & FILE_ATTRIBUTE_REPARSE_POINT)
    except FileNotFoundError:
        return False


def make_link(link, target):
    link.parent.mkdir(parents=True, exist_ok=True)
    if os.name == 'nt':
        env = dict(os.environ, ARMOURY_LINK=str(link), ARMOURY_TARGET=str(target))
        script = "$ErrorActionPreference='Stop'; New-Item -ItemType Junction -Path $env:ARMOURY_LINK -Target $env:ARMOURY_TARGET | Out-Null"
        result = subprocess.run(['powershell', '-NoProfile', '-NonInteractive', '-Command', script],
                                capture_output=True, text=True, env=env)
        if result.returncode:
            try:
                os.symlink(target, link, target_is_directory=True)
            except OSError as exc:
                raise RuntimeError(f'Cannot link {link}: {result.stderr.strip()}; {exc}') from exc
    else:
        os.symlink(target, link, target_is_directory=True)


def unlink(path):
    if not is_link(path):
        raise RuntimeError(f'Refusing to unlink a physical directory: {path}')
    if os.name == 'nt' and not path.is_symlink():
        os.rmdir(path)
    else:
        path.unlink()


def comparable_skill_text(content, name):
    return content.replace('$' + name, '/' + name)


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
            self.assertEqual(
                comparable_skill_text((ROOT / 'skills/openai' / name / 'SKILL.md').read_text(encoding='utf-8'), name),
                comparable_skill_text((ROOT / 'skills/claude' / name / 'SKILL.md').read_text(encoding='utf-8'), name),
            )
        self.assertEqual(names['openai'], {'shortandsweet', 'software-factory'})
        members = set()
        for manifest in (ROOT / 'collections').glob('*/collection.yaml'):
            entries = re.findall(r'^  - ([a-z0-9-]+)$', manifest.read_text(), re.MULTILINE)
            self.assertEqual(len(entries), len(set(entries)))
            self.assertTrue(set(entries) <= names['openai'])
            members.update(entries)
        self.assertEqual(members, names['openai'])
        for name in names['openai']:
            openai_root = ROOT / 'skills/openai' / name
            claude_root = ROOT / 'skills/claude' / name
            openai_files = {p.relative_to(openai_root).as_posix() for p in packaged_files(openai_root)}
            claude_files = {p.relative_to(claude_root).as_posix() for p in packaged_files(claude_root)}
            self.assertEqual(claude_files, openai_files - {'agents/openai.yaml'})
            self.assertFalse((claude_root / 'agents/openai.yaml').exists())
            for original in packaged_files(openai_root):
                relative = original.relative_to(openai_root).as_posix()
                counterpart = claude_root / original.relative_to(openai_root)
                if relative == 'agents/openai.yaml':
                    continue
                if original.name == 'SKILL.md':
                    continue
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
            '1': {'shortandsweet'},
            '2': {'software-factory'},
            'shortandsweet': {'shortandsweet'},
            'collection:software-factory': all_names,
            'COLLECTION:software-factory,shortandsweet': all_names,
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
                            retained_name = sorted(expected)[0]
                            retained = destination / retained_name / 'local.txt'
                            retained.write_text('keep me', encoding='utf-8')
                            records = destination / retained_name / 'specs' / 'index.md'
                            records.parent.mkdir(exist_ok=True)
                            records.write_text('existing records', encoding='utf-8')
                            state = destination / retained_name / 'state/project.json'
                            state.parent.mkdir(exist_ok=True)
                            state.write_text('{"name": "Keep"}')
                            self.run_installer(shell, model, selection, project)
                            self.assertEqual(state.read_text(), '{"name": "Keep"}')
                            self.assertEqual(retained.read_text(encoding='utf-8'), 'keep me')
                            self.assertEqual(records.read_text(encoding='utf-8'), 'existing records')
                            self.assertEqual({p.name for p in project.iterdir()}, {'.agents'})
                            self.assertEqual({p.name for p in (project / '.agents').iterdir()}, {'skills'})
                            self.assertEqual(neighbor.read_text(), 'Neighbor skill')
                            for name in expected:
                                self.assertEqual((destination / name / 'SKILL.md').read_bytes(),
                                                 (ROOT / 'skills' / model / name / 'SKILL.md').read_bytes())
                            self.assertFalse((project / '.claude').exists())

    def test_redirected_installation_parents(self):
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
                            make_link(link, outside)
                            try:
                                self.run_installer(shell, model, 'all', project, success=False)
                                self.assertEqual(list(outside.iterdir()), [])
                            finally:
                                unlink(link)

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
