import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/datumsvorschlag.dart';
import 'package:kern/services/import_service.dart' show Datumsbefund;

/// Die Prüfung „Aufnahmedaten“ (#203): wann der Dateiname gilt, wann die
/// Datei, und wann keiner von beiden.
void main() {
  late AppDatabase db;
  final kopiert = DateTime(2025, 8, 1, 9, 0, 10);

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> lege(
    String id,
    String name, {
    DateTime? am,
    bool geschaetzt = false,
    bool geprueft = true,
    bool papierkorb = false,
  }) => db
      .into(db.assets)
      .insert(
        AssetsCompanion.insert(
          id: id,
          originalFileName: name,
          relativePath: 'originals/$id.jpg',
          checksum: 'summe-$id',
          type: 'IMAGE',
          fileCreatedAt: am ?? kopiert,
          importedAt: kopiert,
          datumGeschaetzt: Value(geschaetzt),
          datumGeprueft: Value(geprueft),
          isTrashed: Value(papierkorb),
        ),
      );

  test('Regeln: geschätzt, Datei und Name einig, uneinig, von Hand', () async {
    // Geschätzt: Die Datei trägt keines, der Name gilt, ohne sie zu lesen.
    await lege('geschaetzt', '22-06-18 16-20-30 c3d4.jpg', geschaetzt: true);
    // Nur der Tag im Namen: Vorschlag, bleibt aber geschätzt.
    await lege('tag', 'IMG-20180517-WA0003.jpg', geschaetzt: true);
    // Ein JPEG unter .MOV-Namen mit dem Kopierdatum: Datei und Name einig.
    await lege('einig', '25-02-03 11-22-33 2002.MOV');
    // Datei nennt etwas anderes als der Name: nichts zu entscheiden.
    await lege('uneinig', '24-03-05 07-10-20 e5f6.mov');
    // Nie nachgesehen, Datei ohne Datum: die Zeile ist der Dateizeitstempel.
    await lege('alt', 'PHOTO-2026-03-14-17-05-09.jpg', geprueft: false);
    // Nachgesehen, Datei ohne Datum, aber nicht geschätzt: von Hand gesetzt.
    await lege('hand', 'IMG_20190312_081502.jpg');
    // Passt schon, liegt im Papierkorb, kein Datum im Namen.
    await lege(
      'passt',
      'IMG_20190601_141538.jpg',
      am: DateTime(2019, 6, 1, 14, 15, 36),
    );
    await lege('weg', '23-04-02 18-30-00 3003.jpg', papierkorb: true);
    await lege('ohne', 'IMG_0042.JPG', geschaetzt: true);

    final gelesen = <String>[];
    final inDatei = {
      'originals/einig.jpg': Datumsbefund(DateTime(2025, 2, 3, 11, 22, 33)),
      'originals/uneinig.jpg': Datumsbefund(DateTime(2024, 3, 5, 14, 57)),
      'originals/alt.jpg': const Datumsbefund(null),
      'originals/hand.jpg': const Datumsbefund(null),
    };
    final v = await datumsvorschlaege(
      db,
      jetzt: DateTime(2026, 10, 21),
      leseDatei: (pfad) async {
        gelesen.add(pfad);
        return inDatei[pfad];
      },
    );
    final nach = {for (final x in v) x.id: x};
    expect(nach.keys.toSet(), {'geschaetzt', 'tag', 'einig', 'alt'});
    expect(nach['geschaetzt']!.neu, DateTime(2022, 6, 18, 16, 20, 30));
    expect(nach['geschaetzt']!.quelle, Datumsquelle.dateiname);
    expect(nach['tag']!.geschaetzt, isTrue);
    expect(nach['einig']!.quelle, Datumsquelle.dateiUndName);
    expect(nach['einig']!.neu, DateTime(2025, 2, 3, 11, 22, 33));
    expect(nach['alt']!.neu, DateTime(2026, 3, 14, 17, 5, 9));
    // Gelesen wird nur, wo der Name widerspricht und nicht geschätzt ist.
    expect(gelesen.toSet(), {
      'originals/einig.jpg',
      'originals/uneinig.jpg',
      'originals/alt.jpg',
      'originals/hand.jpg',
    });
    // Neueste zuerst.
    expect(v.first.id, 'alt');

    // Übernommen über den Befehl: danach kein Vorschlag mehr.
    await db.fuehreAus(AufnahmedatenSetzen([for (final x in v) x.alsEintrag]));
    final danach = await datumsvorschlaege(
      db,
      jetzt: DateTime(2026, 10, 21),
      leseDatei: (pfad) async => inDatei[pfad],
    );
    expect(danach, isEmpty);
    final tag = await db.assetById('tag');
    expect(tag!.datumGeschaetzt, isTrue, reason: 'nur der Tag ist belegt');
    expect((await db.assetById('einig'))!.datumGeschaetzt, isFalse);

    // Für eine einzelne Aufnahme dieselben Regeln.
    expect(
      await datumsvorschlagFuer(
        db,
        'uneinig',
        leseDatei: (pfad) async => inDatei[pfad],
      ),
      isNull,
    );
  });
}
