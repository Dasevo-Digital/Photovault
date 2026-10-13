# Photo Vault Server

Der Server zu Photo Vault (Issue #86): eine Bibliothek ohne Oberfläche,
die Uploads annimmt, auswertet und an Desktop und Handy ausliefert. Er
benutzt denselben Kern wie die App (`packages/kern`) und dieselbe ONNX
Runtime, damit Ergebnisse gleich sind, egal wo sie gerechnet werden.

**Stand: Stufe 1a.** Konten mit Passwort und TOTP, je Konto eine eigene
Bibliothek, Geräte einzeln abmeldbar, optional OIDC. Teilen zwischen
Konten folgt in Stufe 6.

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

- Jedes Konto hat seine eigene Bibliothek – eine eigene Datenbank in
  einem eigenen Ordner, nicht eine gemeinsame, die filtert. Gerechnet wird
  immer nur in einer Bibliothek zugleich; die Modelle teilen sich alle.

## Einstellungen

Alles über Umgebungsvariablen, gleich ob Docker, systemd oder von Hand:

| Variable                  | Vorgabe               |                                         |
|---------------------------|-----------------------|-----------------------------------------|
| `PV_DATEN`                | `./daten`             | Konten, Bibliotheken, Uploads           |
| `PV_ADRESSE`              | `127.0.0.1`           | worauf gehört wird                      |
| `PV_PORT`                 | `8790`                |                                         |
| `PV_MODELLE`              | `<PV_DATEN>/modelle`  | die KI-Modelle                          |
| `PV_ONNXRUNTIME`          | im Bündel `lib/`      | `libonnxruntime.so` für die Modelle     |
| `PV_GEODATEN`             | `<PV_DATEN>/geodaten` | GeoNames für Ortsnamen                  |
| `PV_TOTP`                 | `pflicht`             | `frei`: TOTP nur, wer es einrichtet     |
| `PV_PROXY`                | –                     | vertraute Proxys, siehe unten           |
| `PV_OEFFENTLICH`          | –                     | Adresse von aussen, z. B. `https://fotos.example.de` (für OIDC) |
| `PV_OIDC_AUSSTELLER`      | –                     | `issuer` des OIDC-Anbieters             |
| `PV_OIDC_CLIENT`          | –                     | Client-ID                               |
| `PV_OIDC_GEHEIMNIS`       | –                     | Client-Geheimnis                        |
| `PV_OIDC_GEHEIMNIS_DATEI` | –                     | … oder aus einer Datei (Docker Secret)  |

In `PV_DATEN` liegen `server.sqlite` (Konten und Geräte),
`server.schluessel` (verschlüsselt die TOTP-Geheimnisse; beide nur für
den Besitzer lesbar), `bibliotheken/<Konto>/` und `eingang/<Konto>/`.
Gesichert gehört der ganze Ordner. Fehlt der Schlüssel, ist nichts
verloren ausser den TOTP-Einrichtungen (`konto totp-zuruecksetzen`).

**Modelle:** dieselben Dateien wie in der App. Am einfachsten den Inhalt
des Modellordners der App (Einstellungen → KI-Modelle) nach `PV_MODELLE`
kopieren. Fehlt ein Modell, überspringt der Server die Auswertung, die es
braucht; ohne ONNX Runtime alle, die ein Modell brauchen.

**Ortsnamen:** `cities1000.txt`, `admin1CodesASCII.txt` und
`countryInfo.txt` von GeoNames (dieselben Dateien wie in der App) nach
`PV_GEODATEN`. Ohne sie bleiben die Ortsnamen leer, die Koordinaten nicht.

## Konten

Konten entstehen auf der Kommandozeile – das erste muss es geben, bevor
sich jemand anmelden kann, und wer auf der Maschine Befehle ausführen
darf, darf ohnehin alles:

```sh
photo_vault_server konto anlegen NAME [--verwalter] [--totp-spaeter]
photo_vault_server konto liste
photo_vault_server konto passwort NAME            # neu setzen, alle Geräte ab
photo_vault_server konto totp-zuruecksetzen NAME  # Telefon verloren
photo_vault_server konto entsperren NAME          # nach Fehlversuchen
photo_vault_server konto geraete NAME
photo_vault_server konto abmelden NAME (GERÄT | --alle)
photo_vault_server konto oidc-loesen NAME
```

`konto anlegen` fragt das Passwort (mindestens 12 Zeichen), zeigt einen
QR-Code für die Authenticator-App und nimmt den ersten Code entgegen;
danach stehen dort zehn Wiederherstellungscodes, je einer für eine
Anmeldung ohne Telefon. Mit `--totp-spaeter` richtet die erste Anmeldung
TOTP ein. Das erste Konto ist Verwalter; gab es aus der Zeit vor den
Konten eine Bibliothek (`bibliotheken/standard`), gehört sie ihm.

**Anmelden** in zwei Schritten: Name und Passwort, dann der Code. Das
Gerät bekommt ein Token, das es bei jeder Anfrage als
`Authorization: Bearer pv1_…` mitschickt; der Server hält davon nur den
SHA-256. Ein Gerät, das 180 Tage nicht da war, ist abgemeldet.

**Bremse:** Nach fünf Fehlversuchen in Folge ist ein Name eine Minute
gesperrt, danach doppelt so lange bis höchstens eine Stunde – auch Namen,
die es nicht gibt, damit die Sperre nichts verrät. Eine Adresse mit zehn
Fehlversuchen in 15 Minuten wird abgewiesen, bevor gerechnet wird.

## Reverse Proxy und VPN

Der Server spricht nur HTTP; TLS macht der Proxy. Damit die Bremse die
Adresse des Absenders sieht und nicht die des Proxys, gehört der Proxy in
`PV_PROXY` – Adressen oder Netze, mit Komma getrennt, oder `privat` für
Heimnetz, Docker-Netze und den eigenen Rechner. `X-Forwarded-For` gilt
nur von dort.

Caddy:

```
fotos.example.de {
    reverse_proxy 127.0.0.1:8790
}
```

nginx – Uploads kommen in Stücken; ein Stück darf so gross sein wie
`client_max_body_size`:

```nginx
server {
    listen 443 ssl;
    server_name fotos.example.de;
    client_max_body_size 64m;
    proxy_request_buffering off;
    proxy_read_timeout 300s;
    location / {
        proxy_pass http://127.0.0.1:8790;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

Läuft der Server in Docker, kommt die Verbindung vom Docker-Netz, nicht
von 127.0.0.1: dann `PV_PROXY=privat`. Nur über VPN: `PV_ADRESSE` auf die
Adresse im VPN setzen, ohne Proxy und ohne `PV_PROXY`.

## OIDC

Optional, zusätzlich zum Passwort: Anmelden über einen eigenen Anbieter
(Authentik, Keycloak, Pocket ID …). Beim Anbieter einen vertraulichen
Client anlegen, Weiterleitung `<PV_OEFFENTLICH>/api/v1/anmelden/oidc/zurueck`,
Bereiche `openid profile`. Dann:

```sh
PV_OEFFENTLICH=https://fotos.example.de
PV_OIDC_AUSSTELLER=https://anmeldung.example.de/application/o/fotos/
PV_OIDC_CLIENT=photo-vault
PV_OIDC_GEHEIMNIS_DATEI=/run/secrets/oidc
```

Ein Konto meldet sich zuerst mit Passwort an und verknüpft dann seine
Anmeldung beim Anbieter (`POST /api/v1/konto/oidc`); danach geht es ohne
Passwort. Die Zwei-Faktor-Prüfung liegt dann beim Anbieter. Zurück zur
App führt nur ein Weg auf demselben Gerät (`http://127.0.0.1:…` oder das
Schema `photovault:`), und den Code löst nur ein, wer den Prüfer der App
kennt (PKCE) – eine untergeschobene Anmeldeadresse bringt einem Fremden
nichts.

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
  -e PV_PROXY=privat -v photo-vault-daten:/daten photo-vault-server
docker exec -it photo-vault photo_vault_server konto anlegen NAME
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
sudo -u photovault env PV_DATEN=/var/lib/photo-vault-server \
  /opt/photo-vault-server/bin/photo_vault_server konto anlegen NAME
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

## Schnittstelle (`/api/v1`, Protokoll 2)

Ohne Token gehen nur `zustand` und die Wege der Anmeldung.

| Anfrage | |
|---|---|
| `GET /zustand` | Lebenszeichen; ob TOTP Pflicht und OIDC eingerichtet ist |
| `POST /anmelden` | `{name, passwort, geraet}` → `{token}` oder `{schritt: totp \| totp_einrichten, vorgang, …}` |
| `POST /anmelden/totp` | `{vorgang, code}` – Code oder Wiederherstellungscode → `{token, geraet}` |
| `GET /anmelden/oidc?geraet&rueckweg&pruefwert&zustand` | im Browser öffnen: weiter zum Anbieter |
| `POST /anmelden/oidc/einloesen` | `{code, pruefer}` → `{token}` (Verknüpfen: mit Token → `{verknuepft}`) |
| `POST /abmelden` | dieses Gerät abmelden |
| `GET /konto` | Name, TOTP, übrige Wiederherstellungscodes, OIDC |
| `POST /konto/passwort` | `{alt, neu, code, andereAbmelden?}` |
| `POST /konto/wiederherstellungscodes` | `{code}` → zehn neue |
| `POST /konto/oidc` | `{rueckweg, pruefwert}` → `{adresse}` zum Verknüpfen |
| `GET /geraete`, `DELETE /geraete/<id>` | angemeldete Geräte, eines abmelden |
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

`test/oidc_test.dart` spielt den Anbieter selbst. `test/onnx_ffi_test.dart`
läuft nur mit `PV_ONNXRUNTIME`. Ob die Modelle
über FFI dasselbe rechnen wie die App über das Plugin, prüft
`tool/abdruck_ffi.dart` (Aufruf im Kopf der Datei).
