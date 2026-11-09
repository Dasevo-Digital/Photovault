import 'package:kern/db/database.dart';
import 'package:uuid/uuid.dart';

import 'kamerarolle.dart';
import 'stand.dart';

/// Stapelt eine gesicherte Serie vom iPhone auf dem Server (#314).
///
/// Jedes Bild einer Serie ist auf dem Server eine eigene Aufnahme; ohne
/// Stapel stünden dreissig fast gleiche Bilder in der Zeitleiste. Oben liegt
/// das Titelbild, das auch die Fotos-App zeigt.
///
/// Erst wenn alle Bilder gesichert sind und die Kopie der Bibliothek sie
/// kennt, und nur einmal je Serie: Wer sie danach von Hand auflöst, bekommt
/// sie nicht wieder gestapelt. Liegt ein Bild schon in einem Stapel, bleibt
/// alles, wie es ist.
class Serienstapel {
  const Serienstapel({required this.stand, required this.db});

  final Sicherungsstand stand;
  final AppDatabase db;

  /// Gibt zurück, wie viele Serien neu gestapelt wurden.
  Future<int> bilde(List<Rolleneintrag> alle) async {
    final gruppen = <String, List<Rolleneintrag>>{};
    for (final e in alle) {
      final serie = e.serie;
      if (serie != null) (gruppen[serie] ??= []).add(e);
    }
    if (gruppen.isEmpty) return 0;
    final erledigt = stand.gestapelteSerien();
    final gesichert = stand.gesichertMitAufnahme();
    var gebildet = 0;
    for (final MapEntry(key: serie, value: teile) in gruppen.entries) {
      if (erledigt.contains(serie) || teile.length < 2) continue;
      final titel = teile.where((e) => e.serientitel).firstOrNull;
      final aufnahmen = [for (final e in teile) gesichert[e.id]?.aufnahme];
      if (titel == null || aufnahmen.contains(null)) continue;
      // Zwei gleiche Dateien sind auf dem Server eine Aufnahme.
      final ids = aufnahmen.nonNulls.toSet().toList();
      if (ids.length < 2) {
        stand.merkeSerie(serie);
        continue;
      }
      final zeilen = await (db.select(
        db.assets,
      )..where((t) => t.id.isIn(ids))).get();
      if (zeilen.length < ids.length) continue;
      if (zeilen.every((z) => z.stackId == null)) {
        await db.fuehreAus(
          SerieBilden(const Uuid().v4(), ids, gesichert[titel.id]!.aufnahme),
        );
        gebildet++;
      }
      stand.merkeSerie(serie);
    }
    return gebildet;
  }
}
