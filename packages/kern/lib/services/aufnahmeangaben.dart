import 'package:drift/drift.dart';

import '../db/database.dart';

/// Was die Angaben zu einer Aufnahme zeigen – im Browser wie auf dem
/// Telefon. Eine Rechnung für beide, damit keiner etwas anderes sieht
/// (siehe reiseuebersicht.dart).
typedef Aufnahmeangaben = ({
  AssetData aufnahme,
  List<PersonData> personen,
  List<TagData> schlagwoerter,
  List<AlbumData> alben,

  /// Entwickelt, gekürzt oder restauriert – dann zeigt die Ansicht nicht
  /// das Original.
  bool bearbeitet,
});

/// Die Angaben zu [id]; `null` für Unbekanntes und Gesperrtes.
Future<Aufnahmeangaben?> aufnahmeangaben(AppDatabase db, String id) async {
  final a = await db.assetById(id);
  if (a == null || a.isLocked) return null;
  final alben = await (db.select(db.albums).join([
    innerJoin(db.albumAssets, db.albumAssets.albumId.equalsExp(db.albums.id)),
  ])..where(db.albumAssets.assetId.equals(id))).get();
  return (
    aufnahme: a,
    personen: await db.peopleForAsset(id),
    schlagwoerter: await db.tagsForAsset(id),
    alben: [for (final z in alben) z.readTable(db.albums)],
    bearbeitet:
        a.developedRelativePath != null ||
        a.trimmedRelativePath != null ||
        a.restoredRelativePath != null,
  );
}

/// Die sichtbaren Aufnahmen einer Serie, Titelbild zuerst, dann nach Zeit.
Future<List<AssetData>> serieZumAnsehen(AppDatabase db, String stackId) async {
  final mitglieder = await db.assetsInStack(stackId);
  return [
    for (final a in mitglieder)
      if (!a.isTrashed && !a.isLocked) a,
  ]..sort((x, y) {
    if (x.isStackCover != y.isStackCover) return x.isStackCover ? -1 : 1;
    return x.fileCreatedAt.compareTo(y.fileCreatedAt);
  });
}
