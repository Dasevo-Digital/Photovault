import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:flutter_earth_globe/flutter_earth_globe_controller.dart';
import 'package:flutter_map/flutter_map.dart' show MapCachingProvider;
import 'package:http/http.dart' as http;

import 'gelaende_laden.dart';
import 'gelaendeebenen.dart';
import 'gelaendekacheln.dart';
import 'netzkennung.dart';

/// Luftbildkacheln für den Globus (#9).
///
/// Die Kugel trägt eine Erdtextur von 8192 × 4096 Punkten. Das entspricht
/// ungefähr Kachelstufe 5; ab Zoomstufe 3 brachte Heranzoomen deshalb kein
/// Detail mehr. Jetzt lädt der Globus beim Heranzoomen die Luftbildkacheln
/// nach, die auch die Landschaft im Überflug zeigt (Esri), setzt sie zu
/// einem Mosaik um den Blickpunkt zusammen und legt es im Shader über die
/// Grundtextur (third_party/flutter_earth_globe, ANPASSUNGEN.md).
///
/// **Erst ab Stufe [globusKachelnAb].** Bis dahin zeigt die Grundtextur
/// mindestens halb so fein, wie der Bildschirm auflöst; Kacheln zu holen
/// lohnte nicht. Ohne Netz bleibt es bei der Grundtextur, wie bisher.
class Globuskacheln {
  Globuskacheln(
    this._regler, {
    required this._ansicht,
    http.Client? netz,
    MapCachingProvider? speicher,
  }) : _netz = netz ?? http.Client(),
       _eigenesNetz = netz == null,
       _speicher = speicher ?? gemeinsamerKachelspeicher() {
    _regler.blick.addListener(_blickGeaendert);
    // Steht der Globus schon, kommt keine Änderung mehr, auf die der
    // Lader hören könnte – also gleich einmal nachsehen.
    if (_regler.blick.value != null) _blickGeaendert();
  }

  final FlutterEarthGlobeController _regler;
  final ({double breite, double hoehe, double pixeldichte}) Function() _ansicht;
  final http.Client _netz;
  final bool _eigenesNetz;
  final MapCachingProvider _speicher;

  /// Ob gerade Luftbilder auf der Kugel liegen – für den Nachweis.
  bool get aktiv => _bild != null;

  /// Meldet sich, wenn [aktiv] umschlägt.
  void Function()? beiWechsel;

  ui.Image? _bild;
  Kachelfenster? _fenster;
  Timer? _verzoegerung;
  int _auftrag = 0;
  bool _fertig = false;

  void _blickGeaendert() {
    // Erst wenn der Globus kurz stillsteht: Beim Drehen ändert sich der
    // Blick in jedem Bild, und jedes Mosaik dazwischen wäre umsonst
    // geholt.
    _verzoegerung?.cancel();
    _verzoegerung = Timer(const Duration(milliseconds: 250), _aktualisiere);
  }

  Future<void> _aktualisiere() async {
    final blick = _regler.blick.value;
    if (blick == null || _fertig) return;
    final a = _ansicht();
    final fenster = globusFenster(
      breitengrad: blick.mitte.latitude,
      laengengrad: blick.mitte.longitude,
      radius: blick.radius,
      ansichtBreite: a.breite,
      ansichtHoehe: a.hoehe,
      pixeldichte: a.pixeldichte,
    );
    if (fenster == null) {
      _setze(null, null);
      return;
    }
    final alt = _fenster;
    if (alt != null && alt.umfasst(fenster)) return;

    final auftrag = ++_auftrag;
    final bild = await ladeMosaik(fenster, _netz, _speicher);
    if (_fertig || auftrag != _auftrag) {
      bild?.dispose();
      return;
    }
    _setze(bild, bild == null ? null : fenster);
  }

  void _setze(ui.Image? bild, Kachelfenster? fenster) {
    final vorher = _bild;
    final warAktiv = vorher != null;
    if (vorher == null && bild == null) return;
    _bild = bild;
    _fenster = fenster;
    _regler.setzeDetail(
      bild,
      stufe: fenster?.stufe ?? 0,
      x0: (fenster?.x0 ?? 0).toDouble(),
      y0: (fenster?.y0 ?? 0).toDouble(),
      breite: (fenster?.breite ?? 0).toDouble(),
      hoehe: (fenster?.hoehe ?? 0).toDouble(),
    );
    // Das alte Mosaik erst nach dem nächsten Bild freigeben – bis dahin
    // kann der Maler es noch halten.
    if (vorher != null) {
      WidgetsBinding.instance.endOfFrame.then((_) => vorher.dispose());
    }
    if (warAktiv != aktiv) beiWechsel?.call();
  }

  void dispose() {
    _fertig = true;
    _verzoegerung?.cancel();
    _regler.blick.removeListener(_blickGeaendert);
    final bild = _bild;
    _bild = null;
    if (bild != null) {
      _regler.setzeDetail(null);
      WidgetsBinding.instance.endOfFrame.then((_) => bild.dispose());
    }
    if (_eigenesNetz) _netz.close();
  }
}

/// Ab dieser Kachelstufe lädt der Globus Luftbilder nach. Die Grundtextur
/// (8192 Punkte für den Erdumfang) entspricht Stufe 5; ab 6 zeigen die
/// Kacheln mindestens doppelt so fein.
const globusKachelnAb = 6;

/// Höchstens so viele Kacheln breit und hoch wird ein Mosaik: 4096 × 3072
/// Punkte, 48 MB. Verlangt die Ansicht mehr, wird eine Stufe gröber
/// geladen statt nur ein Teil des Bildschirms.
const globusMosaikBreite = 16;
const globusMosaikHoehe = 12;

/// Ein Ausschnitt aus dem Kachelgitter einer Stufe. [x0] darf über den
/// Rand des Gitters hinausgehen (Datumsgrenze); geladen wird modulo
/// 2^[stufe].
class Kachelfenster {
  const Kachelfenster(this.stufe, this.x0, this.y0, this.breite, this.hoehe);

  final int stufe;
  final int x0;
  final int y0;
  final int breite;
  final int hoehe;

  /// Ob dieses Fenster [anderes] ganz enthält – dann muss nichts neu
  /// geladen werden.
  bool umfasst(Kachelfenster anderes) {
    if (anderes.stufe != stufe) return false;
    final n = 1 << stufe;
    var dx = (anderes.x0 - x0) % n;
    if (dx < 0) dx += n;
    return dx + anderes.breite <= breite &&
        anderes.y0 >= y0 &&
        anderes.y0 + anderes.hoehe <= y0 + hoehe;
  }

  @override
  String toString() => 'Kachelfenster($stufe: $x0,$y0 ${breite}x$hoehe)';
}

/// Die Kachelstufe, deren Kacheln am Blickpunkt ungefähr so fein sind wie
/// der Bildschirm.
///
/// Der Erdumfang auf der Kugel misst 2π·[radius] Punkte, auf dem
/// Breitengrad φ nur cos φ davon; eine Stufe z teilt den Umfang in 2^z
/// Kacheln zu 256 Punkten.
int globusKachelstufe({
  required double radius,
  required double pixeldichte,
  required double breitengrad,
}) {
  final cos = math.cos(breitengrad * math.pi / 180).abs().clamp(0.05, 1.0);
  final umfang = 2 * math.pi * radius * pixeldichte * cos;
  if (umfang <= 256) return 0;
  return (math.log(umfang / 256) / math.ln2).round();
}

/// Das Kachelfenster, das die Ansicht um ([breitengrad], [laengengrad])
/// abdeckt, oder `null`, wenn die Grundtextur genügt.
Kachelfenster? globusFenster({
  required double breitengrad,
  required double laengengrad,
  required double radius,
  required double ansichtBreite,
  required double ansichtHoehe,
  required double pixeldichte,
}) {
  var stufe = math.min(
    globusKachelstufe(
      radius: radius,
      pixeldichte: pixeldichte,
      breitengrad: breitengrad,
    ),
    luftbildEbene.hoechsteStufe,
  );
  if (stufe < globusKachelnAb || breitengrad.abs() > 85) return null;

  final cos = math.cos(breitengrad * math.pi / 180).abs().clamp(0.05, 1.0);
  // Wie viele Kacheln die Ansicht überspannt: Eine Kachel misst am
  // Blickpunkt 2π·R·cos φ / 2^z Bildschirmpunkte. Die Kugel kann
  // kleiner sein als die Ansicht, dann zählt ihr Durchmesser.
  int spanne(double ausdehnung, int z) {
    final kachel = 2 * math.pi * radius * pixeldichte * cos / (1 << z);
    final sichtbar = math.min(ausdehnung, 2 * radius) * pixeldichte;
    return (sichtbar / kachel).ceil() + 2;
  }

  var breite = spanne(ansichtBreite, stufe);
  var hoehe = spanne(ansichtHoehe, stufe);
  while ((breite > globusMosaikBreite || hoehe > globusMosaikHoehe) &&
      stufe > globusKachelnAb) {
    stufe--;
    breite = spanne(ansichtBreite, stufe);
    hoehe = spanne(ansichtHoehe, stufe);
  }
  breite = math.min(breite, globusMosaikBreite);
  hoehe = math.min(hoehe, globusMosaikHoehe);

  final n = 1 << stufe;
  hoehe = math.min(hoehe, n);
  breite = math.min(breite, n);
  final kx = (laengengrad + 180) / 360 * n;
  final phi = breitengrad * math.pi / 180;
  final ky =
      (1 - math.log(math.tan(phi) + 1 / math.cos(phi)) / math.pi) / 2 * n;
  final x0 = (kx - breite / 2).floor();
  final y0 = (ky - hoehe / 2).floor().clamp(0, n - hoehe);
  return Kachelfenster(stufe, x0, y0, breite, hoehe);
}

/// Holt die Kacheln von [fenster] und setzt sie zu einem Bild zusammen.
/// Fehlende Kacheln bleiben durchsichtig; dort zeigt der Shader die
/// Grundtextur. `null`, wenn keine einzige kam.
Future<ui.Image?> ladeMosaik(
  Kachelfenster fenster,
  http.Client netz,
  MapCachingProvider speicher, {
  int gleichzeitig = 6,
}) async {
  final n = 1 << fenster.stufe;
  final auftraege = <(int, int)>[
    for (var j = 0; j < fenster.hoehe; j++)
      for (var i = 0; i < fenster.breite; i++) (i, j),
  ];
  final kacheln = <(int, int, ui.Image)>[];
  var naechster = 0;

  Future<void> arbeiter() async {
    while (naechster < auftraege.length) {
      final (i, j) = auftraege[naechster++];
      final x = (fenster.x0 + i) % n;
      final y = fenster.y0 + j;
      try {
        final roh = await holeKachelRoh(
          netz,
          speicher,
          kacheladresse(
            fenster.stufe,
            x < 0 ? x + n : x,
            y,
            vorlage: luftbildEbene.urlVorlage,
          ),
          kopf: const {'User-Agent': netzkennung},
        );
        if (roh == null) continue;
        final codec = await ui.instantiateImageCodec(roh);
        try {
          kacheln.add((i, j, (await codec.getNextFrame()).image));
        } finally {
          codec.dispose();
        }
      } catch (_) {
        // Eine Kachel darf fehlen; dort bleibt die Grundtextur.
      }
    }
  }

  await Future.wait([for (var k = 0; k < gleichzeitig; k++) arbeiter()]);
  if (kacheln.isEmpty) return null;

  final aufnahme = ui.PictureRecorder();
  final leinwand = ui.Canvas(aufnahme);
  const kante = 256.0;
  for (final (i, j, bild) in kacheln) {
    leinwand.drawImageRect(
      bild,
      ui.Rect.fromLTWH(0, 0, bild.width.toDouble(), bild.height.toDouble()),
      ui.Rect.fromLTWH(i * kante, j * kante, kante, kante),
      ui.Paint()..filterQuality = ui.FilterQuality.low,
    );
  }
  final bild = aufnahme.endRecording();
  try {
    return await bild.toImage(
      (fenster.breite * kante).round(),
      (fenster.hoehe * kante).round(),
    );
  } finally {
    bild.dispose();
    for (final (_, _, k) in kacheln) {
      k.dispose();
    }
  }
}
