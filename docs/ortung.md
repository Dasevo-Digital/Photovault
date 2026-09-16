# Standortbestimmung: was auf welcher Plattform geht

Der Standortknopf auf der Karte („zeig mir, wo ich bin") gibt es unter
macOS und Windows, unter Linux nicht. Das ist keine Bequemlichkeit,
sondern das Ergebnis einer Messung am **25.08.2026**. Dieses Dokument hält
sie fest, damit die Frage nicht alle paar Monate neu aufgemacht wird.

## Wie alle diese Wege funktionieren

Jede Ortung ohne GPS macht dasselbe: Sie scannt die WLANs in der Nähe und
fragt eine Datenbank, wo diese Zugangspunkte stehen. **Die Genauigkeit
kommt aus der Datenbank, nicht aus dem Code davor.** Eine „bessere
Bibliothek" gibt es deshalb nicht – es gibt nur besser gefüllte
Datenbanken.

| Datenquelle | Genauigkeit | Preis | Verfügbar |
|---|---|---|---|
| Apple (CoreLocation) | **±35 m gemessen** | – | nur macOS |
| Microsoft (WinRT) | **±19 m gemessen, 15 m Abweichung** | – | nur Windows |
| beacondb (frei) | **hier keine Daten** | frei | überall |
| Google Geolocation API | 20–50 m | Schlüssel + Kosten | überall |
| GeoIP | 25 km behauptet, **271 km real** | frei | überall |

## Die Messung

Auf dem Windows-Testrechner, in der Wohnlage des Nutzers.

**WLAN-Umgebung.** `netsh wlan show networks` meldete *ein* Netz – ein
veralteter Zwischenstand des Treibers. Ein erzwungener Scan über
`wlanapi.dll` (`WlanScan` + `WlanGetNetworkBssList`) fand **22
BSS-Einträge**, davon 13 mit global verwalteter MAC-Adresse, also echte
fremde Zugangspunkte. Am Scannen liegt es nicht.

**beacondb.** POST auf `https://api.beacondb.net/v1/geolocate`, einmal mit
allen 22 und einmal mit den 13 echten Adressen: beide Male HTTP 404,
`"No location could be estimated based on the data provided"`, in 0,1 s.
Dieselbe Anfrage mit `considerIp: true` liefert HTTP 200 – die Anfrage ist
also richtig, die Datenbank ist hier leer.

**Der IP-Rückfall.** beacondb liefert dann per DB-IP eine Position mit
`accuracy: 25000`. Gegen den Schwerpunkt der grössten Koordinatenhäufung
der Bibliothek gerechnet (235 von 1141 verorteten Aufnahmen): **271 km
daneben.** Ein Ergebnis, das seinen eigenen Fehler um mehr als das
Zehnfache unterschätzt, ist schlimmer als gar keins – es setzt einen Pin,
dem der Nutzer glaubt.

**Windows' eigene Ortung.** Scheiterte zunächst mit `0x80072EE7`. Ursache
war **nicht** Windows: `inference.location.live.net` löste über den
DNS-Filter im Heimnetz auf `0.0.0.0` auf, über Router und 1.1.1.1 auf die
echte Adresse. Nach Freigabe der Domain: Quelle `WiFi`, ±19 m behauptet,
**15 m tatsächliche Abweichung** vom Referenzpunkt, 5,3 s beim ersten
Aufruf, danach aus dem Zwischenspeicher in Millisekunden.

## Was daraus gebaut wurde

**Windows:** ein eigenes Hilfsprogramm `pv_standort.exe`
(`windows/standort/pv_standort.cpp`, C++/WinRT, rund 50 KB), das eine
Zeile JSON ausgibt und sich nach zwölf Sekunden selbst abbricht. Es liegt
neben `photo_vault.exe` und wird über `DesktopImageTools.standort()`
aufgerufen.

Warum ein Prozess und kein Methodenkanal: Unter Windows hat diese App
bislang gar keinen nativen Kanal – alles Plattformnahe läuft über
aufgerufene Werkzeuge. Ein eigener Prozess passt in dieses Muster, kann
die Oberfläche nicht blockieren und lässt sich hart abbrechen. Der
Ortungsdienst lief gemessen mehrere Sekunden und kann hängen.

**Die Herkunft wird ausgewertet, nicht nur die Koordinate.**
`parseStandort` verwirft alles, was nicht aus `WiFi`, `Satellite` oder
`Cellular` stammt. Genau das fängt den 271-km-Fall ab: Windows liefert bei
fehlender WLAN-Abdeckung ebenfalls eine IP-Position und behauptet dazu
eine Güte, die es nicht einhält.

**Linux bleibt aussen vor.** GeoClue ist da und zeigt sogar schon auf
beacondb (`strings /usr/libexec/geoclue` bestätigt es). Nur ist beacondb
hier leer, und was bliebe, wäre der IP-Rückfall. Sobald beacondb in dieser
Gegend Daten hat, ist die Anbindung klein: GeoClue über D-Bus, unter
Flatpak über das Portal `org.freedesktop.portal.Location`.

## Was nicht geprüft werden konnte

Die Linux-Testmaschine ist eine VMware-VM **ohne jede Funkhardware**
(`nmcli` zeigt 0 Netze, nur `ens33`). Eine frühere Messung von „±26 km
unter Linux" war deshalb wertlos – sie hat nur die fehlende WLAN-Karte
gemessen, nicht GeoClue.

Ein Durchgang durch die Oberfläche auf Windows von Hand steht aus; geprüft
sind das Hilfsprogramm, der Dart-Weg bis `NativeImageConverter` und die
Paketierung.
