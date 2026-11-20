import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import release

class Releaseumfang(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name);self.version='9.8.7'
    def lege(self,namen):
        summen={}
        for n in namen:
            (self.root/n).write_bytes(n.encode());summen[n]=hashlib.sha256(n.encode()).hexdigest()
        (self.root/'SHA256SUMS.txt').write_text(''.join(h+'  '+n+'\n'for n,h in summen.items()))
        (self.root/'BUILD-STAND.json').write_text(json.dumps({'fassung':self.version,'commit':'a'*40,'pakete':summen}))
    def test_alle_drei_desktops_ohne_server_sind_ein_vollstaendiger_release(self):
        self.lege(release.dateien(self.version)[:3])
        with patch('release.lauf',return_value='a'*40):release.pruefe_releasepakete(self.version,self.root)
    def test_alle_desktops_mit_beiden_servern_sind_vollstaendig(self):
        self.lege(release.dateien(self.version))
        with patch('release.lauf',return_value='a'*40):release.pruefe_releasepakete(self.version,self.root)
    def test_fehlender_desktop_oder_nur_ein_server_stoppt_vor_jedem_push(self):
        for namen in [release.dateien(self.version)[:2],release.dateien(self.version)[:4]]:
            self.lege(namen)
            with patch('release.lauf') as run:
                with self.assertRaises(SystemExit):release.pruefe_releasepakete(self.version,self.root)
                run.assert_not_called()
    def test_geaendertes_paket_und_falscher_quellstand_werden_abgewiesen(self):
        namen=release.dateien(self.version)[:3];self.lege(namen)
        (self.root/namen[0]).write_bytes(b'andere bytes')
        with self.assertRaises(SystemExit):release.pruefe_releasepakete(self.version,self.root)
        self.lege(namen)
        with patch('release.lauf',return_value='b'*40):
            with self.assertRaises(SystemExit):release.pruefe_releasepakete(self.version,self.root)
