# Datenschutzerklärung

Stand: 27. Oktober 2026 · Photo Vault 3.49.0

## Kurz

Photo Vault ist eine Fotoverwaltung, die ohne weitere Einrichtung **auf dem
eigenen Rechner** arbeitet. Für diese lokale Betriebsart gibt es kein
Benutzerkonto und keine Anmeldung. Freiwillig kann die nutzende Person einen
eigenen Photo Vault Server betreiben oder einen von ihr gewählten Server
verwenden. Eine damit verbundene Bibliothek überträgt ihre Inhalte an diesen
Server; Handy-App und Browseroberfläche arbeiten nur mit einem solchen Server.
Der Herausgeber betreibt keinen zentralen Photo-Vault-Dienst. Es findet
**keine Nutzungsmessung, keine Analyse des Nutzungsverhaltens und keine
Werbung** statt.

Verbindungen ins Netz entstehen an den unten genannten Stellen. Karten- und
Geländedaten werden beim Öffnen der jeweiligen Ansicht geladen. Downloads,
Standortbestimmung, Aktualisierungsprüfung und das Verbinden mit einem Server
benötigen eine ausdrückliche Handlung oder eine zuvor gewählte Einstellung.

## Was wo liegt

**Eine lokale Bibliothek** – Fotos, Videos, Datenbank, Sicherungen – liegt in
dem Ordner, den Sie selbst wählen. Ohne eigene Wahl liegt sie im Datenordner
der App:

- Windows (ausgepackte Fassung): `%APPDATA%\de.dasevo\photovault\`
- Windows (Fassung aus dem Store): `%LOCALAPPDATA%\Packages\…\LocalCache\Roaming\de.dasevo\photovault\`
- macOS: `~/Library/Containers/…/PhotoVault/`
- Linux: `~/.var/app/…/PhotoVault/`

**Eine verbundene Bibliothek** liegt vollständig auf dem gewählten Photo Vault
Server. Desktop und Handy halten eine lokale Kopie der Datenbank und laden
Vorschauen oder Originale bei Bedarf. Änderungen werden mit dem Server
abgeglichen. Die Person oder Organisation, die den Server betreibt, bestimmt
Speicherort, Sicherung, Protokollierung und Zugriffsregeln.

**Gesperrte Fotos** werden mit AES-256-GCM verschlüsselt. Ein zufälliger
Master-Schlüssel wird durch einen mit Argon2id aus dem Kennwort abgeleiteten
Schlüssel geschützt. Bei einer lokalen Bibliothek verlässt er den Rechner
nicht; bei einer verbundenen Bibliothek liegen die verschlüsselten Dateien
auf dem gewählten Server. Wer das Kennwort verliert, verliert den Zugriff –
es gibt keine Hintertür und keine Wiederherstellung durch den Herausgeber.

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
werden lokal zwischengespeichert und erst neu angefragt, wenn ihre vom Dienst
genannte Gültigkeit abgelaufen ist (ohne Angabe nach sieben Tagen). Auf
ausdrücklichen Wunsch lädt die App unter Einstellungen → Karte die Kacheln
rund um alle Aufnahmeorte vor; der Kartendienst erfährt dann auf einmal alle
Gegenden, in denen Fotos entstanden sind.

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

**Eigener Photo Vault Server.** Erst wenn Sie in den Einstellungen eine
Serveradresse angeben und sich anmelden, überträgt die Desktop-App die
Serveradresse, Kontoname, Gerätebezeichnung und Anmeldedaten an diesen Server.
Beim Umzug oder Abgleich einer Bibliothek werden deren Datenbank, Metadaten,
Originale, Vorschaubilder und spätere Änderungen übertragen. Der Server kann
die Bildauswertung übernehmen, Sicherungen erstellen und Dateien an
angemeldete Desktop-, Handy- und Browsergeräte ausliefern. Ein als Rechenhilfe
eingerichteter Rechner erhält zu bearbeitende Aufnahmen vom Server und sendet
die Ergebnisse zurück. Betreiber und Standort dieses Servers werden von der
nutzenden Person gewählt; dessen Datenschutz- und Protokollierungsregeln
gelten zusätzlich.

**Handy-App.** Die Handy-App benötigt einen Photo Vault Server. Sie lädt die
Bibliotheksdatenbank sowie benötigte Vorschauen und Originale, sendet
Änderungen zurück und kann auf ausdrücklichen Wunsch die Kamerarolle samt
Metadaten und Originaldateien sichern. Zwischengespeicherte Daten liegen im
geschützten App-Bereich des Telefons.

**Konten und Anmeldung.** Der selbst betriebene Server speichert Kontonamen,
Passwort-Prüfwerte, TOTP-Einstellungen, Prüfwerte der Wiederherstellungscodes,
Gerätebezeichnungen und gehashte Gerätetokens. Optional kann ein eigener
OIDC-Anbieter verwendet werden. Dieser erhält dann die übliche
Anmeldeanforderung; der Photo Vault Server speichert die Zuordnung aus
Aussteller und dortigem Benutzerkennzeichen. Passwörter und TOTP-Geheimnisse
werden nicht an den Herausgeber übertragen.

Nach einer Anmeldung speichert das Gerät sein Bearer-Token im eigenen
App-Datenbereich, damit es die Verbindung wieder aufnehmen kann. Auf Desktop-
Systemen liegt es getrennt von der Bibliothek und unter macOS/Linux nur für
das Benutzerkonto lesbar; auf dem Telefon liegt es im geschützten App-Bereich.
Das Token ist dort nicht zusätzlich verschlüsselt. Es kann am Server durch
Abmelden des Geräts ungültig gemacht werden.

**Browser, Freigaben und Gastbeiträge.** Die Browseroberfläche lädt
Bibliotheksdaten und Medien vom gewählten Server. Freigabelinks machen die
ausgewählten Inhalte für Personen mit dem Link und gegebenenfalls dem
Passwort erreichbar. Erlaubt der Besitzer Gastbeiträge, werden hochgeladene
Dateien zunächst auf dem Server verarbeitet und als bereinigte Fassung ohne
eingebettete Metadaten gespeichert. Server und vorgeschalteter Proxy können
hierbei technisch notwendige Verbindungsdaten wie IP-Adresse und Zeitpunkt
verarbeiten.

**Karten in Browser und Handy-App.** Auch mit eigenem Server holen
Browseroberfläche und Handy-App Kartenkacheln **direkt** bei den Diensten,
nicht über den Photo Vault Server: die Karte bei OpenStreetMap
(`tile.openstreetmap.org`), Geländeansicht und 3D-Flug Höhendaten bei AWS
Open Data, Luftbilder bei Esri/ArcGIS und Wanderwege bei Waymarked Trails.
Diese Dienste erhalten dabei die IP-Adresse des Geräts und die angefragten
Kachelkoordinaten; daraus lässt sich ableiten, welche Gegend betrachtet wird.
Wanderobjekte fragt dagegen der Server bei der Overpass API ab.

**Unterstützungslink.** Nur wenn Sie den Ko-fi-Link öffnen, wechselt der
Browser zu `ko-fi.com`; dabei gelten dessen Datenschutzbedingungen. Fassungen
für App-Stores zeigen diesen Link nicht.

**Keine Telemetrie.** Die App meldet keine Abstürze, führt keine
Nutzungsmessung durch und sendet keine eigenen Geräte- oder Benutzerkennungen.

## Verarbeitung durch künstliche Intelligenz

Bei einer lokalen Bibliothek laufen Gesichtserkennung, Schlagwörter,
Bildbeschreibungen, Texterkennung und die Suche nach Bildinhalt
**vollständig auf Ihrem Rechner**. Es wird dafür kein Bild an einen fremden
Dienst übertragen. Die Modelle werden einmal heruntergeladen und danach
lokal ausgeführt.

Bei einer verbundenen Bibliothek führt der gewählte Photo Vault Server diese
Arbeiten aus. Freiwillig eingerichtete Rechenhilfen laden einzelne Aufnahmen
vom Server und senden berechnete Merkmale und Beschreibungen zurück. Weder der
lokale noch der Serverbetrieb sendet Bilder zur Auswertung an einen vom
Herausgeber betriebenen KI-Dienst.

## Ihre Rechte

Der Herausgeber erhebt, speichert oder verarbeitet durch Photo Vault keine
Bibliotheks- oder Kontodaten. Eine lokale Bibliothek lässt sich durch Löschen
ihres Ordners entfernen. Bei einer verbundenen Bibliothek richten sich
Auskunft, Berichtigung und Löschung zusätzlich an die Person oder Organisation,
die den gewählten Server betreibt. Konten, Geräte und Freigaben lassen sich
dort verwalten; Serverdateien und Sicherungen müssen vom Betreiber gelöscht
werden. Die App selbst lässt sich über die üblichen Wege des Betriebssystems
entfernen.

## Verantwortlichkeit und Kontakt

Der Herausgeber betreibt kein zentrales Konto und keinen Photo Vault Server
für die Nutzenden. Für eine lokale Bibliothek bestimmt die nutzende Person
selbst über Zweck, Inhalt und Löschung. Bei einem selbst betriebenen oder von
ihr ausgewählten Server ist dessen Betreiber für die dortige Verarbeitung
verantwortlich. Bei den oben aufgeführten Abrufen verarbeiten die jeweiligen
Drittanbieter technisch notwendige Verbindungsdaten nach ihren eigenen
Datenschutzbestimmungen.

Fragen und Datenschutzmeldungen können ohne Veröffentlichung persönlicher
Kontaktdaten über das Issue-System des offiziellen Projekt-Repositorys gestellt
werden. Wer Photo Vault als Store-Angebot oder unter eigener Organisation
verteilt, muss vor der Veröffentlichung seine eigene ladungsfähige
Kontaktangabe und gegebenenfalls weitere Pflichtinformationen ergänzen.
