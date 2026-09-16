/// Kacheln holen und in ein Höhengitter samt Kartenbild verwandeln.
///
/// Getrennt von `gelaendekacheln.dart`, weil dort nur gerechnet wird:
/// Jede Umrechnung lässt sich ohne Netz prüfen, und was hier steht,
/// braucht beides – einen Server und `dart:ui`.
///
/// **Die Karte gehört dazu.** Geländehöhen sind keine Karte: Ohne die
/// Kartenkacheln darüber sieht man Berge ohne Wege, und eine Wanderung
/// vor einer namenlosen Landschaft beantwortet keine Frage. Deshalb holt
/// dieser Dienst beides und legt das eine als Textur auf das andere.
library;

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_map/flutter_map.dart'
    show CachedMapTile, CachedMapTileMetadata, MapCachingProvider;
import 'package:http/http.dart' as http;

import '../widgets/mini_location_map.dart'
    show kachelNochmalVersuchen, kartenKachelFrische, kartenKachelspeicher;
import 'gelaendeebenen.dart';
import 'gelaendekacheln.dart';
import 'hoehenlinien.dart';

/// Wie lange auf eine einzelne Kachel gewartet wird.
///
/// Acht Sekunden. Eine Landschaft, die auf die letzte von sechzehn
/// Kacheln unbegrenzt wartet, erscheint nie.
const Duration gelaendeZeitgrenze = Duration(seconds: 8);

/// Der Kachelspeicher, den auch die Karten benutzen.
///
/// **Es ist derselbe** – eingerichtet in `kartenSpeicherEinrichten()` beim
/// Start, 300 MB, dreissig Tage frisch. Das ist der Kern dieser Funktion
/// und nicht ihr Nebeneffekt: Die Landschaft holt dieselben
/// OpenTopoMap-Kacheln, die die Routenkarte einen Knopfdruck vorher schon
/// geholt hat. Ohne den gemeinsamen Speicher lädt sie dieselben Bilder
/// ein zweites Mal, und beim nächsten Öffnen ein drittes.
///
/// Am echten Speicher gemessen, ein Ausschnitt im Harz
/// (`integration_test/gelaende_speicher_test.dart`):
///
/// ```
/// 1. Öffnen: 32 Abrufe, 906 ms
/// 2. Öffnen:  0 Abrufe,  26 ms
/// ```
///
/// Und ohne Netz erscheint die Landschaft weiterhin, statt „konnte
/// nicht geladen werden" zu melden.
///
/// Angelegt wird er weiterhin an genau einer Stelle – in
/// `mini_location_map.dart`; hier wird er nur geholt.
MapCachingProvider gemeinsamerKachelspeicher() => kartenKachelspeicher();

/// Holt eine Kachel – erst aus dem Speicher, dann aus dem Netz.
///
/// Drei Dinge, die der frühere Weg nicht tat:
///
/// 1. **Aus dem Speicher lesen.** Siehe [gemeinsamerKachelspeicher].
/// 2. **Bei 404 noch einmal fragen.** OpenTopoMap rendert Kacheln bei
///    Bedarf und antwortet auf eine noch nicht fertige nicht mit „warte",
///    sondern mit 404 – ausführlich begründet bei
///    [kachelNochmalVersuchen]. Die Karte hält sich seit Prüfrunde 12
///    daran, die Landschaft nicht: Dort wurde daraus ein dauerhaftes Loch
///    im Gelände.
/// 3. **Eine abgelaufene Kachel ist besser als keine.** Wer ohne Netz
///    unterwegs ist, bekam bisher „konnte nicht geladen werden", obwohl
///    die Kacheln auf der Platte lagen.
Future<Uint8List?> holeKachelRoh(
  http.Client netz,
  MapCachingProvider speicher,
  String url, {
  Map<String, String> kopf = const {},
}) async {
  CachedMapTile? gespeichert;
  if (speicher.isSupported) {
    try {
      gespeichert = await speicher.getTile(url);
    } catch (_) {
      // Ein beschädigter Eintrag ist kein Grund, die Kachel aufzugeben –
      // sie wird gleich frisch geholt.
      gespeichert = null;
    }
    if (gespeichert != null && !gespeichert.metadata.isStale) {
      return gespeichert.bytes;
    }
  }

  for (var versuch = 0; versuch < 2; versuch++) {
    try {
      final antwort =
          await netz.get(Uri.parse(url), headers: kopf).timeout(gelaendeZeitgrenze);
      if (antwort.statusCode == 200) {
        if (speicher.isSupported) {
          try {
            await speicher.putTile(
              url: url,
              metadata: CachedMapTileMetadata(
                staleAt: DateTime.timestamp().add(kartenKachelFrische),
                lastModified: null,
                etag: null,
              ),
              bytes: antwort.bodyBytes,
            );
          } catch (_) {
            // Nicht speichern können heisst nicht, nicht anzeigen können.
          }
        }
        return antwort.bodyBytes;
      }
      if (!kachelNochmalVersuchen(antwort.statusCode)) break;
    } catch (_) {
      // Zeitüberschreitung oder abgerissene Verbindung: einmal noch.
    }
  }

  // Nichts aus dem Netz – dann lieber die abgelaufene Kachel als ein Loch.
  return gespeichert?.bytes;
}

/// Holt die Geländehöhen für einen Ausschnitt.
///
/// Fehlende oder fehlerhafte Kacheln werden **übersprungen**, nicht als
/// Fehler behandelt: Fünfzehn von sechzehn Kacheln ergeben eine
/// Landschaft mit einem Loch, null Kacheln ergeben nichts. Kommt keine
/// einzige an, ist das Ergebnis `null`.
Future<Hoehengitter?> ladeHoehengitter({
  required double sued,
  required double west,
  required double nord,
  required double ost,
  required http.Client netz,
  MapCachingProvider? speicher,
  int hoechstensKacheln = 16,
  int hoechsteStufe = gelaendeHoechsteStufe,
}) async {
  final bereich = kachelbereich(
    sued: sued,
    west: west,
    nord: nord,
    ost: ost,
    hoechstensKacheln: hoechstensKacheln,
    hoechsteStufe: hoechsteStufe,
  );
  final adressen = kacheladressen(bereich);
  final sp = speicher ?? gemeinsamerKachelspeicher();

  final bilder = await Future.wait([
    for (final a in adressen) _holeKachel(netz, sp, a.z, a.x, a.y),
  ]);
  final da = [
    for (final b in bilder)
      if (b != null) b,
  ];
  if (da.isEmpty) return null;

  return gitterAusKacheln(
    zoom: bereich.zoom,
    x0: bereich.x0,
    y0: bereich.y0,
    x1: bereich.x1,
    y1: bereich.y1,
    kacheln: da,
  );
}

Future<Kachelbild?> _holeKachel(
    http.Client netz, MapCachingProvider speicher, int z, int x, int y) async {
  try {
    final roh = await holeKachelRoh(netz, speicher, kacheladresse(z, x, y));
    if (roh == null) return null;
    final rgba = await _nachRgba(roh);
    return rgba == null ? null : (x: x, y: y, rgba: rgba);
  } catch (_) {
    // Eine einzelne Kachel darf ausfallen, ohne die Landschaft
    // mitzunehmen.
    return null;
  }
}

Future<Uint8List?> _nachRgba(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  try {
    final bild = (await codec.getNextFrame()).image;
    try {
      final daten =
          await bild.toByteData(format: ui.ImageByteFormat.rawRgba);
      return daten?.buffer.asUint8List();
    } finally {
      bild.dispose();
    }
  } finally {
    codec.dispose();
  }
}

/// Holt dieselben Kacheln als Kartenbild – die **Übersicht** über der
/// ganzen Landschaft.
///
/// Genau derselbe Ausschnitt und dieselbe Stufe wie beim Höhengitter,
/// sonst läge die Karte verschoben auf der Landschaft.
///
/// **Seit die Blöcke ihre eigenen Texturen holen, ist das hier der
/// Rückfall** – das Bild, das steht, solange ein Block noch lädt oder
/// zu weit weg ist, um einen eigenen Abruf zu lohnen. Es trägt trotzdem
/// alle gewählten Ebenen: Wer die Wegeebene eingeschaltet hat und in die
/// Ferne sieht, soll dort nicht plötzlich eine Karte ohne Wege sehen.
Future<ui.Image?> ladeKartenbild({
  required double sued,
  required double west,
  required double nord,
  required double ost,
  required http.Client netz,
  MapCachingProvider? speicher,
  Gelaendekarte karte = const Gelaendekarte(),
  Hoehengitter? hoehen,
  int hoechstensKacheln = 16,
  int hoechsteStufe = gelaendeHoechsteStufe,
}) async {
  final bereich = kachelbereich(
    sued: sued,
    west: west,
    nord: nord,
    ost: ost,
    hoechstensKacheln: hoechstensKacheln,
    // OpenTopoMap rendert nur bis 17; die Geländekacheln hören bei 15
    // auf. Es ist also dieselbe Stufe – aber die Grenze steht hier
    // trotzdem, damit ein Wechsel der Höhenquelle die Karte nicht
    // sprengt.
    hoechsteStufe: hoechsteStufe,
  );
  final adressen = kacheladressen(bereich);
  final sp = speicher ?? gemeinsamerKachelspeicher();
  final spalten = bereich.x1 - bereich.x0 + 1;
  final zeilen = bereich.y1 - bereich.y0 + 1;

  final sammler = ui.PictureRecorder();
  final leinwand = ui.Canvas(sammler);
  var grundDa = false;

  // **Die Liste einmal holen und mit dem Zaehler arbeiten.** `ebenen`
  // baut bei jedem Zugriff eine neue Liste mit neuen Objekten, und
  // `Kartenebene` hat kein eigenes Gleichheitszeichen: `ebene ==
  // karte.ebenen.first` war deshalb NIE wahr, und das Uebersichtsbild kam
  // gar nicht mehr zustande.
  final ebenen = karte.ebenen;
  for (var nr = 0; nr < ebenen.length; nr++) {
    final ebene = ebenen[nr];
    final bilder = await Future.wait([
      for (final a in adressen)
        _holeKartenkachel(netz, sp, ebene, a.z, a.x, a.y),
    ]);
    if (bilder.every((b) => b == null)) continue;
    if (nr == 0) grundDa = true;
    for (var i = 0; i < adressen.length; i++) {
      final bild = bilder[i];
      if (bild == null) continue;
      final sx = (adressen[i].x - bereich.x0) * kachelKante.toDouble();
      final sy = (adressen[i].y - bereich.y0) * kachelKante.toDouble();
      leinwand.drawImageRect(
        bild,
        ui.Rect.fromLTWH(0, 0, bild.width.toDouble(), bild.height.toDouble()),
        ui.Rect.fromLTWH(
            sx, sy, kachelKante.toDouble(), kachelKante.toDouble()),
        ui.Paint(),
      );
      bild.dispose();
    }
  }

  // Die Höhenlinien auch hier – sonst tauchten sie auf, sobald ein Block
  // seine eigene Textur bekommt, und verschwänden wieder, sobald er
  // verdrängt wird.
  if (grundDa && karte.hoehenlinien && hoehen != null) {
    final spanne = hoehen.spanne;
    zeichneHoehenlinien(
      leinwand,
      hoehenlinien(
        hoehen,
        west: kachelWesten(bereich.x0, bereich.zoom),
        ost: kachelWesten(bereich.x1 + 1, bereich.zoom),
        nord: kachelNorden(bereich.y0, bereich.zoom),
        sued: kachelNorden(bereich.y1 + 1, bereich.zoom),
        abstand: hoehenlinienAbstand(spanne.hoch - spanne.tief),
        maschen: 128,
        grundstufe: bereich.zoom,
      ),
      (spalten * kachelKante).toDouble(),
      (zeilen * kachelKante).toDouble(),
    );
  }

  final bild = grundDa
      ? await sammler
          .endRecording()
          .toImage(spalten * kachelKante, zeilen * kachelKante)
      : null;
  if (!grundDa) sammler.endRecording().dispose();
  return bild;
}

Future<ui.Image?> _holeKartenkachel(http.Client netz,
    MapCachingProvider speicher, Kartenebene ebene, int z, int x, int y) async {
  try {
    final roh = await holeKachelRoh(
      netz,
      speicher,
      kacheladresse(z, x, y, vorlage: ebene.urlVorlage),
      // Die Anbieter bitten ausdrücklich um eine aussagekräftige Kennung
      // statt der Vorgabe der Bibliothek.
      kopf: const {'User-Agent': 'com.example.photoVault'},
    );
    if (roh == null) return null;
    final codec = await ui.instantiateImageCodec(roh);
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  } catch (_) {
    return null;
  }
}
