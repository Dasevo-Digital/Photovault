import '../db/database.dart';
import '../protokoll.dart';
import 'verbindung.dart';

/// Reicht dem Server die Spuren nach, die ein verbundener Rechner bis 3.37
/// nur bei sich angelegt hat.
///
/// Damals schrieb er eine GPX-Spur direkt in seine Kopie statt als Befehl
/// (siehe `SpurAnlegen`). Lief der Abgleich, verbot das sein Schutz; lief er
/// nicht (Server nicht erreichbar), blieb die Spur hier – beim Server und
/// damit in Browser und Handy kam sie nie an. Was vor dem Umzug entstand,
/// hat der Server ohnehin. Gefragt wird, welche Spuren der Server kennt;
/// was hier liegt und dort fehlt, geht als `SpurAnlegen` in die
/// Warteschlange. Hier ersetzt der Befehl die Spur durch sich selbst, also
/// bleibt alles, wie es ist.
///
/// Gibt zurück, wie viele nachgereicht wurden. Kennt der Server den Weg
/// noch nicht (ältere Fassung), geschieht nichts.
Future<int> spurenNachreichen(AppDatabase db, Serververbindung server) async {
  final Map<String, Object?> d;
  try {
    d = await server.hole('api/v1/spuren');
  } on Serverfehler catch (f) {
    if (f.status == 404) return 0;
    rethrow;
  }
  final dort = {for (final k in (d['kennungen'] as List? ?? const [])) '$k'};
  var n = 0;
  for (final s in await db.alleSpuren()) {
    if (dort.contains(s.id)) continue;
    await db.fuehreAus(SpurAnlegen.ausSpur(s, await db.punkteDerSpur(s.id)));
    n++;
  }
  if (n > 0) protokoll('Spuren nachgereicht: $n');
  return n;
}
