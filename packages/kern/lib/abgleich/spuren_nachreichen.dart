import 'dart:convert';

import '../db/database.dart';
import '../protokoll.dart';
import 'abgleich.dart';
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
/// **Erst abholen, dann vergleichen.** Verglichen wurde früher, bevor die
/// Kopie das Protokoll abgeholt hatte – gleich beim Start, sobald der
/// Server sich meldete. Eine Spur, die ein anderes Gerät inzwischen
/// gelöscht hatte, fehlte dann beim Server, lag hier aber noch, und
/// `SpurAnlegen` legte sie samt Punkten für alle Geräte wieder an. Jetzt
/// kommt zuerst die Liste des Servers, dann das Protokoll: Was danach dort
/// gelöscht wird, steht noch in der Liste; was vorher gelöscht wurde, ist
/// nach dem Abholen auch hier fort. Spuren, auf die ein Befehl in der
/// Warteschlange zeigt, gehören ohnehin diesem Befehl.
///
/// **Einmal.** Der Altbestand entsteht nicht mehr; ist er einmal
/// durchgesehen, merkt sich die Kopie das und fragt nicht wieder.
///
/// Gibt zurück, wie viele nachgereicht wurden. Kennt der Server den Weg
/// noch nicht (ältere Fassung), geschieht nichts – auch keine Marke, damit
/// es nach seinem Update nachgeholt wird.
Future<int> spurenNachreichen(Abgleich abgleich) async {
  final db = abgleich.db;
  if (await abgleich.spurenNachgereicht()) return 0;
  final Map<String, Object?> d;
  try {
    d = await abgleich.verbindung.hole('api/v1/spuren');
  } on Serverfehler catch (f) {
    if (f.status == 404) return 0;
    rethrow;
  }
  await abgleich.empfange();
  final dort = {for (final k in (d['kennungen'] as List? ?? const [])) '$k'};
  final befohlen = {
    for (final z
        in await db
            .customSelect(
              'SELECT DISTINCT schluessel FROM pv_aenderungen '
              "WHERE tabelle = 'spuren' "
              'AND ausgang IN (SELECT nr FROM pv_ausgang)',
            )
            .get())
      if ((jsonDecode(z.read<String>('schluessel')) as List).firstOrNull
          case final Object id)
        '$id',
  };
  var n = 0;
  for (final s in await db.alleSpuren()) {
    if (dort.contains(s.id) || befohlen.contains(s.id)) continue;
    await db.fuehreAus(SpurAnlegen.ausSpur(s, await db.punkteDerSpur(s.id)));
    n++;
  }
  await abgleich.merkeSpurenNachgereicht();
  if (n > 0) protokoll('Spuren nachgereicht: $n');
  return n;
}
