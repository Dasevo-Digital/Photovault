import '../db/database.dart';
import '../db/rasterzeile.dart' show rasterSichtbar;
import 'regelpruefung.dart';

/// Eine Regel auf das, was schon da ist.
///
/// Beim Import greifen die Regeln von selbst, auch am Server. Nur eine neue
/// Regel kam bisher nie an die Fotos heran, die vor ihr da waren: Wer „alles
/// aus Italien ins Album“ anlegte, bekam ein leeres Album.
///
/// Dieselbe Auswertung wie beim Import ([regelTrifftZu]), damit der Probelauf
/// und das Anwenden nichts anderes finden als eine Regel im Betrieb.

/// Die sichtbaren Aufnahmen, auf die [regel] zutrifft. Gesperrtes und der
/// Papierkorb gehören nicht dazu.
Future<List<String>> regelTreffer(
  AppDatabase db,
  AutomationRuleData regel,
) async {
  final kiTags = regel.triggerType == 'aiTag'
      ? await db.kiTagNamesByAssetId()
      : const <String, Set<String>>{};
  final zeilen = await db
      .customSelect(
        'SELECT id, latitude, longitude, file_created_at, original_file_name '
        'FROM assets WHERE $rasterSichtbar',
        readsFrom: {db.assets},
      )
      .get();
  return [
    for (final z in zeilen)
      if (regelTrifftZu(
        regel,
        breite: z.readNullable<double>('latitude'),
        laenge: z.readNullable<double>('longitude'),
        datum: z.read<DateTime>('file_created_at'),
        kiTags: kiTags[z.read<String>('id')]?.toList() ?? const [],
        dateiname: z.read<String>('original_file_name'),
      ))
        z.read<String>('id'),
  ];
}

/// Tut für alle Treffer, was die Regel verlangt, und gibt ihre Zahl zurück.
///
/// Als Befehle wie jede Änderung, damit die Geräte davon erfahren; in
/// Portionen, damit keiner zu gross wird. Ein Album, das es nicht mehr gibt,
/// fällt weg, die übrigen Aktionen gelten trotzdem.
Future<int> regelAnwenden(AppDatabase db, AutomationRuleData regel) async {
  final treffer = await regelTreffer(db, regel);
  if (treffer.isEmpty) return 0;
  final album = regel.targetAlbumId;
  final albumDa =
      album != null && (await db.alleAlben()).any((a) => a.id == album);
  final kennungen = (await db.tagIdsForAutomationRule(regel.id)).toSet();
  final namen = [
    for (final t in await db.alleTags())
      if (kennungen.contains(t.id)) t.name,
  ];
  for (final teil in inStuecken(treffer, groesse: 500)) {
    if (albumDa) await db.fuehreAus(AlbumFuellen(album, teil));
    if (regel.autoFavorite) await db.fuehreAus(FavoritSetzen(teil, true));
    for (final name in namen) {
      await db.fuehreAus(SchlagwortAnheften(teil, name));
    }
  }
  return treffer.length;
}
