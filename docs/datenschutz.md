# Datenschutzerklärung

Stand: 2. September 2026 · Photo Vault 3.3.1

## Kurz

Photo Vault ist eine Fotoverwaltung, die **auf dem eigenen Rechner**
arbeitet. Es gibt kein Benutzerkonto, keine Anmeldung und keinen Server
des Anbieters. Fotos, Videos, Gesichtserkennung, Schlagwörter, Orte und
der Stammbaum liegen ausschliesslich lokal. Es findet **keine
Nutzungsmessung, keine Analyse und keine Werbung** statt.

Verbindungen ins Netz entstehen nur an den unten genannten Stellen, und
alle bis auf die Kartenkacheln erst auf ausdrückliche Handlung.

## Was wo liegt

**Die Bibliothek** – Fotos, Videos, Datenbank, Sicherungen – liegt in dem
Ordner, den Sie selbst wählen. Ohne eigene Wahl liegt sie im Datenordner
der App:

- Windows (ausgepackte Fassung): `%APPDATA%\com.example\photo_vault\`
- Windows (Fassung aus dem Store): `%LOCALAPPDATA%\Packages\…\LocalCache\Roaming\com.example\photo_vault\`
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
Thunderforest oder Mapbox. Für die letzten drei ist ein eigener
Zugangsschlüssel nötig, den Sie selbst eintragen. Geladene Kacheln
werden lokal zwischengespeichert; ein einmal geladener Bereich wird
nicht erneut angefragt.

**Modelle für die Bilderkennung.** Nur wenn Sie sie in den Einstellungen
ausdrücklich herunterladen. Bezogen von `huggingface.co` und
`github.com`. Übertragen wird dabei nur die Anfrage nach der Datei.

**Ortsdaten.** Nur wenn Sie sie in den Einstellungen ausdrücklich
herunterladen. Bezogen von `download.geonames.org`.

**Standortbestimmung.** Nur wenn Sie auf der Karte den Standortknopf
drücken. Unter Windows und macOS fragt die App den Ortungsdienst des
Betriebssystems; dieser übermittelt an Microsoft beziehungsweise Apple
Kennungen der WLANs in Ihrer Umgebung. Es gilt dann die
Datenschutzerklärung des jeweiligen Betriebssystemherstellers. Unter
Linux gibt es diese Funktion nicht.

**Sonst nichts.** Die App prüft nicht auf Aktualisierungen, meldet keine
Abstürze und sendet keine Kennungen.

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

## Verantwortlich

    <Name und Kontaktadresse hier eintragen>

Fragen zu dieser Erklärung an dieselbe Adresse.
