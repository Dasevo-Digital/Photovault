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
/// Erst wenn alle Bilder, die noch auf dem Telefon liegen, gesichert sind und
/// die Kopie der Bibliothek sie kennt, und nur einmal je Serie. Welche Bilder
/// dazugehören, steht auch im Stand der Sicherung (#364): Wird eine Serie am
/// Telefon gelichtet, bevor sie gestapelt ist, kommen die schon gesicherten
/// trotzdem in den Stapel. Bilder, die jemand in der Fotos-App ausgewählt hat,
/// bleiben eigene Fotos.
///
/// Wer eine Serie von Hand auflöst, bekommt sie nicht wieder gestapelt – auch
/// nicht nach neuer Anmeldung oder von einem zweiten Gerät: Das merkt sich
/// die Bibliothek ([AppDatabase.merkeSerienausnahmen]). Liegt ein Bild schon
/// in einem Stapel, bleibt alles, wie es ist. Was am Server im Papierkorb
/// liegt oder gesperrt ist, kommt nicht dazu.
class Serienstapel {
  const Serienstapel({required this.stand, required this.db});

  final Sicherungsstand stand;
  final AppDatabase db;

  /// Gibt zurück, wie viele Serien neu gestapelt wurden.
  Future<int> bilde(List<Rolleneintrag> alle) async {
    final erledigt = stand.gestapelteSerien();
    final aufDemTelefon = <String, List<Rolleneintrag>>{};
    for (final e in alle) {
      final serie = e.stapelserie;
      if (serie != null && !erledigt.contains(serie)) {
        (aufDemTelefon[serie] ??= []).add(e);
      }
    }
    final gespeichert = stand.offeneSerien();
    final offen = {...aufDemTelefon.keys, ...gespeichert.keys};
    // Der häufige Fall: alles schon erledigt. Dann nichts weiter lesen.
    if (offen.isEmpty) return 0;
    final gesichert = stand.gesichertMitAufnahme();
    var gebildet = 0;
    for (final serie in offen) {
      final teile = aufDemTelefon[serie] ?? const <Rolleneintrag>[];
      if (teile.any((e) => gesichert[e.id] == null)) continue;
      // Kennung auf dem Server → ob Titelbild.
      final mitglieder = <String, bool>{};
      for (final e in teile) {
        final a = gesichert[e.id]!.aufnahme;
        mitglieder[a] = (mitglieder[a] ?? false) || e.serientitel;
      }
      for (final f in gespeichert[serie] ?? const []) {
        mitglieder[f.aufnahme] = (mitglieder[f.aufnahme] ?? false) || f.titel;
      }
      // Zwei gleiche Dateien sind auf dem Server eine Aufnahme.
      if (mitglieder.length < 2) {
        stand.merkeSerie(serie);
        continue;
      }
      final zeilen = await (db.select(
        db.assets,
      )..where((t) => t.id.isIn(mitglieder.keys))).get();
      if (zeilen.length < mitglieder.length) continue;
      if (zeilen.any((z) => z.stackId != null) ||
          (await db.vonHandAufgeloest(mitglieder.keys)).isNotEmpty) {
        stand.merkeSerie(serie);
        continue;
      }
      final sichtbar = [
        for (final z in zeilen)
          if (!z.isTrashed && !z.isLocked) z,
      ]..sort((a, b) => a.fileCreatedAt.compareTo(b.fileCreatedAt));
      if (sichtbar.length < 2) {
        stand.merkeSerie(serie);
        continue;
      }
      final titel =
          sichtbar.where((z) => mitglieder[z.id] ?? false).firstOrNull ??
          sichtbar.first;
      await db.fuehreAus(
        SerieBilden(const Uuid().v4(), [
          for (final z in sichtbar) z.id,
        ], titel.id),
      );
      gebildet++;
      stand.merkeSerie(serie);
    }
    return gebildet;
  }
}
