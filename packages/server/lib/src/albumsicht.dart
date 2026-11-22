import 'package:drift/drift.dart';
import 'package:kern/db/database.dart';

/// Was in einem Album sichtbar liegt, gefragt in der Datenbank statt über
/// alle Zeilen des Albums (#436) – dieselbe Sichtbarkeit wie
/// `albumAufnahmen`: nichts Gesperrtes, nichts aus dem Papierkorb, von
/// einem Stapel nur das Titelbild.
///
/// Vorher luden die Liste der Freigaben, „Gefällt mir“, Kommentare und die
/// Aktivität eines geteilten Albums jedes Mal alle Zeilen des Albums – nur
/// um sie zu zählen oder eine einzige Kennung darin zu suchen.
extension Albumsicht on AppDatabase {
  /// Wie viele Aufnahmen in [album] sichtbar sind.
  Future<int> sichtbareAnzahl(String album) async {
    final n = assets.id.count();
    final q = selectOnly(assets)
      ..addColumns([n])
      ..where(sichtbareAufnahmeImAlbum(album));
    return (await q.getSingle()).read(n) ?? 0;
  }

  /// Welche von [ids] sichtbar in [album] liegen.
  Future<Set<String>> sichtbarIn(String album, Iterable<String> ids) async {
    final treffer = <String>{};
    for (final stueck in inStuecken(ids.toSet())) {
      final q = selectOnly(assets)
        ..addColumns([assets.id])
        ..where(sichtbareAufnahmeImAlbum(album) & assets.id.isIn(stueck));
      treffer.addAll([for (final z in await q.get()) z.read(assets.id)!]);
    }
    return treffer;
  }

  /// Ob [id] sichtbar in [album] liegt.
  Future<bool> sichtbarImAlbum(String album, String id) async =>
      (await (selectOnly(assets)
                ..addColumns([assets.id])
                ..where(sichtbareAufnahmeImAlbum(album) & assets.id.equals(id))
                ..limit(1))
              .get())
          .isNotEmpty;
}
