#!/usr/bin/env python3
"""Eine Fassung ausliefern – die Schritte, die bisher je Release von Hand
liefen (Issue #188), in der Reihenfolge, in der sie laufen müssen:

    python3 tool/release.py vorbereiten 3.40.0 --metainfo text.xml
    python3 tool/release.py bauen 3.40.0               # oder --nur mac server
    python3 tool/release.py entwurf 3.40.0
    python3 tool/release.py einspielen 3.40.0 --linux --windows --mac
    python3 tool/release.py einspielen 3.40.0 --server      # fragt nach
    python3 tool/release.py veroeffentlichen 3.40.0

vorbereiten   pubspec und Flatpak-Metainfo auf die Fassung, Commit
              „Version x“, annotierte Marke, Datenschutzprüfung, erst main,
              dann die Marke pushen (eine Marke allein schiebt die Historie
              mit).
bauen         Linux (Flatpak) und Windows (Zip) auf den Testrechnern, macOS
              hier, die Server-Pakete mit Docker; alles in den Ordner
              <upload_basis>/PhotoVault-Release-v<x>-Upload, dazu
              SHA256SUMS.txt. Die .app-Bündel unter build/ werden danach
              entfernt, damit Spotlight sie nicht findet.
entwurf       Gitea-Freigabe als Entwurf mit RELEASE-TEXT-v<x>.md aus dem
              Ordner und allen Dateien. Ein vorhandener Entwurf wird
              ergänzt, nicht verdoppelt; ein schon veröffentlichtes
              Release ebenso (Text neu, fehlende Pakete nachgetragen,
              SHA256SUMS.txt ersetzt).
einspielen    Auf den Testrechnern installieren; am Mac wartet ein Wächter,
              bis die App beendet ist, und tauscht sie dann. Der Server nur
              mit --server und nach ausdrücklichem „ja“ – er ist produktiv.
veroeffentlichen  Entwurf freigeben und sync.py für GitHub laufen lassen.

Wohin es geht, steht nicht hier, sondern in
~/.config/photovault-release/ziele.json (nicht im Repo – es ist
öffentlich):

    {
      "gitea_api": "https://<gitea>/api/v1/repos/<besitzer>/<repo>",
      "upload_basis": "~/Desktop",
      "linux_ssh": "<ssh-name>", "linux_repo": "~/photo_vault",
      "windows_ssh": "<ssh-name>",
      "windows_flutter": "C:\\\\src\\\\flutter\\\\bin",
      "server_ssh": "root@<adresse>",
      "server_schluessel": "<pfad zum Schlüssel>",
      "server_known_hosts": "<pfad>",
      "sync_py": "~/Library/Application Support/gitea-github-sync/sync.py",
      "github_repo": "Photovault"
    }

Das Gitea-Token kommt aus dem Schlüsselbund (git credential-osxkeychain)
und wird nirgends gespeichert oder ausgegeben.
"""

import argparse
import hashlib
import json
import os
import re
import shlex
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
KONFIG = Path.home() / '.config' / 'photovault-release' / 'ziele.json'


# --- Hilfen -------------------------------------------------------------------

def ziele():
    if not KONFIG.exists():
        sys.exit(f'Es fehlt {KONFIG} – Aufbau siehe Kopf dieser Datei.')
    return json.loads(KONFIG.read_text())


def lauf(befehl, *, cwd=REPO, pruefen=True, ausgabe=False, eingabe=None):
    """Führt [befehl] aus; mit [ausgabe] kommt stdout zurück."""
    print('›', befehl if isinstance(befehl, str) else ' '.join(shlex.quote(str(b)) for b in befehl), flush=True)
    r = subprocess.run(befehl, cwd=cwd, shell=isinstance(befehl, str), text=True,
                       capture_output=ausgabe, input=eingabe)
    if pruefen and r.returncode != 0:
        if ausgabe:
            sys.stderr.write(r.stdout + r.stderr)
        sys.exit(f'Abgebrochen: Schritt scheiterte (Code {r.returncode}).')
    return r.stdout if ausgabe else r.returncode


def marken():
    return lauf(['git', 'tag', '-l', 'v*', '--sort=v:refname'], ausgabe=True).split()


def marke_dort(ssh, befehl):
    """Die neueste Marke, die das Repo auf einem Testrechner schon hat.

    Das Bündel muss bei ihr ansetzen und nicht bei der vorigen Fassung:
    Hat ein Rechner ein paar Fassungen ausgelassen (3.41 bis 3.44 nur auf
    Mac und Server), fehlten ihm sonst die Commits dazwischen, und das
    Holen brach ab. `None`, wenn er keine kennt – dann das ganze Bündel.
    """
    dort = set(lauf(['ssh', ssh, befehl], ausgabe=True, pruefen=False).split())
    gemeinsam = [m for m in marken() if m in dort]
    return gemeinsam[-1] if gemeinsam else None


def buendel(a, name, marke, basis):
    """Ein Bündel mit main und der Marke, ab [basis] (sonst alles)."""
    datei = a / f'pv-{name}.bundle'
    # Kennt der Rechner die Marke schon, wäre das Bündel womöglich leer.
    ausser = [f'^{basis}'] if basis and basis != marke else []
    lauf(['git', 'bundle', 'create', str(datei), 'main', marke, *ausser])
    return datei


def upload_ordner(z, fassung):
    # Nicht auf „.0“ enden lassen: Spotlight hielte den Ordner sonst für ein
    # Programm – daher das „-Upload“.
    o = Path(os.path.expanduser(z.get('upload_basis', '~/Desktop'))) / f'PhotoVault-Release-v{fassung}-Upload'
    o.mkdir(parents=True, exist_ok=True)
    return o


def arbeitsordner(fassung):
    o = Path(tempfile.gettempdir()) / f'pv-release-{fassung}'
    o.mkdir(parents=True, exist_ok=True)
    return o


def dateien(fassung):
    return [
        f'PhotoVault-{fassung}-macos.zip',
        f'PhotoVault-{fassung}-windows-x64.zip',
        f'PhotoVault-{fassung}-x86_64.flatpak',
        f'PhotoVault-Server-{fassung}-linux-amd64.tar.gz',
        f'PhotoVault-Server-{fassung}-linux-arm64.tar.gz',
    ]


def token(z):
    host = urllib.parse.urlparse(z['gitea_api']).hostname
    r = subprocess.run(['git', 'credential-osxkeychain', 'get'], input=f'protocol=https\nhost={host}\n\n',
                       text=True, capture_output=True)
    for zeile in r.stdout.splitlines():
        if zeile.startswith('password='):
            return zeile[len('password='):]
    sys.exit('Kein Gitea-Token im Schlüsselbund.')


def gitea(z, pfad, daten=None, methode=None, kopf=None, tok=None):
    req = urllib.request.Request(z['gitea_api'] + pfad, data=daten, method=methode,
                                 headers={'Authorization': 'token ' + tok, **(kopf or {})})
    try:
        with urllib.request.urlopen(req, timeout=600) as a:
            inhalt = a.read()
            return a.status, json.loads(inhalt) if inhalt else None
    except urllib.error.HTTPError as e:
        return e.code, e.read()[:300]


# --- vorbereiten ----------------------------------------------------------------

DATENSCHUTZTEXTE = ['docs/datenschutz.md', 'docs/privacy.md']
_MONATE = {
    'de': ['Januar', 'Februar', 'März', 'April', 'Mai', 'Juni', 'Juli', 'August', 'September',
           'Oktober', 'November', 'Dezember'],
    'en': ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September',
           'October', 'November', 'December'],
}


def stand_und_fassung(fassung):
    """Setzt die Kopfzeile der Datenschutztexte auf heute und [fassung].

    Sie nennen, für welche Fassung sie gelten, und
    test/datenschutz_betriebsarten_test.dart verlangt die aktuelle – ohne
    das scheiterte der Push von 3.48.0 an genau dieser Zeile."""
    h = time.localtime()
    for datei, sprache, vorne in [('docs/datenschutz.md', 'de', 'Stand: {t}. {m} {j}'),
                                  ('docs/privacy.md', 'en', 'As of {t} {m} {j}')]:
        d = REPO / datei
        zeile = vorne.format(t=h.tm_mday, m=_MONATE[sprache][h.tm_mon - 1], j=h.tm_year)
        neu, n = re.subn(r'^(Stand: |As of ).*· Photo Vault [0-9.]+$', f'{zeile} · Photo Vault {fassung}',
                         d.read_text(encoding='utf-8'), count=1, flags=re.M)
        if n != 1:
            sys.exit(f'{datei}: Zeile mit Stand und Fassung fehlt.')
        d.write_text(neu, encoding='utf-8')


def vorbereiten(args):
    fassung = args.fassung
    if f'v{fassung}' in marken():
        sys.exit(f'Die Marke v{fassung} gibt es schon.')
    if lauf(['git', 'status', '--porcelain', '--', 'pubspec.yaml', 'packaging', *DATENSCHUTZTEXTE],
            ausgabe=True).strip():
        sys.exit('pubspec.yaml, packaging/ oder die Datenschutztexte haben offene Änderungen.')
    metainfo = Path(args.metainfo).read_text().strip()
    p = REPO / 'pubspec.yaml'
    s = p.read_text()
    alt = next(z for z in s.splitlines() if z.startswith('version: '))
    p.write_text(s.replace(alt, f'version: {fassung}', 1))
    m = REPO / 'packaging/flatpak/de.dasevo.photovault.metainfo.xml'
    s = m.read_text()
    anker = '  <releases>\n'
    if anker not in s:
        sys.exit('Metainfo ohne <releases>.')
    eintrag = (f'    <release version="{fassung}" date="{time.strftime("%Y-%m-%d")}">\n'
               f'      <description>\n'
               + ''.join(f'        {z.strip()}\n' for z in metainfo.splitlines() if z.strip())
               + '      </description>\n    </release>\n')
    m.write_text(s.replace(anker, anker + eintrag, 1))
    lauf(['xmllint', '--noout', str(m)])
    stand_und_fassung(fassung)
    lauf(['git', 'add', 'pubspec.yaml', str(m.relative_to(REPO)), *DATENSCHUTZTEXTE])
    lauf(['git', 'commit', '-q', '-m', f'Version {fassung}'])
    lauf(['git', 'tag', '-a', f'v{fassung}', '-m', f'Photo Vault {fassung}'])
    lauf(['bash', 'tool/pruefe_repository_datenschutz.sh'])
    # Erst main: Eine Marke allein schiebt die Historie mit, und wird main
    # danach abgelehnt, steht eine Marke neben dem Zweig.
    lauf(['git', 'push', 'origin', 'main'])
    lauf(['git', 'push', 'origin', f'v{fassung}'])


# --- bauen ------------------------------------------------------------------------

WINDOWS_BAU = r'''$ErrorActionPreference = 'Stop'
$repo = Join-Path $env:USERPROFILE 'photo_vault'
Set-Location $repo
$env:Path = '{flutter};' + $env:Path
git fetch -q C:/Windows/Temp/pv.bundle refs/heads/main:refs/remotes/bundle/main refs/tags/{marke}:refs/tags/{marke}
if ($LASTEXITCODE -ne 0) {{ throw 'fetch' }}
git reset -q --hard {marke}
git config core.fileMode false
git config core.autocrlf false
git clean -fdq lib test tool assets docs packages apps
git log --oneline -1
$ErrorActionPreference = 'Continue'
powershell -NoProfile -ExecutionPolicy Bypass -File tool\windows_bauen.ps1 -Pruefen -Zip
"BAU-ENDE $LASTEXITCODE"
'''


def bauen(args):
    z = ziele()
    fassung = args.fassung
    nur = set(args.nur or ['linux', 'windows', 'mac', 'server'])
    marke = f'v{fassung}'
    # Mac und Server bauen aus diesem Verzeichnis, Linux und Windows holen
    # sich die Marke selbst.
    if not lauf(['git', 'tag', '-l', marke], ausgabe=True).strip():
        sys.exit(f'Die Marke {marke} gibt es nicht – erst vorbereiten.')
    # HEAD darf hinter der Marke weiter sein, solange seither nur tool/
    # dazukam – etwa eine Berichtigung an diesem Skript, wie bei 3.48.0.
    # Der Code der Apps und des Servers ist dann derselbe wie in der Marke.
    if {'mac', 'server'} & nur:
        anders = lauf(['git', 'diff', '--name-only', marke, 'HEAD', '--', '.', ':(exclude)tool'],
                      ausgabe=True).strip()
        if anders:
            sys.exit(f'HEAD weicht ausserhalb von tool/ von {marke} ab – erst vorbereiten:\n{anders}')
    a = arbeitsordner(fassung)
    u = upload_ordner(z, fassung)

    # Linux und Windows laufen im Hintergrund, während hier macOS baut.
    windows = None
    if 'linux' in nur:
        repo = z.get('linux_repo', '~/photo_vault')
        b = buendel(a, 'linux', marke, marke_dort(z['linux_ssh'], f"git -C {repo} tag -l 'v*'"))
        lauf(['scp', '-q', str(b), f'{z["linux_ssh"]}:/tmp/pv.bundle'])
        linux = (f'cd {z.get("linux_repo", "~/photo_vault")} && git fetch -q /tmp/pv.bundle '
                 f'refs/heads/main:refs/remotes/bundle/main refs/tags/{marke}:refs/tags/{marke} && '
                 f'git reset -q --hard {marke} && git clean -fdq lib test tool assets docs packages apps && '
                 f'export PATH=$HOME/flutter/bin:$HOME/snap/flutter/common/flutter/bin:$PATH && '
                 f'(nohup bash tool/flatpak_bauen.sh --pruefen --buendel > ~/pv_bau_{fassung}.log 2>&1 &)')
        lauf(['ssh', z['linux_ssh'], linux])

    if 'windows' in nur:
        ps1 = a / 'windows_bau.ps1'
        ps1.write_text(WINDOWS_BAU.format(flutter=z.get('windows_flutter', r'C:\src\flutter\bin'), marke=marke))
        basis = marke_dort(z['windows_ssh'], 'powershell -NoProfile -Command "git -C (Join-Path $env:USERPROFILE \'photo_vault\') tag -l \'v*\'"')
        b = buendel(a, 'windows', marke, basis)
        lauf(['scp', '-q', str(b), f'{z["windows_ssh"]}:C:/Windows/Temp/pv.bundle'])
        lauf(['scp', '-q', str(ps1), f'{z["windows_ssh"]}:pv_windows_bau.ps1'])
        windows_log = open(a / 'windows_bau.log', 'w')
        windows = subprocess.Popen(['ssh', z['windows_ssh'], 'powershell -NoProfile -ExecutionPolicy Bypass -File pv_windows_bau.ps1'],
                                   stdout=windows_log, stderr=subprocess.STDOUT)

    if 'mac' in nur:
        lauf(['flutter', 'build', 'macos', '--release'])
        app = REPO / 'build/macos/Build/Products/Release/Photo Vault.app'
        fassung_app = lauf(['/usr/libexec/PlistBuddy', '-c', 'Print CFBundleShortVersionString', str(app / 'Contents/Info.plist')], ausgabe=True).strip()
        if fassung_app != fassung:
            sys.exit(f'Die App meldet {fassung_app}, nicht {fassung}.')
        lauf(['rm', '-rf', str(u / 'Photo Vault.app')])
        lauf(['ditto', str(app), str(u / 'Photo Vault.app')])
        lauf(['rm', '-f', str(u / f'PhotoVault-{fassung}-macos.zip')])
        lauf(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', 'Photo Vault.app', f'PhotoVault-{fassung}-macos.zip'], cwd=u)
        # Die Bündel unter build/ fänden Spotlight und Launchpad – und
        # öffneten womöglich die echte Bibliothek. Vorher prüfen, dass
        # keins läuft.
        if 'photo_vault/build' in lauf('ps -Ao comm', ausgabe=True):
            print('Ein Build-Bündel läuft noch – nicht aufgeräumt.')
        else:
            lauf('rm -rf build/macos/Build/Products/*/Photo\\ Vault*.app')

    if 'server' in nur:
        commit = lauf(['git', 'rev-parse', '--short', f'{marke}^{{commit}}'], ausgabe=True).strip()
        for ziel, plattform in [('paket', 'linux/amd64,linux/arm64'), ('paket-openvino', 'linux/amd64')]:
            lauf(['docker', 'buildx', 'build', '-f', 'packages/server/Dockerfile', '--target', ziel,
                  '--platform', plattform, '--build-arg', f'PV_FASSUNG={fassung}', '--build-arg', f'PV_COMMIT={commit}',
                  '--output', f'type=local,dest={a / ziel}', '.'])
        for arch in ['amd64', 'arm64']:
            lauf(['cp', str(a / 'paket' / f'linux_{arch}' / f'photo-vault-server-linux-{arch}.tar.gz'),
                  str(u / f'PhotoVault-Server-{fassung}-linux-{arch}.tar.gz')])

    if windows is not None:
        if windows.wait() != 0 or 'BAU-ENDE 0' not in (a / 'windows_bau.log').read_text(errors='replace'):
            sys.exit(f'Windows-Bau gescheitert – siehe {a / "windows_bau.log"}.')
        lauf(['scp', '-q', f'{z["windows_ssh"]}:Desktop/PhotoVault-{fassung}-windows-x64.zip', str(u)])

    if 'linux' in nur:
        flatpak = f'Desktop/PhotoVault-{fassung}-x86_64.flatpak'
        for _ in range(180):
            # „[f]latpak“: Sonst findet pgrep die Kommandozeile dieser
            # Abfrage selbst und meldet immer „läuft“ – bei 3.47.0 wartete das
            # Skript so die vollen 60 Minuten auf ein längst fertiges Flatpak.
            r = subprocess.run(['ssh', '-o', 'BatchMode=yes', z['linux_ssh'], 'pgrep -f "[f]latpak_bauen.sh" >/dev/null && echo laeuft || echo fertig'],
                               text=True, capture_output=True)
            if 'fertig' in r.stdout:
                break
            time.sleep(20)
        log = lauf(['ssh', z['linux_ssh'], f'grep -E "✗|FEHLER" ~/pv_bau_{fassung}.log | head -5; test -f ~/{flatpak} && echo DA'], ausgabe=True, pruefen=False)
        if 'DA' not in log:
            sys.exit(f'Flatpak fehlt:\n{log}')
        lauf(['scp', '-q', f'{z["linux_ssh"]}:{flatpak}', str(u)])

    summen(u, fassung)


def summen(u, fassung):
    zeilen = []
    for name in dateien(fassung):
        if not (u / name).exists():
            continue
        h = hashlib.sha256()
        with open(u / name, 'rb') as f:
            for stueck in iter(lambda: f.read(1 << 20), b''):
                h.update(stueck)
        zeilen.append(f'{h.hexdigest()}  {name}')
    (u / 'SHA256SUMS.txt').write_text('\n'.join(zeilen) + '\n')
    print('\n'.join(z[:16] + z[64:] for z in zeilen))


# --- entwurf ----------------------------------------------------------------------

def entwurf(args):
    z = ziele()
    fassung = args.fassung
    u = upload_ordner(z, fassung)
    text = (u / f'RELEASE-TEXT-v{fassung}.md').read_text(encoding='utf-8')
    tok = token(z)
    # Ein veröffentlichtes Release findet /releases/tags/<marke> – so lassen
    # sich Pakete nachtragen, etwa Linux und Windows zu einer Fassung, die
    # zuerst nur für Mac und Server erschien (3.47.0). Entwürfe findet es
    # nicht – die stehen nur in der Liste.
    st, rel = gitea(z, f'/releases/tags/v{fassung}', tok=tok)
    if st != 200 or not isinstance(rel, dict):
        _, alle = gitea(z, '/releases?draft=true&limit=30', tok=tok)
        rel = next((r for r in (alle if isinstance(alle, list) else []) if r.get('tag_name') == f'v{fassung}'), None)
    if rel is None:
        st, rel = gitea(z, '/releases', json.dumps({'tag_name': f'v{fassung}', 'name': f'Photo Vault {fassung}', 'body': text,
                                                     'draft': True, 'prerelease': False}).encode(), 'POST',
                        {'Content-Type': 'application/json'}, tok)
        if st != 201:
            sys.exit(f'Entwurf nicht angelegt: {st} {rel}')
    else:
        gitea(z, f'/releases/{rel["id"]}', json.dumps({'body': text}).encode(), 'PATCH', {'Content-Type': 'application/json'}, tok)
    rid = rel['id']
    vorhanden = {x['name']: x['id'] for x in rel.get('assets', [])}
    # Nur, was gebaut wurde: 3.41 bis 3.44.1 gingen nur an Mac und Server.
    vorhanden_hier = [n for n in dateien(fassung) if (u / n).exists()]
    for name in vorhanden_hier + ['SHA256SUMS.txt']:
        if name in vorhanden:
            if name != 'SHA256SUMS.txt':
                continue
            gitea(z, f'/releases/{rid}/assets/{vorhanden[name]}', methode='DELETE', tok=tok)
        g = uuid.uuid4().hex
        daten = (f'--{g}\r\nContent-Disposition: form-data; name="attachment"; filename="{name}"\r\n'
                 f'Content-Type: application/octet-stream\r\n\r\n').encode() + (u / name).read_bytes() + f'\r\n--{g}--\r\n'.encode()
        st, a = gitea(z, f'/releases/{rid}/assets?name={urllib.parse.quote(name)}', daten, 'POST',
                      {'Content-Type': f'multipart/form-data; boundary={g}'}, tok)
        print(name, st, a.get('size') if isinstance(a, dict) else a)
    _, rel = gitea(z, f'/releases/{rid}', tok=tok)
    print('Freigabe', rel['id'], 'Entwurf' if rel.get('draft') else 'veröffentlicht', len(rel['assets']), 'Dateien')


# --- einspielen -------------------------------------------------------------------

WINDOWS_TAUSCH = r'''$log = Join-Path $env:USERPROFILE 'pv_update.log'
function L($t) {{ Add-Content -Path $log -Value ((Get-Date -Format 'HH:mm:ss') + ' ' + $t) }}
Set-Content -Path $log -Value 'Start'
try {{
  $desk = [Environment]::GetFolderPath('Desktop')
  $d = Join-Path $env:LOCALAPPDATA 'de.dasevo\photovault\PhotoVault'
  if (Get-Process photo_vault -ErrorAction SilentlyContinue) {{
    taskkill /IM photo_vault.exe | Out-Null
    for ($i = 0; $i -lt 30 -and (Get-Process photo_vault -ErrorAction SilentlyContinue); $i++) {{ Start-Sleep 1 }}
  }}
  if (Get-Process photo_vault -ErrorAction SilentlyContinue) {{ L 'FEHLER: App laeuft noch'; exit 1 }}
  $alt = (Get-Item "$desk\PhotoVault\photo_vault.exe").VersionInfo.ProductVersion
  $ablage = "$desk\PhotoVault-$alt-alt"
  if (Test-Path $ablage) {{ L "FEHLER: $ablage gibt es schon"; exit 1 }}
  Move-Item "$desk\PhotoVault" $ablage
  Expand-Archive -Path "$desk\PhotoVault-{fassung}-windows-x64.zip" -DestinationPath $desk
  if (-not (Test-Path "$desk\PhotoVault\photo_vault.exe")) {{ L 'FEHLER: keine photo_vault.exe'; exit 1 }}
  L ('ausgepackt: ' + (Get-Item "$desk\PhotoVault\photo_vault.exe").VersionInfo.ProductVersion)
  Start-Process "$desk\PhotoVault\photo_vault.exe" -WorkingDirectory "$desk\PhotoVault"
  Start-Sleep 25
  $p = Get-Process photo_vault -ErrorAction SilentlyContinue
  if (-not $p) {{ L 'FEHLER: neue App laeuft nicht'; exit 1 }}
  L ('laeuft: reagiert ' + $p.Responding)
  L ('ONNX Runtime geladen: ' + [bool]($p.Modules | Where-Object ModuleName -eq 'onnxruntime.dll'))
  $f = New-Object System.IO.FileStream((Join-Path $d 'library.sqlite'), 'Open', 'Read', 'ReadWrite')
  $h = New-Object byte[] 64; [void]$f.Read($h, 0, 64); $f.Close()
  L ('Schema: ' + ($h[60]*16777216 + $h[61]*65536 + $h[62]*256 + $h[63]))
  L 'FERTIG'
}} catch {{ L ('FEHLER: ' + $_) }}
'''

MAC_TAUSCH = '''#!/bin/bash
# Tauscht /Applications/Photo Vault.app gegen {fassung}, sobald die App nicht mehr läuft.
LOG="$(dirname "$0")/mac_tausch.log"; LOCK="$(dirname "$0")/mac_tausch.lock"
NEU={neu}
ALT="/Applications/Photo Vault.app"
ABLAGE="$HOME/Desktop/PhotoVault-Vorversionen.noindex"
exec >>"$LOG" 2>&1
if ! mkdir "$LOCK" 2>/dev/null; then echo "$(date '+%F %T') läuft schon"; exit 0; fi
trap 'rmdir "$LOCK"' EXIT
echo "$(date '+%F %T') warte, bis Photo Vault beendet ist"
while pgrep -f "/Applications/Photo Vault.app/Contents/MacOS/Photo Vault" >/dev/null; do sleep 10; done
alt_version=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$ALT/Contents/Info.plist" 2>/dev/null || echo unbekannt)
mkdir -p "$ABLAGE"
if [ -e "$ABLAGE/Photo Vault $alt_version.app" ]; then echo "FEHLER: Vorversion $alt_version liegt schon in der Ablage"; exit 1; fi
mv "$ALT" "$ABLAGE/Photo Vault $alt_version.app" || {{ echo "FEHLER beim Wegräumen"; exit 1; }}
ditto "$NEU" "$ALT" || {{ echo "FEHLER beim Kopieren – stelle zurück"; mv "$ABLAGE/Photo Vault $alt_version.app" "$ALT"; exit 1; }}
echo "$(date '+%F %T') FERTIG: $(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$ALT/Contents/Info.plist") in /Applications, $alt_version in der Ablage"
'''


def einspielen(args):
    z = ziele()
    fassung = args.fassung
    a = arbeitsordner(fassung)
    u = upload_ordner(z, fassung)
    if args.linux:
        lauf(['ssh', z['linux_ssh'],
              f'pkill -x photo_vault; sleep 2; flatpak install --user --reinstall -y --bundle ~/Desktop/PhotoVault-{fassung}-x86_64.flatpak 2>&1 | tail -1; '
              'flatpak info de.dasevo.photovault | grep -iE "^ *Version"'])
    if args.windows:
        ps1 = a / 'windows_tausch.ps1'
        ps1.write_text(WINDOWS_TAUSCH.format(fassung=fassung))
        lauf(['scp', '-q', str(ps1), f'{z["windows_ssh"]}:pv_windows_tausch.ps1'])
        # Über die Aufgabenplanung, damit die App in der Sitzung des Nutzers
        # startet und nicht in der unsichtbaren der SSH-Verbindung.
        aufgabe = f'pvtausch{fassung.replace(".", "")}'
        lauf(['ssh', z['windows_ssh'],
              f'schtasks /Create /F /SC ONCE /ST 00:00 /TN {aufgabe} /TR "powershell -NoProfile -ExecutionPolicy Bypass -File %USERPROFILE%\\pv_windows_tausch.ps1" /IT /RL HIGHEST >nul && schtasks /Run /TN {aufgabe} && ping -n 50 127.0.0.1 >nul && type %USERPROFILE%\\pv_update.log'])
    if args.mac:
        skript = a / 'mac_tausch.sh'
        skript.write_text(MAC_TAUSCH.format(fassung=fassung, neu=shlex.quote(str(u / 'Photo Vault.app'))))
        skript.chmod(0o755)
        subprocess.Popen(['nohup', str(skript)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        time.sleep(2)
        print((a / 'mac_tausch.log').read_text() if (a / 'mac_tausch.log').exists() else 'Wächter gestartet.')
    if args.server:
        antwort = input(f'Produktivserver auf {fassung} bringen? Zum Bestätigen „ja“ eingeben: ').strip().lower()
        if antwort != 'ja':
            sys.exit('Server nicht angefasst.')
        paket = a / 'paket-openvino' / 'photo-vault-server-linux-amd64-openvino.tar.gz'
        o = ['-i', os.path.expanduser(z['server_schluessel']), '-o', f'UserKnownHostsFile={os.path.expanduser(z["server_known_hosts"])}',
             '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=10']
        lauf(['scp', '-q', *o, str(paket), f'{z["server_ssh"]}:/root/pv-neu.tar.gz'])
        # Getauscht wird nur das Bündel, nicht die Einheit unter /etc. Hat
        # sie sich geändert, läuft das neue Programm sonst mit der alten –
        # bei 3.49.4 hätte die Gastprüfung so die nötigen Namensräume nicht
        # bekommen. Dann vor dem Anhalten abbrechen.
        lauf(['ssh', *o, z['server_ssh'],
              'set -e; cd /opt; rm -rf photo-vault-server.neu && mkdir photo-vault-server.neu && '
              'tar -xzf /root/pv-neu.tar.gz -C photo-vault-server.neu --strip-components=1; '
              'if ! cmp -s photo-vault-server.neu/systemd/photo-vault-server.service '
              '/etc/systemd/system/photo-vault-server.service; then '
              'echo "Die Einheit im Bündel weicht von /etc/systemd/system ab – erst übernehmen '
              '(README, Einzeldatei mit systemd). Der Dienst läuft unverändert."; '
              'rm -rf photo-vault-server.neu /root/pv-neu.tar.gz; exit 3; fi; '
              'systemctl stop photo-vault-server; rm -rf photo-vault-server.old; '
              'mv photo-vault-server photo-vault-server.old; mv photo-vault-server.neu photo-vault-server; '
              'systemctl start photo-vault-server; sleep 12; systemctl is-active photo-vault-server; rm /root/pv-neu.tar.gz'])


# --- veroeffentlichen -------------------------------------------------------------

def veroeffentlichen(args):
    z = ziele()
    fassung = args.fassung
    tok = token(z)
    _, alle = gitea(z, '/releases?draft=true&limit=30', tok=tok)
    rel = next((r for r in (alle if isinstance(alle, list) else []) if r.get('tag_name') == f'v{fassung}'), None)
    if rel is None:
        sys.exit('Kein Entwurf zu dieser Fassung.')
    st, r = gitea(z, f'/releases/{rel["id"]}', json.dumps({'draft': False}).encode(), 'PATCH', {'Content-Type': 'application/json'}, tok)
    print('Freigabe', r['id'], 'Entwurf' if r['draft'] else 'veröffentlicht', len(r['assets']), 'Dateien')
    sync = os.path.expanduser(z.get('sync_py', '~/Library/Application Support/gitea-github-sync/sync.py'))
    lauf(['python3', sync, z.get('github_repo', 'Photovault')])


def main():
    p = argparse.ArgumentParser(description='Eine Fassung von Photo Vault ausliefern.')
    sub = p.add_subparsers(dest='schritt', required=True)
    v = sub.add_parser('vorbereiten')
    v.add_argument('fassung')
    v.add_argument('--metainfo', required=True, help='Datei mit den <p>-Absätzen für die Flatpak-Metainfo (englisch)')
    b = sub.add_parser('bauen')
    b.add_argument('fassung')
    b.add_argument('--nur', nargs='+', choices=['linux', 'windows', 'mac', 'server'],
                   help='nur diese Plattformen bauen (sonst alle)')
    for name in ['entwurf', 'veroeffentlichen']:
        sub.add_parser(name).add_argument('fassung')
    e = sub.add_parser('einspielen')
    e.add_argument('fassung')
    for ziel in ['linux', 'windows', 'mac', 'server']:
        e.add_argument(f'--{ziel}', action='store_true')
    args = p.parse_args()
    {'vorbereiten': vorbereiten, 'bauen': bauen, 'entwurf': entwurf,
     'einspielen': einspielen, 'veroeffentlichen': veroeffentlichen}[args.schritt](args)


if __name__ == '__main__':
    main()
