# Photo Vault Server

Der Server zu Photo Vault (Issue #86): eine Bibliothek ohne Oberfläche,
die Uploads annimmt, auswertet und an Desktop und Handy ausliefert. Er
benutzt denselben Kern wie die App (`packages/kern`) und dieselbe ONNX
Runtime, damit Ergebnisse gleich sind, egal wo sie gerechnet werden.

**Stand: Stufe 1.** Es gibt noch keine Konten: Zugang hat, wer den
Schlüssel aus `zugang.txt` kennt. Konten mit Passwort und TOTP folgen in
Stufe 1a (#100). Bis dahin den Server nicht ins Netz stellen.

## Was er tut

- Nimmt Dateien in Stücken an (tus 1.0.0) und importiert sie wie die App:
  Miniatur, Vorschau, Aufnahmedaten, Dubletten über die Prüfsumme.
- Bearbeitet jede neue Aufnahme nach wie die App: Live Photos und Motion
  Photos zusammenführen, Kameravorgaben und Regeln anwenden, Ortsnamen
  eintragen (mit GeoNames-Daten, siehe unten).
- Wertet danach aus, in derselben Reihenfolge wie die Hintergrundanalyse
  der App: Bildanalyse (Schärfe, Gesichter, CLIP), Texterkennung,
  Schlagwörter, Bildbeschreibung, Spracherkennung in Videos,
  Wiedererkennung benannter Personen. Gesammelt: Ein Durchgang beginnt
  zehn Sekunden nach der letzten neuen Datei, nicht nach jeder einzelnen.
  Modelle werden erst geladen, wenn es etwas für sie gibt, und nach einer
  Minute ohne Arbeit wieder freigegeben.

## Einstellungen

Alles über Umgebungsvariablen, gleich ob Docker, systemd oder von Hand:

| Variable         | Vorgabe               |                                     |
|------------------|-----------------------|-------------------------------------|
| `PV_DATEN`       | `./daten`             | Bibliotheken, Uploads, Zugang       |
| `PV_ADRESSE`     | `127.0.0.1`           | worauf gehört wird                  |
| `PV_PORT`        | `8790`                |                                     |
| `PV_MODELLE`     | `<PV_DATEN>/modelle`  | die KI-Modelle                      |
| `PV_ONNXRUNTIME` | im Bündel `lib/`      | `libonnxruntime.so` für die Modelle |
| `PV_GEODATEN`    | `<PV_DATEN>/geodaten` | GeoNames für Ortsnamen              |

Beim ersten Start entsteht `<PV_DATEN>/zugang.txt` mit einem zufälligen
Schlüssel; jede Anfrage braucht ihn als `Authorization: Bearer …`.

**Modelle:** dieselben Dateien wie in der App. Am einfachsten den Inhalt
des Modellordners der App (Einstellungen → KI-Modelle) nach `PV_MODELLE`
kopieren. Fehlt ein Modell, überspringt der Server die Auswertung, die es
braucht; ohne ONNX Runtime alle, die ein Modell brauchen.

**Ortsnamen:** `cities1000.txt`, `admin1CodesASCII.txt` und
`countryInfo.txt` von GeoNames (dieselben Dateien wie in der App) nach
`PV_GEODATEN`. Ohne sie bleiben die Ortsnamen leer, die Koordinaten nicht.

## Docker

Das Bild bringt alles mit: den Server, die ONNX Runtime 1.28.3 und die
Werkzeuge für HEIC, RAW und Video. Gebaut wird vom Wurzelordner des Repos
aus, für amd64 und arm64:

```sh
docker buildx build -f packages/server/Dockerfile \
  --platform linux/amd64,linux/arm64 -t photo-vault-server .
```

Starten, die Daten in einem eigenen Volume, nur auf dem eigenen Rechner
erreichbar (davor gehört der Reverse Proxy):

```sh
docker run -d --name photo-vault -p 127.0.0.1:8790:8790 \
  -v photo-vault-daten:/daten photo-vault-server
docker exec photo-vault cat /daten/zugang.txt
```

Der Server läuft im Bild als Benutzer `photovault` (UID 8790). Wer statt
eines Volumes einen Ordner einbindet, gibt ihn diesem Benutzer
(`chown -R 8790:8790 …`). Die Gesundheitsprüfung fragt `/api/v1/zustand`.

## Einzeldatei mit systemd

Dasselbe Programm als Bündel (`bin/`, `lib/` mit SQLite und ONNX Runtime,
`systemd/`), je Plattform ein tar.gz:

```sh
docker buildx build -f packages/server/Dockerfile --target paket \
  --platform linux/amd64,linux/arm64 --output type=local,dest=aus .
```

Auf dem Server (Debian 12 und neuer, Ubuntu 22.04 und neuer):

```sh
sudo apt install ffmpeg libheif-examples libheif-plugin-libde265 libraw-bin
sudo tar -xzf photo-vault-server-linux-amd64.tar.gz -C /opt
sudo useradd --system --user-group --home-dir /var/lib/photo-vault-server \
  --shell /usr/sbin/nologin photovault
sudo cp /opt/photo-vault-server/systemd/photo-vault-server.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now photo-vault-server
sudo cat /var/lib/photo-vault-server/zugang.txt
```

Die Daten liegen unter `/var/lib/photo-vault-server`. Eigene Einstellungen
gehören nach `/etc/photo-vault-server.env` (eine `NAME=wert`-Zeile je
Variable). Gibt es `libheif-plugin-libde265` auf einer älteren Fassung
nicht, steckt der HEVC-Dekoder noch in `libheif1` selbst; das Programm
heisst dort `heif-convert` statt `heif-dec`, der Server kennt beide Namen.

## Von Hand

```sh
cd packages/server
dart pub get
PV_DATEN=/pfad/zu/daten PV_ONNXRUNTIME=/pfad/zu/libonnxruntime.so.1.28.3 \
  dart run bin/photo_vault_server.dart
```

Bilder, Videos und Ton liest der Server über dieselben Werkzeuge wie die
App unter Linux: `ffmpeg`/`ffprobe`, `heif-dec` (libheif mit
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
| `GET /auswertung` | ob ausgewertet wird, Stufe und Fortschritt |
| `POST /auswertung` | einen Durchgang sofort anstossen |

Beim Hochladen gehören zu `Upload-Metadata` `filename` und `geaendert`
(Änderungszeit der Datei in Millisekunden – der letzte Anhalt fürs Datum,
wenn die Datei keines trägt). Die Antwort auf das letzte Stück trägt
`Pv-Ausgang` und `Pv-Aufnahme`.

## Prüfen

```sh
dart analyze
dart test
```

`test/onnx_ffi_test.dart` läuft nur mit `PV_ONNXRUNTIME`. Ob die Modelle
über FFI dasselbe rechnen wie die App über das Plugin, prüft
`tool/abdruck_ffi.dart` (Aufruf im Kopf der Datei).
