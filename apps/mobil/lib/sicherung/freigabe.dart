import 'package:kern/db/database.dart';

import 'kamerarolle.dart';
import 'stand.dart';

/// Speicher auf dem Telefon freigeben (Issue #129): löscht dort, was
/// sicher auf dem Server liegt – und nur das.
///
/// Drei Bedingungen, jede für sich notwendig: Die Aufnahme steht im
/// Sicherungsstand als hochgeladen oder als schon vorhanden erkannt; ihr
/// Änderungsstand ist seither derselbe (eine Bearbeitung nach der
/// Sicherung wäre sonst weg); und die Aufnahme auf dem Server steht in der
/// Kopie der Bibliothek noch da, nicht im Papierkorb.
class Speicherfreigabe {
  const Speicherfreigabe({
    required this.stand,
    required this.rolle,
    required this.db,
  });

  final Sicherungsstand stand;
  final Kamerarolle rolle;
  final AppDatabase db;

  /// Die Kennungen auf dem Telefon, die weg können.
  Future<List<String>> kandidaten() async {
    final gesichert = stand.gesichertMitAufnahme();
    if (gesichert.isEmpty) return const [];
    final aufDemTelefon = <String, String>{};
    for (final e in await rolle.eintraege(videos: true)) {
      final g = gesichert[e.id];
      if (g != null && g.geaendert == e.geaendert.millisecondsSinceEpoch) {
        aufDemTelefon[e.id] = g.aufnahme;
      }
    }
    final da = await db.vorhandeneAufnahmen(aufDemTelefon.values);
    return [
      for (final MapEntry(key: lokal, value: aufnahme) in aufDemTelefon.entries)
        if (da.contains(aufnahme)) lokal,
    ];
  }

  /// Löscht [ids] vom Telefon; das System fragt dabei selbst noch einmal.
  /// Gibt zurück, wie viele wirklich gingen.
  Future<int> gib(List<String> ids) =>
      ids.isEmpty ? Future.value(0) : rolle.loesche(ids);
}
