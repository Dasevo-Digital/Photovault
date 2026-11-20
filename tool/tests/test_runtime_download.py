"""Prüft Download/Entpacken ohne Netz anhand eigener Archive."""
import hashlib
import io
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
