import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/screens/dokumente_screen.dart';
import 'package:photo_vault/services/dokumenterkennung.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// Ausweise und Karten aus dem erkannten Text.
///
/// Die Prüfzeilen sind die Musterdokumente aus ICAO 9303 und der
/// Mustermann-Ausweis – mit Prüfziffern, die stimmen.
void main() {
  group('Prüfzeile', () {
    test('Reisepass (TD3)', () {
      final fund = dokumentImText(
        'Reisepass\n'
        'P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<\n'
        'L898902C36UTO7408122F1204159ZE184226B<<<<<10',
      );
      expect(fund, (
        art: Dokumentart.reisepass,
        grund: Dokumentgrund.pruefzeile,
      ));
    });

    test('Personalausweis (TD1), mit falsch gelesenen Füllzeichen', () {
      final fund = dokumentImText(
        'IDD«T220001293««««««««««««««\n'
        '6408125 «2010315D«««««««««««««4\n'
        'MUSTERMANN<<ERIKA<<<<<<<<<<<<<',
      );
      expect(fund, (art: Dokumentart.ausweis, grund: Dokumentgrund.pruefzeile));
    });

    test('Aufenthaltstitel teilt das Format, der Aufdruck entscheidet', () {
      final fund = dokumentImText(
        'AUFENTHALTSTITEL\nARD<<X00000000<<<<<<<<<<<<<<<\n'
        '6408125F2010315D<<<<<<<<<<<<<4',
      );
      expect(fund?.art, Dokumentart.aufenthaltstitel);
    });

    test('eine falsche Prüfziffer ist keine Prüfzeile', () {
      expect(dokumentImText('6408124<2010315D<<<<<<'), isNull);
      expect(dokumentImText('6408125<2010316D<<<<<<'), isNull);
    });
  });

  group('Kartennummer', () {
    test('in Vierergruppen und gültig', () {
      expect(dokumentImText('VISA\n4111 1111 1111 1111\nVALID THRU 12/29'), (
        art: Dokumentart.karte,
        grund: Dokumentgrund.kartennummer,
      ));
      expect(dokumentImText('5500-0000-0000-0004')?.art, Dokumentart.karte);
    });

    test('Luhn falsch, oder ohne Gruppen wie auf einem Kassenbon', () {
      expect(dokumentImText('4111 1111 1111 1112'), isNull);
      expect(dokumentImText('Beleg 4111111111111111 Summe 12,30'), isNull);
    });
  });

  test('Schlüsselwörter, auch über Zeilen und Leerzeichen hinweg', () {
    expect(dokumentImText('BUNDESREPUBLIK DEUTSCHLAND\nFÜHRERSCHEIN'), (
      art: Dokumentart.fuehrerschein,
      grund: Dokumentgrund.schluesselwort,
    ));
    expect(
      dokumentImText('UK DRIVING\nLICENCE')?.art,
      Dokumentart.fuehrerschein,
    );
    expect(dokumentImText('Personalausweis')?.art, Dokumentart.ausweis);
  });

  test('gewöhnlicher Text ist nichts', () {
    expect(dokumentImText(null), isNull);
    expect(dokumentImText(''), isNull);
    expect(
      dokumentImText('Speisekarte\nSchnitzel 12,50\nTel. 0711 123456'),
      isNull,
    );
    expect(dokumentImText('Zug 4711 nach Hamburg, Gleis 12, 08:15'), isNull);
  });

  group('Datenbank', () {
    late AppDatabase db;
    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      for (final (id, text, gesperrt) in [
        ('pass', 'REISEPASS PASSPORT', false),
        ('menue', 'Speisekarte', false),
        ('leer', null, false),
        ('tresor', 'PERSONALAUSWEIS', true),
        ('karte', '4111 1111 1111 1111', false),
      ]) {
        await db
            .into(db.assets)
            .insert(
              AssetsCompanion.insert(
                id: id,
                originalFileName: '$id.jpg',
                relativePath: 'originals/$id.jpg',
                checksum: 'pruef-$id',
                type: 'IMAGE',
                fileCreatedAt: DateTime(2026, 1, id.length),
                importedAt: DateTime(2026),
              ),
            );
        if (text != null) await db.setOcrResult(id, text);
        if (gesperrt) await db.setAssetsLocked([id], true);
      }
    });
    tearDown(() => db.close());

    test('nur offen liegende Funde, abgelehnte bleiben weg', () async {
      final vorher = await ladeDokumentvorschlaege(db);
      expect({for (final v in vorher) v.asset.id}, {'pass', 'karte'});

      await db.verwirfDokumentvorschlaege(['karte']);
      final nachher = await ladeDokumentvorschlaege(db);
      expect([for (final v in nachher) v.asset.id], ['pass']);
    });
  });

  test('Migration 87 auf 88 legt die Tabelle an', () async {
    final dir = await Directory.systemTemp.createTemp('photo_vault_v87_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/library.sqlite');
    final initial = AppDatabase(NativeDatabase(file));
    await initial.setzeStammbaumZuletzt(ansicht: 'faecher', person: 'p1');
    await initial.close();

    final alt = sqlite.sqlite3.open(file.path);
    alt.execute('DROP TABLE verworfene_dokumente');
    alt.execute('PRAGMA user_version = 87');
    alt.close();

    final db = AppDatabase(NativeDatabase(file));
    addTearDown(db.close);
    expect((await db.stammbaumZuletzt()).person, 'p1');
    expect(await db.texteFuerDokumentsuche(), isEmpty);
    await db.verwirfDokumentvorschlaege(['x']);
  });
}
