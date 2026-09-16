import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/import_service.dart';
import 'package:photo_vault/services/search_filters.dart';
import 'package:photo_vault/services/serienvorschlag.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';

/// **Ein geratenes Datum sah aus wie ein gemessenes.**
///
/// An der echten Bibliothek tragen 1097 von 7443 Aufnahmen einen
/// Zeitstempel auf die volle Stunde – ohne Minute, ohne Sekunde. Bei
/// Gleichverteilung wären zwei zu erwarten. **948 davon tragen sogar
/// denselben Zeitpunkt auf die Sekunde**, den 27.08.2006 um 00:00 Uhr.
///
/// In den Dateien nachgesehen steht dort wörtlich
/// `DateTimeOriginal: 0000:00:00 00:00:00` – die Uhr der Kamera war nie
/// gestellt. Der Import fällt dann auf den Zeitstempel der Datei zurück,
/// und das ist richtig so; es ist der letzte Ausweg und im Quelltext
/// auch als solcher benannt. Falsch war, dass danach **nichts** mehr
/// davon wusste: Der geratene Wert stand in derselben Spalte wie ein
/// gemessener.
///
/// Was daraus folgte, ist an drei Stellen sichtbar und wird hier
/// geprüft: die Erinnerungen behaupteten „vor 20 Jahren, an genau diesem
/// Tag" für 948 Aufnahmen, die Serienerkennung fand eine „Serie" mit 943
/// Mitgliedern, und im Infoblatt stand eine Uhrzeit auf die Sekunde
/// genau, die aus dem Dateisystem stammte.
void main() {
  late Directory wurzel;
  late Directory eingang;
  late AppDatabase db;
  late StoragePaths paths;
  late ImportService importService;
  late LibraryState library;

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_datumsherkunft_');
    eingang = Directory(p.join(wurzel.path, 'eingang'))..createSync();
    paths =
        await StoragePaths.forTesting(Directory(p.join(wurzel.path, 'lib')));
    db = AppDatabase(NativeDatabase.memory());
    importService = ImportService(db, paths);
    library = LibraryState()
      ..db = db
      ..paths = paths
      ..importService = importService;
  });

  tearDown(() async {
    await db.close();
    wurzel.deleteSync(recursive: true);
  });

  /// JPEG-Bytes, wahlweise mit Aufnahmedatum in den EXIF-Daten.
  ///
  /// [inhalt] macht die Bytes verschieden – sonst hätten zwei Bilder
  /// dieselbe Prüfsumme und der Import lehnte das zweite als Duplikat ab.
  Uint8List jpeg({DateTime? datum, int inhalt = 0}) {
    final bild = img.Image(width: 8, height: 8);
    bild.setPixelRgb(0, 0, inhalt % 256, 0, 0);
    if (datum != null) {
      String z(int v, int n) => v.toString().padLeft(n, '0');
      bild.exif.exifIfd['DateTimeOriginal'] =
          '${z(datum.year, 4)}:${z(datum.month, 2)}:${z(datum.day, 2)} '
          '${z(datum.hour, 2)}:${z(datum.minute, 2)}:${z(datum.second, 2)}';
    }
    return img.encodeJpg(bild);
  }

  Future<AssetData> importiere(String name, {DateTime? datum, int inhalt = 0}) async {
    final datei = File(p.join(eingang.path, name))
      ..writeAsBytesSync(jpeg(datum: datum, inhalt: inhalt));
    final ergebnis = await importService.importFile(datei.path);
    expect(ergebnis.outcome, ImportOutcome.imported, reason: name);
    return (await db.assetById(ergebnis.assetId!))!;
  }

  /// Eine Aufnahme, wie sie vor Schema 75 in der Datenbank stand: mit
  /// geratenem Datum, aber ohne jeden Vermerk darüber.
  Future<void> altbestand(String id, DateTime wann,
          {bool geschaetzt = false}) =>
      db.insertAsset(AssetsCompanion.insert(
        id: id,
        originalFileName: '$id.jpg',
        relativePath: 'originals/2006/08/$id.jpg',
        checksum: 'pruef-$id',
        type: 'IMAGE',
        fileCreatedAt: wann,
        importedAt: DateTime(2026),
        datumGeschaetzt: Value(geschaetzt),
      ));

  group('beim Import', () {
    test('eine Datei ohne Aufnahmedatum wird als geschätzt vermerkt', () async {
      final a = await importiere('ohne.jpg');
      expect(a.datumGeschaetzt, isTrue,
          reason: 'der Wert stammt aus lastModified(), nicht aus der Datei');
      expect(a.datumGeprueft, isTrue,
          reason: 'nachgesehen wurde gerade eben – der Nachtrag darf sie '
              'überspringen');
    });

    test('eine Datei MIT Aufnahmedatum wird nicht vermerkt', () async {
      // Die Gegenprobe zum vorigen Test: Stünde die Marke immer, wäre sie
      // keine Auskunft, sondern ein Aufdruck.
      final a = await importiere('mit.jpg',
          datum: DateTime(2013, 7, 4, 15, 22, 8), inhalt: 1);
      expect(a.datumGeschaetzt, isFalse);
      expect(a.fileCreatedAt, DateTime(2013, 7, 4, 15, 22, 8));
    });
  });

  group('der Nachtrag über die Bibliothek', () {
    /// Legt eine Datei an der Stelle ab, an der die Datenbank sie
    /// vermutet – der Nachtrag liest die Bibliothek, nicht den Eingang.
    Future<void> legeAb(String id, {DateTime? datum, int inhalt = 0}) async {
      final datei = paths.absolute('originals/2006/08/$id.jpg');
      await datei.parent.create(recursive: true);
      await datei.writeAsBytes(jpeg(datum: datum, inhalt: inhalt));
    }

    test('markiert genau die Dateien ohne Datum', () async {
      await altbestand('ohne', DateTime(2006, 8, 27));
      await altbestand('mit', DateTime(2006, 8, 27));
      await legeAb('ohne');
      await legeAb('mit', datum: DateTime(2013, 7, 4, 15, 22, 8), inhalt: 1);

      expect(await db.countDatumsherkunft(), 2,
          reason: 'vor dem Lauf ist bei keiner nachgesehen worden');
      await for (final _ in library.backfillDatumsherkunft()) {}

      expect((await db.assetById('ohne'))!.datumGeschaetzt, isTrue);
      expect((await db.assetById('mit'))!.datumGeschaetzt, isFalse);
      expect(await db.countDatumsherkunft(), 0,
          reason: 'ein zweiter Lauf hätte nichts mehr zu tun');
    });

    test('eine fehlende Datei bleibt ungeprüft statt als geschätzt zu gelten',
        () async {
      // „Nicht da" heisst nicht „ohne Datum". Würde sie hier markiert,
      // wäre die Marke eine Behauptung über eine Datei, die niemand
      // gelesen hat – und ein späterer Lauf käme nie wieder auf sie
      // zurück.
      await altbestand('verschwunden', DateTime(2006, 8, 27));
      await for (final _ in library.backfillDatumsherkunft()) {}

      final a = (await db.assetById('verschwunden'))!;
      expect(a.datumGeschaetzt, isFalse);
      expect(a.datumGeprueft, isFalse);
      expect(await db.countDatumsherkunft(), 1);
    });

    test('eine Datei, die niemand lesen kann, gilt nicht als datenlos',
        () async {
      // **Der Fund, der diesen Zweig erzwungen hat.** Der erste Lauf über
      // die echte Bibliothek meldete 2806 Aufnahmen ohne Datum – darunter
      // ALLE 909 CR3. Vier davon mit exiftool gegengelesen: alle vier
      // tragen ein DateTimeOriginal. Die Ursache war nicht die Datei,
      // sondern der Leser – CR3 ist ein ISO-BMFF-Container, `package:exif`
      // liest dort nichts, und der native Rückfall braucht einen
      // Method-Channel, den es im Prüflauf nicht gibt.
      //
      // Hier nachgestellt mit einer CR3-Endung über Bytes, die kein
      // Format sind: Ein Fehlschlag des Werkzeugs darf keine Aussage über
      // die Datei werden.
      await db.insertAsset(AssetsCompanion.insert(
        id: 'roh',
        originalFileName: 'roh.cr3',
        relativePath: 'originals/2006/08/roh.cr3',
        checksum: 'pruef-roh',
        type: 'IMAGE',
        fileCreatedAt: DateTime(2006, 8, 27),
        importedAt: DateTime(2026),
      ));
      final datei = paths.absolute('originals/2006/08/roh.cr3');
      await datei.parent.create(recursive: true);
      await datei.writeAsBytes(List<int>.filled(64, 7));

      await for (final _ in library.backfillDatumsherkunft()) {}

      final a = (await db.assetById('roh'))!;
      expect(a.datumGeschaetzt, isFalse,
          reason: '909 richtig datierte CR3 haetten sonst eine Marke bekommen');
      expect(a.datumGeprueft, isFalse,
          reason: 'sie soll im naechsten Lauf wieder drankommen');
    });

    test('eine CR3 wird nicht erst ganz gelesen', () async {
      // `package:exif` liefert bei CR3 nichts – nachgezaehlt an der
      // echten Bibliothek: 0 von 8 Stichproben tragen auch nur einen Tag.
      // 909 CR3 mit je rund 29 MB sind 28 GB, die durch den Speicher
      // gingen fuer ein sicheres Nichts; isoliert gemessen 5646 ms gegen
      // 136 ms.
      //
      // Geprueft wird das ueber ein als `.cr3` benanntes JPEG: Sagt der
      // Kopf etwas anderes als der Name, MUSS doch ganz gelesen werden –
      // sonst rutschte ein Standbild unter falschem Namen durch, so wie
      // die 31 JPEGs, die in dieser Bibliothek `.mov` heissen.
      await db.insertAsset(AssetsCompanion.insert(
        id: 'getarnt',
        originalFileName: 'getarnt.cr3',
        relativePath: 'originals/2006/08/getarnt.cr3',
        checksum: 'pruef-getarnt',
        type: 'IMAGE',
        fileCreatedAt: DateTime(2006, 8, 27),
        importedAt: DateTime(2026),
      ));
      final datei = paths.absolute('originals/2006/08/getarnt.cr3');
      await datei.parent.create(recursive: true);
      await datei.writeAsBytes(jpeg(datum: DateTime(2013, 7, 4, 15, 22, 8)));

      await for (final _ in library.backfillDatumsherkunft()) {}

      final a = (await db.assetById('getarnt'))!;
      expect(a.datumGeprueft, isTrue);
      expect(a.datumGeschaetzt, isFalse,
          reason: 'das JPEG traegt ein Datum, der Name luegt nur');
    });

    test('ein zweiter Lauf mit „alle" nimmt die Marke wieder zurück',
        () async {
      // Der Weg für Dateien, die ausserhalb der App nachträglich ein
      // Datum bekommen haben. Ohne das Zurücknehmen bliebe die Marke für
      // immer stehen, obwohl der Grund weg ist.
      await altbestand('spaeter', DateTime(2006, 8, 27));
      await legeAb('spaeter');
      await for (final _ in library.backfillDatumsherkunft()) {}
      expect((await db.assetById('spaeter'))!.datumGeschaetzt, isTrue);

      await legeAb('spaeter', datum: DateTime(2013, 7, 4), inhalt: 2);
      await for (final _ in library.backfillDatumsherkunft(alle: true)) {}
      expect((await db.assetById('spaeter'))!.datumGeschaetzt, isFalse);
    });
  });

  test('ein von Hand gesetztes Datum nimmt die Marke zurück', () async {
    // Wer das Datum selbst einträgt, weiss mehr als die Datei. Bliebe die
    // Marke stehen, hinge sie ausgerechnet an dem Wert, der von allen der
    // belegteste ist.
    await altbestand('a', DateTime(2006, 8, 27), geschaetzt: true);
    await db.setAufnahmezeitpunkt('a', DateTime(1998, 5, 3, 14, 30));

    final a = (await db.assetById('a'))!;
    expect(a.fileCreatedAt, DateTime(1998, 5, 3, 14, 30));
    expect(a.datumGeschaetzt, isFalse);
  });

  test('die Erinnerungen übergehen geschätzte Daten', () async {
    // Der Abschnitt macht aus dem Datum eine Behauptung: „vor 20 Jahren,
    // an genau diesem Tag". An der echten Bibliothek wären am 27. August
    // 948 Aufnahmen auf einmal erschienen, von denen keine an diesem Tag
    // entstand.
    final heute = DateTime(2026, 8, 27);
    await altbestand('geraten', DateTime(2006, 8, 27), geschaetzt: true);
    await altbestand('gemessen', DateTime(2006, 8, 27, 14, 12, 3));

    final treffer = await db.assetsOnThisDay(heute);
    expect([for (final a in treffer) a.id], ['gemessen'],
        reason: 'ohne den Filter stünden hier beide');
  });

  test('die Serienerkennung übergeht geschätzte Daten', () async {
    // Eine Serie ist über ihren zeitlichen Abstand definiert. Aufnahmen
    // mit geratenem Datum tragen alle denselben Zeitstempel – der Abstand
    // ist null, nicht weil sie zusammengehören, sondern weil niemand ihre
    // Zeit kennt. Genau so entstand die „Serie" mit 943 Mitgliedern.
    final wann = DateTime(2006, 8, 27);
    for (final id in ['g1', 'g2', 'g3']) {
      await altbestand(id, wann, geschaetzt: true);
    }
    for (final id in ['m1', 'm2']) {
      await altbestand(id, wann);
    }
    // Alle fünf sehen sich zum Verwechseln ähnlich: Über die Ähnlichkeit
    // allein wären sie eine einzige Gruppe.
    final gleich = Float32List.fromList([1, 0, 0, 0]);
    final einbettungen = {
      for (final id in ['g1', 'g2', 'g3', 'm1', 'm2']) id: gleich,
    };

    final gruppen = await serienvorschlaege(db, einbettungen);
    final drin = {for (final g in gruppen) ...[for (final a in g) a.id]};
    expect(drin, {'m1', 'm2'},
        reason: 'die drei geschätzten dürfen gar nicht erst zusammenfinden');
  });

  test('der Suchfilter findet genau die geschätzten', () async {
    await altbestand('geraten', DateTime(2006, 8, 27), geschaetzt: true);
    await altbestand('gemessen', DateTime(2006, 8, 27, 14, 12, 3));

    final treffer = await db
        .searchAssets(const SearchFilters(nurGeschaetztesDatum: true));
    expect([for (final a in treffer) a.id], ['geraten']);

    // Ohne den Filter stehen beide da – sonst prüfte der Test nur, dass
    // die Bibliothek klein ist.
    expect((await db.searchAssets(const SearchFilters())).length, 2);
  });

  test('gespeicherte Suchen tragen den Filter mit', () async {
    const f = SearchFilters(nurGeschaetztesDatum: true);
    expect(SearchFilters.fromJson(f.toJson()).nurGeschaetztesDatum, isTrue);
    // Und eine Suche von vor der Änderung liest sich weiter, ohne den
    // Filter versehentlich einzuschalten.
    expect(SearchFilters.fromJson(const <String, dynamic>{})
        .nurGeschaetztesDatum, isFalse);
  });
}
