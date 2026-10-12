# Anpassungen gegenüber flutter_earth_globe 2.2.1

Diese Kopie stammt aus dem Paket `flutter_earth_globe` 2.2.1 (MIT, © George
Panagiotou, <https://github.com/Pana-g/flutter_earth_globe>), unverändert aus
dem Archiv von pub.dev übernommen. Weggelassen sind `example/`, `doc/`,
`screenshots/` und `README.md`, in `pubspec.yaml` der Abschnitt
`screenshots`. Geändert sind drei Dinge (Issue #9).

## 1. Kachelmosaik über der Grundtextur

Die Kugel trägt eine einzelne Erdtextur. Bei 8192 × 4096 Punkten entspricht
sie ungefähr Kachelstufe 5; weiter heranzoomen vergrösserte nur. Jetzt kann
die App ein Mosaik aus Web-Mercator-Kacheln setzen, und der Shader zeigt es
dort, wo es liegt.

| Datei | Was |
|---|---|
| `shaders/sphere.frag` | Sechs Uniforms (`uDetailAktiv`, `uDetailZoom`, `uDetailX0`, `uDetailY0`, `uDetailBreite`, `uDetailHoehe`) und ein dritter Abtaster `uDetail`. Aus Breite und Länge des Punkts wird die Kachelposition (Web Mercator, über die Datumsgrenze per `mod`); im Mosaik kommt die Farbe von dort, zum Rand hin eine halbe Kachel lang überblendet, gewichtet mit dem Alphakanal (fehlende Kacheln sind durchsichtig). Jenseits von ±85,05° gibt es keine Kacheln. |
| `lib/sphere_shader_painter.dart` | Setzt die sechs Werte und den Abtaster bei jedem Bild; ohne Mosaik zeigt der Abtaster auf die Grundtextur, damit er nie ein freigegebenes Bild hält. |
| `lib/flutter_earth_globe_controller.dart` | `setzeDetail(bild, stufe:, x0:, y0:, breite:, hoehe:)` und `blick`: die Koordinaten unter der Mitte der Ansicht und der Kugelradius. |
| `lib/rotating_globe.dart` | Reicht das Mosaik an den Maler weiter und meldet nach jedem Bild mit geänderter Drehung oder Zoomstufe den Blick (über `convert2DPointToSphereCoordinates`, dieselbe Rechnung wie beim Antippen). |

Die Kacheln holt und setzt die App selbst: `lib/services/globuskacheln.dart`.

## 2. Bilinear statt des nächsten Pixels

`FragmentShader.setImageSampler` tastet ohne Angabe den nächsten Pixel ab.
Beim Heranzoomen stand die Textur dadurch in Klötzchen da. Die Abtaster für
Tag- und Nachttextur und das Mosaik nehmen jetzt `FilterQuality.low`.

## 3. Keine Pixelkopie, solange der Shader zeichnet

`loadSurface` legte zu jeder Textur eine `Uint32List`-Kopie an – auch wenn
der Shader zeichnet, der sie nie liest. Bei der 8K-Textur waren das 134 MB
zusätzlich, und der Globus erschien erst, wenn die Kopie fertig war. Jetzt
entsteht sie in `verarbeiteFuerCpu()` erst, wenn der CPU-Weg sie braucht
(`rotating_globe.dart`, dort wo er vorher mangels Kopie abbrach).
