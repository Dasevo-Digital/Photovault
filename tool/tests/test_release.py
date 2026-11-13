import base64
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
import unittest.mock
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


class Wiederholen(unittest.TestCase):
    """Schritte, die aus dem Netz laden, versuchen es noch einmal (#294)."""

    def setUp(self):
        self.ordner = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.ordner)
        self.zaehler = self.ordner / 'n'
        # Scheitert zweimal, dann geht es. Als Liste: Ein Text liefe unter
        # Windows durch cmd.exe, nicht durch sh.
        self.befehl = [sys.executable, '-c',
                       'import pathlib, sys\n'
                       'p = pathlib.Path(sys.argv[1])\n'
                       'n = int(p.read_text()) + 1 if p.exists() else 1\n'
                       'p.write_text(str(n))\n'
                       'sys.exit(0 if n >= 3 else 1)\n',
                       str(self.zaehler)]

    def test_beim_dritten_mal_klappt_es(self):
        with unittest.mock.patch('release.time.sleep') as schlafen:
            release.lauf(self.befehl, cwd=self.ordner, versuche=3, pause=5)
        self.assertEqual(self.zaehler.read_text().strip(), '3')
        self.assertEqual(schlafen.call_count, 2)

    def test_ohne_versuche_bricht_es_gleich_ab(self):
        with unittest.mock.patch('release.time.sleep') as schlafen:
            with self.assertRaises(SystemExit):
                release.lauf(self.befehl, cwd=self.ordner)
        self.assertEqual(self.zaehler.read_text().strip(), '1')
        schlafen.assert_not_called()


class BasisImages(unittest.TestCase):
    """Was vor dem Server-Bau bereitliegen soll, folgt dem Dockerfile."""

    def test_aus_den_arg_vorgaben(self):
        d = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, d)
        (d / 'Dockerfile').write_text(
            'ARG DART_FASSUNG=9.8.7\nARG DEBIAN=forky-slim\nARG UBUNTU=99.04\n'
            'FROM dart:${DART_FASSUNG} AS bau\nFROM debian:${DEBIAN}\n')
        self.assertEqual(release.basis_images(d / 'Dockerfile'), ['dart:9.8.7', 'debian:forky-slim'])

    def test_das_echte_dockerfile(self):
        images = release.basis_images(REPO / 'packages/server/Dockerfile')
        self.assertEqual(len(images), 2)
        self.assertTrue(images[0].startswith('dart:'))


class PrePush(unittest.TestCase):
    """Ein Tag auf einem schon geprüften main-Commit läuft nicht noch
    einmal durch alle Tests (#287)."""

    def setUp(self):
        # Der Hook ist ein Bash-Skript für Mac und Linux. Unter Windows fände
        # dieser Aufruf die WSL-Hülle in System32 und liefe gar nicht.
        if os.name == 'nt':
            self.skipTest('Der Hook läuft nur auf Mac und Linux.')
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


class Notarisieren(unittest.TestCase):
    """Apple notarisiert das Mac-Paket (#319, #89, #382)."""

    ZIELE = {'mac_signatur': 'ABC', 'mac_notar_profil': 'pv-notar'}

    def laufe(self, antworten):
        """Spielt notarytool mit [antworten] nach – je Einreichung (stdout,
        stderr, Code) oder nur stdout; merkt sich jeden Aufruf."""
        aufrufe = []
        antworten = [a if isinstance(a, tuple) else (a, '', 0) for a in antworten]

        def run(befehl, **kw):
            aufrufe.append(befehl)
            aus, fehler, code = antworten.pop(0)
            return subprocess.CompletedProcess(befehl, code, aus, fehler)

        def lauf(befehl, **kw):
            aufrufe.append(befehl)
            return '' if kw.get('ausgabe') else 0

        with unittest.mock.patch('release.subprocess.run', side_effect=run), \
                unittest.mock.patch('release.lauf', side_effect=lauf), \
                unittest.mock.patch('release.time.sleep') as schlafen:
            try:
                release._notarisiere_mac('9.9.9', Path('/gibt/es/nicht'), self.ZIELE)
            except SystemExit as e:
                return aufrufe, schlafen, e
        return aufrufe, schlafen, None

    @staticmethod
    def art(aufrufe):
        return [' '.join(a[:3]) for a in aufrufe]

    def test_angenommen_heftet_das_ticket_an_und_packt_neu(self):
        aufrufe, _, fehler = self.laufe(['{"id": "x1", "status": "Accepted"}'])
        self.assertIsNone(fehler)
        self.assertIn('xcrun stapler staple', self.art(aufrufe))
        self.assertEqual(aufrufe[-1][0], 'ditto')

    def test_abgelehnt_holt_die_begruendung_und_schickt_nicht_noch_einmal(self):
        aufrufe, schlafen, fehler = self.laufe(['{"id": "x2", "status": "Invalid", "message": "nein"}'])
        self.assertIsNotNone(fehler)
        self.assertIn('Invalid', str(fehler))
        arten = self.art(aufrufe)
        self.assertEqual(arten.count('xcrun notarytool submit'), 1)
        self.assertIn('xcrun notarytool log', arten)
        self.assertNotIn('xcrun stapler staple', arten)
        schlafen.assert_not_called()

    def test_zeit_um_reicht_nicht_noch_einmal_ein(self):
        # Nach --timeout liegt das Paket weiter bei Apple: eine zweite
        # Einreichung wartete nur noch einmal sechs Stunden.
        aufrufe, schlafen, fehler = self.laufe([('{"id": "x5", "status": "In Progress"}', '', 1)])
        self.assertIsNotNone(fehler)
        self.assertIn('x5', str(fehler))
        self.assertEqual(self.art(aufrufe).count('xcrun notarytool submit'), 1)
        schlafen.assert_not_called()

    def test_ohne_einreichung_ein_zweiter_versuch_mit_grund(self):
        with unittest.mock.patch('builtins.print') as drucke:
            aufrufe, schlafen, fehler = self.laufe([
                ('', 'Error: No Keychain password item found for profile', 69),
                '{"id": "x3", "status": "Accepted"}',
            ])
        self.assertIsNone(fehler)
        self.assertEqual(self.art(aufrufe).count('xcrun notarytool submit'), 2)
        self.assertEqual(schlafen.call_count, 1)
        gedruckt = ' '.join(str(c.args[0]) for c in drucke.call_args_list if c.args)
        self.assertIn('Keychain password item', gedruckt, 'der Grund geht nicht verloren')

    def test_zweimal_ohne_einreichung_bricht_ab(self):
        aufrufe, _, fehler = self.laufe([('Fehler', '', 1), ('Fehler', '', 1)])
        self.assertIsNotNone(fehler)
        self.assertNotIn('xcrun stapler staple', self.art(aufrufe))

    def test_vorspann_vor_dem_json_zaehlt_nicht_als_keine_antwort(self):
        aufrufe, schlafen, fehler = self.laufe(['Waiting...\n{"id": "x4", "status": "Accepted"}\n'])
        self.assertIsNone(fehler)
        self.assertEqual(self.art(aufrufe).count('xcrun notarytool submit'), 1)
        schlafen.assert_not_called()

    def test_json_auch_eingerueckt_nach_vorspann(self):
        self.assertEqual(release._letztes_json('{\n  "status": "Invalid"\n}')['status'], 'Invalid')
        self.assertEqual(release._letztes_json('Warte …\n{\n  "id": "a",\n  "status": "Accepted"\n}\n')['id'], 'a')
        self.assertEqual(release._letztes_json('kein json'), {})

    def test_ohne_profil_bleibt_es_unnotarisiert(self):
        with unittest.mock.patch('release.lauf') as lauf:
            release._notarisiere_mac('9.9.9', Path('/x'), {'mac_signatur': 'ABC'})
        lauf.assert_not_called()


class MacBau(unittest.TestCase):
    """Ein halbes Mac-Paket bleibt nicht liegen (#382)."""

    def setUp(self):
        self.u = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.u)

    def baue(self, scheitern):
        (self.u / 'PhotoVault-9.9.9-macos.zip').write_text('alt')
        (self.u / 'Photo Vault.app').mkdir()

        def lauf(befehl, **kw):
            if isinstance(befehl, list) and befehl[:2] == ['rm', '-rf']:
                for p in befehl[2:]:
                    shutil.rmtree(p, ignore_errors=True) if Path(p).is_dir() else Path(p).unlink(missing_ok=True)
            if isinstance(befehl, str) and befehl.startswith('ps'):
                return ''
            return '' if kw.get('ausgabe') else 0

        def packe(fassung, u):
            (u / f'PhotoVault-{fassung}-macos.zip').write_text('signiert, nicht notarisiert')
            (u / 'Photo Vault.app').mkdir(exist_ok=True)

        with unittest.mock.patch('release.lauf', side_effect=lauf), \
                unittest.mock.patch('release._signiere_mac'), \
                unittest.mock.patch('release._packe_mac', side_effect=packe), \
                unittest.mock.patch('release._notarisiere_mac', side_effect=scheitern):
            release._baue_mac('9.9.9', self.u, {})

    def test_scheitert_die_notarisierung_liegt_nichts_da(self):
        with self.assertRaises(SystemExit):
            self.baue(SystemExit('abgelehnt'))
        self.assertFalse((self.u / 'PhotoVault-9.9.9-macos.zip').exists())
        self.assertFalse((self.u / 'Photo Vault.app').exists())

    def test_auch_bei_ctrl_c(self):
        with self.assertRaises(KeyboardInterrupt):
            self.baue(KeyboardInterrupt())
        self.assertFalse((self.u / 'PhotoVault-9.9.9-macos.zip').exists())


class Entwurf(unittest.TestCase):
    """Was im Entwurf schon liegt, bleibt nur, wenn es dasselbe ist (#382)."""

    def setUp(self):
        self.u = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.u)
        (self.u / 'RELEASE-TEXT-v9.9.9.md').write_text('# Photo Vault 9.9.9')
        self.mac = 'PhotoVault-9.9.9-macos.zip'
        (self.u / self.mac).write_bytes(b'neu notarisiert!')

    def laufe(self, oben_summe, entwurf=True, groesse=None):
        import hashlib
        lokal = hashlib.sha256((self.u / self.mac).read_bytes()).hexdigest()
        (self.u / 'SHA256SUMS.txt').write_text(f'{lokal}  {self.mac}\n')
        rel = {'id': 7, 'draft': entwurf, 'assets': [
            {'id': 1, 'name': self.mac, 'size': groesse or (self.u / self.mac).stat().st_size},
            {'id': 2, 'name': 'SHA256SUMS.txt', 'size': 90, 'browser_download_url': 'x'},
        ]}
        anfragen = []

        def gitea(z, pfad, daten=None, methode=None, kopf=None, tok=None):
            anfragen.append((methode or 'GET', pfad.split('?')[0]))
            if pfad == '/releases/tags/v9.9.9':
                return 200, rel
            if methode == 'POST':
                return 201, {'size': 1}
            if methode == 'DELETE':
                return 204, None
            return 200, rel

        summe = lokal if oben_summe == 'gleich' else 'f' * 64
        with unittest.mock.patch('release.ziele', return_value={}), \
                unittest.mock.patch('release.token', return_value='t'), \
                unittest.mock.patch('release.upload_ordner', return_value=self.u), \
                unittest.mock.patch('release.gitea', side_effect=gitea), \
                unittest.mock.patch('release._lade_anhang', return_value=f'{summe}  {self.mac}\n'):
            try:
                release.entwurf(unittest.mock.Mock(fassung='9.9.9'))
            except SystemExit as e:
                return anfragen, e
        return anfragen, None

    def test_gleich_bleibt(self):
        anfragen, fehler = self.laufe('gleich')
        self.assertIsNone(fehler)
        self.assertNotIn(('DELETE', '/releases/7/assets/1'), anfragen)
        self.assertNotIn(('DELETE', '/releases/7/assets/2'), anfragen)

    def test_gleich_gross_aber_anders_wird_ersetzt(self):
        anfragen, fehler = self.laufe('anders')
        self.assertIsNone(fehler)
        self.assertIn(('DELETE', '/releases/7/assets/1'), anfragen)
        self.assertIn(('DELETE', '/releases/7/assets/2'), anfragen)

    def test_veroeffentlicht_wird_nichts_ersetzt(self):
        anfragen, fehler = self.laufe('anders', entwurf=False)
        self.assertIsNotNone(fehler)
        self.assertNotIn('DELETE', [m for m, _ in anfragen])
        self.assertNotIn('POST', [m for m, _ in anfragen])

    def test_summen_lesen(self):
        self.assertEqual(release.summen_lesen('a' * 64 + '  x.zip\nunsinn\n' + 'b' * 64 + ' *y.zip\n'),
                         {'x.zip': 'a' * 64, 'y.zip': 'b' * 64})


if __name__ == '__main__':
    unittest.main()
