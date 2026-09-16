import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/serienvergleich.dart';

/// **Die Gesichter einer Serie nebeneinander.**
///
/// Aus fünf fast gleichen Aufnahmen die eine herauszusuchen, auf der
/// niemand blinzelt, ist die Arbeit, für die es Narrative Select gibt.
/// Alles Nötige lag längst da: die 160×160-Ausschnitte auf der Platte, die
/// Schärfe je Gesicht seit Fassung 61 in der Datenbank. Es fehlte die
/// Ansicht, die beides nebeneinanderstellt.
///
/// **Zum Augenzustand.** Er steht in dieser Ansicht, weil das Gesicht
/// daneben steht. Als Warnung ohne Bild stand er bis Fassung 63 in der
/// Sichtungsleiste – und hatte dort unrecht: An der echten Bibliothek
/// meldete das Modell für 64,5 % der grossen Gesichter „geschlossen", und
/// fünf zufällig herausgegriffene Gesichter mit dem Wert 0,00 hatten
/// allesamt die Augen offen.
void main() {
  late Directory temp;
  late AppDatabase db;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('pv_serienvgl_');
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() async {
    await db.close();
    temp.deleteSync(recursive: true);
  });

  Future<AssetData> lege(String id, {int rating = 0}) async {
    await db.insertAsset(AssetsCompanion.insert(
      id: id,
      relativePath: 'originals/$id.jpg',
      originalFileName: '$id.jpg',
      type: 'IMAGE',
      checksum: id,
      fileCreatedAt: DateTime(2024, 5, 1, 12, 0, int.parse(id.substring(1))),
      importedAt: DateTime(2024),
      rating: Value(rating),
    ));
    return (await db.assetById(id))!;
  }

  Future<void> legeGesicht(
    String id,
    String assetId, {
    double breite = 0.2,
    double? schaerfe,
    double? augen,
    String? personId,
    bool ignoriert = false,
  }) =>
      db.insertFace(FacesCompanion.insert(
        id: id,
        assetId: assetId,
        boxX: 0.1,
        boxY: 0.1,
        boxW: breite,
        boxH: breite,
        cropRelativePath: Value('faces/$id.jpg'),
        schaerfe: Value(schaerfe),
        eyeOpenScore: Value(augen),
        personId: Value(personId),
        isIgnored: Value(ignoriert),
      ));

  test('eine Spalte je Aufnahme, Gesichter nach Grösse', () async {
    final a = await lege('a1');
    // Bewusst in „falscher" Reihenfolge angelegt: Die Anordnung soll aus
    // der Grösse kommen, nicht aus der Erkennungsreihenfolge – sonst
    // spränge dieselbe Person von Spalte zu Spalte.
    await legeGesicht('klein', 'a1', breite: 0.05);
    await legeGesicht('gross', 'a1', breite: 0.30);
    await legeGesicht('mittel', 'a1', breite: 0.15);

    final spalten = await serienspalten(db, [a]);
    expect(spalten.length, 1);
    expect([for (final g in spalten.single.gesichter) g.breite],
        [0.30, 0.15, 0.05]);
  });

  test('das schärfste Gesicht zählt, nicht der Durchschnitt', () async {
    // Auf einem Gruppenbild ist hinten fast immer jemand weich. Erst wenn
    // auch der beste Kopf weich ist, hat man ein Bild ohne brauchbares
    // Gesicht – dieselbe Regel wie in der Sichtung.
    final a = await lege('a1');
    await legeGesicht('f1', 'a1', schaerfe: 5);
    await legeGesicht('f2', 'a1', schaerfe: 800);
    await legeGesicht('f3', 'a1', schaerfe: 12);
    expect((await serienspalten(db, [a])).single.besteSchaerfe, 800);
  });

  test('ohne gemessene Schärfe bleibt die Spalte ohne Urteil', () async {
    final a = await lege('a1');
    await legeGesicht('f1', 'a1');
    expect((await serienspalten(db, [a])).single.besteSchaerfe, isNull);
  });

  test('beiseitegelegte Gesichter kommen nicht mit', () async {
    final a = await lege('a1');
    await legeGesicht('f1', 'a1', schaerfe: 100);
    await legeGesicht('weg', 'a1', schaerfe: 900, ignoriert: true);
    final spalte = (await serienspalten(db, [a])).single;
    expect(spalte.gesichter.length, 1);
    expect(spalte.besteSchaerfe, 100,
        reason: 'ein beiseitegelegtes Gesicht darf die Auswahl nicht '
            'bestimmen');
  });

  test('der Name der Person steht dabei', () async {
    final a = await lege('a1');
    await db.createPerson(PeopleCompanion.insert(id: 'p1', name: 'Anna'));
    await legeGesicht('f1', 'a1', personId: 'p1');
    await legeGesicht('f2', 'a1', breite: 0.1);
    final koepfe = (await serienspalten(db, [a])).single.gesichter;
    expect(koepfe.first.name, 'Anna');
    expect(koepfe.last.name, isNull);
  });

  test('der Augenwert wird durchgereicht, auch wenn er fehlt', () async {
    final a = await lege('a1');
    await legeGesicht('f1', 'a1', augen: 0.93);
    await legeGesicht('f2', 'a1', breite: 0.1);
    final koepfe = (await serienspalten(db, [a])).single.gesichter;
    expect(koepfe.first.augenOffen, closeTo(0.93, 1e-9));
    expect(koepfe.last.augenOffen, isNull,
        reason: '„nicht berechnet" ist etwas anderes als „Augen zu"');
  });

  test('eine Serie behält ihre Reihenfolge', () async {
    final a = await lege('a1');
    final b = await lege('a2');
    final c = await lege('a3');
    final spalten = await serienspalten(db, [a, b, c]);
    expect([for (final s in spalten) s.asset.id], ['a1', 'a2', 'a3']);
  });

  test('eine Aufnahme ohne Gesichter ergibt eine leere Spalte', () async {
    final a = await lege('a1');
    final spalte = (await serienspalten(db, [a])).single;
    expect(spalte.gesichter, isEmpty);
    expect(spalte.besteSchaerfe, isNull);
  });
}
