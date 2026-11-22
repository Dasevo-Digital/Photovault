"""Eigenständiger Wartungsschritt: sichern, verifizieren, tauschen, prüfen.

Daten und Rückfallkopien verlassen den Server nicht. Rückfallkopien werden
nie automatisch gelöscht. Das Modul bleibt ohne expliziten main-Aufruf passiv.
"""
import hashlib
import json
import os
import re
import shutil
import sqlite3
import subprocess
import sys
import tarfile
import time
from pathlib import Path


def sha256(pfad):
    with pfad.open('rb') as datei:
        digest=hashlib.sha256()
        for block in iter(lambda:datei.read(1024*1024),b''):
            digest.update(block)
        return digest.hexdigest()


def pruefe_kopie(quelle, kopie):
    """Verifiziert Dateimenge, Typen, Inhalte und relative Verknüpfungen."""
    def inventar(root):
        if root.is_symlink():
            raise ValueError('Sicherungswurzel darf keine Verknüpfung sein')
        def rechte(p):
            st=p.lstat()
            return (st.st_mode,st.st_uid,st.st_gid)
        if root.is_file():
            return {'.': ('datei',sha256(root),rechte(root))}
        gefunden={'.':('ordner','',rechte(root))}
        for p in root.rglob('*'):
            rel=p.relative_to(root).as_posix()
            if p.is_symlink():
                if not p.resolve().is_relative_to(root.resolve()):
                    raise ValueError('Externe Verknüpfung im Sicherungsumfang')
                typ,wert='link',os.readlink(p)
            elif p.is_file():
                typ,wert='datei',sha256(p)
            elif p.is_dir():
                typ,wert='ordner',''
            else:
                raise ValueError('Nicht regulärer Eintrag im Sicherungsumfang')
            gefunden[rel]=(typ,wert,rechte(p))
        return gefunden
    a, b = inventar(quelle), inventar(kopie)
    if a != b:
        raise ValueError('Sicherung hat abweichende Inhalte')
    return len(a)


def sichere(quelle, ziel):
    if quelle.is_symlink():
        raise ValueError('Sicherungswurzel darf keine Verknüpfung sein')
    if quelle.is_dir():
        shutil.copytree(quelle, ziel, symlinks=True)
    else:
        shutil.copy2(quelle, ziel)
    if getattr(os,'geteuid',lambda:1)() == 0:
        for original, kopie in [(quelle,ziel), *[(p,ziel/p.relative_to(quelle)) for p in quelle.rglob('*')]] if quelle.is_dir() else [(quelle,ziel)]:
            st=original.lstat()
            os.chown(kopie,st.st_uid,st.st_gid,follow_symlinks=False)
    return pruefe_kopie(quelle, ziel)


def entpacke(paket, ziel):
    with tarfile.open(paket) as tar:
        for item in tar.getmembers():
            pfad = Path(item.name)
            if pfad.is_absolute() or '..' in pfad.parts or not (item.isfile() or item.isdir() or item.issym()):
                raise ValueError('Unsicherer Archiveintrag')
            if item.issym():
                link = pfad.parent / item.linkname
                if Path(item.linkname).is_absolute() or '..' in link.parts:
                    raise ValueError('Unsichere Archivverknüpfung')
        # Vor jedem Eintrag noch einmal auf bereits entpackte Links prüfen.
        ziel.mkdir(mode=0o700,parents=True,exist_ok=True)
        for item in tar.getmembers():
            target=ziel/item.name
            if not target.resolve().is_relative_to(ziel.resolve()):
                raise ValueError('Archivziel verlässt den Zielordner')
            tar.extract(item,ziel)
    ordner = [p for p in ziel.iterdir() if p.is_dir()]
    if len(ordner) != 1 or not (ordner[0] / 'bin/photo_vault_server').is_file():
        raise ValueError('Kein eindeutiges Serverbündel')
    return ordner[0]


SQLITE_ENDUNGEN = ('.sqlite', '.sqlite-wal', '.sqlite-shm')


def zustandsdateien(daten):
    """Was ein Update im Datenordner ändert – ohne die Fotos.

    Dateien direkt im Datenordner (server.sqlite, server.schluessel …),
    direkt in jedem Bibliotheksordner und in dessen library/-Ordner, dazu
    jede SQLite-Datei samt WAL und SHM, wo sie auch liegt. Originale,
    Miniaturen, Fassungen, Modelle und Kacheln liegen in Unterordnern und
    bleiben aussen vor: Das Update schreibt sie nicht, und eine Vollkopie
    passt auf einer kleinen Systemplatte nicht (am Server 100 GB Fotos bei
    8 GB frei, 3.68.0).
    """
    gefunden = set()

    def nimm(p):
        if p.is_symlink():
            raise ValueError('Verknüpfung im Zustandsumfang')
        if p.is_file():
            gefunden.add(p.relative_to(daten))

    def dateien_in(ordner):
        if ordner.is_dir() and not ordner.is_symlink():
            for p in ordner.iterdir():
                nimm(p)

    dateien_in(daten)
    bibliotheken = daten / 'bibliotheken'
    if bibliotheken.is_dir() and not bibliotheken.is_symlink():
        for b in bibliotheken.iterdir():
            if b.is_dir() and not b.is_symlink():
                dateien_in(b)
                dateien_in(b / 'library')
    for wurzel, ordner, namen in os.walk(daten):
        for name in namen:
            if name.endswith(SQLITE_ENDUNGEN):
                nimm(Path(wurzel) / name)
    return gefunden


def _kopiere_mit_besitz(quelle, ziel):
    ziel.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    shutil.copy2(quelle, ziel)
    if getattr(os, 'geteuid', lambda: 1)() == 0:
        st = quelle.lstat()
        os.chown(ziel, st.st_uid, st.st_gid, follow_symlinks=False)


def pruefe_zustand(daten, sicherung):
    """Die Zustandssicherung enthält genau die Zustandsdateien, inhaltsgleich."""
    jetzt = zustandsdateien(daten)
    gesichert = {p.relative_to(sicherung) for p in sicherung.rglob('*') if p.is_file()}
    if jetzt != gesichert or any(sha256(daten / r) != sha256(sicherung / r) for r in jetzt):
        raise ValueError('Zustandssicherung hat abweichende Inhalte')
    return len(jetzt)


def sichere_zustand(daten, ziel):
    ziel.mkdir(mode=0o700)
    for rel in sorted(zustandsdateien(daten)):
        _kopiere_mit_besitz(daten / rel, ziel / rel)
    return pruefe_zustand(daten, ziel)


def stelle_zustand_her(daten, sicherung, fehlgeschlagen):
    """Setzt die Zustandsdateien auf die Sicherung zurück.

    Was die neue Fassung angelegt oder geändert hat, wandert nach
    [fehlgeschlagen] – auch eine WAL-Datei, die es vorher nicht gab: Bliebe
    sie liegen, spielte die alte Datenbank beim Öffnen fremde Seiten ein.
    """
    gesichert = {p.relative_to(sicherung) for p in sicherung.rglob('*') if p.is_file()}
    for rel in sorted(zustandsdateien(daten)):
        aufheben = fehlgeschlagen / rel
        aufheben.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        shutil.move(str(daten / rel), str(aufheben))
    for rel in sorted(gesichert):
        _kopiere_mit_besitz(sicherung / rel, daten / rel)
    return pruefe_zustand(daten, sicherung)


def pruefe_datenbanken(sicherung, arbeit):
    """Prüft jede gesicherte SQLite-Datenbank an einer Arbeitskopie.

    Nicht an Ort und Stelle: Auch lesend schreibt SQLite bei einer
    WAL-Datenbank in die -shm-Datei, und die Sicherung wiche danach vom
    Original ab (3.68.0).
    """
    try:
        for db in sicherung.rglob('*.sqlite'):
            arbeit.mkdir(mode=0o700, parents=True, exist_ok=True)
            kopie = arbeit / 'pruefung.sqlite'
            for endung in ['', '-wal']:
                quelle = Path(str(db) + endung)
                if quelle.exists():
                    shutil.copy2(quelle, Path(str(kopie) + endung))
            con = sqlite3.connect(kopie)
            try:
                if con.execute('PRAGMA integrity_check').fetchone() != ('ok',):
                    raise ValueError('Datenbankprüfung der Sicherung fehlgeschlagen')
            finally:
                con.close()
            for endung in ['', '-wal', '-shm']:
                Path(str(kopie) + endung).unlink(missing_ok=True)
    finally:
        if arbeit.exists():
            shutil.rmtree(arbeit)


class RueckwegFehler(RuntimeError):
    pass


def tausche_mit_rueckweg(programm, neu, daten, sicherung, kennung, *, starte, stoppe, gesund, zustand=False):
    # Ein bloßer Dateiname/Marker genügt vor dem Tausch nicht.
    if zustand:
        pruefe_zustand(daten, sicherung / 'zustand')
    else:
        pruefe_kopie(daten,sicherung/'daten')
    pruefe_kopie(programm,sicherung/'programm')
    alt=programm.with_name(programm.name+'.alt-'+kennung)
    if alt.exists():
        raise ValueError('Vorversionsordner ist schon belegt')
    programm.rename(alt)
    try:
        neu.rename(programm)
    except BaseException:
        alt.rename(programm)
        raise
    try:
        starte()
        if not gesund():
            raise ValueError('Neue Fassung antwortet nicht')
    except BaseException:
        try:
            stoppe()
            if zustand:
                stelle_zustand_her(daten, sicherung / 'zustand', sicherung / 'fehlgeschlagen')
            else:
                restore=daten.with_name(daten.name+'.wiederherstellung-'+kennung)
                sichere(sicherung/'daten',restore)
                daten.rename(daten.with_name(daten.name+'.fehlgeschlagen-'+kennung))
                restore.rename(daten)
            programm.rename(neu.parent/('fehlgeschlagen-'+kennung))
            alt.rename(programm)
            starte()
            if not gesund():
                raise ValueError('Vorversion antwortet nicht')
        except BaseException as e:
            raise RueckwegFehler('Rückweg nicht vollständig; Sicherung und alle Stände erhalten') from e
        raise
    return alt


def main(args):
    if not re.fullmatch('[a-f0-9]{32}', args['kennung']):
        raise ValueError('Ungültige Wartungskennung')
    dienst = 'photo-vault-server'
    def run(*cmd):
        return subprocess.run(cmd, check=True, text=True, capture_output=True).stdout.strip()
    daten = Path(args['daten']).resolve()
    programm = Path('/opt/photo-vault-server')
    paket = Path(args['paket'])
    if daten == Path('/') or daten == programm or daten.is_relative_to(programm) or programm.is_relative_to(daten):
        raise ValueError('Daten- und Programmordner müssen getrennt sein')
    if not daten.is_dir() or sha256(paket) != args['sha256']:
        raise ValueError('Datenordner oder Paketprüfung fehlgeschlagen')
    pid = int(run('systemctl', 'show', dienst, '--property=MainPID', '--value'))
    umgebung = dict(v.split(b'=', 1) for v in Path(f'/proc/{pid}/environ').read_bytes().split(b'\0') if b'=' in v)
    aktuell = umgebung.get(b'PV_DATEN')
    if not aktuell or Path(os.fsdecode(aktuell)).resolve() != daten:
        raise ValueError('Datenordner stimmt nicht mit laufendem Dienst überein')
    # Alle effektiven Einheiten und EnvironmentFiles gehören zur Sicherung.
    konfiguration = set()
    for feld in ['FragmentPath', 'DropInPaths']:
        for name in run('systemctl', 'show', dienst, '--property=' + feld, '--value').split():
            konfiguration.add(Path(name))
    env = run('systemctl', 'show', dienst, '--property=EnvironmentFiles', '--value')
    for name in re.findall(r'([^\s]+)\s+\(ignore_errors=(?:yes|no)\)', env):
        p = Path(name)
        if p.exists():
            konfiguration.add(p)
    if not konfiguration or any(not p.is_absolute() or not p.is_file() for p in konfiguration):
        raise ValueError('Dienstkonfiguration nicht vollständig lesbar')
    def groesse(dateien):
        return sum(p.stat().st_size for p in dateien if p.is_file() and not p.is_symlink())
    alle_daten = [Path(w) / n for w, _, ns in os.walk(daten) for n in ns]
    programmgroesse = groesse(programm.rglob('*'))
    zusatz = paket.stat().st_size * 6 + 1024**3
    basis = Path('/var/backups') / ('photovault-' + args['kennung'])
    orte = [basis.parent, daten.parent, programm.parent]
    def passt(umfang):
        return all(shutil.disk_usage(p).free >= umfang * 2 + zusatz for p in orte)
    # Die Vollsicherung, wo sie passt; sonst nur, was das Update ändert
    # (siehe zustandsdateien). Die Fotos schreibt das Update nicht.
    if passt(groesse(alle_daten) + programmgroesse):
        zustand = False
    elif passt(groesse(daten / r for r in zustandsdateien(daten)) + programmgroesse):
        zustand = True
    else:
        raise ValueError('Zu wenig Platz für Sicherung und Rückweg')
    basis.mkdir(mode=0o700)
    staging = Path('/opt') / ('photovault-neu-' + args['kennung'])
    staging.mkdir(mode=0o700)
    neu = entpacke(paket, staging)
    einheit = Path(run('systemctl', 'show', dienst, '--property=FragmentPath', '--value'))
    if (neu / 'systemd/photo-vault-server.service').read_bytes() != einheit.read_bytes():
        raise ValueError('Diensteinheit abweichend; vor dem Update gesondert abstimmen')
    gestoppt = False
    erfolg = False
    def gesund():
        for _ in range(30):
            if subprocess.run(['systemctl', 'is-active', '--quiet', dienst]).returncode == 0:
                env = os.environ.copy()
                env.update({os.fsdecode(k): os.fsdecode(v) for k, v in umgebung.items()})
                if subprocess.run([str(programm / 'bin/photo_vault_server'), '--lebenszeichen'], env=env,
                                  stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0:
                    return True
            time.sleep(1)
        return False
    try:
        gestoppt = True
        run('systemctl', 'stop', dienst)
        if int(run('systemctl', 'show', dienst, '--property=MainPID', '--value')) != 0:
            raise ValueError('Dienst ist noch nicht angehalten')
        datensicherung = basis / ('zustand' if zustand else 'daten')
        n = sichere_zustand(daten, datensicherung) if zustand else sichere(daten, datensicherung)
        sichere(programm, basis / 'programm')
        config = basis / 'konfiguration'
        config.mkdir(mode=0o700)
        for i, p in enumerate(sorted(konfiguration)):
            sichere(p, config / str(i))
        pruefe_datenbanken(datensicherung, basis / 'pruefung')
        (basis / 'geprueft.json').write_text(json.dumps({'version': args['fassung'], 'eintraege': n,
                                                       'umfang': 'zustand' if zustand else 'voll',
                                                       'konfiguration': [str(p) for p in sorted(konfiguration)]}))
        tausche_mit_rueckweg(programm,neu,daten,basis,args['kennung'],
                            starte=lambda:run('systemctl','start',dienst),
                            stoppe=lambda:run('systemctl','stop',dienst),gesund=gesund,zustand=zustand)
        erfolg=True
        print('Server aktualisiert; ' + ('Sicherung von Datenbanken und Zustand (ohne Fotos)' if zustand
                                         else 'vollständige Sicherung') + ' und Vorversion bleiben erhalten.')
    except RueckwegFehler:
        raise
    except BaseException:
        if gestoppt:
            run('systemctl', 'start', dienst)
            if not gesund():
                raise RuntimeError('Rückweg antwortet nicht; Sicherung und alle Stände erhalten')
        raise
    finally:
        # Prüf-/Rückfallstände bleiben absichtlich für die Abnahme vorhanden.
        if erfolg and programm.exists() and paket.exists():
            paket.unlink()


if __name__ == '__main__':
    main(json.loads(sys.argv[1]))
