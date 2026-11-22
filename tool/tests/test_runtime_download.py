"""Prüft Download/Entpacken ohne Netz anhand eigener Archive."""
import hashlib
import io
import os
import re
import shutil
import subprocess
import tarfile
import tempfile
import unittest
from pathlib import Path

class RuntimeDownload(unittest.TestCase):
    def setUp(self):
        if not shutil.which('cmake'):
            self.skipTest('CMake für Archivprüfungen nicht installiert')
        self.temporary=tempfile.TemporaryDirectory(prefix='pv_cmake_')
        self.addCleanup(self.temporary.cleanup)
        self.root=Path(self.temporary.name)
        self.helper=Path(__file__).resolve().parents[2]/'third_party/flutter_onnxruntime/cmake/runtime_download.cmake'
    def ausfuehren(self,data,hash=None):
        quelle=self.root/'quelle.tgz';quelle.write_bytes(data)
        cmake=self.root/'probe.cmake'
        cmake.write_text('include("'+self.helper.as_posix()+'")\n'+
            'pv_runtime_download("'+quelle.as_uri()+'" "'+(self.root/'cache.tgz').as_posix()+'" "'+(self.root/'runtime').as_posix()+'" "'+(hash or hashlib.sha256(data).hexdigest())+'")\n')
        return subprocess.run(['cmake','-P',str(cmake)],text=True,capture_output=True)
    def archiv(self):
        b=io.BytesIO()
        with tarfile.open(fileobj=b,mode='w:gz') as tar:
            data=b'header';info=tarfile.TarInfo('runtime/include/onnxruntime_cxx_api.h');info.size=len(data);tar.addfile(info,io.BytesIO(data))
        return b.getvalue()
    def test_erfolg_nur_nach_vollstaendigem_entpacken(self):
        r=self.ausfuehren(self.archiv());self.assertEqual(r.returncode,0,r.stderr)
        self.assertEqual((self.root/'runtime/include/onnxruntime_cxx_api.h').read_bytes(),b'header')
        self.assertFalse((self.root/'cache.tgz').exists());self.assertFalse((self.root/'unpack').exists())
    def test_falsche_summe_legt_keinen_fertigen_cache_an(self):
        r=self.ausfuehren(self.archiv(),'0'*64);self.assertNotEqual(r.returncode,0)
        self.assertIn('SHA256 differs',r.stderr);self.assertFalse((self.root/'runtime').exists());self.assertFalse((self.root/'cache.tgz').exists())
    def test_keine_html_fehlerseite_als_archiv(self):
        r=self.ausfuehren(b'<html>404</html>');self.assertNotEqual(r.returncode,0)
        self.assertIn('extraction failed',r.stderr);self.assertFalse((self.root/'runtime').exists())

    def fetch(self,data,name,override='',quelle=None,default='http://127.0.0.1:9/nichts'):
        ordner=self.root/'ablage';ordner.mkdir(exist_ok=True);(ordner/name).write_bytes(data)
        cmake=self.root/'fetch.cmake'
        cmake.write_text('include("'+self.helper.as_posix()+'")\n'+
            'pv_runtime_fetch("'+default+'" "'+name+'" "'+override+'" "'+(self.root/'cache.tgz').as_posix()+'" "'+(self.root/'runtime').as_posix()+'")\n')
        umgebung=dict(os.environ);umgebung.pop('PV_ONNXRUNTIME_QUELLE',None)
        if quelle is not None:umgebung['PV_ONNXRUNTIME_QUELLE']=quelle
        return subprocess.run(['cmake','-P',str(cmake)],text=True,capture_output=True,env=umgebung)
    def test_jede_summe_der_liste_gilt(self):
        data=self.archiv()
        r=self.ausfuehren(data,'0'*64+';'+hashlib.sha256(data).hexdigest());self.assertEqual(r.returncode,0,r.stderr)
        self.assertTrue((self.root/'runtime/include/onnxruntime_cxx_api.h').exists())
    def test_eigene_quelle_aus_der_umgebung(self):
        # #473: Die Vorgabe ist nicht erreichbar, die eigene Ablage schon.
        data=self.archiv()
        r=self.fetch(data,'probe.tgz',hashlib.sha256(data).hexdigest(),quelle=(self.root/'ablage').as_uri()+'/')
        self.assertEqual(r.returncode,0,r.stderr);self.assertIn('ablage/probe.tgz',r.stdout+r.stderr)
        self.assertTrue((self.root/'runtime/include/onnxruntime_cxx_api.h').exists())
    def test_eigene_quelle_nur_mit_fester_summe(self):
        r=self.fetch(self.archiv(),'nicht-gelistet.tgz',quelle=(self.root/'ablage').as_uri())
        self.assertNotEqual(r.returncode,0);self.assertIn('No pinned SHA256',r.stderr)
        self.assertFalse((self.root/'runtime').exists())
    def test_eigene_quelle_mit_falschem_archiv_scheitert(self):
        # Gelistet, aber nicht dieses Archiv: Die feste Summe gilt auch für die Ablage.
        r=self.fetch(self.archiv(),'onnxruntime-linux-x64-1.28.3.tgz',quelle=(self.root/'ablage').as_uri())
        self.assertNotEqual(r.returncode,0);self.assertIn('SHA256 differs',r.stderr)
        self.assertFalse((self.root/'runtime').exists())
    def test_liste_liefert_alle_summen_eines_namens(self):
        cmake=self.root/'pins.cmake'
        cmake.write_text('include("'+self.helper.as_posix()+'")\n'
            'pv_runtime_pins("onnxruntime-linux-x64-1.28.3.tgz" "" s)\nmessage(STATUS "PINS=${s}")\n'
            'pv_runtime_pins("onnxruntime-linux-x64-1.28.3.tgz" "ABC" s)\nmessage(STATUS "HAND=${s}")\n')
        r=subprocess.run(['cmake','-P',str(cmake)],text=True,capture_output=True);self.assertEqual(r.returncode,0,r.stderr)
        erwartet=sorted(PINS['onnxruntime-linux-x64-1.28.3.tgz'])
        zeile=[z for z in r.stdout.splitlines() if 'PINS=' in z][0].split('PINS=')[1]
        self.assertEqual(sorted(zeile.split(';')),erwartet);self.assertIn('HAND=abc',r.stdout)


LISTE=Path(__file__).resolve().parents[2]/'third_party/flutter_onnxruntime/onnxruntime-pruefsummen.txt'
PINS={}
for _zeile in LISTE.read_text().splitlines():
    if _zeile and not _zeile.startswith('#'):
        _summe,_name=_zeile.split('  ');PINS.setdefault(_name,set()).add(_summe)


class Pruefsummenliste(unittest.TestCase):
    """Ohne CMake: Die Liste, die CMake, Dockerfile und release.py lesen."""
    def test_jede_zeile_ist_summe_und_name(self):
        for zeile in LISTE.read_text().splitlines():
            if zeile and not zeile.startswith('#'):
                self.assertRegex(zeile,r'^[0-9a-f]{64}  onnxruntime-(linux|win)-[a-z0-9]+-\d+\.\d+\.\d+\.(tgz|zip)$')
    def test_alle_gebauten_archive_haben_eine_summe(self):
        dockerfile=(LISTE.parents[2]/'packages/server/Dockerfile').read_text()
        fassung=re.search(r'^ARG ORT_FASSUNG=(\S+)',dockerfile,re.M).group(1)
        for name in [f'onnxruntime-linux-x64-{fassung}.tgz',f'onnxruntime-linux-aarch64-{fassung}.tgz',f'onnxruntime-win-x64-{fassung}.zip']:
            self.assertIn(name,PINS)
