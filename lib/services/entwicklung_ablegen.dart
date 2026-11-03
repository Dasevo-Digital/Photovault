import 'dart:typed_data';

import 'package:drift/drift.dart' show Insertable;
import 'package:kern/db/database.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;

/// Legt das gerenderte Ergebnis einer Entwicklung von [assetId] ab und
/// trägt es mit [einstellungen] ein. Gibt den neuen Pfad zurück.
///
/// **Ein neuer Name je Speichern (#258).** Verbundene Geräte halten
/// Dateien unter ihrem Namen vor und holen eine nur, wenn sie fehlt (siehe
/// [StoragePaths.bereit]). Bis 3.50.0 schrieb der Rechner jede Entwicklung
/// nach `developed/<id>.jpg`; nach erneutem Entwickeln zeigten Handy und
/// andere Rechner deshalb dauerhaft die alte Fassung. Handy-App und
/// Browser vergaben schon einen neuen Namen.
///
/// **Reihenfolge.** Erst die Datei (in einer verbundenen Kopie zum Server),
/// dann der Befehl, der auf sie zeigt – so sieht kein Gerät einen Pfad,
/// hinter dem nichts liegt. Scheitert eins davon, geht die neue Datei hier
/// wieder weg, der Eintrag bleibt beim Alten und der Fehler beim Aufrufer –
/// nahm der Server die Datei nicht, als [EntwicklungNichtAbgelegt].
/// Danach verschwindet die vorige Fassung hier; am Server bleibt sie
/// liegen, bis verbundene Geräte dort Dateien löschen dürfen (#109).
Future<String> legeEntwicklungAb({
  required AppDatabase db,
  required StoragePaths paths,
  required String assetId,
  required Uint8List jpeg,
  required Insertable<DevelopSettingsData> einstellungen,
}) async => _lege(
  db: db,
  paths: paths,
  ordner: 'developed',
  vorher: (await db.assetById(assetId))?.developedRelativePath,
  neu: paths.neuerEntwicklungspfad(assetId),
  jpeg: jpeg,
  befehl: (neu) => EntwicklungSpeichern(assetId, einstellungen, neu),
);

/// Legt das Ergebnis einer KI-Restaurierung oder des KI-Entrauschens von
/// [assetId] ab – genau wie [legeEntwicklungAb], unter `restored/` (#284).
///
/// Bis 3.52 schrieb der Rechner jedes Ergebnis nach `restored/<id>.jpg`
/// und trug es nur bei sich ein. In einer verbundenen Bibliothek erfuhr
/// der Server nichts davon; Handy und Browser zeigten weiter das Bild
/// davor.
Future<String> legeRestaurierungAb({
  required AppDatabase db,
  required StoragePaths paths,
  required String assetId,
  required Uint8List jpeg,
}) async => _lege(
  db: db,
  paths: paths,
  ordner: 'restored',
  vorher: (await db.assetById(assetId))?.restoredRelativePath,
  neu: paths.neuerRestaurierungspfad(assetId),
  jpeg: jpeg,
  befehl: (neu) => RestaurierungSpeichern(assetId, neu),
);

Future<String> _lege({
  required AppDatabase db,
  required StoragePaths paths,
  required String ordner,
  required String? vorher,
  required String neu,
  required Uint8List jpeg,
  required Befehl<void> Function(String neu) befehl,
}) async {
  final datei = paths.absolute(neu);
  await datei.parent.create(recursive: true);
  await datei.writeAsBytes(jpeg, flush: true);
  try {
    try {
      await paths.abgelegt(neu);
    } catch (e) {
      throw EntwicklungNichtAbgelegt(e);
    }
    await db.fuehreAus(befehl(neu));
  } catch (_) {
    if (await datei.exists()) await datei.delete();
    rethrow;
  }
  // Nur, was wirklich ein Ergebnis dieser Art war – nie ein Original.
  if (vorher != null &&
      vorher != neu &&
      p.isWithin(ordner, p.normalize(vorher))) {
    final alt = paths.absolute(vorher);
    if (await alt.exists()) await alt.delete();
  }
  return neu;
}

/// Der Server (oder wer sonst [StoragePaths.ablege] ist) hat die Datei
/// einer Entwicklung oder Restaurierung nicht genommen; nichts ist
/// eingetragen.
class EntwicklungNichtAbgelegt implements Exception {
  const EntwicklungNichtAbgelegt(this.ursache);

  final Object ursache;

  @override
  String toString() => 'pv_entwicklung_nicht_abgelegt: $ursache';
}
