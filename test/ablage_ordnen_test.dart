import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/import_service.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';

/// **Die Ablage wieder in Ordnung bringen.**
///
/// An einer echten Bibliothek lagen **1102 von 7988 Aufnahmen** im Ordner
/// eines anderen Monats, als ihr Datum sagt: Ein von Hand gesetztes Datum
/// schrieb bis Fassung 2.6 nur die Spalte. Die Ursache ist behoben (siehe
/// `datum_setzen_verschiebt_test.dart`) – diese Aufgabe räumt auf, was
/// vorher entstanden ist.
///
/// **Was sie ausdrücklich nicht tut:** das Datum anfassen. Das gilt als
/// richtig; falsch ist nur der Ort auf der Platte. Wer das Datum neu aus
/// der Datei lesen will, nimmt die Datumskorrektur.
void main() {
  late Directory temp;
  late AppDatabase db;
  late StoragePaths pfade;
  late ImportService imp;
  late LibraryState library;
  var farbe = 0;

  setUp(() async {
    temp = Directory.systemTemp.createTempSync('pv_ablage_');
    db = AppDatabase(NativeDatabase.memory());
    pfade = await StoragePaths.forTesting(Directory(p.join(temp.path, 'lib')));
    imp = ImportService(db, pfade);
    library = LibraryState()
      ..db = db
      ..paths = pfade
      ..importService = imp;
  });
  tearDown(() async {
    await db.close();
    temp.deleteSync(recursive: true);
  });

  Future<AssetData> lege(String name, DateTime dateizeit) async {
    final rein = Directory(p.join(temp.path, 'rein'))
      ..createSync(recursive: true);
    final bild = img.Image(width: 8, height: 8);
    img.fill(bild, color: img.ColorRgb8(10 + (farbe++ * 23) % 200, 20, 30));
    final datei = File(p.join(rein.path, name))
      ..writeAsBytesSync(Uint8List.fromList(img.encodeJpg(bild)))
      ..setLastModifiedSync(dateizeit);
    final erg = await imp.importFile(datei.path);
    expect(erg.outcome, ImportOutcome.imported);
    return (await db.assetById(erg.assetId!))!;
  }

  /// Der alte, kaputte Weg: Datum ändern, Datei liegen lassen. Genau so
  /// sind die 1102 entstanden.
  Future<void> nurSpalteAendern(String id, DateTime neu) =>
      db.setFileCreatedAt(id, neu);

  test('was schief liegt, wird gefunden – und sonst nichts', () async {
    final heil = await lege('a.jpg', DateTime(2020, 4, 5));
    final schief = await lege('b.jpg', DateTime(2007, 1, 4));
    await nurSpalteAendern(schief.id, DateTime(2013, 8, 27));

    final gefunden = await db.assetsFuerAblageordnung();
    expect(gefunden.map((a) => a.id), [schief.id]);
    expect(gefunden.map((a) => a.id), isNot(contains(heil.id)));
    expect(await db.countAblageordnung(), gefunden.length,
        reason: 'Zahl und Liste dürfen nicht auseinanderlaufen');
  });

  test('der Lauf legt die Datei um und lässt das Datum in Ruhe', () async {
    final asset = await lege('c.jpg', DateTime(2007, 1, 4, 20, 28));
    final alt = pfade.absolute(asset.relativePath);
    await nurSpalteAendern(asset.id, DateTime(2013, 8, 27, 9, 15));

    await library.ordneAblageNeu().drain<void>();

    final neu = (await db.assetById(asset.id))!;
    expect(neu.fileCreatedAt, DateTime(2013, 8, 27, 9, 15),
        reason: 'das Datum ist das Richtige, nicht das zu Korrigierende');
    expect(neu.relativePath, contains(p.join('2013', '08')));
    expect(File(pfade.absolute(neu.relativePath).path).existsSync(), isTrue);
    expect(alt.existsSync(), isFalse);
  });

  test('danach ist nichts mehr offen', () async {
    for (var i = 0; i < 5; i++) {
      final a = await lege('d$i.jpg', DateTime(2007, 1, 4));
      await nurSpalteAendern(a.id, DateTime(2006 + i, 8, 27));
    }
    expect(await db.countAblageordnung(), 5);
    await library.ordneAblageNeu().drain<void>();
    expect(await db.countAblageordnung(), 0,
        reason: 'ein zweiter Lauf hätte sonst wieder etwas zu tun');
  });

  test('ein Foto aus dem Papierkorb kommt mit', () async {
    // Anders als bei der Datumskorrektur: Die Datei liegt weiterhin unter
    // originals/, und die Frage lautet hier nicht „stimmt das Datum",
    // sondern „stimmt der Ordner".
    final asset = await lege('e.jpg', DateTime(2007, 1, 4));
    await nurSpalteAendern(asset.id, DateTime(2015, 3));
    await db.moveToTrash([asset.id]);
    expect((await db.assetsFuerAblageordnung()).map((a) => a.id),
        contains(asset.id));
  });

  test('eine Aufnahme, deren Datei fehlt, hält den Lauf nicht auf', () async {
    final weg = await lege('f.jpg', DateTime(2007, 1, 4));
    final da = await lege('g.jpg', DateTime(2007, 1, 4));
    await nurSpalteAendern(weg.id, DateTime(2014, 2));
    await nurSpalteAendern(da.id, DateTime(2014, 2));
    pfade.absolute(weg.relativePath).deleteSync();

    await library.ordneAblageNeu().drain<void>();

    // Die vorhandene Datei ist umgelegt; die fehlende bekommt ihr Datum
    // trotzdem vermerkt, statt den ganzen Lauf abzubrechen.
    expect((await db.assetById(da.id))!.relativePath,
        contains(p.join('2014', '02')));
  });

  test('der Fortschritt zählt bis zur letzten Aufnahme', () async {
    for (var i = 0; i < 3; i++) {
      final a = await lege('h$i.jpg', DateTime(2007, 1, 4));
      await nurSpalteAendern(a.id, DateTime(2016, 6));
    }
    final schritte = await library.ordneAblageNeu().toList();
    expect(schritte.first.total, 3);
    expect(schritte.last.done, 3);
  });

  test('eine Aufnahme mit passendem Ordner wird nicht angefasst', () async {
    final asset = await lege('i.jpg', DateTime(2020, 4, 5));
    final vorher = asset.relativePath;
    await library.ordneAblageNeu().drain<void>();
    expect((await db.assetById(asset.id))!.relativePath, vorher);
  });

  test('der Monatsanfang zählt nach Ortszeit', () async {
    // Der Fallstrick der SQL-Abfrage: `originalRelativePath` nimmt Jahr
    // und Monat der Ortszeit, `strftime` rechnet ohne Zusatz in UTC.
    // Ohne 'localtime' läge in einer Zone östlich von Greenwich jede
    // Aufnahme der ersten Stunden eines Monats scheinbar falsch.
    final asset = await lege('j.jpg', DateTime(2021, 7, 1, 0, 30));
    expect(asset.relativePath, contains(p.join('2021', '07')));
    expect((await db.assetsFuerAblageordnung()).map((a) => a.id),
        isNot(contains(asset.id)),
        reason: 'diese Aufnahme liegt richtig');
  });

  test('auch der letzte Moment eines Monats liegt richtig', () async {
    final asset = await lege('k.jpg', DateTime(2021, 7, 31, 23, 30));
    expect(asset.relativePath, contains(p.join('2021', '07')));
    expect((await db.assetsFuerAblageordnung()).map((a) => a.id),
        isNot(contains(asset.id)));
  });

  test('eine Aufnahme ausserhalb von originals/ bleibt aussen vor', () async {
    // Zugesicherte Grenze der Abfrage: Sie schneidet die sieben Zeichen
    // hinter „originals/" heraus. Was anderswo liegt, hat dort nichts zu
    // suchen und würde beim Vergleich Unsinn ergeben.
    await db.insertAsset(AssetsCompanion.insert(
      id: 'fremd',
      relativePath: 'irgendwo/anders/x.jpg',
      originalFileName: 'x.jpg',
      type: 'IMAGE',
      checksum: 'fremd',
      fileCreatedAt: DateTime(2019, 9, 9),
      importedAt: DateTime(2026),
      isTrashed: const Value(false),
    ));
    expect((await db.assetsFuerAblageordnung()).map((a) => a.id),
        isNot(contains('fremd')));
  });

  /// **Der Beipackzettel zieht mit um.**
  ///
  /// Bis Fassung 2.6 tat er das nicht. An der echten Bibliothek lagen
  /// dadurch 1244 von 7370 `.xmp`-Dateien an einem Platz, an dem ihr Foto
  /// längst nicht mehr war – mit Beschreibung, Schlagwörtern,
  /// Personennamen und Ort im Klartext. Weil [dateienVon] den NEUEN Pfad
  /// nennt, wurden sie weder beim Sperren verschlüsselt noch beim Löschen
  /// entfernt.
  test('ein Umzug nimmt den Beipackzettel mit', () async {
    final asset = await lege('x.jpg', DateTime(2007, 1, 4));
    final alterZettel = pfade.absolute(pfade.xmpSidecarPath(asset.relativePath))
      ..writeAsStringSync('<x:xmpmeta>Oma im Garten</x:xmpmeta>');
    await nurSpalteAendern(asset.id, DateTime(2013, 8, 27));

    await library.ordneAblageNeu().drain<void>();

    final neu = (await db.assetById(asset.id))!;
    final neuerZettel = pfade.absolute(pfade.xmpSidecarPath(neu.relativePath));
    expect(alterZettel.existsSync(), isFalse,
        reason: 'sonst bleibt ein Metadatensatz ohne Foto liegen');
    expect(neuerZettel.existsSync(), isTrue);
    expect(neuerZettel.readAsStringSync(), contains('Oma im Garten'));
  });

  test('eine Aufnahme ohne Beipackzettel zieht trotzdem um', () async {
    final asset = await lege('y.jpg', DateTime(2007, 1, 4));
    await nurSpalteAendern(asset.id, DateTime(2013, 8, 27));
    await library.ordneAblageNeu().drain<void>();
    expect((await db.assetById(asset.id))!.relativePath,
        contains(p.join('2013', '08')));
  });

  test('ein liegengebliebener Zettel wird eingesammelt', () async {
    // Genau der Zustand, den die 1244 hinterlassen haben: Das Foto liegt
    // richtig, der Zettel steht noch am alten Platz.
    final asset = await lege('z.jpg', DateTime(2020, 4, 5));
    final verirrt = pfade.absolute('originals/00-1/11/${asset.id}.xmp')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('<x:xmpmeta/>');

    expect(await db.countAblageordnung(), 0,
        reason: 'die Aufnahme selbst liegt richtig – nur der Zettel nicht');
    expect(await library.zaehleAblageordnung(), 1,
        reason:
            'die Karte muss diese Arbeit anzeigen, sonst sieht sie niemand');

    await library.ordneAblageNeu().drain<void>();

    expect(verirrt.existsSync(), isFalse);
    expect(
        pfade.absolute(pfade.xmpSidecarPath(asset.relativePath)).existsSync(),
        isTrue);
    expect(await library.zaehleAblageordnung(), 0,
        reason: 'ein zweiter Lauf haette sonst wieder etwas zu tun');
  });

  test('ein Zettel ohne Aufnahme wird in Ruhe gelassen', () async {
    // Löschen ist hier nicht die Aufgabe: Wem der Zettel gehört, weiss
    // niemand mehr, und ein Lauf, der Dateien wegwirft, muss anders
    // heissen als „ordnen".
    final fremd = pfade.absolute('originals/2019/09/nicht-vorhanden.xmp')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('<x:xmpmeta/>');
    expect(await library.verirrteBeipackzettel(), isEmpty);
    await library.ordneAblageNeu().drain<void>();
    expect(fremd.existsSync(), isTrue);
  });

  test('der Fortschritt zaehlt Aufnahmen und Zettel zusammen', () async {
    final a = await lege('p.jpg', DateTime(2007, 1, 4));
    await nurSpalteAendern(a.id, DateTime(2016, 6));
    final b = await lege('q.jpg', DateTime(2020, 4, 5));
    pfade.absolute('originals/00-1/11/${b.id}.xmp')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('<x:xmpmeta/>');

    final schritte = await library.ordneAblageNeu().toList();
    expect(schritte.first.total, 2,
        reason: 'die Gesamtzahl darf unterwegs nicht wachsen');
    expect(schritte.last.done, 2);
  });
}
