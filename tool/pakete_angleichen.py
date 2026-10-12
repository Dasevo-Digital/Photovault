#!/usr/bin/env python3
"""Gibt Kern und Server dieselben Paketfassungen wie der App.

Kern (packages/kern) und Server (packages/server) lösen ihre Pakete selbst
auf, damit sich der Server ohne Flutter bauen lässt. Dabei kann pub andere
Fassungen wählen als für die App – und eine andere Fassung von
`package:image` verkleinert ein Bild ein wenig anders. Am 12.10.2026
gemessen: CLIP-Einbettung um bis zu 1e-5 verschoben, Florence schrieb
einen anderen Satz. Ergebnisse vom Server wären dann nicht mehr dieselben
wie aus der App.

Dieses Skript übernimmt für jedes Paket, das Kern oder Server zur Laufzeit
benutzen und das auch die App hat, deren Fassung (samt Prüfsumme) in die
eigene Sperrdatei und ruft danach `dart pub get`. Die Werkzeuge zum Bauen
und Prüfen (build_runner, drift_dev, test und was sie mitbringen) bleiben
bei ihren eigenen Fassungen: Sie rechnen nichts, und `package:test` braucht
neuere als das `flutter_test` der App. test/pakete_gleich_test.dart prüft,
dass es so bleibt.

    python3 tool/pakete_angleichen.py
"""
import json
import re
import subprocess
import sys
from pathlib import Path

WURZEL = Path(__file__).resolve().parent.parent
ZIELE = [WURZEL / 'packages' / 'kern', WURZEL / 'packages' / 'server']


def bloecke(text):
    """Die Einträge unter `packages:` als {name: [zeilen]}."""
    zeilen = text.split('\n')
    anfang = zeilen.index('packages:') + 1
    aus, name = {}, None
    for i in range(anfang, len(zeilen)):
        z = zeilen[i]
        if z and not z.startswith(' '):
            break
        m = re.match(r'^  ([A-Za-z0-9_]+):$', z)
        if m:
            name = m.group(1)
            aus[name] = []
        elif name is not None:
            aus[name].append(z)
    return aus


def laufzeitpakete(ziel: Path) -> set:
    """Was das Paket zur Laufzeit braucht: seine Abhängigkeiten ohne die
    fürs Entwickeln, mit allem, was sie mitbringen."""
    r = subprocess.run(['dart', 'pub', 'deps', '--json'], cwd=ziel,
                       capture_output=True, text=True, check=True)
    d = json.loads(r.stdout)
    pakete = {p['name']: p for p in d['packages']}
    wurzel = next(p for p in d['packages'] if p['kind'] == 'root')
    offen, gesehen = list(wurzel['directDependencies']), set()
    while offen:
        n = offen.pop()
        if n in gesehen or n not in pakete:
            continue
        gesehen.add(n)
        offen.extend(pakete[n].get('dependencies', []))
    return gesehen


def gleiche_an(ziel: Path, app: dict) -> int:
    laufzeit = laufzeitpakete(ziel)
    datei = ziel / 'pubspec.lock'
    text = datei.read_text()
    eigene = bloecke(text)
    geaendert = 0
    for name, zeilen in eigene.items():
        if name not in laufzeit:
            continue
        quelle = app.get(name)
        if quelle is None or not any('source: hosted' in z for z in quelle):
            continue
        if not any('source: hosted' in z for z in zeilen):
            continue
        # Die Art der Abhängigkeit (direkt oder mitgezogen) bleibt die
        # eigene, Beschreibung, Quelle und Fassung kommen von der App.
        art = [z for z in zeilen if z.strip().startswith('dependency:')]
        neu = art + [z for z in quelle if not z.strip().startswith('dependency:')]
        if neu != zeilen:
            alt = '  %s:\n%s' % (name, '\n'.join(zeilen))
            ersatz = '  %s:\n%s' % (name, '\n'.join(neu))
            text = text.replace(alt, ersatz, 1)
            geaendert += 1
    datei.write_text(text)
    return geaendert


def main():
    app = bloecke((WURZEL / 'pubspec.lock').read_text())
    for ziel in ZIELE:
        n = gleiche_an(ziel, app)
        print(f'{ziel.name}: {n} Pakete auf die Fassung der App gesetzt')
        r = subprocess.run(['dart', 'pub', 'get'], cwd=ziel,
                           capture_output=True, text=True)
        if r.returncode != 0:
            print(r.stdout[-2000:], r.stderr[-2000:], file=sys.stderr)
            sys.exit(f'{ziel.name}: dart pub get scheiterte')


if __name__ == '__main__':
    main()
