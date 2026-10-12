# Photo Vault Server

Der Server zu Photo Vault (Issue #86): eine Bibliothek ohne Oberfläche,
die Uploads annimmt, auswertet und an Desktop und Handy ausliefert. Er
benutzt denselben Kern wie die App (`packages/kern`), damit Ergebnisse
gleich sind, egal wo sie gerechnet werden.

**Stand: Stufe 1 im Aufbau.** Es gibt noch keine Konten: Zugang hat, wer
den Schlüssel aus `zugang.txt` kennt. Konten mit Passwort und TOTP folgen
in Stufe 1a (#100). Bis dahin den Server nicht ins Netz stellen.

## Starten

```sh
cd packages/server
dart pub get
PV_DATEN=/pfad/zu/daten dart run bin/photo_vault_server.dart
```

| Variable     | Vorgabe              |                                    |
|--------------|----------------------|------------------------------------|
| `PV_DATEN`   | `./daten`            | Bibliotheken, Uploads, Zugang      |
| `PV_ADRESSE` | `127.0.0.1`          | worauf gehört wird                 |
| `PV_PORT`    | `8790`               |                                    |
| `PV_MODELLE` | `<PV_DATEN>/modelle` | die KI-Modelle                     |

Beim ersten Start entsteht `<PV_DATEN>/zugang.txt` mit einem zufälligen
Schlüssel; jede Anfrage braucht ihn als `Authorization: Bearer …`.

Bilder, Videos und Ton liest der Server über dieselben Werkzeuge wie die
App unter Linux: `ffmpeg`/`ffprobe`, `heif-convert` (libheif mit
HEVC-Plugin) und `dcraw_emu`/`raw-identify` (LibRaw). Fehlen sie, gehen
JPEG, PNG und die anderen Formate, die Dart selbst liest, trotzdem.

## Schnittstelle (`/api/v1`, Protokoll 1)

| Anfrage | |
|---|---|
| `GET /zustand` | Lebenszeichen, ohne Schlüssel |
| `GET /bibliothek` | Schema, Zahl der Aufnahmen |
| `GET /aufnahmen?anzahl=300&nach=…` | Zeitleiste, neueste zuerst; `weiter` der Antwort ist `nach` der nächsten Seite |
| `GET /aufnahmen/<id>` | alle Angaben einer Aufnahme |
| `GET /aufnahmen/<id>/miniatur\|vorschau\|original` | die Datei, mit `Range` |
| `POST /befehle` | eine Änderung als Befehl `{art, werte}` (siehe `packages/kern/lib/befehle`) |
| `POST/HEAD/PATCH/DELETE /hochladen…` | Hochladen in Stücken nach tus 1.0.0 |

Beim Hochladen gehören zu `Upload-Metadata` `filename` und `geaendert`
(Änderungszeit der Datei in Millisekunden – der letzte Anhalt fürs Datum,
wenn die Datei keines trägt). Die Antwort auf das letzte Stück trägt
`Pv-Ausgang` und `Pv-Aufnahme`.

## Prüfen

```sh
dart analyze
dart test
```
