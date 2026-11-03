import base64
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import release

REPO = Path(__file__).resolve().parents[2]
ZIELE = {'windows_ssh': 'testwin', 'linux_ssh': 'testlinux'}


class Laeufer:
    """Ein gestellter Testrechner: merkt sich jeden Aufruf, antwortet auf
    ssh mit [antwort]."""

    def __init__(self, antwort, code=0):
        self.antwort, self.code, self.aufrufe = antwort, code, []

    def __call__(self, befehl):
        self.aufrufe.append(befehl)
        text = self.antwort if befehl[0] == 'ssh' else ''
        return subprocess.CompletedProcess(befehl, self.code if befehl[0] == 'ssh' else 0, text, '')

    def scp(self):
        return [a for a in self.aufrufe if a[0] == 'scp']


class Bereitlegen(unittest.TestCase):
    """Der Upload-Ordner auf den Testrechnern (#286)."""

    def setUp(self):
        self.ordner = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.ordner)
        (self.ordner / 'SHA256SUMS.txt').write_text('a' * 64 + '  x\n')

    def test_liegt_das_paket_dort_kommen_nur_die_summen(self):
        l = Laeufer('ZIEL Desktop/PhotoVault-Release-v1.2.3-Upload\nDA\n')
        release.fern_bereitlegen(ZIELE, 'linux', '1.2.3', self.ordner, runner=l)
        befehl = l.aufrufe[0][-1]
        self.assertIn('mkdir -p ~/Desktop/PhotoVault-Release-v1.2.3-Upload', befehl)
        self.assertIn('mv -f ~/Desktop/PhotoVault-1.2.3-x86_64.flatpak', befehl)
        self.assertEqual(l.scp(), [[
            'scp', '-q', str(self.ordner / 'SHA256SUMS.txt'),
            'testlinux:Desktop/PhotoVault-Release-v1.2.3-Upload/SHA256SUMS.txt',
        ]])

    def test_fehlt_es_dort_geht_es_von_hier_hinueber(self):
        (self.ordner / 'PhotoVault-1.2.3-windows-x64.zip').write_bytes(b'zip')
        l = Laeufer('ZIEL Desktop/PhotoVault-Release-v1.2.3-Upload\r\n')
        release.fern_bereitlegen(ZIELE, 'windows', '1.2.3', self.ordner, runner=l)
        ziele = [a[-1] for a in l.scp()]
        self.assertEqual(ziele, [
            'testwin:Desktop/PhotoVault-Release-v1.2.3-Upload/PhotoVault-1.2.3-windows-x64.zip',
            'testwin:Desktop/PhotoVault-Release-v1.2.3-Upload/SHA256SUMS.txt',
        ])
        code = base64.b64decode(l.aufrufe[0][-1].split('EncodedCommand ')[1]).decode('utf-16le')
        self.assertIn("GetFolderPath('Desktop')", code)
        self.assertIn('Move-Item', code)

    def test_fehlt_es_hier_und_dort_bricht_es_ab(self):
        l = Laeufer('ZIEL Desktop/PhotoVault-Release-v1.2.3-Upload\n')
        with self.assertRaises(SystemExit):
            release.fern_bereitlegen(ZIELE, 'linux', '1.2.3', self.ordner, runner=l)
        self.assertEqual(l.scp(), [])

    def test_ohne_ordner_dort_bricht_es_ab(self):
        l = Laeufer('', code=255)
        with self.assertRaises(SystemExit):
            release.fern_bereitlegen(ZIELE, 'linux', '1.2.3', self.ordner, runner=l)


class PrePush(unittest.TestCase):
    """Ein Tag auf einem schon geprüften main-Commit läuft nicht noch
    einmal durch alle Tests (#287)."""

    def setUp(self):
        self.repo = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.repo)

        def git(*a):
            return subprocess.run(['git', *a], cwd=self.repo, check=True, text=True,
                                  capture_output=True).stdout.strip()

        self.git = git
        git('init', '-q', '-b', 'main')
        git('config', 'user.email', 'pruefung')
        git('config', 'user.name', 'test')
        (self.repo / '.githooks').mkdir()
        shutil.copy(REPO / '.githooks/pre-push', self.repo / '.githooks/pre-push')
        (self.repo / 'tool').mkdir()
        # Die Datenschutzprüfung als Attrappe, die sich meldet.
        pruefung = self.repo / 'tool/pruefe_repository_datenschutz.sh'
        pruefung.write_text('#!/bin/sh\necho DATENSCHUTZ\n')
        pruefung.chmod(0o755)
        git('add', '.')
        git('commit', '-q', '-m', 'eins')
        self.eins = git('rev-parse', 'HEAD')
        (self.repo / 'neu.txt').write_text('x')
        git('add', '.')
        git('commit', '-q', '-m', 'zwei')
        self.zwei = git('rev-parse', 'HEAD')
        # Was der Server hat: main bis „eins“.
        git('update-ref', 'refs/remotes/origin/main', self.eins)

    def hook(self, zeilen):
        umgebung = {k: v for k, v in os.environ.items() if not k.startswith('GIT_')}
        return subprocess.run(['bash', '.githooks/pre-push', 'origin', 'https://example.invalid/r.git'],
                              cwd=self.repo, input=zeilen, text=True, capture_output=True, env=umgebung)

    def test_marke_auf_geprueftem_commit_nur_datenschutz(self):
        self.git('tag', '-a', 'v1', '-m', 'eins', self.eins)
        tag = self.git('rev-parse', 'v1')
        r = self.hook(f'refs/tags/v1 {tag} refs/tags/v1 {"0" * 40}\n')
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn('DATENSCHUTZ', r.stderr)
        self.assertIn('nur Datenschutz', r.stderr)

    def test_marke_auf_neuem_commit_alle_pruefungen(self):
        self.git('tag', '-a', 'v2', '-m', 'zwei', self.zwei)
        tag = self.git('rev-parse', 'v2')
        r = self.hook(f'refs/tags/v2 {tag} refs/tags/v2 {"0" * 40}\n')
        # Die übrigen Schritte gibt es in diesem Repo nicht – dass der Hook
        # an ihnen scheitert, zeigt, dass er sie laufen lässt.
        self.assertNotIn('nur Datenschutz', r.stderr)
        self.assertIn('pre-push: python3', r.stderr)

    def test_main_immer_alle_pruefungen(self):
        r = self.hook(f'refs/heads/main {self.eins} refs/heads/main {self.eins}\n')
        self.assertNotIn('nur Datenschutz', r.stderr)
        self.assertIn('pre-push: python3', r.stderr)


if __name__ == '__main__':
    unittest.main()
