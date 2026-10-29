#!/usr/bin/env python3
"""Desktop-Installation mit Vorprüfung, Staging und verifiziertem Rückfall."""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import uuid
import zipfile
from pathlib import Path


class Installationsfehler(RuntimeError):
    pass


def befehl(args):
    return subprocess.run(args, capture_output=True, text=True, errors='replace',
                          env={**os.environ, 'LC_ALL': 'C'})


def sha256(datei):
    h = hashlib.sha256()
    with Path(datei).open('rb') as f:
        for teil in iter(lambda: f.read(1024 * 1024), b''):
            h.update(teil)
    return h.hexdigest()


def pruefe_paket(datei):
    datei = Path(datei)
    if not datei.is_file():
        raise Installationsfehler('Das Installationspaket fehlt.')
    manifest = datei.parent / 'SHA256SUMS.txt'
    if not manifest.is_file():
        raise Installationsfehler('Die Prüfsummenliste fehlt.')
    eintraege = [teile for zeile in manifest.read_text().splitlines() if len(teile := zeile.split(maxsplit=1)) == 2]
    hashes = [h for h, name in eintraege if name.lstrip('*') == datei.name]
    if len(hashes) != 1 or not re.fullmatch('[a-f0-9]{64}', hashes[0]) or sha256(datei) != hashes[0]:
        raise Installationsfehler('Die Paketprüfsumme stimmt nicht.')
    return hashes[0]


class Installationsablauf:
    """Alle Plattformen verwenden dieselbe Reihenfolge und Fehlerbehandlung."""
    def ausfuehren(self):
        self.vorpruefen()
        try:
            self.vorbereiten()
        except BaseException:
            self.aufraeumen()
            raise
        try:
            self.tauschen()
            self.nachpruefen()
        except BaseException as ursache:
            try:
                self.zuruecksetzen()
            except BaseException as rueckfall:
                raise Installationsfehler('Installation und Rückfall fehlgeschlagen; Sicherung beibehalten.') from rueckfall
            self.aufraeumen()
            raise ursache
        self.zustand['installiert'] = True
        try:
            self.abschliessen()
        except Exception:
            self.zustand['warnung'] = 'Installiert und geprueft; temporaere Ablage konnte nicht vollstaendig entfernt werden.'
        return self.zustand


class Dateischritte(Installationsablauf):
    def __init__(self, version, *, runner=befehl, zustand=None):
        if not re.fullmatch(r'\d+\.\d+\.\d+(?:[-+][A-Za-z0-9.-]+)?', version):
            raise Installationsfehler('Ungültige Version.')
        self.runner = runner
        self.zustand = dict(zustand or {})
        self.zustand.setdefault('version', version)
        self.zustand.setdefault('kennung', uuid.uuid4().hex)

    def _lauf(self, args):
        r = self.runner([str(a) for a in args])
        if r.returncode != 0:
            raise Installationsfehler('Installationsschritt fehlgeschlagen: ' + str(args[0]))
        return r.stdout.strip()


class MacInstallation(Dateischritte):
    def __init__(self, version, quelle, ziel, ablage, **kwargs):
        super().__init__(version, **kwargs)
        self.quelle, self.ziel, self.ablage = map(Path, (quelle, ziel, ablage))
        ident = self.zustand['kennung']
        self.stage = self.ziel.parent / ('.' + self.ziel.stem + '-' + ident + '-stage' + self.ziel.suffix)
        self.alt = self.ziel.parent / ('.' + self.ziel.stem + '-' + ident + '-alt' + self.ziel.suffix)
        self.fehlerziel = self.ziel.parent / ('.' + self.ziel.stem + '-' + ident + '-fehler' + self.ziel.suffix)

    @staticmethod
    def _info(app):
        with (app / 'Contents/Info.plist').open('rb') as f:
            return plistlib.load(f)

    def _geschlossen(self):
        exe = self.ziel / 'Contents/MacOS' / self._info(self.ziel)['CFBundleExecutable']
        r = self.runner(['pgrep', '-f', '^' + re.escape(str(exe)) + r'(\s|$)'])
        if r.returncode != 1:
            raise Installationsfehler('Die installierte App muss zuerst geordnet beendet werden.')

    def _signatur(self, app):
        self._lauf(['codesign', '--verify', '--deep', '--strict', app])

    def vorpruefen(self):
        neu, alt = self._info(self.quelle), self._info(self.ziel)
        if neu['CFBundleShortVersionString'] != self.zustand['version'] or neu['CFBundleIdentifier'] != 'de.dasevo.photovault':
            raise Installationsfehler('Das App-Bündel gehört nicht zur gewünschten Version.')
        paket = self.quelle.parent / ('PhotoVault-' + self.zustand['version'] + '-macos.zip')
        self.zustand['paketHash'] = pruefe_paket(paket)
        with zipfile.ZipFile(paket) as z:
            info = plistlib.loads(z.read(self.quelle.name + '/Contents/Info.plist'))
            exe = self.quelle.name + '/Contents/MacOS/' + info['CFBundleExecutable']
            if info['CFBundleShortVersionString'] != self.zustand['version'] or hashlib.sha256(z.read(exe)).hexdigest() != sha256(self.quelle / 'Contents/MacOS' / neu['CFBundleExecutable']):
                raise Installationsfehler('Die entpackte App stimmt nicht mit dem Releasepaket ueberein.')
        self._geschlossen()
        self._signatur(self.quelle)
        if any(self.ziel.rglob('library.sqlite')):
            raise Installationsfehler('Bibliotheksdaten im Programmordner: Austausch abgebrochen.')
        self.zustand['altVersion'] = alt['CFBundleShortVersionString']
        self.zustand['altHash'] = sha256(self.ziel / 'Contents/MacOS' / alt['CFBundleExecutable'])
        for p in (self.stage, self.alt, self.fehlerziel):
            if p.exists():
                raise Installationsfehler('Ein Austauschpfad ist bereits belegt.')

    def vorbereiten(self):
        self.ablage.mkdir(parents=True, exist_ok=True)
        archiv = self.ablage / ('PhotoVault-' + self.zustand['altVersion'] + '-vor-' + self.zustand['version'] + '-' + self.zustand['kennung'] + '.zip')
        self._lauf(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', self.ziel, archiv])
        with zipfile.ZipFile(archiv) as z:
            if z.testzip() is not None:
                raise Installationsfehler('Die Sicherung der Vorversion ist beschädigt.')
            info = plistlib.loads(z.read(self.ziel.name + '/Contents/Info.plist'))
            if info['CFBundleShortVersionString'] != self.zustand['altVersion']:
                raise Installationsfehler('Die Sicherung enthält nicht die Vorversion.')
        self.zustand['sicherung'] = str(archiv)
        self._lauf(['ditto', self.quelle, self.stage])
        self._signatur(self.stage)
        if self._info(self.stage)['CFBundleShortVersionString'] != self.zustand['version']:
            raise Installationsfehler('Unvollständiges Staging-Bündel.')

    def tauschen(self):
        self._geschlossen()
        self.ziel.rename(self.alt)
        self.stage.rename(self.ziel)

    def nachpruefen(self):
        self._signatur(self.ziel)
        info = self._info(self.ziel)
        source = self._info(self.quelle)
        if info['CFBundleShortVersionString'] != self.zustand['version'] or sha256(self.ziel / 'Contents/MacOS' / info['CFBundleExecutable']) != sha256(self.quelle / 'Contents/MacOS' / source['CFBundleExecutable']):
            raise Installationsfehler('Die installierte App stimmt nicht mit dem Paket überein.')

    def zuruecksetzen(self):
        if not self.alt.exists():
            return
        if self.ziel.exists():
            self.ziel.rename(self.fehlerziel)
        self.alt.rename(self.ziel)
        info = self._info(self.ziel)
        if sha256(self.ziel / 'Contents/MacOS' / info['CFBundleExecutable']) != self.zustand['altHash']:
            raise Installationsfehler('Der Rückfall konnte nicht verifiziert werden.')

    def aufraeumen(self):
        for p in (self.stage, self.fehlerziel):
            if p.exists():
                shutil.rmtree(p)

    def abschliessen(self):
        if self.alt.exists():
            shutil.rmtree(self.alt)
        self.aufraeumen()


class LinuxInstallation(Dateischritte):
    app = 'de.dasevo.photovault'

    def __init__(self, version, *, desktop=None, **kwargs):
        super().__init__(version, **kwargs)
        self.desktop = Path(desktop or self.zustand.get('desktop') or Path.home() / 'Desktop')
        self.zustand['desktop'] = str(self.desktop)

    def _stand(self):
        text = self._lauf(['flatpak', 'info', '--user', self.app])
        version = re.search(r'^\s*Version:\s*(\S+)', text, re.MULTILINE)
        commit = self._lauf(['flatpak', 'info', '--user', '--show-commit', self.app])
        if version is None or not re.fullmatch('[a-f0-9]{64}', commit):
            raise Installationsfehler('Der installierte Flatpak-Stand ist nicht lesbar.')
        return version[1], commit

    def _geschlossen(self):
        text = self._lauf(['flatpak', 'ps', '--columns=application'])
        if self.app in text.split():
            raise Installationsfehler('Die installierte App muss zuerst geordnet beendet werden.')

    def vorpruefen(self):
        self._geschlossen()
        version, commit = self._stand()
        name = 'PhotoVault-' + self.zustand['version'] + '-x86_64.flatpak'
        quelle = self.desktop / ('PhotoVault-Release-v' + self.zustand['version'] + '-Upload') / name
        if not quelle.exists():
            quelle = self.desktop / name
        self.zustand['paketHash'] = pruefe_paket(quelle)
        self.zustand['quelle'] = str(quelle)
        self.zustand['altVersion'], self.zustand['altCommit'] = version, commit
        altname = 'PhotoVault-' + version + '-x86_64.flatpak'
        kandidaten = [self.desktop / ('PhotoVault-Release-v' + version + '-Upload') / altname, self.desktop / altname]
        alt = next((p for p in kandidaten if p.is_file()), None)
        if alt is None:
            raise Installationsfehler('Das Rückfallpaket der installierten Version fehlt.')
        self.zustand['alteQuelle'] = str(alt)
        self.zustand['alterPaketHash'] = sha256(alt)
        self.zustand['stage'] = str(self.desktop / ('.PhotoVault-' + self.zustand['kennung']))
        if Path(self.zustand['stage']).exists():
            raise Installationsfehler('Der Staging-Ordner ist bereits belegt.')

    def vorbereiten(self):
        stage = Path(self.zustand['stage'])
        stage.mkdir()
        shutil.copyfile(self.zustand['quelle'], stage / 'neu.flatpak')
        shutil.copyfile(self.zustand['alteQuelle'], stage / 'alt.flatpak')
        if sha256(stage / 'neu.flatpak') != self.zustand['paketHash'] or sha256(stage / 'alt.flatpak') != self.zustand['alterPaketHash']:
            raise Installationsfehler('Das vorbereitete Paket stimmt nicht.')

    def _installiere(self, datei):
        self._lauf(['flatpak', 'install', '--user', '--reinstall', '--noninteractive', '-y', '--bundle', datei])

    def tauschen(self):
        self._geschlossen()
        self._installiere(Path(self.zustand['stage']) / 'neu.flatpak')

    def nachpruefen(self):
        version, commit = self._stand()
        if version != self.zustand['version'] or (version != self.zustand['altVersion'] and commit == self.zustand['altCommit']):
            raise Installationsfehler('Die installierte Flatpak-Version stimmt nicht.')
        self.zustand['installierterCommit'] = commit

    def zuruecksetzen(self):
        try:
            if self._stand() == (self.zustand['altVersion'], self.zustand['altCommit']):
                return
        except Installationsfehler:
            # Auch eine nach dem Austausch nicht mehr lesbare Installation
            # benötigt den Rückfall aus dem vorher vorbereiteten Paket.
            pass
        self._installiere(Path(self.zustand['stage']) / 'alt.flatpak')
        if self._stand() != (self.zustand['altVersion'], self.zustand['altCommit']):
            raise Installationsfehler('Der Flatpak-Rückfall stimmt nicht mit der Vorversion überein.')

    def aufraeumen(self):
        if 'stage' in self.zustand:
            p = Path(self.zustand['stage'])
            if p.exists():
                shutil.rmtree(p)

    def abschliessen(self):
        self.aufraeumen()


class FernInstallation(Installationsablauf):
    """Der Aufrufer steuert dieselben Phasen auch auf einem anderen Rechner.

    Windows verwendet ein eigenes PowerShell-Modul für Dateisystem und
    Versionsressourcen; die Transaktionssteuerung bleibt hier testbar.
    """
    def __init__(self, plattform, host, version, *, runner=befehl):
        self.plattform, self.host, self.runner = plattform, host, runner
        self.zustand = {'version': version, 'kennung': uuid.uuid4().hex}
        self.skript = 'pv_installation_' + self.zustand['kennung'] + ('.ps1' if plattform == 'windows' else '.py')

    def _phase(self, phase):
        plan = base64.b64encode(json.dumps(self.zustand).encode()).decode()
        if self.plattform == 'windows':
            code = '& (Join-Path $env:USERPROFILE \'' + self.skript + "') -Phase '" + phase + "' -PlanBase64 '" + plan + "'"
            command = 'powershell -NoProfile -ExecutionPolicy Bypass -EncodedCommand ' + base64.b64encode(code.encode('utf-16le')).decode()
        else:
            command = 'python3 ' + self.skript + ' --phase ' + phase + ' --plan ' + plan
        r = self.runner(['ssh', '-o', 'BatchMode=yes', self.host, command])
        if r.returncode != 0:
            raise Installationsfehler(self.plattform + ': ' + phase + ' fehlgeschlagen.')
        zeilen = [s[len('PV_RESULT '):] for s in r.stdout.splitlines() if s.startswith('PV_RESULT ')]
        if not zeilen:
            raise Installationsfehler('Der Installationsnachweis fehlt.')
        self.zustand.update(json.loads(zeilen[-1]))

    def vorpruefen(self):
        quelle = Path(__file__).parent / 'installieren/windows.ps1' if self.plattform == 'windows' else Path(__file__)
        r = self.runner(['scp', '-q', str(quelle), self.host + ':' + self.skript])
        if r.returncode != 0:
            raise Installationsfehler('Das Installationsmodul konnte nicht übertragen werden.')
        try:
            self._phase('vorpruefen')
        except BaseException:
            self._entferne_modul()
            raise

    def _entferne_modul(self):
        if self.plattform == 'windows':
            code = 'Remove-Item -LiteralPath (Join-Path $env:USERPROFILE \'' + self.skript + "') -ErrorAction SilentlyContinue"
            command = 'powershell -NoProfile -EncodedCommand ' + base64.b64encode(code.encode('utf-16le')).decode()
        else:
            command = 'rm -- ' + self.skript
        r = self.runner(['ssh', '-o', 'BatchMode=yes', self.host, command])
        if r.returncode != 0:
            raise Installationsfehler('Das temporaere Installationsmodul konnte nicht entfernt werden.')

    def vorbereiten(self): self._phase('vorbereiten')
    def tauschen(self): self._phase('tauschen')
    def nachpruefen(self): self._phase('nachpruefen')
    def zuruecksetzen(self): self._phase('zuruecksetzen')
    def aufraeumen(self):
        self._phase('aufraeumen')
        self._entferne_modul()

    def abschliessen(self):
        self._phase('abschliessen')
        self._entferne_modul()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--phase', required=True, choices=['vorpruefen', 'vorbereiten', 'tauschen', 'nachpruefen', 'zuruecksetzen', 'aufraeumen', 'abschliessen'])
    parser.add_argument('--plan', required=True)
    args = parser.parse_args()
    state = json.loads(base64.b64decode(args.plan))
    installation = LinuxInstallation(state['version'], zustand=state)
    try:
        getattr(installation, args.phase)()
        print('PV_RESULT ' + json.dumps(installation.zustand))
    except Exception as e:
        print('PV_ERROR ' + str(e), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
