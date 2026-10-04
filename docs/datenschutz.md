# Datenschutzerklärung

Stand: 30. September 2026 · Photo Vault 3.18.1

## Kurz

Photo Vault ist eine Fotoverwaltung, die **auf dem eigenen Rechner**
arbeitet. Es gibt kein Benutzerkonto, keine Anmeldung und keinen Server
des Anbieters. Fotos, Videos, Gesichtserkennung, Schlagwörter, Orte und
der Stammbaum liegen ausschliesslich lokal. Es findet **keine
Nutzungsmessung, keine Analyse und keine Werbung** statt.

Verbindungen ins Netz entstehen nur an den unten genannten Stellen. Karten-
und Geländedaten werden beim Öffnen der jeweiligen Ansicht geladen; alle
anderen Abrufe benötigen eine ausdrückliche Handlung.

## Was wo liegt

**Die Bibliothek** – Fotos, Videos, Datenbank, Sicherungen – liegt in dem
Ordner, den Sie selbst wählen. Ohne eigene Wahl liegt sie im Datenordner
der App:

- Windows (ausgepackte Fassung): `%APPDATA%\de.dasevo\photovault\`
- Windows (Fassung aus dem Store): `%LOCALAPPDATA%\Packages\…\LocalCache\Roaming\de.dasevo\photovault\`
- macOS: `~/Library/Containers/…/PhotoVault/`
- Linux: `~/.var/app/…/PhotoVault/`

**Gesperrte Fotos** werden mit AES-256-GCM verschlüsselt; der Schlüssel
wird aus Ihrem Kennwort abgeleitet (Argon2id) und verlässt den Rechner
nicht. Wer das Kennwort verliert, verliert den Zugriff – es gibt keine
Hintertür und keine Wiederherstellung durch den Anbieter.

## Wann die App ins Netz geht

**Kartenkacheln.** Sobald Sie die Karte, eine Reise, eine Aktivität oder
die Geländeansicht öffnen, werden Kartenausschnitte von dem gewählten
Kartendienst geladen. Übertragen werden dabei die angefragten
Kachelkoordinaten und Ihre IP-Adresse. Aus den Koordinaten lässt sich
ableiten, welche Gegend Sie betrachten – also mittelbar, wo Ihre Fotos
aufgenommen wurden. Je nach Einstellung sind das:
OpenStreetMap, OpenTopoMap, CyclOSM, Esri/ArcGIS, CARTO, MapTiler,
Thunderforest, Mapbox oder Google Maps. Für mehrere kommerzielle Anbieter ist
ein eigener Zugangsschlüssel nötig, den Sie selbst eintragen. Geladene Kacheln
werden lokal zwischengespeichert; ein einmal geladener Bereich wird
nicht erneut angefragt.

**Gelände- und Wanderinformationen.** Beim Öffnen entsprechender Ansichten
lädt die App Höhendaten von AWS Open Data, Wanderwege von Waymarked Trails
und – wenn Wanderobjekte angefordert werden – Objekte über die Overpass API.
Dabei werden Ihre IP-Adresse und der betrachtete Kartenausschnitt beziehungsweise
das abgefragte Gebiet übertragen. Auch diese Antworten werden lokal
zwischengespeichert, soweit die jeweilige Funktion dies unterstützt.

**Modelle für die Bilderkennung.** Nur wenn Sie sie in den Einstellungen
ausdrücklich herunterladen. Bezogen von `huggingface.co` und
`github.com`. Übertragen wird dabei nur die Anfrage nach der Datei.

**Ortsdaten.** Nur wenn Sie sie in den Einstellungen ausdrücklich
herunterladen. Bezogen von `download.geonames.org`.

**Aktualisierungsprüfung.** Nur wenn Sie in den Einstellungen ausdrücklich
auf „Nach Aktualisierungen suchen“ drücken. Die App fragt dabei die öffentliche
Release-Liste über `api.github.com` ab. Übertragen werden die technisch
notwendige IP-Adresse und die übliche HTTP-Anfrage, aber keine Angaben aus der
Bibliothek. Die App prüft nicht automatisch und installiert nichts selbst.

**Standortbestimmung.** Nur wenn Sie auf der Karte den Standortknopf
drücken. Unter Windows und macOS fragt die App den Ortungsdienst des
Betriebssystems; dieser übermittelt an Microsoft beziehungsweise Apple
Kennungen der WLANs in Ihrer Umgebung. Es gilt dann die
Datenschutzerklärung des jeweiligen Betriebssystemherstellers. Unter
Linux gibt es diese Funktion nicht.

**Keine Telemetrie.** Die App meldet keine Abstürze, führt keine
Nutzungsmessung durch und sendet keine eigenen Geräte- oder Benutzerkennungen.

## Verarbeitung durch künstliche Intelligenz

Gesichtserkennung, Schlagwörter, Bildbeschreibungen, Texterkennung und
die Suche nach Bildinhalt laufen **vollständig auf Ihrem Rechner**. Es
wird kein Bild und kein Ausschnitt an einen Dienst übertragen. Die
Modelle werden einmal heruntergeladen und danach lokal ausgeführt.

## Ihre Rechte

Da der Anbieter keinerlei personenbezogene Daten erhebt, speichert oder
verarbeitet, gibt es beim Anbieter auch nichts, worüber Auskunft erteilt
oder was gelöscht werden könnte. Ihre Daten liegen bei Ihnen. Die
Bibliothek lässt sich jederzeit löschen, indem Sie den Ordner löschen;
die App selbst lässt sich über die üblichen Wege des Betriebssystems
entfernen.

## Verantwortlichkeit und Kontakt

Photo Vault betreibt kein Konto und keinen eigenen Verarbeitungsserver. Für
die ausschließlich lokale Bibliothek bestimmt die nutzende Person selbst über
Zweck, Inhalt und Löschung. Bei den oben aufgeführten Abrufen verarbeiten die
jeweiligen Drittanbieter die technisch notwendigen Verbindungsdaten nach ihren
eigenen Datenschutzbestimmungen.

Fragen und Datenschutzmeldungen können ohne Veröffentlichung persönlicher
Kontaktdaten über das Issue-System des offiziellen Projekt-Repositorys gestellt
werden. Wer Photo Vault als Store-Angebot oder unter eigener Organisation
verteilt, muss vor der Veröffentlichung seine eigene ladungsfähige
Kontaktangabe und gegebenenfalls weitere Pflichtinformationen ergänzen.
