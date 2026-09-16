# Bildschirmfotos

## Regel

Auf Bildschirmfotos in diesem Repository dürfen **ausschließlich frei
lizenzierte Beispielbilder** zu sehen sein – niemals Fotos aus einer echten
Bibliothek. Ein einmal veröffentlichtes Bild lässt sich nicht
zurückholen, und eine Fotoverwaltung zeigt naturgemäß genau das, was privat
ist: Gesichter, Orte, Aufnahmedaten.

Das betrifft nicht nur das offensichtliche Foto in der Mitte, sondern auch:

- Vorschaubilder am Rand, Filmstreifen, Personen-Kacheln
- Dateinamen und Pfade in der Informationsleiste
- GPS-Orte in der Kartenansicht
- Namen echter Personen im Personen-Tab

## Vorgehen für neue Aufnahmen

1. **Eigene Demo-Bibliothek anlegen.** In den Einstellungen unter
   Speicherort einen leeren Ordner wählen (z.B. `~/PhotoVault-Demo`) – die
   eigene Bibliothek bleibt davon unberührt.
2. **Frei lizenzierte Fotos importieren.** Geeignete Quellen:
   - [Unsplash](https://unsplash.com/license) – kostenlos nutzbar
   - [Wikimedia Commons](https://commons.wikimedia.org/) – gemeinfrei/CC
   - [raw.pixls.us](https://raw.pixls.us/) – RAW-Beispiele, meist CC0
     (dieselbe Quelle nutzt `tool/fetch_format_samples.sh`)
3. **Aufnehmen.** Unter macOS mit `⇧⌘4`, dann Leertaste, dann auf das
   Fenster klicken – das erfasst nur das Fenster, nicht den Schreibtisch.
4. **Vor dem Commit prüfen:** Ist auf dem Bild irgendetwas zu sehen, das zu
   einer realen Person, einem realen Ort oder einem privaten Dateipfad
   gehört? Im Zweifel neu aufnehmen.

## Zwei Wege, ein Bild zu bekommen

Die vier Aufnahmen oben sind am **Fenster** entstanden. Für den
Stammbaum ging das nicht: Die Ansicht braucht eine Familie über vier
Generationen, und die von Hand über die Oberfläche einzugeben, nur um
davon ein Bild zu machen, wäre mühsam und bei jeder Wiederholung anders.

Diese drei Bilder werden deshalb **gerendert** – von
`tool/bildschirmfotos_test.dart`:

```
flutter test tool/bildschirmfotos_test.dart
```

Gezeichnet wird derselbe Widgetbaum mit demselben Thema; das Bild zeigt
also die App, nur aufgenommen durch die Testbühne statt durch den
Fensterserver. Damit die Schrift lesbar ist statt als Platzhalterbalken
zu erscheinen, lädt das Werkzeug eine Systemschrift und die
Symbolschrift nach.

**Auf diesen drei Bildern ist kein einziges Foto zu sehen.** Die
Stammbaum-Ansichten kommen ohne aus, und die gezeigte Familie ist frei
erfunden. Die Regel oben ist damit nicht nur eingehalten, sondern
gegenstandslos.

Vom **Fächer** gibt es bewusst keine Aufnahme: Er beschriftet seine Ringe
mit einem `TextPainter`, dessen Schrift weder aus dem Thema noch aus
einem `FontLoader` kommt – dort blieben Platzhalterbalken stehen. Ein
Bild, das die App kaputt aussehen lässt, obwohl sie es nicht ist, wäre
schlechter als keines.

## Erwartete Dateien

| Datei | Inhalt | Entstanden |
|---|---|---|
| `timeline.png` | Timeline mit Monatsgruppierung | am Fenster |
| `entwickeln.png` | Entwickeln-Bildschirm mit Histogramm und Reglern | am Fenster |
| `personen.png` | Personen-Tab mit Gesichtsgruppen | am Fenster |
| `karte.png` | Kartenansicht mit Fotoorten | am Fenster |
| `stammbaum.png` | Stammbaum, Baum-Sicht um eine Person | gerendert |
| `stammbaum-sanduhr.png` | Sanduhr mit Seitenlinie über vier Generationen | gerendert |
| `stammbaum-verwandte.png` | Alle Verwandten mit berechneter Bezeichnung | gerendert |

Sind die Dateien vorhanden, können sie in der Haupt-README wieder als
Bildtabelle eingebunden werden:

```markdown
| Timeline | Entwickeln |
|---|---|
| ![Timeline](docs/screenshots/timeline.png) | ![Entwickeln](docs/screenshots/entwickeln.png) |
```
