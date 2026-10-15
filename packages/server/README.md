# Photo Vault Server

Der Server zu Photo Vault (Issue #86): eine Bibliothek ohne Oberfläche,
die Uploads annimmt, auswertet und an Desktop und Handy ausliefert. Er
benutzt denselben Kern wie die App (`packages/kern`) und dieselbe ONNX
Runtime, damit Ergebnisse gleich sind, egal wo sie gerechnet werden.

**Stand: Stufe 2.** Konten mit Passwort und TOTP, je Konto eine eigene
Bibliothek, Geräte einzeln abmeldbar, optional OIDC. Die Desktop-App
verbindet sich (Einstellungen → Server): Sie hält eine Kopie der
Bibliothek, gleicht sie ab und arbeitet offline weiter; eine bestehende
Bibliothek zieht auf Wunsch auf den Server um. Teilen zwischen Konten
folgt in Stufe 6.

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
| `PV_BESCHLEUNIGER`        | `cpu`                 | `openvino`, `cuda`, siehe Beschleuniger |
| `PV_SELBST_RECHNEN`       | `alles`               | `nichts` oder Stufen, siehe Rechenhilfe |
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

## Verbundene Geräte

Ein Gerät hält eine Kopie der Bibliothek (dasselbe Schema wie die App) und
folgt den Änderungen des Servers. **Der Server ist der einzige
Schreiber:** Das Gerät schickt seine Änderungen als Befehle, wendet sie
vorweg selbst an und gleicht danach mit dem Stand des Servers ab – auch
nach Tagen ohne Verbindung.

- Jede Bibliothek schreibt mit, welche Zeile sich ändert
  (`pv_aenderungen`, über Trigger). Ein Gerät holt die Änderungen seit
  seinem Stand ab, mit Long-Poll bis 30 Sekunden.
- Abgeglichen wird alles ausser dem, was nur auf einem Rechner gilt
  (Sicherungen, Aufträge, Ansicht, PIN und Tresorschlüssel).
- Dateien kommen bei Bedarf (`/dateien/<pfad>`); Miniaturen und
  Gesichtsausschnitte lädt die App im Hintergrund vor.
- Was in der Kopie Dateien schreiben würde (Sperren, Entwickeln,
  endgültig löschen, Videoschnitt, Restaurieren), geht verbunden noch
  nicht; die App sagt es. Importieren lädt zum Server hoch, und die
  Auswertung läuft dort.

**Umzug:** Eine Bibliothek, die bisher nur auf einem Rechner lag, zieht
mit allen Dateien in eine leere Bibliothek des Servers (Einstellungen →
Server → „Diese Bibliothek auf den Server umziehen“). Die leere Bibliothek
wird dabei beiseitegelegt (`bibliotheken/<Konto>.vor-umzug-<Zeit>`), nicht
gelöscht; ein unterbrochener Umzug setzt fort.

## Konten

**Das erste Konto entsteht in der App.** Hat der Server noch keines,
bietet die Desktop- oder Handy-App beim Verbinden an, es mit dem
eingegebenen Namen und Passwort anzulegen; es wird Verwalter, danach
folgt die Einrichtung von TOTP wie bei jeder Anmeldung. Das geht nur,
solange es kein Konto gibt, und nur aus dem Heimnetz (private Adressen,
auch über VPN) – nicht über einen Proxy, dem der Server nicht traut, und
nicht von aussen: Wer den Server zuerst erreicht, bekommt ihn.

**Weitere Konten legt ein Verwalter in der App an** (Desktop:
Einstellungen → Server → Konten verwalten; Handy: Konto → Konten
verwalten). Dort setzt er auch Passwörter neu, setzt TOTP zurück,
entsperrt und entfernt Konten. Ein entferntes Konto verliert seine Geräte;
seine Bibliothek legt der Server beiseite
(`bibliotheken/<Konto>.entfernt-<Zeit>`), gelöscht wird sie nur von Hand.
Das eigene Konto ändert jeder für sich.

Auf der Kommandozeile geht dasselbe – auch das erste Konto, und wer auf
der Maschine Befehle ausführen darf, darf ohnehin alles:

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

## Beschleuniger

Die Modelle rechnen auf der CPU, solange `PV_BESCHLEUNIGER` nichts anderes
sagt:

| Wert | |
|---|---|
| `openvino` | Intel-Grafik über OpenVINO (`openvino:NPU`, `openvino:CPU`, `openvino:GPU.1` … für andere Geräte) |
| `cuda`, `cuda:1` | NVIDIA über CUDA (braucht eine ONNX Runtime mit CUDA und die CUDA-Bibliotheken) |
| `coreml` | nur zum Prüfen auf einem Mac |

**Jedes Modell besteht erst eine Gegenprobe.** Seine ersten drei Läufe
rechnen auf dem Beschleuniger und auf der CPU; nur wenn die Ausgaben
übereinstimmen (Kosinus ≥ 0,9999, Abweichung ≤ 1 %) **und** der
Beschleuniger im besten Lauf nicht langsamer ist (den ersten, in dem er
oft noch übersetzt, nicht gezählt), übernimmt er. Sonst bleibt das Modell
auf der CPU. `GET /api/v1/auswertung` zeigt unter `beschleuniger`, welche
Modelle geprüft, noch in Prüfung oder verworfen sind (mit Grund), und
unter `tempo` die Millisekunden je Lauf auf beiden Seiten. Jedes Ergebnis
vermerkt in der Bibliothek, mit welchem Modell, wo und worauf es gerechnet
wurde.

**Gemessen auf einer Intel Iris Xe** (i9-12900HK, Container mit vier
Kernen und 4 GiB): CLIP rechnet auf der Grafik 30 statt 50 ms, die
Gesichtserkennung 6 statt 10 ms – die Ergebnisse sind dieselben wie auf
der CPU. Texterkennung, Augenprüfung und die Bildbeschreibung sind dort
langsamer oder laden nicht und bleiben auf der CPU. Weil die
Bildbeschreibung den grössten Teil der Zeit braucht, war ein ganzer
Durchgang über 30 Bilder mit der Grafik nur 3 % schneller (100 statt
103 s) und brauchte 1,5 GB mehr Speicher. **Auf einer solchen Grafik ist
die CPU die bessere Wahl** – zumal der Server dann mit derselben Fassung
der ONNX Runtime rechnet wie die App.

**Intel-Grafik mit Docker:** Das Bild mit OpenVINO baut ein eigenes Ziel
(nur amd64):

```sh
docker buildx build -f packages/server/Dockerfile --target openvino \
  --platform linux/amd64 -t photo-vault-server:openvino .
docker run -d --name photo-vault -p 127.0.0.1:8790:8790 \
  --device /dev/dri --group-add "$(stat -c %g /dev/dri/renderD128)" \
  -e PV_PROXY=privat -v photo-vault-daten:/daten photo-vault-server:openvino
```

Es bringt Intels Bau der ONNX Runtime mit OpenVINO mit – den gibt es fertig
nur bis Fassung 1.24.1, die App rechnet mit 1.28.3. Der Server sagt das
beim Start; auf der CPU können Ergebnisse deshalb minimal anders ausfallen
als in der App. OpenVINO übersetzt die Modelle für die Grafik beim ersten
Laden und legt sie unter `<PV_DATEN>/beschleuniger` ab.

**Intel-Grafik mit systemd:** Das Bündel mit OpenVINO baut das Ziel
`paket-openvino` (nur amd64):

```sh
docker buildx build -f packages/server/Dockerfile --target paket-openvino \
  --platform linux/amd64 --output type=local,dest=aus .
```

Eingerichtet wird es wie unter „Einzeldatei mit systemd“, dazu der
Treiber (Ubuntu 26.04; Debian hat ihn nicht), die Gruppe `render` und
eine Ergänzung der Einheit, die dem Server den Render-Knoten zeigt:

```sh
sudo apt install intel-opencl-icd libze-intel-gpu1 libze1
sudo usermod -aG render photovault
sudo mkdir -p /etc/systemd/system/photo-vault-server.service.d
sudo cp /opt/photo-vault-server/systemd/intel-grafik.conf \
  /etc/systemd/system/photo-vault-server.service.d/
```

In `/etc/photo-vault-server.env`:

```
PV_ONNXRUNTIME=/opt/photo-vault-server/lib/openvino/libonnxruntime.so.1.24.1
PV_BESCHLEUNIGER=openvino
```

In einem LXC-Container unter Proxmox reicht der Wirt den Render-Knoten
durch – als `root` auf dem Wirt, mit der Kennung der Gruppe `render` im
Container (`getent group render`, unter Ubuntu 26.04 meist 991):

```sh
pct set <ID> -dev0 /dev/dri/renderD128,gid=991,mode=0660
```

**Die Bildbeschreibung ist empfindlich:** Sie wählt Wort für Wort das
wahrscheinlichste nächste, und schon die Rundung einer anderen Fassung der
ONNX Runtime oder eines anderen Prozessors kann ein Wort kippen – danach
geht der Satz anders weiter. Gemessen an zehn Bildern: Schärfe, CLIP,
Texterkennung und Gesichter waren zwischen Linux und macOS, 1.24.1 und
1.28.3 gleich, die Beschreibung in sechs bis neun Fällen anders
formuliert. Das gilt auch für die Rechenhilfe.

## Rechenhilfe

Ein verbundener Rechner kann für den Server mitrechnen (App:
Einstellungen → Server → „Für den Server mitrechnen“). Solange die App
offen ist, holt er Aufträge für Bildanalyse, Texterkennung und
Bildbeschreibung, rechnet sie mit seinen Modellen und schickt die
Ergebnisse zurück; eingetragen wird auf dem Server, nach denselben Regeln
wie bei seinen eigenen Läufen. Spracherkennung bleibt beim Server.

- **Nie doppelt:** Der Server vergibt jede Aufnahme je Art an höchstens
  einen – an einen Rechner oder an sich selbst. Ein Auftrag gilt zehn
  Minuten; wird ein Rechner zugeklappt, nimmt danach ein anderer ihn.
- **Was ein Rechner nicht rechnen kann** (Datei nicht lesbar, Modell
  fehlt), gibt er zurück; dann rechnet es der Server, und kein Rechner
  bekommt es wieder, bis der Server neu startet.
- **Geprüft wird, was ankommt:** Länge und Werte der Einbettung, Lage der
  Gesichter, Grösse der Ausschnitte und Texte. Was nicht passt, lehnt der
  Server ab.
- Die Kopie auf dem Rechner wächst dabei nicht: Fehlt dort eine Datei,
  holt er sie in eine Zwischenablage und löscht sie nach dem Rechnen.
- Was auf den Ergebnissen aufbaut (Schlagwörter, Wiedererkennung),
  rechnet der Server danach selbst.
- Die Herkunft jedes Ergebnisses nennt den Rechner (z. B.
  `Rechner (macOS)`) statt `Server (Linux)`.

Mit `PV_SELBST_RECHNEN` rechnet der Server nur noch, was dort steht:
`nichts`, oder Stufen mit Komma, z. B.
`PV_SELBST_RECHNEN=schlagwoerter,spracherkennung,wiedererkennung` für
einen schwachen Server, dem die Rechner die Bildmodelle abnehmen. Bekannt
sind `bildanalyse`, `texterkennung`, `schlagwoerter`, `bildbeschreibung`,
`spracherkennung` und `wiedererkennung`. Was dann kein Rechner übernimmt,
bleibt offen, bis einer kommt.

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
| `POST /einrichten` | wie `/anmelden`, legt aber zuerst das erste Konto an – nur ohne Konto und aus dem Heimnetz (sonst 409 bzw. 403); `zustand` meldet dann `einrichten: true` |
| `POST /anmelden/totp` | `{vorgang, code}` – Code oder Wiederherstellungscode → `{token, geraet}` |
| `GET /anmelden/oidc?geraet&rueckweg&pruefwert&zustand` | im Browser öffnen: weiter zum Anbieter |
| `POST /anmelden/oidc/einloesen` | `{code, pruefer}` → `{token}` (Verknüpfen: mit Token → `{verknuepft}`) |
| `POST /abmelden` | dieses Gerät abmelden |
| `GET /konto` | Name, TOTP, übrige Wiederherstellungscodes, OIDC |
| `POST /konto/passwort` | `{alt, neu, code, andereAbmelden?}` |
| `POST /konto/wiederherstellungscodes` | `{code}` → zehn neue |
| `POST /konto/oidc` | `{rueckweg, pruefwert}` → `{adresse}` zum Verknüpfen |
| `GET /geraete`, `DELETE /geraete/<id>` | angemeldete Geräte, eines abmelden |
| `GET /konten`, `POST /konten` | Verwalter: alle Konten; `{name, passwort, verwalter?}` legt eines an |
| `POST /konten/<id>/passwort\|totp-zuruecksetzen\|entsperren`, `DELETE /konten/<id>` | Verwalter: für ein anderes Konto – `{neu}` meldet dessen Geräte ab; Entfernen legt die Bibliothek beiseite |
| `GET /abgleich/stand` | wie weit das Protokoll reicht |
| `GET /abgleich/aenderungen?nach=N&warten=25` | geänderte Zeilen seit N (Long-Poll) |
| `POST /abgleich/zeilen` | einzelne Zeilen, wie der Server sie sieht |
| `GET /abgleich/abzug` | die ganze Bibliothek als SQLite-Datei |
| `GET /dateien/<pfad>` | eine Datei der Bibliothek, mit `Range` |
| `POST /umzug/beginnen`, `GET /umzug/stand`, `…/umzug/hochladen` (tus), `POST /umzug/abschliessen` | Umzug einer bestehenden Bibliothek |
| `GET /bibliothek` | Schema, Zahl der Aufnahmen |
| `GET /aufnahmen?anzahl=300&nach=…` | Zeitleiste, neueste zuerst; `weiter` der Antwort ist `nach` der nächsten Seite |
| `GET /aufnahmen/<id>` | alle Angaben einer Aufnahme |
| `GET /aufnahmen/<id>/miniatur\|vorschau\|original` | die Datei, mit `Range` |
| `POST /pruefsummen` | `{pruefsummen: [SHA-256 …]}` → `{vorhanden: {pruefsumme: kennung}}` – was schon da ist (Sicherung der Kamerarolle) |
| `POST /suche/text` | `{text}` → `{vektor, text}` – Suchtext für die Bildsuche eingebettet; 404 ohne Modell |
| `POST /befehle` | Änderungen als Befehle: einzeln `{art, werte}` oder im Stapel `{befehle: [{kennung, art, werte}]}` – jede Kennung höchstens einmal |
| `POST/HEAD/PATCH/DELETE /hochladen…` | Hochladen in Stücken nach tus 1.0.0 |
| `GET /auswertung` | ob ausgewertet wird, Stufe und Fortschritt; der Beschleuniger und seine Gegenproben |
| `POST /rechnen/auftraege` | `{arten, teile?, anzahl?}` → `{auftraege: [{id, art, aufnahme, datei, teile?, deutsch?}], gueltig}` – Arbeit für einen Rechner (Rechenhilfe) |
| `POST /rechnen/ergebnis` | `{auftrag, ergebnis}` – trägt ein; 409, wenn der Auftrag abgelaufen oder fremd ist, 400 bei unbrauchbaren Werten |
| `POST /rechnen/zurueck` | `{auftrag, auslassen?}` – ohne Ergebnis zurück; mit `auslassen` rechnet es der Server |
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
