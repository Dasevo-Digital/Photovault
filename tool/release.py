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
              „Version x“, Datenschutzprüfung, lokale annotierte Marke.
              Main und Marke erst beim Entwurf nach geprüften Paketen pushen.
bauen         Linux (Flatpak) und Windows (Zip) auf den Testrechnern, macOS
              hier, die Server-Pakete mit Docker; alles in den Ordner
              <upload_basis>/PhotoVault-Release-v<x>-Upload, dazu
              SHA256SUMS.txt. Die .app-Bündel unter build/ werden danach
              entfernt, damit Spotlight sie nicht findet. Auf den
              Testrechnern entsteht derselbe Ordner mit Paket und Summen,
              wie ihn der Installer dort sucht. Scheitert eine Plattform,
              laufen die anderen zu Ende; der Fehler kommt am Schluss.
entwurf       Gitea-Freigabe als Entwurf mit RELEASE-TEXT-v<x>.md aus dem
              Ordner und allen Dateien. Ein vorhandener Entwurf wird
              ergänzt, nicht verdoppelt; ein schon veröffentlichtes
              Release ebenso (Text neu, fehlende Pakete nachgetragen,
              SHA256SUMS.txt ersetzt).
einspielen    Desktop-Apps installieren; laufende Apps zuvor geordnet beenden.
              Vorprüfung, Vorbereitung, Austausch und Nachprüfung werden
              getrennt ausgeführt, bei Fehlern wird die Vorversion geprüft
              zurückgesetzt. Der Server nur
              mit --server und nach ausdrücklichem „ja“ – er ist produktiv.
veroeffentlichen  Entwurf ausschließlich auf Gitea freigeben.
                 Das GitHub-Release wird anschließend von Hand angelegt.

Wohin es geht, steht nicht hier, sondern in
~/.config/photovault-release/ziele.json (nicht im Repo – es ist
öffentlich):

    {
      "gitea_api": "https://<gitea>/api/v1/repos/<besitzer>/<repo>",
      "upload_basis": "~/Desktop",
      "arbeit_basis": "<Ordner ausserhalb von /tmp, z. B. …/worktrees.noindex/arbeit>",
      "linux_ssh": "<ssh-name>", "linux_repo": "~/photo_vault",
      "windows_ssh": "<ssh-name>",
      "windows_flutter": "C:\\\\src\\\\flutter\\\\bin",
      "server_ssh": "root@<adresse>",
      "server_schluessel": "<pfad zum Schlüssel>",
      "server_known_hosts": "<pfad>",
      "onnxruntime_quelle": "https://<gitea>/api/packages/<besitzer>/generic/onnxruntime/{version}"
    }

„onnxruntime_quelle“ ist optional: der Ordner mit den Archiven der ONNX
Runtime (#473), {version} wird ersetzt. Liegt er auf dem Gitea-Host, geht
das Token mit. Die Archive werden hier geprüft und an die Bauten
weitergereicht; ohne den Eintrag laden die Bauten selbst aus der Freigabe
onnxruntime-<fassung> auf GitHub.

Das Gitea-Token kommt aus dem Schlüsselbund (git credential-osxkeychain)
und wird nirgends gespeichert oder ausgegeben.
"""

from contextlib import contextmanager
import argparse
import base64
import hashlib
import json
import os
import re
import shlex
import shutil
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


def lauf(befehl, *, cwd=None, pruefen=True, ausgabe=False, eingabe=None, versuche=1, pause=90):
    """Führt [befehl] aus; mit [ausgabe] kommt stdout zurück.

    Mit [versuche] wird ein gescheiterter Schritt nach [pause] Sekunden
    wiederholt – für alles, was beim Bauen aus dem Netz lädt (#294). Bei
    3.54.0 scheiterten Docker und Xcode eine Stunde lang an Zeitüberschreitungen
    zu GitHub und Docker Hub, die jeweils nach Minuten wieder vorbei waren.
    """
    cwd = REPO if cwd is None else cwd
    text = befehl if isinstance(befehl, str) else ' '.join(shlex.quote(str(b)) for b in befehl)
    for versuch in range(1, versuche + 1):
        print('›', text, flush=True)
        r = subprocess.run(befehl, cwd=cwd, shell=isinstance(befehl, str), text=True,
                           capture_output=ausgabe, input=eingabe)
        if r.returncode == 0 or not pruefen or versuch == versuche:
            break
        print(f'Schritt scheiterte (Code {r.returncode}) – Versuch {versuch + 1} von {versuche} '
              f'in {pause} s.', flush=True)
        time.sleep(pause)
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


def upload_ordner(z, fassung, anlegen=True):
    # Nicht auf „.0“ enden lassen: Spotlight hielte den Ordner sonst für ein
    # Programm – daher das „-Upload“.
    o = Path(os.path.expanduser(z.get('upload_basis', '~/Desktop'))) / f'PhotoVault-Release-v{fassung}-Upload'
    if anlegen:
        o.mkdir(parents=True, exist_ok=True)
    return o


def _fassung_von(ordner):
    return tuple(int(t) for t in ordner.name.removeprefix('pv-release-').split('.'))


def arbeitsordner(fassung, z=None, anlegen=True):
    """Wo die Serverpakete gebaut werden, darunter das für den eigenen
    Server (OpenVINO), das nicht in den Upload-Ordner kommt. Ohne
    `arbeit_basis` im Temp-Ordner – den leerte macOS bei 3.67.2 aber
    innerhalb von Stunden, und das Paket für `einspielen --server` war weg
    (#382). Besser neben den Worktrees in einem `.noindex`-Ordner."""
    basis = (z or {}).get('arbeit_basis')
    o = (Path(os.path.expanduser(basis)) if basis else Path(tempfile.gettempdir())) / f'pv-release-{fassung}'
    if not anlegen:
        return o
    o.mkdir(parents=True, exist_ok=True)
    if basis:
        # Dort räumt niemand auf: Je Fassung liegen rund 200 MB Serverpakete.
        # Die zwei neuesten anderen bleiben, für ein Zurück – nach der
        # Fassung, nicht nach der Zeit, und ein leerer Ordner zählt nicht
        # mit: Ein vertippter Lauf verdrängte sonst einen echten (#396).
        andere = []
        for p in o.parent.glob('pv-release-*'):
            try:
                if p != o and p.is_dir() and re.fullmatch(r'pv-release-\d+\.\d+\.\d+', p.name):
                    andere.append((p, any(p.iterdir())))
            except OSError:
                continue  # gerade weg
        leer = [p for p, voll in andere if not voll]
        volle = sorted((p for p, voll in andere if voll), key=_fassung_von, reverse=True)
        for alt in leer + volle[2:]:
            shutil.rmtree(alt, ignore_errors=True)
            print('Arbeitsordner entfernt:', alt.name)
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
    lauf(['bash', 'tool/pruefe_repository_datenschutz.sh'])
    lauf(['git', 'tag', '-a', f'v{fassung}', '-m', f'Photo Vault {fassung}'])
    print('Nur lokal vorbereitet. Veröffentlicht wird nach gebauten und geprüften Paketen.')


# --- bauen ------------------------------------------------------------------------

WINDOWS_BAU = r'''$ErrorActionPreference = 'Stop'
$repo = Join-Path $env:LOCALAPPDATA 'PhotoVaultBuilds/{kennung}'
$bundle = Join-Path $env:TEMP '{kennung}.bundle'
$ort = Join-Path $env:TEMP '{kennung}-ort'
if (Test-Path -LiteralPath $repo) {{ throw 'Isolierter Bauordner ist schon belegt' }}
$env:Path = '{flutter};' + $env:Path
# Geprüfte Archive der ONNX Runtime vom Mac (#473), sonst lädt CMake selbst.
if (Test-Path -LiteralPath $ort) {{ $env:PV_ONNXRUNTIME_QUELLE = ([Uri]$ort).AbsoluteUri }}
try {{
  git clone --no-checkout -- $bundle $repo
  if ($LASTEXITCODE -ne 0) {{ throw 'clone' }}
  Set-Location $repo
  git config core.autocrlf false
  git checkout --detach {commit}
  if ($LASTEXITCODE -ne 0) {{ throw 'checkout' }}
  powershell -NoProfile -ExecutionPolicy Bypass -File tool\windows_bauen.ps1 -Pruefen -Zip
  $status = $LASTEXITCODE
  if ($status -ne 0) {{ throw "Bau fehlgeschlagen: $status" }}
}} finally {{
  Set-Location $env:USERPROFILE
  if (Test-Path -LiteralPath $repo) {{ Remove-Item -LiteralPath $repo -Recurse -Force }}
  if (Test-Path -LiteralPath $bundle) {{ Remove-Item -LiteralPath $bundle -Force }}
  if (Test-Path -LiteralPath $ort) {{ Remove-Item -LiteralPath $ort -Recurse -Force }}
}}
'BAU-ENDE 0'
'''

@contextmanager
def isolierter_baum(basis, commit):
    """Alle lokalen Builds lesen einen festen Commit in eigener Arbeitskopie."""
    global REPO
    quelle = REPO
    ziel = Path(tempfile.mkdtemp(prefix='quelle-', dir=basis))
    try:
        lauf(['git', 'clone', '--quiet', '--no-hardlinks', '--no-checkout', '--', str(quelle), str(ziel)])
        lauf(['git', 'checkout', '--quiet', '--detach', commit], cwd=ziel)
        REPO = ziel
        yield ziel
    finally:
        REPO = quelle
        # Nur der in diesem Aufruf neu angelegte Baum, nie eine Benutzerkopie.
        shutil.rmtree(ziel)


def linux_bau(kennung, commit, ort=False):
    """[ort]: Die geprüften Archive der ONNX Runtime liegen schon unter
    /tmp/<kennung>-ort (siehe ort_bereitstellen)."""
    ordner = f'/tmp/{kennung}-ort'
    inner = 'trap \'cd /; rm -rf -- "$1" "$3"; rm -f -- "$2"\' EXIT; bash tool/flatpak_bauen.sh --pruefen --buendel && echo BAU-ENDE-0'
    quelle = f'export PV_ONNXRUNTIME_QUELLE={shlex.quote("file://" + ordner)}; ' if ort else ''
    return (f'set -eu; work=$(mktemp -d "$HOME/{kennung}.XXXXXX"); '
            f'bundle=/tmp/{kennung}.bundle; '
            'git clone --quiet --no-checkout -- "$bundle" "$work"; '
            'cd "$work"; '
            f'git checkout --quiet --detach {shlex.quote(commit)}; '
            'export PATH="$HOME/flutter/bin:$HOME/snap/flutter/common/flutter/bin:$PATH"; '
            + quelle +
            f'nohup bash -c {shlex.quote(inner)} pv "$work" "$bundle" {shlex.quote(ordner)} > "$HOME/pv_bau_{kennung}.log" 2>&1 &')


ORT_SUMMEN = 'third_party/flutter_onnxruntime/onnxruntime-pruefsummen.txt'


def ort_pruefsummen(text):
    """Name → erlaubte Summen aus onnxruntime-pruefsummen.txt."""
    summen = {}
    for zeile in text.splitlines():
        m = re.match(r'([0-9a-f]{64})  (\S+)\s*$', zeile)
        if m:
            summen.setdefault(m.group(2), set()).add(m.group(1))
    return summen


def ort_bereitstellen(z, a, commit):
    """Legt die Archive der ONNX Runtime für den Bau von [commit] geprüft in
    a/onnxruntime ab und gibt den Ordner zurück – None, wenn ziele.json keine
    eigene Ablage nennt; dann laden die Bauten selbst aus der Vorgabe (#473).

    Die Ablage auf Gitea ist nicht öffentlich. Das Token aus dem
    Schlüsselbund geht deshalb nur hier auf dem Mac mit und nur an den
    Gitea-Host; die Bau-Rechner bekommen die geprüften Dateien. Geprüft wird
    gegen die Summen des Commits, die auch CMake und das Dockerfile lesen."""
    quelle = z.get('onnxruntime_quelle')
    if not quelle:
        return None
    r = subprocess.run(['git', 'show', f'{commit}:{ORT_SUMMEN}'], cwd=REPO, text=True, capture_output=True)
    if r.returncode != 0:
        print(f'› {ORT_SUMMEN} fehlt in {commit[:10]} – die Bauten laden die ONNX Runtime selbst', flush=True)
        return None
    summen = ort_pruefsummen(r.stdout)
    ordner = a / 'onnxruntime'
    ordner.mkdir(parents=True, exist_ok=True)
    gitea_host = urllib.parse.urlparse(z.get('gitea_api', '')).hostname
    tok = None
    try:
        for name, erlaubt in sorted(summen.items()):
            ziel = ordner / name
            if ziel.is_file() and _sha256(ziel) in erlaubt:
                continue
            m = re.search(r'-(\d+\.\d+\.\d+)\.(?:tgz|zip)$', name)
            url = quelle.replace('{version}', m.group(1) if m else '').rstrip('/') + '/' + name
            kopf = {}
            if gitea_host and urllib.parse.urlparse(url).hostname == gitea_host:
                tok = tok or token(z)
                kopf['Authorization'] = 'token ' + tok
            teil = ordner / (name + '.teil')
            try:
                with urllib.request.urlopen(urllib.request.Request(url, headers=kopf), timeout=600) as antwort, \
                        open(teil, 'wb') as f:
                    shutil.copyfileobj(antwort, f)
            except (urllib.error.URLError, OSError) as e:
                teil.unlink(missing_ok=True)
                sys.exit(f'ONNX Runtime {name} nicht geladen: {e}')
            summe = _sha256(teil)
            if summe not in erlaubt:
                teil.unlink()
                sys.exit(f'ONNX Runtime {name}: Prüfsumme {summe} steht nicht in {ORT_SUMMEN}.')
            teil.replace(ziel)
    finally:
        tok = None
    print(f'› ONNX Runtime geprüft bereit: {", ".join(sorted(summen))}', flush=True)
    return ordner


def bauen(args):
    z = ziele()
    fassung = args.fassung
    nur = set(args.nur or ['linux', 'windows', 'mac'])
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
    a = arbeitsordner(fassung, z)
    u = upload_ordner(z, fassung)
    commit = lauf(['git','rev-parse',f'{marke}^{{commit}}'],ausgabe=True).strip()
    kennung = f'pv-{fassung}-{uuid.uuid4().hex}'
    gebaut=set()
    belegte_pakete={}
    try:
        alt=json.loads((u/'BUILD-STAND.json').read_text())
        if alt.get('commit')==commit and alt.get('fassung')==fassung:
            belegte_pakete={n:h for n,h in alt.get('pakete',{}).items() if n in dateien(fassung) and (u/n).is_file() and _sha256(u/n)==h}
    except (OSError,ValueError,AttributeError):
        pass

    ort = ort_bereitstellen(z, a, commit) if {'linux', 'windows', 'server'} & nur else None

    # Linux und Windows laufen im Hintergrund, während hier macOS baut.
    windows = None
    if 'linux' in nur:
        b = buendel(a, 'linux', marke, None)
        lauf(['scp', '-q', str(b), f'{z["linux_ssh"]}:/tmp/{kennung}.bundle'])
        if ort:
            lauf(['scp', '-q', '-r', str(ort), f'{z["linux_ssh"]}:/tmp/{kennung}-ort'])
        lauf(['ssh', z['linux_ssh'], linux_bau(kennung, commit, ort is not None)])

    if 'windows' in nur:
        ps1 = a / 'windows_bau.ps1'
        ps1.write_text(WINDOWS_BAU.format(flutter=z.get('windows_flutter', r'C:\src\flutter\bin').replace("'","''"), kennung=kennung,commit=commit))
        b = buendel(a, 'windows', marke, None)
        lauf(['scp', '-q', str(b), f'{z["windows_ssh"]}:AppData/Local/Temp/{kennung}.bundle'])
        lauf(['scp', '-q', str(ps1), f'{z["windows_ssh"]}:{kennung}.ps1'])
        if ort:
            lauf(['scp', '-q', '-r', str(ort), f'{z["windows_ssh"]}:AppData/Local/Temp/{kennung}-ort'])
        windows_log = open(a / 'windows_bau.log', 'w')
        windows = subprocess.Popen(['ssh', z['windows_ssh'], f'powershell -NoProfile -ExecutionPolicy Bypass -File {kennung}.ps1'],
                                   stdout=windows_log, stderr=subprocess.STDOUT)

    # Scheitert hier etwas, laufen Linux und Windows trotzdem zu Ende und
    # kommen in den Ordner (#286); der Fehler kommt am Schluss.
    fehler = []
    fertig = []
    if 'mac' in nur:
        try:
            with isolierter_baum(a, commit):
                _baue_mac(fassung, u, z)
                gebaut.add('mac')
        except SystemExit as e:
            fehler.append(f'macOS: {e}')

    if 'server' in nur:
        try:
            with isolierter_baum(a, commit):
                _baue_server(fassung, marke, a, u, ort)
                gebaut.add('server')
        except SystemExit as e:
            fehler.append(f'Server: {e}')

    if windows is not None:
        if windows.wait() != 0 or 'BAU-ENDE 0' not in (a / 'windows_bau.log').read_text(errors='replace'):
            fehler.append(f'Windows-Bau gescheitert – siehe {a / "windows_bau.log"}.')
        else:
            lauf(['scp', '-q', f'{z["windows_ssh"]}:Desktop/PhotoVault-{fassung}-windows-x64.zip', str(u)])
            fertig.append('windows')
            gebaut.add('windows')

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
        log = lauf(['ssh', z['linux_ssh'], f'grep -E "✗|FEHLER|BAU-ENDE-0" ~/pv_bau_{kennung}.log | tail -5; test -f ~/{flatpak} && echo DA'], ausgabe=True, pruefen=False)
        if 'DA' not in log or 'BAU-ENDE-0' not in log:
            fehler.append(f'Flatpak fehlt:\n{log}')
        else:
            if '✗' in log or 'FEHLER' in log:
                print(f'Das Flatpak ist da, die Prüfung meldet aber:\n{log}')
            lauf(['scp', '-q', f'{z["linux_ssh"]}:{flatpak}', str(u)])
            fertig.append('linux')
            gebaut.add('linux')

    summen(u, fassung)
    for plattform in fertig:
        fern_bereitlegen(z, plattform, fassung, u)
    if fehler:
        sys.exit('\n'.join(fehler))
    namen={'mac':[f'PhotoVault-{fassung}-macos.zip'],
           'windows':[f'PhotoVault-{fassung}-windows-x64.zip'],
           'linux':[f'PhotoVault-{fassung}-x86_64.flatpak'],
           'server':[f'PhotoVault-Server-{fassung}-linux-amd64.tar.gz',f'PhotoVault-Server-{fassung}-linux-arm64.tar.gz']}
    for plattform in gebaut:
        for name in namen[plattform]:
            belegte_pakete[name]=_sha256(u/name)
    (u/'BUILD-STAND.json').write_text(json.dumps({'fassung':fassung,'commit':commit,'pakete':belegte_pakete},indent=2)+'\n')


def _baue_mac(fassung, u, z):
    # Was von einem früheren Lauf liegt oder von diesem nur halb fertig wurde
    # (signiert, aber nicht notarisiert), darf nicht als fertig gelten:
    # summen() nähme es auf, entwurf lüde es hoch, einspielen spielte es
    # ein (#382). Scheitert ein Schritt, liegt für macOS also nichts da.
    reste = [str(u / f'PhotoVault-{fassung}-macos.zip'), str(u / 'Photo Vault.app')]
    lauf(['rm', '-rf', *reste])
    # Xcode lädt Swift-Pakete (ONNX Runtime) beim ersten Bau eines Baums.
    try:
        lauf(['flutter', 'build', 'macos', '--release'], versuche=3)
        _signiere_mac(z)
        _packe_mac(fassung, u)
        _notarisiere_mac(fassung, u, z)
    except BaseException:
        # Auch bei Ctrl-C mitten im stundenlangen Warten auf Apple.
        lauf(['rm', '-rf', *reste])
        raise
    finally:
        # Auch wenn etwas scheitert: Die Bündel unter build/ fänden Spotlight
        # und Launchpad – und öffneten womöglich die echte Bibliothek. Vorher
        # prüfen, dass keins läuft.
        if str(REPO / 'build') in lauf('ps -Ao comm', ausgabe=True):
            print('Ein Build-Bündel läuft noch – nicht aufgeräumt.')
        else:
            lauf('rm -rf build/macos/Build/Products/*/Photo\\ Vault*.app')


def _signiere_mac(z):
    """Signiert das Bündel mit Hardened Runtime (#319, #1/#89).

    Der Flutter-Bau signiert ad-hoc und ohne Hardened Runtime; damit liesse
    sich fremder Code über DYLD_INSERT_LIBRARIES in die App laden. Steht in
    ziele.json eine `mac_signatur` (der Name einer „Developer ID
    Application“ im Schlüsselbund), signiert er damit, sonst ad-hoc.
    Das Skript prüft danach jedes Teil nach und bricht ab, wenn eines nicht
    gehärtet ist."""
    app = REPO / 'build/macos/Build/Products/Release/Photo Vault.app'
    kennung = z.get('mac_signatur')
    lauf(['bash', str(REPO / 'tool/macos_signieren.sh'), str(app),
          *(['--kennung', kennung] if kennung else [])])


def _notarisiere_mac(fassung, u, z):
    """Lässt das Paket von Apple notarisieren und heftet das Ticket an,
    sofern eine Developer-ID signiert hat und ein Profil für notarytool
    eingerichtet ist (`mac_notar_profil` in ziele.json, angelegt mit
    `xcrun notarytool store-credentials`). Danach öffnet macOS die App ohne
    Rechtsklick. Ohne beides bleibt es beim gehärteten, aber nicht
    notarisierten Bündel."""
    profil = z.get('mac_notar_profil')
    if not (z.get('mac_signatur') and profil):
        print('macOS: nicht notarisiert (keine Developer-ID oder kein Profil für notarytool)')
        return
    paket = f'PhotoVault-{fassung}-macos.zip'
    # Die erste Einreichung eines neuen Teams lag bei 3.67.1 drei Stunden bei
    # Apple. Länger als sechs wartet der Bau nicht. Ein zweiter Versuch nur,
    # wenn keine Antwort kam – eine Ablehnung wird nicht anders, wenn man
    # dasselbe Paket noch einmal schickt; dann holt der Bau Apples Begründung.
    print('macOS: zur Notarisierung bei Apple – das kann Stunden dauern.', flush=True)
    befehl = ['xcrun', 'notarytool', 'submit', paket, '--keychain-profile', profil,
              '--wait', '--timeout', '6h', '--output-format', 'json']
    antwort = {}
    for versuch in range(2):
        print('›', ' '.join(befehl), flush=True)
        beginn = time.monotonic()
        r = subprocess.run(befehl, cwd=u, text=True, capture_output=True)
        antwort = _letztes_json(r.stdout)
        # Mit einer Kennung liegt das Paket bei Apple – auch wenn die Zeit
        # um ist. Nur ohne sie kam es gar nicht an (Netz, Schlüsselbund).
        if antwort.get('id'):
            break
        meldung = (r.stderr or r.stdout or '').strip()
        print(f'notarytool ohne Einreichung (Code {r.returncode}): {meldung[-600:]}', flush=True)
        # Lief es lange, war das Paket wohl doch bei Apple und nur die
        # Antwort fehlt – noch einmal einzureichen hiesse, wieder Stunden zu
        # warten (#382).
        if time.monotonic() - beginn > 600:
            sys.exit('notarytool lief lange und meldete keine Einreichung – nicht noch einmal eingereicht. '
                     f'Stand: xcrun notarytool history --keychain-profile {profil}')
        if versuch == 0:
            print('Neuer Versuch in 90 s.', flush=True)
            time.sleep(90)
    status = antwort.get('status')
    if status != 'Accepted':
        kennung = antwort.get('id')
        if kennung and status in (None, 'In Progress'):
            sys.exit(f'Apple hat nach sechs Stunden noch nicht entschieden (Einreichung {kennung}, '
                     f'xcrun notarytool info {kennung} --keychain-profile {profil}). Das Paket ist '
                     'weggeräumt; nach der Annahme mit bauen --nur mac neu bauen.')
        if kennung:
            lauf(['xcrun', 'notarytool', 'log', kennung, '--keychain-profile', profil], cwd=u, pruefen=False)
        sys.exit(f'Apple hat das Paket nicht notarisiert: {status or "keine Antwort"} {antwort.get("message", "")}'.strip())
    print(f'macOS: notarisiert ({antwort.get("id")})', flush=True)
    # Gleich nach der Annahme findet stapler das Ticket mitunter noch nicht
    # („Record not found“). Scheitert es, wäre die Notarisierung vertan.
    lauf(['xcrun', 'stapler', 'staple', 'Photo Vault.app'], cwd=u, versuche=4, pause=90)
    lauf(['xcrun', 'stapler', 'validate', 'Photo Vault.app'], cwd=u)
    # Das Paket neu, mit dem angehefteten Ticket.
    lauf(['rm', '-f', paket], cwd=u)
    lauf(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', 'Photo Vault.app', paket], cwd=u)


def _letztes_json(text):
    """Das letzte JSON-Objekt in [text]. Mit `--output-format json` gibt
    notarytool laut Hilfe am Ende genau eines aus; stünde davor oder danach
    doch noch etwas, hielte der Bau eine Annahme sonst für „keine Antwort“
    und reichte dasselbe Paket ein zweites Mal ein. Verschachtelte Objekte
    zählen zu ihrem äusseren."""
    text = text or ''
    letztes = {}
    antwort = None
    dekoder = json.JSONDecoder()
    i = text.find('{')
    while i != -1:
        try:
            wert, ende = dekoder.raw_decode(text, i)
        except json.JSONDecodeError:
            i = text.find('{', i + 1)
            continue
        if isinstance(wert, dict):
            letztes = wert
            # Die Antwort trägt Kennung oder Stand; ein anderes Objekt danach
            # verdeckt sie nicht (#396).
            if 'id' in wert or 'status' in wert:
                antwort = wert
        i = text.find('{', ende)
    return antwort if antwort is not None else letztes


def _packe_mac(fassung, u):
    app = REPO / 'build/macos/Build/Products/Release/Photo Vault.app'
    fassung_app = lauf(['/usr/libexec/PlistBuddy', '-c', 'Print CFBundleShortVersionString', str(app / 'Contents/Info.plist')], ausgabe=True).strip()
    if fassung_app != fassung:
        sys.exit(f'Die App meldet {fassung_app}, nicht {fassung}.')
    lauf(['rm', '-rf', str(u / 'Photo Vault.app')])
    lauf(['ditto', str(app), str(u / 'Photo Vault.app')])
    lauf(['rm', '-f', str(u / f'PhotoVault-{fassung}-macos.zip')])
    lauf(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', 'Photo Vault.app', f'PhotoVault-{fassung}-macos.zip'], cwd=u)


def basis_images(dockerfile):
    """Die Basis-Images, aus denen die Pakete des Servers entstehen – mit
    den Fassungen aus den ARG-Vorgaben des Dockerfiles, damit beide nicht
    auseinanderlaufen."""
    text = Path(dockerfile).read_text()
    vorgaben = dict(re.findall(r'^ARG ([A-Z_]+)=(\S+)', text, re.M))
    # Nur die Stufen der Pakete; ubuntu gehört zum Bild für OpenVINO.
    return [f'dart:{vorgaben["DART_FASSUNG"]}', f'debian:{vorgaben["DEBIAN"]}']


def _halte_vor(images, plattformen, versuche=3, pause=30):
    """Holt [images] für [plattformen] in Dockers Speicher (#294).

    BuildKit fragt ein Basis-Image bei Docker Hub nach, solange es nicht
    lokal unter seinem Namen liegt – bei 3.54.0 scheiterte der Bau daran
    eine Stunde lang. Liegt es da, braucht der Bau Docker Hub nicht. Gelingt
    das Holen nicht, geht es trotzdem weiter: Der Bau fragt dann selbst und
    wiederholt."""
    for image in images:
        for plattform in plattformen:
            for versuch in range(versuche):
                r = subprocess.run(['docker', 'pull', '-q', '--platform', plattform, image],
                                   text=True, capture_output=True)
                if r.returncode == 0:
                    print(f'› {image} ({plattform}) liegt bereit', flush=True)
                    break
                if versuch + 1 < versuche:
                    time.sleep(pause)
            else:
                print(f'› {image} ({plattform}) nicht geholt – der Bau fragt selbst nach', flush=True)


def _baue_server(fassung, marke, a, u, ort=None):
    commit = lauf(['git', 'rev-parse', '--short', f'{marke}^{{commit}}'], ausgabe=True).strip()
    _halte_vor(basis_images(REPO / 'packages/server/Dockerfile'), ['linux/amd64', 'linux/arm64'])
    # Geprüfte Archive der ONNX Runtime als Kontext „ort-archiv“ (#473).
    kontext = ['--build-context', f'ort-archiv={ort}'] if ort else []
    for ziel, plattform in [('paket', 'linux/amd64,linux/arm64'), ('paket-openvino', 'linux/amd64')]:
        # Das Basis-Image fragt BuildKit bei jedem Bau bei Docker Hub nach.
        lauf(['docker', 'buildx', 'build', '-f', 'packages/server/Dockerfile', '--target', ziel,
              '--platform', plattform, '--build-arg', f'PV_FASSUNG={fassung}', '--build-arg', f'PV_COMMIT={commit}',
              *kontext, '--output', f'type=local,dest={a / ziel}', '.'], versuche=4, pause=120)
    for arch in ['amd64', 'arm64']:
        lauf(['cp', str(a / 'paket' / f'linux_{arch}' / f'photo-vault-server-linux-{arch}.tar.gz'),
              str(u / f'PhotoVault-Server-{fassung}-linux-{arch}.tar.gz')])


def _sha256(pfad):
    h = hashlib.sha256()
    with open(pfad, 'rb') as f:
        for stueck in iter(lambda: f.read(1 << 20), b''):
            h.update(stueck)
    return h.hexdigest()


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


def fern_bereitlegen(z, plattform, fassung, u, runner=None):
    """Legt auf dem Testrechner [plattform] den Upload-Ordner an, wie ihn
    der Installer dort sucht: das Paket und SHA256SUMS.txt daneben (#286).

    `bauen` lässt das Paket auf dem Desktop des Testrechners liegen, ohne
    Prüfsummen; der Installer verweigert es dann („Die Prüfsummenliste
    fehlt“). Bei 3.52.0 und 3.53.0 musste der Ordner von Hand entstehen.
    Liegt das Paket dort gar nicht, kommt es von hier. Lässt sich beliebig
    oft aufrufen.
    """
    # Die Konsole von Windows schreibt nicht immer UTF-8.
    run = runner or (lambda befehl: subprocess.run(befehl, text=True, capture_output=True, errors='replace'))
    ordner = f'PhotoVault-Release-v{fassung}-Upload'
    if plattform == 'windows':
        host, name = z['windows_ssh'], f'PhotoVault-{fassung}-windows-x64.zip'
        # Wie der Installer (installieren/windows.ps1): der Desktop des
        # Kontos, auch wenn er umgeleitet ist; scp braucht ihn relativ zum
        # Profil.
        code = (
            "$d=[Environment]::GetFolderPath('Desktop'); "
            f"$o=Join-Path $d '{ordner}'; "
            "New-Item -ItemType Directory -Force -Path $o | Out-Null; "
            f"$z=Join-Path $d '{name}'; "
            "if (Test-Path -LiteralPath $z) { Move-Item -Force -LiteralPath $z -Destination $o }; "
            "$r=$o; if ($o.StartsWith($env:USERPROFILE + '\\')) { $r=$o.Substring($env:USERPROFILE.Length + 1) }; "
            "'ZIEL ' + ($r -replace '\\\\', '/'); "
            f"if (Test-Path -LiteralPath (Join-Path $o '{name}')) {{ 'DA' }}"
        )
        befehl = 'powershell -NoProfile -EncodedCommand ' + base64.b64encode(code.encode('utf-16le')).decode()
    else:
        host, name = z['linux_ssh'], f'PhotoVault-{fassung}-x86_64.flatpak'
        # Wie der Installer (installation.py): ~/Desktop.
        befehl = (f'mkdir -p ~/Desktop/{ordner} && '
                  f'if [ -f ~/Desktop/{name} ]; then mv -f ~/Desktop/{name} ~/Desktop/{ordner}/; fi; '
                  f'echo "ZIEL Desktop/{ordner}"; test -f ~/Desktop/{ordner}/{name} && echo DA')
    r = run(['ssh', '-o', 'BatchMode=yes', host, befehl])
    zeilen = (r.stdout or '').splitlines()
    ziel = next((x[5:].strip() for x in zeilen if x.startswith('ZIEL ')), None)
    if r.returncode != 0 or not ziel:
        sys.exit(f'{plattform}: Upload-Ordner nicht angelegt.\n{r.stdout}{r.stderr}')
    if 'DA' not in (x.strip() for x in zeilen):
        if not (u / name).exists():
            sys.exit(f'{plattform}: {name} fehlt hier und dort.')
        print(f'› {name} nach {host}:{ziel}', flush=True)
        if run(['scp', '-q', str(u / name), f'{host}:{ziel}/{name}']).returncode != 0:
            sys.exit(f'{plattform}: {name} nicht übertragen.')
    if run(['scp', '-q', str(u / 'SHA256SUMS.txt'), f'{host}:{ziel}/SHA256SUMS.txt']).returncode != 0:
        sys.exit(f'{plattform}: SHA256SUMS.txt nicht übertragen.')
    print(f'› {plattform}: {ziel} mit {name} und SHA256SUMS.txt', flush=True)


# --- entwurf ----------------------------------------------------------------------

def summen_lesen(text):
    """`<sha256>  <name>` je Zeile → {name: sha256}."""
    summen = {}
    for zeile in (text or '').splitlines():
        teile = zeile.split(None, 1)
        if len(teile) == 2 and re.fullmatch(r'[0-9a-f]{64}', teile[0]):
            summen[teile[1].strip().lstrip('*')] = teile[0]
    return summen


def _lade_anhang(anhang, tok):
    """Der Inhalt einer kleinen Datei im Release (SHA256SUMS.txt); leer,
    wenn sie sich nicht laden lässt – dann gilt alles als anders."""
    url = anhang.get('browser_download_url')
    if not url:
        return ''
    try:
        req = urllib.request.Request(url)
        # Nur an diese Adresse: Leitete Gitea zu einem Speicher weiter,
        # ginge das Token sonst mit (#382).
        req.add_unredirected_header('Authorization', 'token ' + tok)
        with urllib.request.urlopen(req, timeout=60) as a:
            return a.read(1 << 20).decode('utf-8', 'replace')
    except Exception:  # noqa: BLE001 – dann gilt alles als anders
        return ''


class AnhangNichtGeladen(Exception):
    """Ein Anhang liess sich nicht laden – nicht dasselbe wie ein falscher."""


def _sha256_anhang(anhang, tok):
    """Die SHA-256 eines Anhangs, wie er tatsächlich auf dem Server liegt –
    ganz geladen, nicht nach der gemeldeten Grösse (#392). Lässt er sich
    nicht laden, [AnhangNichtGeladen] mit dem Grund: Bis 3.67.4 hiess auch
    ein Netzfehler „nicht die Datei von hier“ (#395)."""
    url = anhang.get('browser_download_url')
    if not url:
        raise AnhangNichtGeladen('ohne Adresse')
    try:
        req = urllib.request.Request(url)
        req.add_unredirected_header('Authorization', 'token ' + tok)
        h = hashlib.sha256()
        with urllib.request.urlopen(req, timeout=600) as a:
            for stueck in iter(lambda: a.read(1 << 20), b''):
                h.update(stueck)
        return h.hexdigest()
    except Exception as e:  # noqa: BLE001 – der Grund geht mit
        raise AnhangNichtGeladen(f'{type(e).__name__}: {e}') from e


def _lade_hoch(z, rid, name, daten, kopf, tok, groesse, versuche=3, pause=10):
    """Legt einen Anhang ins Release, mit Wiederholung (#396). Vor jedem
    neuen Versuch wird nachgesehen, ob er nicht doch angekommen ist – sonst
    läge er doppelt da. Gibt Status und Antwort des letzten Versuchs."""
    st, a = None, None
    for versuch in range(versuche):
        if versuch:
            time.sleep(pause)
            try:
                _, rel = gitea(z, f'/releases/{rid}', tok=tok)
            except (urllib.error.URLError, OSError):
                rel = None
            da = next((x for x in (rel or {}).get('assets', [])
                       if x.get('name') == name and x.get('size') == groesse), None) if isinstance(rel, dict) else None
            if da:
                return 201, da
        try:
            st, a = gitea(z, f'/releases/{rid}/assets?name={urllib.parse.quote(name)}', daten, 'POST', kopf, tok)
        except (urllib.error.URLError, OSError) as e:
            st, a = None, f'{type(e).__name__}: {e}'
        if st == 201:
            return st, a
        if versuch + 1 < versuche:
            print(f'{name}: {st} – neuer Versuch in {pause} s')
    return st, a


def release_dateien(fassung, ordner):
    """Drei Desktoppakete, wahlweise mit beiden vollständig gebauten Serverpaketen."""
    try:
        stand=json.loads((ordner/'BUILD-STAND.json').read_text())
        pakete=stand['pakete']
        if not isinstance(pakete,dict):
            raise ValueError('pakete')
    except (OSError,ValueError,KeyError,TypeError):
        sys.exit('Geprüfter Buildstand fehlt – Pakete vor Veröffentlichung neu bauen.')
    alle=dateien(fassung)
    if set(pakete) not in (set(alle[:3]),set(alle)):
        sys.exit('Unvollständiger Releaseumfang: alle Desktoppakete und gegebenenfalls beide Serverpakete erforderlich.')
    return [name for name in alle if name in pakete]


def pruefe_releasepakete(fassung, ordner):
    erwartet = release_dateien(fassung,ordner)
    summen = summen_lesen((ordner / 'SHA256SUMS.txt').read_text())
    if set(summen)!=set(erwartet):
        sys.exit('Prüfsummen und geplanter Releaseumfang stimmen nicht überein.')
    for name in erwartet:
        datei = ordner / name
        if not datei.is_file() or summen.get(name) != _sha256(datei):
            sys.exit(f'Releasepaket fehlt oder Prüfsumme weicht ab: {name}')
    stand=json.loads((ordner/'BUILD-STAND.json').read_text())
    commit=lauf(['git','rev-parse',f'v{fassung}^{{commit}}'],ausgabe=True).strip()
    if stand.get('fassung')!=fassung or stand.get('commit')!=commit or stand.get('pakete')!={n:summen[n] for n in erwartet}:
        sys.exit('Buildstand, Tag und Pakete stimmen nicht überein.')


def entwurf(args):
    z = ziele()
    fassung = args.fassung
    u = upload_ordner(z, fassung, anlegen=False)
    if not u.is_dir():
        sys.exit(f'Kein Upload-Ordner {u.name} – ist {fassung} gebaut?')
    text = (u / f'RELEASE-TEXT-v{fassung}.md').read_text(encoding='utf-8')
    pruefe_releasepakete(fassung, upload_ordner(z, fassung, anlegen=False))
    tok = token(z)
    # Ein veröffentlichtes Release findet /releases/tags/<marke> – so lassen
    # sich Pakete nachtragen, etwa Linux und Windows zu einer Fassung, die
    # zuerst nur für Mac und Server erschien (3.47.0). Entwürfe findet es
    # nicht – die stehen nur in der Liste.
    st, rel = gitea(z, f'/releases/tags/v{fassung}', tok=tok)
    if st != 200 or not isinstance(rel, dict):
        _, alle = gitea(z, '/releases?draft=true&limit=30', tok=tok)
        rel = next((r for r in (alle if isinstance(alle, list) else []) if r.get('tag_name') == f'v{fassung}'), None)
    # Ein veröffentlichtes Release bleibt, wie es ist (#382): Der Abgleich
    # nach GitHub legt nur fehlende Dateien an und ersetzt nichts – ein
    # neuer Text oder eine neue SHA256SUMS.txt liefen dort auseinander. Nur
    # mit --nachtragen kommen fehlende Pakete dazu (3.47.0: Linux und
    # Windows nach Mac und Server).
    veroeffentlicht = rel is not None and not rel.get('draft', True)
    if veroeffentlicht and not getattr(args, 'nachtragen', False):
        sys.exit('Das Release ist schon veröffentlicht – nichts geändert. '
                 'Fehlende Pakete nur mit --nachtragen.')
    lauf(['bash','tool/pruefe_repository_datenschutz.sh'])
    lauf(['git','push','origin','main'])
    lauf(['bash','tool/pruefe_repository_datenschutz.sh'])
    lauf(['git','push','origin',f'v{fassung}'])
    if rel is None:
        st, rel = gitea(z, '/releases', json.dumps({'tag_name': f'v{fassung}', 'name': f'Photo Vault {fassung}', 'body': text,
                                                     'draft': True, 'prerelease': False}).encode(), 'POST',
                        {'Content-Type': 'application/json'}, tok)
        if st != 201:
            sys.exit(f'Entwurf nicht angelegt: {st} {rel}')
    elif not veroeffentlicht:
        gitea(z, f'/releases/{rel["id"]}', json.dumps({'body': text}).encode(), 'PATCH', {'Content-Type': 'application/json'}, tok)
    rid = rel['id']
    vorhanden = {x['name']: x for x in rel.get('assets', [])}
    # Nur, was gebaut wurde: 3.41 bis 3.44.1 gingen nur an Mac und Server.
    vorhanden_hier = release_dateien(fassung,u)
    # Was oben schon liegt, bleibt nur, wenn es dasselbe ist – nach der
    # Prüfsumme in der SHA256SUMS.txt dort, nicht nach der Grösse: Ein neu
    # gebautes Paket kann gleich gross sein. Blieb die alte Datei stehen,
    # passte sie nicht mehr zur neuen SHA256SUMS.txt (bei 3.67.1 das
    # notarisierte Mac-Paket nach dem nur signierten, #382).
    # Die Prüfsummen aus den Dateien selbst, nicht aus einer vorhandenen
    # SHA256SUMS.txt: Eine von Hand ersetzte Datei gleicher Grösse fiele
    # sonst nicht auf.
    summen(u, fassung)
    lokal = summen_lesen((u / 'SHA256SUMS.txt').read_text())
    oben = summen_lesen(_lade_anhang(vorhanden['SHA256SUMS.txt'], tok)) if 'SHA256SUMS.txt' in vorhanden else {}

    # Mit --pruefen zählt der Anhang selbst, nicht, was die SHA256SUMS.txt
    # dort über ihn sagt (#395): Meldet veroeffentlichen einen Anhang, der
    # gleich gross und richtig genannt, aber nicht die Datei von hier ist,
    # ersetzt ihn nur das. Bis 3.67.4 half dann nur Löschen von Hand.
    def gleich(n):
        if not (vorhanden[n].get('size') == (u / n).stat().st_size and oben.get(n) and oben.get(n) == lokal.get(n)):
            return False
        if not getattr(args, 'pruefen', False):
            return True
        try:
            return _sha256_anhang(vorhanden[n], tok) == lokal.get(n)
        except AnhangNichtGeladen as e:
            sys.exit(f'{n} liess sich zum Prüfen nicht laden ({e}) – nichts geändert.')

    anders = [n for n in vorhanden_hier if n in vorhanden and not gleich(n)]
    # Pakete im Entwurf, die hier fehlen, stammen von einem früheren Bau,
    # der nicht mehr gilt – etwa ein nur signiertes Mac-Paket, nachdem der
    # Neubau scheiterte und es weggeräumt hat.
    veraltet = [n for n in dateien(fassung) if n in vorhanden and n not in vorhanden_hier]
    if veroeffentlicht and (anders or veraltet):
        sys.exit(f'Im veröffentlichten Release liegt anderes als hier: {", ".join(anders + veraltet)}. '
                 'Nichts geändert – dafür eine neue Fassung bauen.')
    for name in veraltet:
        st, a = gitea(z, f'/releases/{rid}/assets/{vorhanden[name]["id"]}', methode='DELETE', tok=tok)
        if st not in (200, 204):
            sys.exit(f'{name} liess sich nicht entfernen: {st} {a}')
        print(name, 'entfernt (hier nicht mehr gebaut)')
    for name in vorhanden_hier + ['SHA256SUMS.txt']:
        if name in vorhanden:
            if name != 'SHA256SUMS.txt' and name not in anders:
                continue
            if name == 'SHA256SUMS.txt' and oben == lokal:
                continue
            st, a = gitea(z, f'/releases/{rid}/assets/{vorhanden[name]["id"]}', methode='DELETE', tok=tok)
            if st not in (200, 204):
                sys.exit(f'{name} liess sich nicht ersetzen: {st} {a}')
        g = uuid.uuid4().hex
        daten = (f'--{g}\r\nContent-Disposition: form-data; name="attachment"; filename="{name}"\r\n'
                 f'Content-Type: application/octet-stream\r\n\r\n').encode() + (u / name).read_bytes() + f'\r\n--{g}--\r\n'.encode()
        st, a = _lade_hoch(z, rid, name, daten, {'Content-Type': f'multipart/form-data; boundary={g}'}, tok,
                           groesse=(u / name).stat().st_size)
        print(name, st, a.get('size') if isinstance(a, dict) else a)
        if st != 201:
            if name == 'SHA256SUMS.txt' and veroeffentlicht:
                # Die alte ist schon gelöscht (#396).
                sys.exit('SHA256SUMS.txt kam nicht an – im veröffentlichten Release fehlt jetzt die Liste. '
                         f'Gleich noch einmal: release.py entwurf {fassung} --nachtragen')
            sys.exit(f'{name} kam nicht an: {st}')
    _, rel = gitea(z, f'/releases/{rid}', tok=tok)
    print('Freigabe', rel['id'], 'Entwurf' if rel.get('draft') else 'veröffentlicht', len(rel['assets']), 'Dateien')
    if veroeffentlicht:
        print('Pakete und SHA256SUMS.txt des GitHub-Releases bei Bedarf von Hand aktualisieren.')


# --- einspielen -------------------------------------------------------------------


def einspielen(args):
    z = ziele()
    fassung = args.fassung
    # Nichts anlegen: Eine vertippte Fassung liess sonst leere Ordner auf
    # dem Schreibtisch und neben den Worktrees zurück (#396).
    u = upload_ordner(z, fassung, anlegen=False)
    if not u.is_dir():
        sys.exit(f'Kein Upload-Ordner {u.name} – ist {fassung} gebaut?')
    a = arbeitsordner(fassung, z, anlegen=False)
    from installation import FernInstallation, MacInstallation, Installationsfehler
    try:
        # Auch hier: Wurde mit einem älteren Skript oder mit --nur gebaut,
        # fehlt der Ordner sonst (#286).
        if args.linux:
            fern_bereitlegen(z, 'linux', fassung, u)
            print(json.dumps(FernInstallation('linux', z['linux_ssh'], fassung).ausfuehren(), ensure_ascii=False))
        if args.windows:
            fern_bereitlegen(z, 'windows', fassung, u)
            print(json.dumps(FernInstallation('windows', z['windows_ssh'], fassung).ausfuehren(), ensure_ascii=False))
        if args.mac:
            print(json.dumps(MacInstallation(fassung, u / 'Photo Vault.app', Path('/Applications/Photo Vault.app'),
                  Path.home() / 'Desktop/PhotoVault-Vorversionen.noindex').ausfuehren(), ensure_ascii=False))
    except Installationsfehler as e:
        sys.exit(str(e))
    if args.server:
        antwort = input(f'Produktivserver auf {fassung} bringen? Zum Bestätigen „ja“ eingeben: ').strip().lower()
        if antwort != 'ja':
            sys.exit('Server nicht angefasst.')
        from server_wartung import aktualisieren
        paket = a / 'paket-openvino' / 'photo-vault-server-linux-amd64-openvino.tar.gz'
        aktualisieren(z, paket, fassung)


# --- veroeffentlichen -------------------------------------------------------------

def veroeffentlichen(args):
    z = ziele()
    fassung = args.fassung
    u = upload_ordner(z, fassung, anlegen=False)
    pruefe_releasepakete(fassung,u)
    tok = token(z)
    _, alle = gitea(z, '/releases?draft=true&limit=30', tok=tok)
    rel = next((r for r in (alle if isinstance(alle, list) else []) if r.get('tag_name') == f'v{fassung}'), None)
    if rel is None:
        sys.exit('Kein Entwurf zu dieser Fassung.')
    # Nichts freigeben, dem ein Paket fehlt, das nur halb oben liegt, das
    # anders ist als hier oder das hier gar nicht mehr gebaut ist (#382) –
    # nach der Prüfsumme, nicht nur nach der Grösse.
    u = upload_ordner(z, fassung, anlegen=False)
    anhaenge = {x['name']: x for x in rel.get('assets', [])}
    lokal = {n: _sha256(u / n) for n in release_dateien(fassung,u)}
    oben = summen_lesen(_lade_anhang(anhaenge['SHA256SUMS.txt'], tok)) if 'SHA256SUMS.txt' in anhaenge else {}
    fehler = []
    if not oben:
        fehler.append('SHA256SUMS.txt fehlt im Entwurf oder liess sich nicht lesen')
    for n, h in lokal.items():
        if anhaenge.get(n, {}).get('size') != (u / n).stat().st_size:
            fehler.append(f'{n}: fehlt im Entwurf oder ist anders gross')
        elif oben and oben.get(n) != h:
            fehler.append(f'{n}: Prüfsumme im Entwurf passt nicht')
        else:
            try:
                ist = _sha256_anhang(anhaenge[n], tok)
            except AnhangNichtGeladen as e:
                fehler.append(f'{n}: liess sich zum Prüfen nicht laden ({e})')
                continue
            if ist != h:
                # Gleich gross und richtig in der SHA256SUMS.txt genannt,
                # aber der Anhang selbst kann trotzdem ein anderer sein
                # (#392).
                fehler.append(f'{n}: der hochgeladene Anhang ist nicht die Datei von hier – '
                              f'„release.py entwurf {fassung} --pruefen“ lädt ihn neu hoch')
    for n in anhaenge:
        if n != 'SHA256SUMS.txt' and n not in lokal:
            fehler.append(f'{n}: liegt im Entwurf, aber nicht hier')
    if fehler:
        sys.exit('Nicht veröffentlicht:\n' + '\n'.join(fehler))
    st, r = gitea(z, f'/releases/{rel["id"]}', json.dumps({'draft': False}).encode(), 'PATCH', {'Content-Type': 'application/json'}, tok)
    print('Freigabe', r['id'], 'Entwurf' if r['draft'] else 'veröffentlicht', len(r['assets']), 'Dateien')
    print(f'GitHub-Release v{fassung} für Photovault anschließend von Hand anlegen.')


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
    en = sub.add_parser('entwurf')
    en.add_argument('fassung')
    en.add_argument('--nachtragen', action='store_true',
                    help='fehlende Pakete in ein schon veröffentlichtes Release legen')
    en.add_argument('--pruefen', action='store_true',
                    help='vorhandene Anhänge ganz laden und ersetzen, was nicht die Datei von hier ist')
    sub.add_parser('veroeffentlichen').add_argument('fassung')
    e = sub.add_parser('einspielen')
    e.add_argument('fassung')
    for ziel in ['linux', 'windows', 'mac', 'server']:
        e.add_argument(f'--{ziel}', action='store_true')
    args = p.parse_args()
    if not re.fullmatch(r'[0-9]{1,4}\.[0-9]{1,4}\.[0-9]{1,4}',args.fassung):
        p.error('Version muss aus drei Zahlen bestehen.')
    {'vorbereiten': vorbereiten, 'bauen': bauen, 'entwurf': entwurf,
     'einspielen': einspielen, 'veroeffentlichen': veroeffentlichen}[args.schritt](args)


if __name__ == '__main__':
    main()
