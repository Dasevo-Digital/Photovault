# Plan: die vier Wünsche nach 1.13.0

Aus der Liste vom 26.08.2026. Vier Fehler sind behoben (Globus-Pin,
stehenbleibende Meldung, fehlender Schwager, Flatpak-Bündel); was hier
steht, ist der Rest. Vier Stufen, jede mit eigenem Commit und eigenen
Tests, jede einzeln auslieferbar.

**Zwei Entscheidungen sind gefallen:**
- Eine Aktivität steht **für sich** und *kann* zu einer Reise gehören.
- Das Gelände wird **echt dreidimensional**, nicht als Topo-Karte mit
  Profil daneben.

Die Datenbank geht dabei von Fassung **53 auf 55**.

---

## Reihenfolge — und warum sie so ist

Die Ortsansicht zuerst, weil sie zwei Wünsche auf einmal erledigt und
nichts am Unterbau ändert. Die Meldungszentrale als zweites und nicht als
letztes: Sie fasst 82 Stellen an, und jeder Bildschirm, der vorher
entsteht, ist einer mehr, der danach umgestellt werden muss.

---

## Stufe 1 — Die Ortsansicht (kein Schemawechsel) — **erledigt**

**Zwei Wünsche, ein Bildschirm.** „Klick auf ein Land soll die Regionen
zeigen" und „Klick auf einen Pin soll die Fotos zeigen" enden beide bei
derselben Frage: *Was war hier?*

Heute endet beides in einer Sackgasse. In der Länderliste öffnet ein Klick
auf ein Land nur das Markierungsmenü (`laenderliste_screen.dart`, Zeile
107); auf der Weltkarte zeigt ein Klick auf einen Punkt Name, Anzahl und
zwei Marken-Knöpfe (`weltkarte_screen.dart`, `_punktGewaehlt`).

### Was schon da ist

`SearchFilters` führt `locationCountry`, `locationState` und
`locationCity`, und `database.dart` wertet sie in `queryAssets` aus
(Zeilen 3508–3515). Die Frage „zeig mir die Fotos aus Niedersachsen" ist
also bereits beantwortbar — es fehlt nur der Weg dorthin.

**Nachgesehen und berichtigt:** `SearchScreen` nimmt *keine* fertigen
Filter entgegen, es beginnt mit `const SearchFilters()`. Die Fotos werden
deshalb in der Ortsansicht selbst über `queryAssets` geholt und als
Raster eingebettet, statt auf die Suche zu verweisen. Das ist ohnehin der
bessere Weg: Ein Ort ist kein Suchergebnis, und wer von dort zurückgeht,
soll wieder beim Ort landen und nicht in einer Suchmaske.

### Umsetzung

- Neu: `lib/screens/ortsansicht_screen.dart`, aufgerufen mit
  `(art, schlüssel)` — Land, Region oder Ort.
- **Kopf:** Flagge, Name, Hauptstadt/Erdteil (Land) bzw. übergeordneter
  Ort, dazu die Zahlen aus `besuchteOrte()` und der Markenstand.
- **Mitte:** die nächste Ebene als Liste zum Weiterklicken. Land →
  Regionen (aus `geo.regionscodes` und `laenderkatalog`), Region → Orte.
  Besuchte zuerst, unbesuchte darunter ausgegraut — die Liste soll auch
  zeigen, was noch fehlt, sonst ist sie nur ein Spiegel der Fotos.
- **Unten:** die Fotos, über die vorhandene Suche mit gesetztem Filter.
- **Reisen dazu:** Welche bestätigten Reisen diesen Ort berühren, aus
  `ReiseAufnahmen` ⨝ `assets`. Das ist der Teil des Wunsches, den die
  reine Ortsfilterung nicht abdeckt.
- **Eingänge:** die Zeile in der Länderliste, der Punkt auf der Weltkarte
  (statt des heutigen Blattes; die Marken-Knöpfe wandern in die
  Ortsansicht), und die Fläche auf der Karte.

> **Falle: ein Ort ohne Fotos ist der Normalfall.** Von 252 Ländern hat
> die Beispielbibliothek fünf. Die Ansicht muss ohne ein einziges Foto
> etwas Sinnvolles zeigen — Hauptstadt, Erdteil, Regionenzahl, und den
> Knopf zum Markieren.

### Prüfung

Die Zusammenstellung als reine Funktion (`ortsuebersicht(...)`) mit
eigenen Tests: Land mit Fotos, Land ohne Fotos, Region ohne verzeichnete
Unterorte, Ort ohne Region. Dazu Widget-Tests für den Weg Land → Region →
Ort und zurück.

---

## Stufe 2 — Die Meldungszentrale (kein Schemawechsel) — **erledigt**

**82 Meldungen in 24 Dateien**, keine einzige mit eigener Dauer, keine
Historie. Wer eine verpasst, hat sie verpasst.

### Umsetzung

- Neu: `lib/services/meldungsdienst.dart` — eine Liste von Meldungen mit
  Art (Hinweis/Erfolg/Warnung/Fehler), Text, Zeit, optionaler Aktion und
  Kennung. Rein und ohne Flutter-Abhängigkeit ausser `ChangeNotifier`,
  damit die Regeln prüfbar sind: Wann verblasst was, was wird
  zusammengefasst, was bleibt liegen.
- Neu: `lib/widgets/meldungsfenster.dart` — die Einblendung **rechts
  oben**, gestapelt, jede einzeln wegklickbar, mit ablaufendem Balken.
  Fehler verblassen **nicht** von selbst; alles andere schon.
- **Historie** über ein Glockensymbol in der Titelleiste, mit Zahl.
  Nur im Speicher: Eine Meldung, die den Neustart überlebt, ist keine
  Meldung mehr, sondern eine Aufgabe — und dafür gibt es die
  Aufgabenliste bereits.
- **Umstellung in zwei Schritten:** erst der Dienst samt Anzeige und eine
  Brücke, die `showSnackBar` weiterhin bedient; dann die 24 Dateien
  einzeln. `meldung_mit_knopf.dart` von heute geht darin auf.

> **Mitzudenken:** Eine Einblendung rechts oben verdeckt genau dort etwas.
> Sie braucht einen sicheren Abstand zu den Knöpfen der Titelleiste und
> muss bei schmalem Fenster nach unten ausweichen.

> **Sprachausgabe:** Eine Meldung, die nur erscheint, wird nicht
> vorgelesen. `SemanticsService.announce` gehört dazu — die SnackBar
> hatte das umsonst.

### Prüfung

Die Regeln als reine Funktionen mit Tests (Verblassen, Zusammenfassen
gleicher Meldungen, Fehler bleiben). Widget-Tests für Stapel, Wegklicken
und Historie. Der heutige Test, der Flutters `persist`-Verhalten
festhält, bleibt bestehen, bis die letzte SnackBar weg ist.

### Was beim Bauen anders kam als geplant

- **Der Verlauf ist eine Tafel im Stapel, kein Dialog.** Der
  Meldungsstapel hängt in `MaterialApp.builder` und liegt damit
  *ausserhalb* des Navigators: Dort gibt es weder Overlay noch
  Navigator, `showDialog` wäre also gar nicht möglich gewesen. Für die
  Tooltips bringt das Fenster ein eigenes `Overlay` mit.
- **Fristen laufen nur, solange jemand zusieht** (`hasListeners`). Ohne
  das hing in jedem Widget-Test, dessen Bildschirm etwas meldet, eine
  Uhr in der Luft, und der Rahmen brach mit „A Timer is still pending"
  ab – in Tests, die mit Meldungen nichts zu tun haben.
- **`meldung_mit_knopf.dart` ist samt Test entfallen**, weil keine
  SnackBar mehr übrig ist. Die Lehre daraus steht jetzt im Kopf von
  `meldungsdienst.dart`.
- **`pumpAndSettle` lässt Meldungen verblassen.** Der ablaufende Balken
  ist ein anstehendes Bild; `pumpAndSettle` läuft, bis keines mehr
  aussteht, und ist danach über die Frist hinaus. Vier vorhandene Tests
  suchten die Meldung deshalb vergeblich auf dem Schirm – sie lesen sie
  jetzt aus dem Verlauf.

---

## Stufe 3 — Aktivitäten (Schema 54) — **erledigt**

`Reisen` führt heute Name, Zeitraum, Notiz und Titelbild — mehr nicht.

### Umsetzung

- **Schema 54:** Tabelle `Aktivitaeten` (Kennung, Name, Art, von, bis,
  Notiz, `reiseId` **nullable**, `spurId` nullable) und
  `AktivitaetAufnahmen` (Kennung, Aufnahme) nach dem Muster von
  `ReiseAufnahmen`. Die nullable `reiseId` ist die getroffene
  Entscheidung: Die Sonntagswanderung vor der Haustür braucht keine Reise.
- **Arten** als Aufzählung mit Symbol: Wanderung, Radtour, Ausflug,
  Besichtigung, Bootsfahrt, Sonstiges. Übersetzt in beiden ARB-Dateien.
- **Vorschlagen statt verlangen**, wie bei den Reisen: Eine Häufung von
  Aufnahmen an einem Tag in einem Umkreis ist ein Kandidat. Die Rechnung
  dafür steht in `reiseroute.dart` (`aufenthaltsorte`) schon bereit.
- Anzeige in `reise_detail_screen` als Kapitel, und eine eigene Liste für
  die Aktivitäten ohne Reise.

### Prüfung

Migration 53 → 54 an Kopien der echten Bibliotheken, SHA-256 davor und
danach. Die Zuordnung als reine Funktion prüfen: Eine Aktivität ohne
Reise, eine mit, eine, deren Zeitraum über den der Reise hinausragt.

### Was beim Bauen anders kam als geplant

- **Nicht `aufenthaltsorte`, sondern die Zeit.** Der Plan wollte die
  vorhandene Ortsgruppierung wiederverwenden. Sie ist das falsche
  Werkzeug: Ihr Radius von 15 km zerschneidet eine lange Wanderung und
  wirft dafür die Vormittagswanderung mit dem Abendspaziergang in
  derselben Stadt zusammen. Eine Aktivität ist ein **zusammenhängendes
  Stück Zeit** – getrennt wird an einer Lücke von 90 Minuten und am
  Kalendertag.
- **Zwei Bedingungen, oder-verknüpft.** „Bewegung" allein striche die
  Fahrt zum Wildpark (viele Bilder, kein Weg); „Entfernung von zu Hause"
  allein striche die Sonntagswanderung vor der Haustür. Beides zu
  verlangen striche beide, keines von beidem machte jeden Tag im eigenen
  Garten zur Unternehmung.
- **Die Art wird nur nach oben behauptet.** Zwischen zwei Aufnahmen
  liegt mehr Weg als die Luftlinie und meist eine Pause – die gerechnete
  Geschwindigkeit ist eine Untergrenze. Belegt ist daraus nur: „schneller
  als 25 km/h heisst Fahrzeug". Nach unten wird der harmloseste Fall
  gewählt, denn eine falsch geratene Art ist ein Klick, eine falsch
  behauptete eine Unwahrheit in der Datenbank.
- **`spurId` ist nicht dabei.** Der Plan sah die Spalte schon hier vor.
  Eine Spalte, die kein Code liest, lässt sich nicht prüfen – und in
  Stufe 4 gehört die Verbindung ohnehin auf die neue Seite
  (`Spuren.aktivitaetId`), die dort ihre eigene Migration bekommt.
- **`Routenkarte` ist aus `reise_detail_screen.dart` herausgelöst**, weil
  eine Wanderung dieselbe Karte verdient wie eine Reise – nur mit
  engeren Massen (100 m Mindestabstand statt 1 km, 200 m Ortsradius
  statt 15 km).

### Was die echte Bibliothek dazu sagt

Gegen die Kopie der Produktivbibliothek gerechnet: **1091 verortete
Aufnahmen von 7988**, daraus **16 Vorschläge** über zwölf Jahre – 6
Wanderungen, 1 Radtour, 9 Besichtigungen. Keine Flut und kein
Fehlschlag. Die längste: 39 Bilder über 338 Minuten und 18,7 km. Der
Grund, dass es nicht mehr sind, ist keine zu strenge Regel, sondern die
Ortsangabe: Sieben von acht Aufnahmen dieser Bibliothek haben gar keine
Koordinate.

---

## Stufe 4 — GPX-Spuren, Höhenprofil und Gelände (Schema 55)

**Erledigt** – Spur, Profil und Gelände.

### Der Blocker zuerst

`liesGpx` (`lib/services/gpx.dart`, Zeilen 63–73) liest Breite, Länge und
Zeit. **`<ele>` wird verworfen**, und die Spur wird nirgends gespeichert —
sie dient einmalig dem Verorten von Fotos und ist danach weg. Ohne beides
gibt es kein Profil und keine Linie.

- `Spurpunkt` bekommt `hoehe` (nullable — nicht jede Datei hat sie).
- **Schema 55:** `Spuren` (Kennung, Name, Quelle, von, bis, Punktzahl,
  Länge, Auf- und Abstieg) und `Spurpunkte` (Spur, Nummer, Breite, Länge,
  Höhe, Zeit).
- Auf- und Abstieg werden **beim Einlesen** gerechnet und gespeichert,
  mit einer Schwelle gegen das Rauschen der GPS-Höhe: Ohne sie summiert
  eine flache Runde hundert Höhenmeter, die es nie gab.

### Höhenprofil

`lib/widgets/hoehenprofil.dart` als `CustomPaint`, nach dem Muster von
`faecher_ansicht.dart` — dort steht auch, wie eine gemalte Fläche eine
Beschreibung für die Sprachausgabe bekommt. Ein Finger auf dem Profil
zeigt die Stelle auf der Karte und umgekehrt.

### Was beim Bauen anders kam als geplant (Spur und Profil)

- **Die Schwelle allein reicht nicht.** Sie wirkt gegen den *Abstand
  zweier Messungen*, und der ist beim Rauschen doppelt so gross wie
  dessen Ausschlag: Ein Gerät, das um ±3 m schwankt, springt zwischen
  zwei Punkten um 6 m – über einer Schwelle von 5. Erst ein Mittel über
  fünf Punkte nimmt dem Rauschen die Spitzen, die Schwelle fängt danach
  den Rest. Gegengeprüft: dieselbe flache Runde ergibt ohne Glättung
  über hundert Höhenmeter, mit Glättung sechs. Der Preis ist, dass ein
  scharfer Knick ein paar Meter verliert – bei hundert gemessenen drei.
- **Das Mitteln schrumpft symmetrisch**, damit die Enden stehen bleiben.
  Ein einseitiges Fenster zöge den ersten Punkt in Richtung des zweiten;
  ein Anstieg verlöre an beiden Enden Meter, die er hatte.
- **Ein zweiter Lesepfad statt eines geänderten.** `liesGpx` behält
  seinen Vertrag (nur Punkte mit Zeit, nach Zeit sortiert) – für das
  Verorten von Fotos ist das richtig. Daneben steht `liesGpxPunkte`:
  alle Punkte in der Reihenfolge der Datei, denn für eine Linie ist die
  aufgezeichnete Folge die Aussage, und eine geplante Route hat gar
  keine Zeit.
- **Der Profilpunkt trägt seinen Spur-Index mit.** Daran hängt die Marke
  auf der Karte: Das Profil kennt nur die Punkte *mit* Höhe, sein
  eigener Index ist also nicht der Index in der Spur. Ohne den
  mitgeführten Index müsste man die Strecke rückwärts suchen und
  Kommazahlen vergleichen.
- **Gemessen:** 10.000 Punkte als Stapel in 56 ms geschrieben.

### Das Gelände — ohne neue Bibliothek

**Gemessen, nicht vermutet:** Geländekacheln im `terrarium`-Format sind
frei und brauchen keinen Schlüssel; sie werden über dieselbe XYZ-Adresse
geholt wie die Kartenkacheln. Eine Probe auf Kachel 11/1080/689 (50,6° N,
9,8° O — Vogelsberg) ergab **337 bis 807 m**, was mit dem Taufstein
(773 m) zusammenpasst. Die Höhe steckt als
`r · 256 + g + b/256 − 32768` in den Bildpunkten.

Damit ist keine Fremdbibliothek nötig:

1. **Kacheln** über die vorhandene Kachelmaschinerie samt Zwischenspeicher
   (`karten_kachelspeicher`), nur mit anderer Adresse.
2. **Gitter** aus den Höhen, aufgelöst nach Zoomstufe.
3. **Darstellung** über `Canvas.drawVertices` mit selbst gerechneter
   Kamera — Dreiecke, Farbe je Eckpunkt aus Höhe und Schattierung. Reines
   Flutter, keine Erweiterung, kein Plugin.
4. **Die Spur** darübergelegt, mit der Höhe aus der GPX-Datei statt aus
   den Kacheln: Was das Gerät gemessen hat, ist die Aussage; die Kacheln
   sind die Kulisse.

> **Warum das anders ist als MapLibre.** Dort trug ein Paket auf pub.dev
> einen grünen Haken für Linux und scheiterte dort trotzdem. Hier kommt
> nichts dazu, was scheitern könnte: `drawVertices` ist Flutter selbst,
> und eigene Shader laufen in dieser App auf allen drei Plattformen
> nachweislich (Globus, `develop_adjustments.frag`).

> **Was gemessen werden muss, bevor es bleibt:** Dreieckszahl gegen
> Bildrate. Ein Gitter von 256×256 sind 130.000 Dreiecke je Kachel — das
> ist zu viel und muss heruntergerechnet werden. Die Zahl entscheidet die
> Messung, nicht die Schätzung.

> **Und die Grenze, die bleibt:** Geländehöhen sind keine Karte. Ohne die
> Kartenkacheln darüber sieht man Berge ohne Wege. Die Textur aus
> OpenTopoMap auf das Gitter zu legen ist der zweite Schritt und der,
> der aus einer Landschaft eine brauchbare Landschaft macht.

### Abbruchkriterium

Wenn die Landschaft bei einer echten Wanderung nicht **mehr** zeigt als
Karte plus Profil, wird sie nicht ausgeliefert. Das entscheidest du am
Bildschirm.

**Am Bildschirm angesehen (Rhön bei Dipperz, 160 Punkte über sechs
Kilometer): bestanden.** Die Karte ist lesbar – Ortsnamen, Höhenlinien,
Höhenpunkte –, das Relief ist zu erkennen, und die Spur läuft sichtbar
über einen Kamm an der Milseburg vorbei. Das ist die Auskunft, die weder
die Karte noch das Profil geben.

### Was das Bauen ergab

- **Die Messung fiel anders aus als erwartet.** Selbst 130.000 Dreiecke
  brauchen nur 4,71 ms – aber gemessen ist damit nur die Rechnung in
  Dart, nicht die Arbeit der Grafikkarte. Gewählt wurde deshalb 96
  (18.050 Dreiecke, 0,86 ms): Luft für langsamere Maschinen, und am
  Bildschirm von 192 nicht zu unterscheiden.
- **Zwei Zahlen mussten am Bildschirm nachjustiert werden**, nicht am
  Schreibtisch: die Überhöhung von 2 auf 3 (mit 2 war ein Mittelgebirge
  eine ebene Platte) und die Grundhelligkeit der Schattierung von 0,45
  auf 0,72 (die Schattierung multipliziert die Karte – bei 0,45 war die
  halbe Karte nicht mehr zu lesen).
- **Und ein Fehler, den nur das Bild zeigte:** Die Grundfarbe des
  Geländes muss Weiss sein, sobald eine Karte darauf liegt. `modulate`
  multipliziert beides; ein sandiges Braun dunkelte die Karte ein
  zweites Mal ab, und die Landschaft sah aus wie bei Nacht.
- **Ein echter Fehler im Verkleinern:** „jeden n-ten Punkt nehmen" liess
  den Ostrand weg, während das Rechteck weiter die volle Breite
  behauptete – die Landschaft wäre gedehnt gewesen. Gefunden hat ihn ein
  Test, nicht das Auge.
- **Linux nachgeprüft, und zwar am Bild.** Genau hier lag der
  MapLibre-Fehlschlag, deshalb nicht auf „müsste laufen" verlassen: auf
  TestKubuntu gebaut, in der laufenden Plasma-Sitzung gestartet und
  abfotografiert. Dasselbe Bild wie unter macOS – Textur, Relief, Spur.
  `drawVertices` samt `ImageShader` und `modulate` läuft dort unter
  Xwayland.
- **Offen bleiben Windows und das Flatpak.** TestWindows war nicht
  erreichbar; das Flatpak ist ein eigener Bau. Beides gehört zur
  nächsten Auslieferung.

---

## Kritische Dateien

| Stufe | Dateien |
|---|---|
| 1 | **neu** `lib/screens/ortsansicht_screen.dart`, **neu** `lib/services/ortsuebersicht.dart`, `lib/screens/laenderliste_screen.dart`, `lib/screens/weltkarte_screen.dart` |
| 2 | **neu** `lib/services/meldungsdienst.dart`, **neu** `lib/widgets/meldungsfenster.dart`, `lib/widgets/meldung_mit_knopf.dart` (geht darin auf), 24 Bildschirme |
| 3 | `lib/db/database.dart` (Migration `from < 54`), **neu** `lib/services/aktivitaeten.dart`, `lib/screens/reise_detail_screen.dart` |
| 4 | `lib/services/gpx.dart`, `lib/db/database.dart` (`from < 55`), **neu** `lib/widgets/hoehenprofil.dart`, **neu** `lib/services/gelaendekacheln.dart`, **neu** `lib/widgets/gelaende.dart` |
| alle | `lib/l10n/app_de.arb` **und** `app_en.arb` |

Neue Texte gehören in **beide** ARB-Dateien. `keine_festen_texte_test.dart`
fängt Vergessenes; `flutter gen-l10n` erkennt einen halben Durchgang nicht.

---

## Offene Risiken

- **Die Ortsansicht kann zu voll werden.** Kopf, Unterebene, Reisen und
  Fotos auf einem Blatt — bei einem Land mit 34 Regionen und 600 Fotos
  ist das viel. Notfalls Reiter statt Untereinander.
- **Die Meldungszentrale fasst 82 Stellen an.** Die Brücke hält die
  Umstellung klein, aber jede umgestellte Stelle ist eine, die vorher
  keinen Test hatte.
- **Die Höhe aus GPS ist verrauscht.** Der Auf- und Abstieg hängt an der
  gewählten Schwelle, und jede Wahl ist angreifbar. Sie gehört
  aufgeschrieben und benannt, nicht versteckt.
- **Das Gelände ist die einzige Stufe, die scheitern kann.** Sie steht
  deshalb zuletzt und hat ein Abbruchkriterium.
