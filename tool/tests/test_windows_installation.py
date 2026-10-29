"""Prüft die PowerShell-Phasen auf temporären Programmpaketen ohne Appstart."""
import base64
import hashlib
import json
import shutil
import subprocess
import tempfile
import unittest
from unittest import skipUnless
import uuid
import zipfile
from pathlib import Path

POWERSHELL = shutil.which('powershell')
MODUL = Path(__file__).resolve().parents[1] / 'installieren/windows.ps1'


def powershell(code):
    encoded = base64.b64encode(code.encode('utf-16le')).decode()
    return subprocess.run([POWERSHELL, '-NoProfile', '-EncodedCommand', encoded], capture_output=True)


def zitat(path):
    return "'" + str(path).replace("'", "''") + "'"


@skipUnless(POWERSHELL, 'Windows PowerShell wird für die nativen Dateiphase-Tests benötigt.')
class WindowsDateiphasen(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.bin_temp = tempfile.TemporaryDirectory(prefix='pv_installer_exe_')
        cls.binaries = {}
        for version in ['3.49.3', '3.49.4']:
            out = Path(cls.bin_temp.name) / (version + '.exe')
            source = ('using System.Reflection; [assembly: AssemblyVersion("' + version + '.0")] '
                      '[assembly: AssemblyInformationalVersion("' + version + '")] '
                      'public class Probe { public static void Main() {} }')
            r = powershell('Add-Type -TypeDefinition ' + zitat(source) + ' -OutputAssembly ' + zitat(out) + ' -OutputType ConsoleApplication')
            if r.returncode:
                raise AssertionError(r.stderr.decode(errors='replace'))
            cls.binaries[version] = out.read_bytes()

    @classmethod
    def tearDownClass(cls):
        cls.bin_temp.cleanup()

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='pv_windows_installation_')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.target = self.root / 'PhotoVault'
        self.target.mkdir()
        (self.target / 'photo_vault.exe').write_bytes(self.binaries['3.49.3'])
        (self.target / 'daten.txt').write_bytes(b'alter Programmstand')
        self.paket = self.root / 'PhotoVault-Release-v3.49.4-Upload/PhotoVault-3.49.4-windows-x64.zip'
        self.paket.parent.mkdir()
        with zipfile.ZipFile(self.paket, 'w') as z:
            z.writestr('PhotoVault/photo_vault.exe', self.binaries['3.49.4'])
            z.writestr('PhotoVault/daten.txt', b'neuer Programmstand')
        self.manifest = self.paket.parent / 'SHA256SUMS.txt'
        self.manifest.write_text(hashlib.sha256(self.paket.read_bytes()).hexdigest() + '  ' + self.paket.name + '\n')
        self.plan = {'version': '3.49.4', 'kennung': uuid.uuid4().hex, 'desktop': str(self.root)}

    def phase(self, name, *, erfolgreich=True):
        encoded = base64.b64encode(json.dumps(self.plan).encode()).decode()
        r = powershell('& ' + zitat(MODUL) + ' -Phase ' + zitat(name) + ' -PlanBase64 ' + zitat(encoded))
        self.assertEqual(r.returncode == 0, erfolgreich, r.stdout.decode(errors='replace') + r.stderr.decode(errors='replace'))
        if erfolgreich:
            text = r.stdout.decode('utf-8-sig', errors='replace')
            result = next(line[10:] for line in text.splitlines() if line.startswith('PV_RESULT '))
            self.plan.update(json.loads(result))

    def alt_intakt(self):
        self.assertEqual((self.target / 'photo_vault.exe').read_bytes(), self.binaries['3.49.3'])
        self.assertEqual((self.target / 'daten.txt').read_bytes(), b'alter Programmstand')
        self.assertEqual(list(self.target.glob('PhotoVault*')), [])

    def test_erfolg_prueft_alle_dateien_und_behaelt_vorversion(self):
        for name in ['vorpruefen', 'vorbereiten', 'tauschen', 'nachpruefen', 'abschliessen']:
            self.phase(name)
        self.assertEqual((self.target / 'photo_vault.exe').read_bytes(), self.binaries['3.49.4'])
        self.assertEqual((Path(self.plan['alt']) / 'photo_vault.exe').read_bytes(), self.binaries['3.49.3'])
        self.assertFalse(Path(self.plan['stage']).exists())

    def test_beschaedigtes_paket_beruehrt_vorversion_nicht(self):
        self.paket.write_bytes(b'b kaputt')
        self.phase('vorpruefen', erfolgreich=False)
        self.alt_intakt()

    def test_bibliotheksdatei_verhindert_austausch(self):
        (self.target / 'library.sqlite').write_bytes(b'synthetische Bibliotheksmarkierung')
        self.phase('vorpruefen', erfolgreich=False)
        self.alt_intakt()

    def test_fehler_zwischen_umbenennungen_stellt_vorversion_direkt_wieder_her(self):
        self.phase('vorpruefen')
        self.phase('vorbereiten')
        shutil.rmtree(Path(self.plan['stage']) / 'PhotoVault')
        self.phase('tauschen', erfolgreich=False)
        self.phase('zuruecksetzen')
        self.phase('aufraeumen')
        self.alt_intakt()

    def test_fehlerhafte_nachpruefung_rollt_den_gesamten_ordner_zurueck(self):
        for name in ['vorpruefen', 'vorbereiten', 'tauschen']:
            self.phase(name)
        (self.target / 'daten.txt').write_bytes(b'andere Daten')
        self.phase('nachpruefen', erfolgreich=False)
        self.phase('zuruecksetzen')
        self.phase('aufraeumen')
        self.alt_intakt()
