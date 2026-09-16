import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/import_service.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';

import 'cr3_bauen.dart';

/// Der Weg von der Aufgabe „Orte einlesen" bis in die Datenbank.
///
/// **Warum eigens dafür ein Test.** Fassung 2.2.3 lieferte einen Knopf
/// aus, den niemand drücken konnte: Die Rechnung dahinter war geprüft,
/// der Weg zu ihr nicht. Hier ist es dieselbe Gefahr – `leseCr3Gps` hat
/// seinen eigenen Prüfstand, aber ob der Nachholvorgang ihn überhaupt
/// erreicht, sieht man dort nicht.
///
/// An der echten Bibliothek gegengefahren: 5838 Fotos ohne Ort, danach
/// 5316 – **522 CR3-Aufnahmen** haben einen bekommen, in 15 Sekunden.
void main() {
  late Directory tempRoot;
  late AppDatabase db;
  late StoragePaths paths;
  late LibraryState library;

  setUp(() async {
    tempRoot = Directory.systemTemp.createTempSync('pv_orte_');
    paths = await StoragePaths.forTesting(
        Directory(p.join(tempRoot.path, 'library')));
    db = AppDatabase(NativeDatabase.memory());
    library = LibraryState()
      ..db = db
      ..paths = paths
      ..importService = ImportService(db, paths);
  });

  tearDown(() async {
    await db.close();
    tempRoot.deleteSync(recursive: true);
  });

  /// Legt eine Aufnahme an, deren Datei unter [inhalt] in der Bibliothek
  /// liegt – ohne Ort in der Zeile, so wie eine vor der Reparatur
  /// importierte CR3 dasteht.
  Future<void> aufnahme(String name, List<int> inhalt) async {
    final relativ = 'originals/2026/06/$name';
    final datei = paths.absolute(relativ);
    await datei.parent.create(recursive: true);
    await datei.writeAsBytes(inhalt);
    await db.into(db.assets).insert(AssetsCompanion.insert(
          id: name,
          originalFileName: name,
          relativePath: relativ,
          checksum: name,
          type: 'IMAGE',
          fileCreatedAt: DateTime(2026, 6, 1),
          importedAt: DateTime(2026, 6, 1),
        ));
  }

  test('der Nachholvorgang traegt den Ort einer CR3 ein', () async {
    await aufnahme(
        'mit_ort.cr3',
        cr3Mit(gpsVerzeichnis(
          breite: beispielBreite,
          breiteRef: 'N',
          laenge: beispielLaenge,
          laengeRef: 'E',
        )));
    await aufnahme('ohne_ort.jpg', [0xFF, 0xD8, 0xFF, 0xE0, ...List.filled(64, 0)]);

    expect(await db.countLocationBackfill(), 2);

    var letzter = 0;
    await for (final fortschritt in library.backfillLocations()) {
      letzter = fortschritt.done;
    }

    expect(letzter, 2, reason: 'beide Dateien wurden angesehen');
    // Ueber `alle: true` gezaehlt: Seit Fassung 64 vermerkt der Lauf, wo
    // er nachgesehen hat, und die gewoehnliche Zahl faellt danach auf
    // null. Gefragt ist hier aber, wer einen ORT bekommen hat – und das
    // ist genau die CR3.
    expect(await db.countLocationBackfill(alle: true), 1,
        reason: 'genau die CR3 hat einen Ort bekommen');
    expect(await db.countLocationBackfill(), 0,
        reason: 'beide sind angesehen, keine steht mehr an');
    expect((await db.assetById('ohne_ort.jpg'))!.latitude, isNull);

    final zeile = await db.assetById('mit_ort.cr3');
    expect(zeile!.latitude, closeTo(52.2431111, 1e-6));
    expect(zeile.longitude, closeTo(10.5852778, 1e-6));
  });

  test('eine Datei ohne Ort bleibt ohne Ort, nicht auf 0/0', () async {
    // Der Fehler, der plausibel aussieht: Ein Nullpunkt im Golf von
    // Guinea ist eine Koordinate, nur nicht diese.
    await aufnahme('leer.cr3', cr3Mit(leererKasten));
    await for (final _ in library.backfillLocations()) {}
    expect((await db.assetById('leer.cr3'))!.latitude, isNull);
  });
}

/// Ein `CMT4`-Kasten ohne brauchbares Verzeichnis.
final leererKasten = Uint8List(16);
