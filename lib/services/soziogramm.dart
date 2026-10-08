/// **Wer mit wem auf Fotos ist** – als Netz.
///
/// MacFamilyTree zeigt ein Soziogramm der eingetragenen Beziehungen. Hier
/// steht etwas anderes und Eigenes: Die Fotos selbst sagen, wer mit wem
/// Zeit verbracht hat. Jede Person ist ein Knoten, jedes gemeinsame Foto
/// verstärkt die Linie zwischen zweien.
///
/// Rein und ohne Datenbankklassen, damit sich Zählung und Anordnung prüfen
/// lassen: Die Anordnung ist ein Kräftemodell mit festem Anfangszustand –
/// dieselbe Bibliothek ergibt zweimal dasselbe Bild.
library;

import 'dart:math' as math;
import 'dart:ui';

/// Wie viele Personen das Netz höchstens zeigt – die mit den meisten
/// Fotos. Mehr werden ein Knäuel.
const soziogrammHoechstensPersonen = 30;

/// Eine Linie zwischen zweien, mit der Zahl gemeinsamer Fotos.
typedef Soziogrammkante = ({String a, String b, int fotos});

class Soziogramm {
  /// Person -> Zahl ihrer Fotos, nur die gezeigten.
  final Map<String, int> personen;

  /// Die Linien, die stärksten zuerst.
  final List<Soziogrammkante> kanten;

  const Soziogramm({required this.personen, required this.kanten});

  bool get istLeer => kanten.isEmpty;
}

/// Zählt aus [auftritte] (je Gesicht: Person und Foto), wer wie oft mit
/// wem auf einem Foto ist.
///
/// Gezählt werden Fotos, nicht Gesichter: Wer auf einem Bild zweimal
/// erkannt wurde – im Spiegel, auf einem Plakat im Hintergrund –, war
/// trotzdem nur einmal dabei. Und eine Linie braucht mindestens
/// [mindestens] gemeinsame Fotos; ein einziges zufälliges Gruppenbild
/// macht noch keine Verbindung.
Soziogramm soziogramm(
  Iterable<({String personId, String assetId})> auftritte, {
  int hoechstens = soziogrammHoechstensPersonen,
  int mindestens = 2,
}) {
  final jeFoto = <String, Set<String>>{};
  for (final a in auftritte) {
    (jeFoto[a.assetId] ??= {}).add(a.personId);
  }
  final fotosJePerson = <String, int>{};
  for (final personen in jeFoto.values) {
    for (final p in personen) {
      fotosJePerson[p] = (fotosJePerson[p] ?? 0) + 1;
    }
  }
  final gezeigt =
      (fotosJePerson.keys.toList()..sort((x, y) {
            final c = fotosJePerson[y]!.compareTo(fotosJePerson[x]!);
            return c != 0 ? c : x.compareTo(y);
          }))
          .take(hoechstens)
          .toSet();

  final paare = <String, int>{};
  for (final personen in jeFoto.values) {
    final dabei = personen.where(gezeigt.contains).toList()..sort();
    for (var i = 0; i < dabei.length; i++) {
      for (var j = i + 1; j < dabei.length; j++) {
        final k = '${dabei[i]}\u0000${dabei[j]}';
        paare[k] = (paare[k] ?? 0) + 1;
      }
    }
  }
  final kanten = <Soziogrammkante>[
    for (final MapEntry(key: k, value: n) in paare.entries)
      if (n >= mindestens)
        (a: k.split('\u0000')[0], b: k.split('\u0000')[1], fotos: n),
  ]..sort((x, y) => y.fotos.compareTo(x.fotos));

  // Wer mit niemandem verbunden ist, bleibt draussen: Ein einzelner Punkt
  // ohne Linie sagt in einem Netz nichts.
  final verbunden = {
    for (final k in kanten) ...[k.a, k.b],
  };
  return Soziogramm(
    personen: {
      for (final p in gezeigt)
        if (verbunden.contains(p)) p: fotosJePerson[p]!,
    },
    kanten: kanten,
  );
}

/// Ordnet die Personen von [netz] in einem Quadrat von 0 bis 1 an.
///
/// Ein Kräftemodell nach Fruchterman und Reingold: Alle stossen sich ab,
/// Linien ziehen an – je mehr gemeinsame Fotos, desto stärker. Begonnen
/// wird auf einem Kreis in fester Reihenfolge, nicht zufällig, damit das
/// Bild beim nächsten Öffnen dasselbe ist.
Map<String, Offset> soziogrammAnordnung(Soziogramm netz, {int schritte = 300}) {
  final ids = netz.personen.keys.toList()..sort();
  final n = ids.length;
  if (n == 0) return const {};
  if (n == 1) return {ids.single: const Offset(0.5, 0.5)};
  final pos = <String, Offset>{
    for (final (i, id) in ids.indexed)
      id: Offset(
        0.5 + 0.35 * math.cos(2 * math.pi * i / n),
        0.5 + 0.35 * math.sin(2 * math.pi * i / n),
      ),
  };
  final ideal = math.sqrt(1 / n) * 0.8;
  final staerkste = netz.kanten.fold(1, (m, k) => math.max(m, k.fotos));
  var temperatur = 0.1;
  for (var s = 0; s < schritte; s++) {
    final schub = {for (final id in ids) id: Offset.zero};
    for (var i = 0; i < n; i++) {
      for (var j = i + 1; j < n; j++) {
        final a = ids[i], b = ids[j];
        var d = pos[a]! - pos[b]!;
        if (d.distance < 1e-6) d = Offset(1e-3 * (i + 1), 1e-3 * (j + 1));
        final kraft = ideal * ideal / d.distance;
        final r = d / d.distance * kraft;
        schub[a] = schub[a]! + r;
        schub[b] = schub[b]! - r;
      }
    }
    for (final k in netz.kanten) {
      final d = pos[k.a]! - pos[k.b]!;
      final gewicht = 0.5 + k.fotos / staerkste;
      final kraft = d.distance * d.distance / ideal * gewicht;
      if (d.distance < 1e-9) continue;
      final z = d / d.distance * kraft;
      schub[k.a] = schub[k.a]! - z;
      schub[k.b] = schub[k.b]! + z;
    }
    for (final id in ids) {
      final v = schub[id]!;
      final laenge = v.distance;
      final weg = laenge < 1e-9
          ? Offset.zero
          : v / laenge * math.min(laenge, temperatur);
      final p = pos[id]! + weg;
      // Zur Mitte ziehen statt am Rand zu kleben.
      pos[id] =
          Offset(p.dx.clamp(0.0, 1.0), p.dy.clamp(0.0, 1.0)) * 0.995 +
          const Offset(0.5, 0.5) * 0.005;
    }
    temperatur = math.max(0.002, temperatur * 0.985);
  }
  // Auf die Fläche strecken, mit Rand für Bild und Namen.
  final xs = pos.values.map((p) => p.dx), ys = pos.values.map((p) => p.dy);
  final minX = xs.reduce(math.min), maxX = xs.reduce(math.max);
  final minY = ys.reduce(math.min), maxY = ys.reduce(math.max);
  final bx = math.max(maxX - minX, 1e-6), by = math.max(maxY - minY, 1e-6);
  return {
    for (final MapEntry(key: id, value: p) in pos.entries)
      id: Offset(
        0.08 + 0.84 * (p.dx - minX) / bx,
        0.08 + 0.84 * (p.dy - minY) / by,
      ),
  };
}
