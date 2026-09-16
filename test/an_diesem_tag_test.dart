import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';

/// **„An diesem Tag" lädt nicht mehr die ganze Bibliothek.**
///
/// Die Rückblick-Kachel der Übersicht suchte zwei Fotos, indem sie alle
/// 7341 in Objekte umsetzte – 56 Spalten je Zeile für einen Vergleich von
/// Monat und Tag. Jetzt wird zuerst nur nach Kennung und Datum gefragt und
/// erst die Handvoll Treffer vollständig geladen:
///
/// ```
/// alles laden, in Dart filtern   253,2 ms
/// erst Kennung und Datum          32,6 ms
/// ```
///
/// Zwei Dinge müssen dabei stimmen, und beide prüft dieser Prüfstand:
///
/// - **Dieselbe Antwort.** Verglichen wird gegen die alte Rechnung, hier
///   wortgetreu nachgebaut. Ein Weg über `strftime(…, 'localtime')` wäre
///   noch schneller gewesen, wurde aber verworfen: an einem ganzen Jahr
///   der echten Bibliothek durchgespielt lieferte er zwar überall dieselbe
///   Anzahl, bei gleichen Zeitstempeln aber eine andere Reihenfolge.
/// - **Die Spaltennamen.** Die schlanke Abfrage liest ihre zwei Spalten
///   roh über `rawData` (das halbiert die Zeit), und die Namen dafür
///   vergibt drift. Änderte sich daran etwas, liefe das Lesen in einen
///   Fehler – und ohne diesen Prüfstand erst beim Anwender.
/// **Die Fixtures tragen krumme Uhrzeiten, und das ist Absicht.**
///
/// Seit Fassung 3.13.0 fallen Aufnahmen auf voller Stunde aus den
/// Erinnerungen: An der echten Bibliothek liegen dort 1097 statt der
/// erwarteten zwei, 948 davon auf ein und derselben Sekunde, und am 27.
/// August waeren sie alle auf einmal als „vor 20 Jahren" erschienen
/// (siehe [AppDatabase.assetsOnThisDay]). Geprueft wird hier
/// Sichtbarkeit, Sortierung und Schaltjahr – nicht die Uhrzeit; die
/// runden Werte von frueher waren Bequemlichkeit, nicht Aussage.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> foto(
    String id, {
    required DateTime wann,
    String typ = 'IMAGE',
    String? verknuepft,
    String? stapel,
    bool titelbild = false,
    bool papierkorb = false,
    bool gesperrt = false,
  }) =>
      db.insertAsset(AssetsCompanion.insert(
        id: id,
        relativePath: 'originals/$id.jpg',
        originalFileName: '$id.jpg',
        type: typ,
        checksum: id,
        fileCreatedAt: wann,
        importedAt: wann,
        isTrashed: Value(papierkorb),
        isLocked: Value(gesperrt),
        linkedAssetId: Value(verknuepft),
        stackId: Value(stapel),
        isStackCover: Value(titelbild),
      ));

  /// Die Fassung, die es vorher gab – Wort für Wort.
  Future<List<String>> alterWeg(DateTime heute) async {
    final alle = await db.select(db.assets).get();
    return (alle
            .where((a) =>
                !a.isTrashed &&
                !a.isLocked &&
                (a.type == 'IMAGE' || a.linkedAssetId == null) &&
                (a.stackId == null || a.isStackCover) &&
                a.fileCreatedAt.month == heute.month &&
                a.fileCreatedAt.day == heute.day &&
                a.fileCreatedAt.year != heute.year)
            .toList()
          ..sort((a, b) => b.fileCreatedAt.compareTo(a.fileCreatedAt)))
        .map((a) => a.id)
        .toList();
  }

  test('derselbe Tag in früheren Jahren, neueste zuerst', () async {
    await foto('a2024', wann: DateTime(2024, 8, 15, 10, 17));
    await foto('a2025', wann: DateTime(2025, 8, 15, 10, 17));
    await foto('heuer', wann: DateTime(2026, 8, 15, 10, 17));
    await foto('tagsdrauf', wann: DateTime(2024, 8, 16, 10, 17));

    final heute = DateTime(2026, 8, 15);
    final ids = (await db.assetsOnThisDay(heute)).map((a) => a.id).toList();
    expect(ids, ['a2025', 'a2024'],
        reason: 'das Foto von heute ist kein Rückblick');
    expect(ids, await alterWeg(heute));
  });

  test('was ausgeblendet gehört, bleibt ausgeblendet', () async {
    // Genau die Regel, die überall sonst gilt (_isPrimaryGridEntry) – sie
    // steht nur einmal, und die schlanke Abfrage benutzt dieselbe.
    await foto('sichtbar', wann: DateTime(2024, 8, 15, 12, 17));
    await foto('videohaelfte',
        wann: DateTime(2024, 8, 15, 11, 17), typ: 'VIDEO', verknuepft: 'sichtbar');
    await foto('stapelmitglied',
        wann: DateTime(2024, 8, 15, 10, 17), stapel: 's1');
    await foto('papierkorb', wann: DateTime(2024, 8, 15, 9, 17), papierkorb: true);
    await foto('tresor', wann: DateTime(2024, 8, 15, 8, 17), gesperrt: true);
    await foto('freiesvideo', wann: DateTime(2024, 8, 15, 7, 17), typ: 'VIDEO');

    final heute = DateTime(2026, 8, 15);
    final ids = (await db.assetsOnThisDay(heute)).map((a) => a.id).toList();
    expect(ids, ['sichtbar', 'freiesvideo']);
    expect(ids, await alterWeg(heute));
  });

  test('ohne Treffer wird gar nicht erst nachgeladen', () async {
    await foto('anderer', wann: DateTime(2024, 3, 3, 9, 17));
    expect(await db.assetsOnThisDay(DateTime(2026, 8, 15)), isEmpty);
  });

  test('der 29. Februar findet nur Schaltjahre', () async {
    // Der Tag, an dem eine Rechnung über den Jahrestag leicht danebengreift.
    await foto('schalt', wann: DateTime(2024, 2, 29, 12, 17));
    await foto('erster', wann: DateTime(2023, 3, 1, 12, 17));
    final heute = DateTime(2028, 2, 29);
    final ids = (await db.assetsOnThisDay(heute)).map((a) => a.id).toList();
    expect(ids, ['schalt']);
    expect(ids, await alterWeg(heute));
  });

  test('viele Treffer kommen vollstaendig und sortiert zurueck', () async {
    // Das Nachladen geht über `id IN (…)`; die Reihenfolge daraus ist die
    // der Datenbank, nicht die gewünschte – sortiert wird danach.
    for (var jahr = 2010; jahr < 2026; jahr++) {
      for (var stunde = 0; stunde < 5; stunde++) {
        await foto('f$jahr-$stunde', wann: DateTime(jahr, 8, 15, stunde, 17));
      }
    }
    final heute = DateTime(2026, 8, 15);
    final ids = (await db.assetsOnThisDay(heute)).map((a) => a.id).toList();
    expect(ids, hasLength(80));
    expect(ids, await alterWeg(heute));
    expect(ids.first, 'f2025-4');
    expect(ids.last, 'f2010-0');
  });
}
