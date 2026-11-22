import hashlib
import io
import json
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import release
import server_wartung
import server_wartung_fern as fern

class Wartung(unittest.TestCase):
    def setUp(self):
        self.temp=Path(tempfile.mkdtemp(prefix='pv_wartung_'))
        self.addCleanup(release.entferne_baum,self.temp)

    def test_sicherung_prueft_inhalt_und_menge(self):
        quelle=self.temp/'quelle';quelle.mkdir();(quelle/'foto').write_bytes(b'foto')
        ziel=self.temp/'backup';fern.sichere(quelle,ziel)
        (ziel/'foto').write_bytes(b'fXto')
        with self.assertRaises(ValueError):fern.pruefe_kopie(quelle,ziel)
        (ziel/'foto').write_bytes(b'foto');(ziel/'zusaetzlich').touch()
        with self.assertRaises(ValueError):fern.pruefe_kopie(quelle,ziel)

    def test_externe_symlinks_sind_keine_vollstaendige_sicherung(self):
        if os.name=='nt':self.skipTest('Verknüpfungsrechte')
        quelle=self.temp/'quelle';quelle.mkdir();(self.temp/'extern').write_bytes(b'original')
        (quelle/'link').symlink_to(self.temp/'extern')
        with self.assertRaises(ValueError):fern.sichere(quelle,self.temp/'backup')
        self.assertEqual((self.temp/'extern').read_bytes(),b'original')

    def test_archiv_ausserhalb_wird_vor_entpacken_abgewiesen(self):
        for name in ['../../ausbruch','/absolut']:
            paket=self.temp/'paket.tar.gz'
            with tarfile.open(paket,'w:gz') as tar:
                info=tarfile.TarInfo(name);info.size=1;tar.addfile(info,io.BytesIO(b'x'))
            with self.assertRaises(ValueError):fern.entpacke(paket,self.temp/'ziel')
            self.assertFalse((self.temp/'ziel').exists())

    def test_ohne_inventarisierte_daten_keine_uebertragung(self):
        paket=self.temp/'paket';paket.write_bytes(b'paket')
        with patch('server_wartung.subprocess.run') as run:
            with self.assertRaises(SystemExit):server_wartung.aktualisieren({},paket,'1.2.3')
        run.assert_not_called()


    def test_misslungener_start_rollt_programm_und_migrierte_daten_zurueck(self):
        programm=self.temp/'app';programm.mkdir();(programm/'version').write_text('alt')
        daten=self.temp/'daten';daten.mkdir();(daten/'katalog').write_text('schema-alt')
        staging=self.temp/'staging';staging.mkdir();neu=staging/'neu';neu.mkdir();(neu/'version').write_text('neu')
        backup=self.temp/'sicherung';backup.mkdir();fern.sichere(programm,backup/'programm');fern.sichere(daten,backup/'daten')
        starts=[]
        def starte():
            v=(programm/'version').read_text();starts.append(v)
            if v=='neu':(daten/'katalog').write_text('schema-neu')
        with self.assertRaises(ValueError):
            fern.tausche_mit_rueckweg(programm,neu,daten,backup,'probe',starte=starte,stoppe=lambda:None,gesund=lambda:(programm/'version').read_text()=='alt')
        self.assertEqual(starts,['neu','alt'])
        self.assertEqual((daten/'katalog').read_text(),'schema-alt')
        self.assertEqual((backup/'daten/katalog').read_text(),'schema-alt')
        self.assertEqual((self.temp/'daten.fehlgeschlagen-probe/katalog').read_text(),'schema-neu')

    def _datenordner(self):
        daten=self.temp/'daten';(daten/'bibliotheken/konto/library/originals').mkdir(parents=True)
        (daten/'modelle').mkdir()
        (daten/'server.sqlite').write_text('server-alt');(daten/'server.schluessel').write_text('schluessel')
        (daten/'bibliotheken/konto/library.sqlite').write_text('bib-alt')
        (daten/'bibliotheken/konto/library.sqlite-wal').write_text('wal-alt')
        (daten/'bibliotheken/konto/library/ausschnitte.json').write_text('{}')
        (daten/'bibliotheken/konto/library/originals/foto.jpg').write_bytes(b'foto')
        (daten/'modelle/clip.onnx').write_bytes(b'modell')
        return daten

    def test_zustand_umfasst_datenbanken_und_kopfdateien_ohne_fotos(self):
        daten=self._datenordner()
        self.assertEqual({p.as_posix() for p in fern.zustandsdateien(daten)},{
            'server.sqlite','server.schluessel','bibliotheken/konto/library.sqlite',
            'bibliotheken/konto/library.sqlite-wal','bibliotheken/konto/library/ausschnitte.json'})
        n=fern.sichere_zustand(daten,self.temp/'zustand')
        self.assertEqual(n,5)
        self.assertFalse((self.temp/'zustand/bibliotheken/konto/library/originals').exists())
        (daten/'server.sqlite').write_text('anders')
        with self.assertRaises(ValueError):fern.pruefe_zustand(daten,self.temp/'zustand')

    def test_misslungener_start_mit_zustandssicherung_setzt_datenbanken_zurueck(self):
        programm=self.temp/'app';programm.mkdir();(programm/'version').write_text('alt')
        daten=self._datenordner()
        staging=self.temp/'staging';staging.mkdir();neu=staging/'neu';neu.mkdir();(neu/'version').write_text('neu')
        backup=self.temp/'sicherung';backup.mkdir();fern.sichere(programm,backup/'programm');fern.sichere_zustand(daten,backup/'zustand')
        bib=daten/'bibliotheken/konto'
        def starte():
            if (programm/'version').read_text()=='neu':
                (bib/'library.sqlite').write_text('bib-neu')
                (bib/'library.sqlite-shm').write_text('shm-neu')
                (daten/'server.sqlite').write_text('server-neu')
        with self.assertRaises(ValueError):
            fern.tausche_mit_rueckweg(programm,neu,daten,backup,'probe',starte=starte,stoppe=lambda:None,
                                      gesund=lambda:(programm/'version').read_text()=='alt',zustand=True)
        self.assertEqual((programm/'version').read_text(),'alt')
        self.assertEqual((bib/'library.sqlite').read_text(),'bib-alt')
        self.assertEqual((daten/'server.sqlite').read_text(),'server-alt')
        self.assertFalse((bib/'library.sqlite-shm').exists(),'die SHM der neuen Fassung ist weg')
        self.assertEqual((bib/'library/originals/foto.jpg').read_bytes(),b'foto')
        self.assertEqual((backup/'fehlgeschlagen/bibliotheken/konto/library.sqlite').read_text(),'bib-neu')

    def test_datenbankpruefung_veraendert_die_sicherung_nicht(self):
        # 3.68.0: Die Integritätsprüfung öffnete die gesicherte Datenbank an
        # Ort und Stelle; SQLite schrieb dabei in ihre -shm, und die Prüfung
        # vor dem Tausch fand eine abweichende Sicherung.
        import sqlite3
        daten=self.temp/'daten';(daten/'bibliotheken/konto').mkdir(parents=True)
        quelle=self.temp/'quelle.sqlite'
        con=sqlite3.connect(quelle);con.execute('PRAGMA journal_mode=WAL');con.execute('PRAGMA wal_autocheckpoint=0')
        con.execute('CREATE TABLE t(x)');con.executemany('INSERT INTO t VALUES (?)',[(i,) for i in range(500)]);con.commit()
        for endung in ['','-wal','-shm']:
            shutil.copy2(str(quelle)+endung,daten/('bibliotheken/konto/library.sqlite'+endung))
        con.close()
        backup=self.temp/'zustand';fern.sichere_zustand(daten,backup)
        fern.pruefe_datenbanken(backup,self.temp/'pruefung')
        self.assertEqual(fern.pruefe_zustand(daten,backup),3)
        self.assertFalse((self.temp/'pruefung').exists(),'die Arbeitskopie ist wieder weg')

    def test_defekte_sicherung_stoppt_vor_programmtausch(self):
        programm=self.temp/'app';programm.mkdir();(programm/'v').write_text('alt')
        daten=self.temp/'daten';daten.mkdir();backup=self.temp/'backup';backup.mkdir()
        fern.sichere(programm,backup/'programm');fern.sichere(daten,backup/'daten')
        (backup/'programm/v').write_text('anders')
        with self.assertRaises(ValueError):
            fern.tausche_mit_rueckweg(programm,self.temp/'neu',daten,backup,'probe',starte=lambda:self.fail('gestartet'),stoppe=lambda:None,gesund=lambda:True)
        self.assertEqual((programm/'v').read_text(),'alt')

    def test_linux_baut_ohne_originalrepo_zurueckzusetzen(self):
        script=release.linux_bau('pv-1.2.3-'+'a'*32,'b'*40)
        if os.name!='nt':  # Windows-Runner: „bash“ ist dort die WSL-Hülle ohne System
            subprocess.run(['bash','-n'],input=script,text=True,check=True)
        self.assertNotIn('reset',script);self.assertNotIn('git clean',script)
        self.assertIn('mktemp -d',script);self.assertIn('git clone',script)
        self.assertIn('checkout --quiet --detach '+'b'*40,script)
        self.assertNotIn('photo_vault',script)
        windows=release.WINDOWS_BAU.format(kennung='probe',flutter='test',commit='b'*40)
        self.assertNotIn('reset',windows);self.assertNotIn('git clean',windows)
        self.assertIn('PhotoVaultBuilds/probe',windows)

    def test_isolierter_baum_erhaelt_lokale_aenderungen_auch_bei_fehler(self):
        repo=self.temp/'original';repo.mkdir()
        def git(*args):return subprocess.check_output(['git',*args],cwd=repo,text=True).strip()
        git('init','-q');git('config','user.name','test');git('config','user.email','')
        (repo/'datei').write_text('commit');git('add','datei');git('commit','-qm','test')
        commit=git('rev-parse','HEAD');(repo/'datei').write_text('offene arbeit')
        with patch.object(release,'REPO',repo):
            with self.assertRaises(RuntimeError):
                with release.isolierter_baum(self.temp,commit) as kopie:
                    self.assertEqual((kopie/'datei').read_text(),'commit')
                    raise RuntimeError('Probeabbruch')
            self.assertEqual(release.REPO,repo)
        self.assertEqual((repo/'datei').read_text(),'offene arbeit')
        self.assertFalse(any(self.temp.glob('quelle-*')))

    def test_fehlendes_oder_veraendertes_paket_stoppt_vor_push(self):
        with patch('release.dateien',return_value=['a.zip']):
            (self.temp/'a.zip').write_bytes(b'ab')
            (self.temp/'SHA256SUMS.txt').write_text(hashlib.sha256(b'ab').hexdigest()+'  a.zip\n')
            (self.temp/'BUILD-STAND.json').write_text(json.dumps({'fassung':'1.2.3','commit':'a'*40,'pakete':{'a.zip':hashlib.sha256(b'ab').hexdigest()}}))
            with patch('release.lauf',return_value='a'*40):
                release.pruefe_releasepakete('1.2.3',self.temp)
            (self.temp/'a.zip').write_bytes(b'ac')
            with self.assertRaises(SystemExit):release.pruefe_releasepakete('1.2.3',self.temp)
