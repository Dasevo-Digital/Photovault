import 'package:kern/abgleich/verbindung.dart';
import 'package:kern/db/database.dart';

import 'kamerarolle.dart';
import 'stand.dart';

/// Speicher auf dem Telefon freigeben (Issue #129): löscht dort, was
/// sicher auf dem Server liegt – und nur das.
///
/// Drei Bedingungen, jede für sich notwendig: Die Aufnahme steht im
/// Sicherungsstand als hochgeladen oder als schon vorhanden erkannt; ihr
/// Änderungsstand ist seither derselbe (eine Bearbeitung nach der
/// Sicherung wäre sonst weg); und der Server selbst bestätigt, dass die
/// Aufnahme dort noch liegt, nicht im Papierkorb.
///
/// **Warum den Server fragen und nicht nur die Kopie (#425).** Die Kopie
/// ist nur so aktuell wie der letzte Abgleich. Stand der still – das
/// Telefon lange offline, vom Server abgemeldet, ein anderes Schema –,
/// während am Rechner etwas in den Papierkorb ging und der Papierkorb
/// geleert wurde, führte die Kopie die Aufnahme weiter als vorhanden, und
/// das Telefon löschte die letzte Kopie. Die Kopie bleibt als zusätzlicher
/// Filter; entscheidend ist die Antwort des Servers. Ohne sie geht nichts.
///
/// Eine Serie bleibt ganz auf dem Telefon (#314). In der Fotos-App ist sie
/// ein einziges Bild, und was iOS mit den übrigen Bildern macht, wenn das
/// Titelbild geht, sagt es nicht zu.
class Speicherfreigabe {
  const Speicherfreigabe({
    required this.stand,
    required this.rolle,
    required this.db,
    required this.verbindung,
  });

  final Sicherungsstand stand;
  final Kamerarolle rolle;
  final AppDatabase db;

  /// Der Server, der bestätigt, was er noch hat.
  final Serververbindung verbindung;

  /// So viele Kennungen je Anfrage (der Server nimmt bis zu 5000).
  static const _stueck = 1000;

  /// Die Kennungen auf dem Telefon, die weg können.
  ///
  /// Wirft [KeineVerbindung] oder [Serverfehler], wenn der Server nicht
  /// bestätigen kann – dann bleibt alles auf dem Telefon.
  Future<List<String>> kandidaten() async {
    final gesichert = stand.gesichertMitAufnahme();
    if (gesichert.isEmpty) return const [];
    final aufDemTelefon = <String, String>{};
    for (final e in await rolle.eintraege(videos: true)) {
      final g = gesichert[e.id];
      if (g != null &&
          e.serie == null &&
          g.geaendert == e.geaendert.millisecondsSinceEpoch &&
          !(await e.bearbeitetesVideo?.call() ?? false)) {
        aufDemTelefon[e.id] = g.aufnahme;
      }
    }
    final inDerKopie = await db.vorhandeneAufnahmen(aufDemTelefon.values);
    final amServer = await _amServer(inDerKopie);
    return [
      for (final MapEntry(key: lokal, value: aufnahme) in aufDemTelefon.entries)
        if (amServer.contains(aufnahme)) lokal,
    ];
  }

  /// Welche von [ids] der Server als vorhanden meldet. `aufnahmen/liste`
  /// nennt nur, was dort liegt und weder im Papierkorb noch gesperrt ist.
  Future<Set<String>> _amServer(Set<String> ids) async {
    final liste = ids.toList();
    final da = <String>{};
    for (var i = 0; i < liste.length; i += _stueck) {
      final teil = liste.sublist(
        i,
        i + _stueck > liste.length ? liste.length : i + _stueck,
      );
      final antwort = await verbindung.schicke('api/v1/aufnahmen/liste', {
        'ids': teil,
      });
      for (final a in (antwort['aufnahmen']! as List).cast<Map>()) {
        final id = a['id'];
        // Nur, wonach gefragt wurde.
        if (id is String && ids.contains(id)) da.add(id);
      }
    }
    return da;
  }

  /// Löscht [ids] vom Telefon; das System fragt dabei selbst noch einmal.
  /// Gibt zurück, wie viele wirklich gingen.
  Future<int> gib(List<String> ids) =>
      ids.isEmpty ? Future.value(0) : rolle.loesche(ids);
}
