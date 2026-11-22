// Der Stand der Sicherung über das Abmelden hinaus (#431).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault_mobil/sicherung/gedaechtnis.dart';
import 'package:photo_vault_mobil/sicherung/stand.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory wurzel;
  late Directory kopie;
  late Sicherungsgedaechtnis gedaechtnis;
  final server = Uri.parse('https://fotos.example.org/');
  final zeit = DateTime(2026, 5, 6, 7);

  setUp(() {
    wurzel = Directory.systemTemp.createTempSync('pv_gedaechtnis_');
    kopie = Directory(p.join(wurzel.path, 'bibliothek'));
    gedaechtnis = Sicherungsgedaechtnis.neben(kopie);
  });

  tearDown(() => wurzel.deleteSync(recursive: true));

  /// Eine Bibliothek, wie der Abzug sie bringt, mit diesen Aufnahmen.
  void bibliothekMit(List<String> ids) {
    final db = sqlite3.open(p.join(kopie.path, 'library.sqlite'));
    db.execute('CREATE TABLE assets (id TEXT PRIMARY KEY)');
    for (final id in ids) {
      db.execute('INSERT INTO assets VALUES (?)', [id]);
    }
    db.close();
  }

  /// Ein Stand wie nach einiger Zeit eingeschalteter Sicherung.
  void standVorDemAbmelden() {
    final stand = Sicherungsstand.oeffne(kopie)
      ..einstellungen = const Sicherungseinstellungen(an: true, videos: false)
      ..erledige('f1', zeit, ausgang: 'hochgeladen', aufnahme: 'a1')
      ..erledige('f2', zeit, ausgang: 'vorhanden', aufnahme: 'a2')
      ..merkeOrt('f3', 'bild', 'summe', 'irgendwo');
    expect(stand.sperre('app'), isTrue);
    stand.schliesse();
  }

  /// Abmelden: aufheben, dann geht der Ordner.
  void abmelden() {
    gedaechtnis.bewahre(kopie, server: server, konto: 'erika');
    kopie.deleteSync(recursive: true);
    kopie.createSync();
  }

  test('dasselbe Konto: eingeschaltet, und Erledigtes geht nicht noch '
      'einmal hoch', () {
    standVorDemAbmelden();
    abmelden();
    // Am Server inzwischen endgültig gelöscht: a1. Die Bibliothek kennt a2.
    bibliothekMit(['a2']);

    final mit = gedaechtnis.stelleWiederHer(
      kopie,
      server: Uri.parse('https://fotos.example.org'),
      konto: 'erika',
    );
    expect(mit, isTrue);
    final stand = Sicherungsstand.oeffne(kopie);
    addTearDown(stand.schliesse);
    expect(stand.einstellungen.an, isTrue);
    expect(stand.einstellungen.videos, isFalse);
    expect(stand.bekannt().erledigt.keys, unorderedEquals(['f1', 'f2']));
    // Angefangenes und die Sperre gehörten zum alten Lauf.
    expect(stand.ort('f3', 'bild', 'summe'), isNull);
    expect(stand.sperre('anderer'), isTrue);
  });

  test('ein anderes Konto oder ein anderer Server beginnt von vorn', () {
    standVorDemAbmelden();
    abmelden();
    bibliothekMit(['a1', 'a2']);

    expect(
      gedaechtnis.stelleWiederHer(kopie, server: server, konto: 'max'),
      isFalse,
    );
    expect(
      gedaechtnis.stelleWiederHer(
        kopie,
        server: Uri.parse('https://anders.example.org/'),
        konto: 'erika',
      ),
      isFalse,
    );
    expect(
      File(p.join(kopie.path, Sicherungsstand.dateiname)).existsSync(),
      isFalse,
    );
  });

  test('neu aufgesetzter Server unter derselben Adresse: nur die '
      'Einstellungen kommen mit', () {
    standVorDemAbmelden();
    abmelden();
    // Die neue Bibliothek kennt keine der gesicherten Aufnahmen.
    bibliothekMit(['neu1']);

    expect(
      gedaechtnis.stelleWiederHer(kopie, server: server, konto: 'erika'),
      isFalse,
    );
    final stand = Sicherungsstand.oeffne(kopie);
    addTearDown(stand.schliesse);
    expect(stand.einstellungen.an, isTrue);
    expect(
      stand.bekannt().erledigt,
      isEmpty,
      reason: 'sonst ginge nie etwas zum neuen Server',
    );
  });

  test('der Name der Datei verrät weder Server noch Konto', () {
    standVorDemAbmelden();
    abmelden();
    final namen = [for (final f in gedaechtnis.ablage.listSync()) f.path];
    expect(namen, hasLength(1));
    expect(namen.single, isNot(contains('example')));
    expect(namen.single, isNot(contains('erika')));
  });
}
