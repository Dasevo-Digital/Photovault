import base64
import hashlib
import json
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from installation import FernInstallation, Installationsfehler, LinuxInstallation, MacInstallation


def antwort(args, code=0, text=''):
    return subprocess.CompletedProcess(args, code, text, '')


def manifest(datei):
    datei.parent.mkdir(parents=True, exist_ok=True)
    (datei.parent / 'SHA256SUMS.txt').write_text(hashlib.sha256(datei.read_bytes()).hexdigest() + '  ' + datei.name + '\n')


class Fernlaeufer:
    def __init__(self, fehler=None):
        self.fehler, self.phasen = set(fehler or []), []

    def __call__(self, args):
        if args[0] == 'scp':
            return antwort(args)
        cmd = args[-1]
        if 'EncodedCommand ' in cmd:
            cmd = base64.b64decode(cmd.split('EncodedCommand ', 1)[1]).decode('utf-16le')
        phase = re.search(r"(?:--phase |Phase ')(\w+)", cmd)
        if phase is None:
            return antwort(args)
        phase = phase[1]
        self.phasen.append(phase)
        if phase in self.fehler:
            return antwort(args, 1)
        return antwort(args, text='PV_RESULT {}')


class Phasenvertrag(unittest.TestCase):
    def test_windows_dateiliste_bleibt_aus_der_befehlszeile(self):
        plan = {'dateien': {'ordner/Beispieldatei-%04d.txt' % i: 'a' * 64 for i in range(1000)}}
        uebertragen = []
        def runner(args):
            if args[0] == 'scp':
                uebertragen.append(json.loads(Path(args[-2]).read_text(encoding='utf-8')))
            else:
                self.assertLess(len(args[-1]), 8192)
                cmd = base64.b64decode(args[-1].split('EncodedCommand ', 1)[1]).decode('utf-16le')
                self.assertIn('-PlanDatei ', cmd)
                self.assertNotIn('-PlanBase64 ', cmd)
            return antwort(args, text='PV_RESULT {}')
        installation = FernInstallation('windows', 'testziel', '3.49.5', runner=runner)
        installation.zustand.update(plan)
        installation._phase('tauschen')
        self.assertEqual(uebertragen, [installation.zustand])

    def test_alle_plattformen_brechen_vor_dem_austausch_ab(self):
        for platform in ['linux', 'windows']:
            for phase in ['vorpruefen', 'vorbereiten']:
                with self.subTest(platform=platform, phase=phase):
                    runner = Fernlaeufer([phase])
                    with self.assertRaises(Installationsfehler):
                        FernInstallation(platform, 'testziel', '3.49.4', runner=runner).ausfuehren()
                    self.assertNotIn('tauschen', runner.phasen)
                    self.assertNotIn('nachpruefen', runner.phasen)

    def test_tausch_und_nachprueffehler_loesen_rueckfall_aus(self):
        for platform in ['linux', 'windows']:
            for phase in ['tauschen', 'nachpruefen']:
                with self.subTest(platform=platform, phase=phase):
                    runner = Fernlaeufer([phase])
                    with self.assertRaises(Installationsfehler):
                        FernInstallation(platform, 'testziel', '3.49.4', runner=runner).ausfuehren()
                    self.assertEqual(runner.phasen[-2:], ['zuruecksetzen', 'aufraeumen'])
                    self.assertNotIn('abschliessen', runner.phasen)

    def test_bei_fehlgeschlagenem_rueckfall_bleibt_die_ablage_erhalten(self):
        for platform in ['linux', 'windows']:
            runner = Fernlaeufer(['nachpruefen', 'zuruecksetzen'])
            with self.assertRaises(Installationsfehler):
                FernInstallation(platform, 'testziel', '3.49.4', runner=runner).ausfuehren()
            self.assertNotIn('aufraeumen', runner.phasen)

    def test_erfolg_benoetigt_eine_nachpruefung(self):
        for platform in ['linux', 'windows']:
            runner = Fernlaeufer()
            ergebnis = FernInstallation(platform, 'testziel', '3.49.4', runner=runner).ausfuehren()
            self.assertTrue(ergebnis['installiert'])
            self.assertEqual(runner.phasen, ['vorpruefen', 'vorbereiten', 'tauschen', 'nachpruefen', 'abschliessen'])


class LinuxVertrag(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='pv_install_linux_')
        self.addCleanup(self.temp.cleanup)
        self.desktop = Path(self.temp.name)
        self.paket = self.desktop / 'PhotoVault-Release-v3.49.4-Upload/PhotoVault-3.49.4-x86_64.flatpak'
        self.paket.parent.mkdir()
        self.paket.write_bytes(b'neues synthetisches Paket')
        manifest(self.paket)
        (self.desktop / 'PhotoVault-3.49.3-x86_64.flatpak').write_bytes(b'vorheriges synthetisches Paket')
        self.version, self.commit = '3.49.3', 'a' * 64
        self.aktiv, self.installfehler, self.falsche_version = False, False, False
        self.installationen = []

    def runner(self, args):
        if args[1] == 'ps':
            return antwort(args, text='de.dasevo.photovault' if self.aktiv else '')
        if args[1] == 'info':
            return antwort(args, text=self.commit if '--show-commit' in args else 'Version: ' + self.version)
        if args[1] == 'install':
            self.installationen.append(args[-1])
            if self.installfehler:
                return antwort(args, 1)
            if Path(args[-1]).name == 'alt.flatpak':
                self.version, self.commit = '3.49.3', 'a' * 64
            else:
                self.version = '3.49.2' if self.falsche_version else '3.49.4'
                self.commit = 'b' * 64
            return antwort(args)
        raise AssertionError(args)

    def installation(self):
        return LinuxInstallation('3.49.4', desktop=self.desktop, runner=self.runner)

    def test_fehler_der_installation_bleibt_ein_fehler(self):
        self.installfehler = True
        with self.assertRaises(Installationsfehler):
            self.installation().ausfuehren()
        self.assertEqual(self.version, '3.49.3')
        self.assertEqual(len(self.installationen), 1)

    def test_falsche_nachpruefung_stellt_den_vorherigen_commit_wieder_her(self):
        self.falsche_version = True
        with self.assertRaises(Installationsfehler):
            self.installation().ausfuehren()
        self.assertEqual((self.version, self.commit), ('3.49.3', 'a' * 64))
        self.assertEqual(Path(self.installationen[-1]).name, 'alt.flatpak')

    def test_unlesbare_teilinstallation_verhindert_den_rueckfall_nicht(self):
        def runner(args):
            if args[1] == 'info' and self.version == 'unlesbar':
                return antwort(args, 1)
            r = self.runner(args)
            if args[1] == 'install' and Path(args[-1]).name == 'neu.flatpak':
                self.version = 'unlesbar'
                return antwort(args, 1)
            return r
        with self.assertRaises(Installationsfehler):
            LinuxInstallation('3.49.4', desktop=self.desktop, runner=runner).ausfuehren()
        self.assertEqual((self.version, self.commit), ('3.49.3', 'a' * 64))
        self.assertEqual(Path(self.installationen[-1]).name, 'alt.flatpak')

    def test_fehlendes_oder_beschaedigtes_paket_erreicht_keinen_austausch(self):
        for defekt in ['fehlt', 'hash']:
            with self.subTest(defekt=defekt):
                if defekt == 'fehlt':
                    self.paket.unlink()
                else:
                    self.paket.write_bytes(b'b beschaedigt')
                with self.assertRaises(Installationsfehler):
                    self.installation().ausfuehren()
                self.assertEqual(self.installationen, [])

    def test_laufende_app_wird_nicht_beendet(self):
        self.aktiv = True
        with self.assertRaises(Installationsfehler):
            self.installation().ausfuehren()
        self.assertEqual(self.installationen, [])

    def test_unvollstaendige_vorbereitung_laesst_vorversion_intakt(self):
        with patch('installation.shutil.copyfile', side_effect=OSError('synthetisch voll')):
            with self.assertRaises(OSError):
                self.installation().ausfuehren()
        self.assertEqual(self.version, '3.49.3')
        self.assertEqual(self.installationen, [])
        self.assertEqual(list(self.desktop.glob('.PhotoVault-*')), [])

    def test_erfolg_liefert_tatsaechlichen_commit(self):
        r = self.installation().ausfuehren()
        self.assertEqual(r['installierterCommit'], 'b' * 64)
        self.assertEqual(self.version, '3.49.4')
        self.assertEqual(list(self.desktop.glob('.PhotoVault-*')), [])


class MacVertrag(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='pv_install_mac_')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.quelle, self.ziel = self.root / 'quelle', self.root / 'installiert'
        self.ablage = self.root / 'vorversionen'
        for app, version, daten in [(self.quelle, '3.49.4', b'neu'), (self.ziel, '3.49.3', b'alt')]:
            (app / 'Contents/MacOS').mkdir(parents=True)
            (app / 'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': 'de.dasevo.photovault', 'CFBundleShortVersionString': version, 'CFBundleExecutable': 'probe'}))
            (app / 'Contents/MacOS/probe').write_bytes(daten)
        self.paket = self.root / 'PhotoVault-3.49.4-macos.zip'
        self.zip(self.quelle, self.paket)
        manifest(self.paket)
        self.aktiv, self.teilkopie, self.nachprueffehler = False, False, False
        self.aufrufe = []

    @staticmethod
    def zip(app, ziel):
        with zipfile.ZipFile(ziel, 'w') as z:
            for f in app.rglob('*'):
                if f.is_file():
                    z.write(f, str(f.relative_to(app.parent)))

    def runner(self, args):
        self.aufrufe.append(args)
        if args[0] == 'pgrep':
            return antwort(args, 0 if self.aktiv else 1)
        if args[0] == 'codesign':
            post = Path(args[-1]) == self.ziel and (self.ziel / 'Contents/MacOS/probe').read_bytes() == b'neu'
            return antwort(args, 1 if post and self.nachprueffehler else 0)
        if args[0] == 'ditto' and '-c' in args:
            self.zip(Path(args[-2]), Path(args[-1]))
            return antwort(args)
        if args[0] == 'ditto':
            if self.teilkopie:
                Path(args[-1]).mkdir()
                (Path(args[-1]) / 'teil').write_bytes(b'teilweise')
                return antwort(args, 1)
            shutil.copytree(args[-2], args[-1])
            return antwort(args)
        raise AssertionError(args)

    def installation(self, klasse=MacInstallation):
        return klasse('3.49.4', self.quelle, self.ziel, self.ablage, runner=self.runner)

    def test_teilkopie_belaesst_vorversion_direkt_am_ziel(self):
        self.teilkopie = True
        with self.assertRaises(Installationsfehler):
            self.installation().ausfuehren()
        self.assertEqual((self.ziel / 'Contents/MacOS/probe').read_bytes(), b'alt')
        self.assertEqual(list(self.ziel.glob('*.app')), [])
        self.assertEqual(list(self.root.glob('.*stage*')), [])

    def test_nachprueffehler_rollt_tausch_vollstaendig_zurueck(self):
        self.nachprueffehler = True
        with self.assertRaises(Installationsfehler):
            self.installation().ausfuehren()
        self.assertEqual((self.ziel / 'Contents/MacOS/probe').read_bytes(), b'alt')
        self.assertEqual(list(self.root.glob('.*alt*')), [])
        self.assertEqual(len(list(self.ablage.glob('*.zip'))), 1)

    def test_fehler_zwischen_den_beiden_umbenennungen(self):
        class Teiltausch(MacInstallation):
            def tauschen(self):
                self.ziel.rename(self.alt)
                raise OSError('synthetischer Austauschfehler')
        with self.assertRaises(OSError):
            self.installation(Teiltausch).ausfuehren()
        self.assertEqual((self.ziel / 'Contents/MacOS/probe').read_bytes(), b'alt')

    def test_laufende_app_wird_nicht_geschlossen(self):
        self.aktiv = True
        with self.assertRaises(Installationsfehler):
            self.installation().ausfuehren()
        self.assertFalse(self.ablage.exists())
        self.assertFalse(any(a[0] == 'ditto' for a in self.aufrufe))

    def test_fehlendes_paket_verschiebt_keine_app(self):
        self.paket.unlink()
        with self.assertRaises(Installationsfehler):
            self.installation().ausfuehren()
        self.assertEqual((self.ziel / 'Contents/MacOS/probe').read_bytes(), b'alt')

    def test_beschaedigtes_paket_verschiebt_keine_app(self):
        self.paket.write_bytes(b'kaputt')
        with self.assertRaises(Installationsfehler):
            self.installation().ausfuehren()
        self.assertFalse(self.ablage.exists())

    def test_erfolg_behaelt_verifizierte_vorversion(self):
        result = self.installation().ausfuehren()
        self.assertTrue(result['installiert'])
        self.assertEqual((self.ziel / 'Contents/MacOS/probe').read_bytes(), b'neu')
        self.assertTrue(Path(result['sicherung']).is_file())
        self.assertFalse(any(a[0] in ('open', 'kill', 'pkill') for a in self.aufrufe))


if __name__ == '__main__':
    unittest.main()
