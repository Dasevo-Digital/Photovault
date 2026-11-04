import 'verbindung.dart';

/// Der Server kennt endgültiges Löschen noch nicht (vor 3.55).
class PapierkorbServerZuAlt implements Exception {
  const PapierkorbServerZuAlt();

  @override
  String toString() => 'pv_papierkorb_server_zu_alt';
}

/// Löscht am Server endgültig aus dem Papierkorb (#296): [ids] oder ohne
/// sie alles darin. Gibt zurück, wie viele Aufnahmen gingen.
///
/// Kein Befehl, der in der Warteschlange auf das Netz warten könnte: Was
/// hier geht, ist unwiderruflich, und wer es auslöst, soll sehen, ob es
/// geklappt hat. Die eigene Kopie erfährt es danach über den Abgleich wie
/// jedes andere Gerät.
Future<int> leereServerpapierkorb(
  Serververbindung verbindung, {
  Iterable<String>? ids,
}) async {
  try {
    final a = await verbindung.schicke(
      'api/v1/papierkorb/leeren',
      ids == null ? {'alle': true} : {'ids': ids.toList()},
      zeitlimit: const Duration(minutes: 10),
    );
    return a['geloescht'] as int? ?? 0;
  } on Serverfehler catch (e) {
    if (e.status == 404 || e.status == 405) throw const PapierkorbServerZuAlt();
    rethrow;
  }
}

/// Ob der Server endgültig löschen kann – aus `api/v1/zustand`.
bool kannPapierkorbLeeren(Map<String, Object?> zustand) =>
    ((zustand['funktionen'] as Map?)?['papierkorb'] as int? ?? 0) >= 1;
