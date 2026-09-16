import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/gedcom_import.dart';
import 'package:photo_vault/services/lebenslauf.dart';
import 'package:photo_vault/services/stammbaum.dart';

/// Der Weg von der eingelesenen Datei in die Datenbank.
///
/// Der Einleser selbst ist in gedcom_import_test.dart geprüft, ohne
/// Datenbank. Hier geht es um das, was erst zusammen sichtbar wird: dass
/// die frisch vergebenen Kennungen durchgängig passen, dass die
/// Partnerzeile in ihrer gespeicherten Form landet und dass eine
/// abgebrochene Übernahme nichts Halbes hinterlässt.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  const t = gedcomBezeichnungenTest;

  const datei = '0 HEAD\r\n'
      '1 CHAR UTF-8\r\n'
      '0 @I1@ INDI\r\n'
      '1 NAME Hans /Meier/\r\n'
      '1 SEX M\r\n'
      '1 BIRT\r\n'
      '2 DATE 2 APR 1931\r\n'
      '2 PLAC Hamburg\r\n'
      '0 @I2@ INDI\r\n'
      '1 NAME Grete /Meier/\r\n'
      '1 SEX F\r\n'
      '0 @I3@ INDI\r\n'
      '1 NAME Karl /Meier/\r\n'
      '0 @F1@ FAM\r\n'
      '1 HUSB @I1@\r\n'
      '1 WIFE @I2@\r\n'
      '1 CHIL @I3@\r\n'
      '0 TRLR\r\n';

  /// Derselbe Ablauf wie im Bildschirm, nur ohne Oberfläche.
  Future<Map<String, String>> uebernimm(String inhalt,
      {List<String> kennungen = const ['n1', 'n2', 'n3']}) async {
    final gelesen = liesGedcom(utf8.encode(inhalt), texte: t);
    final neu = <String, String>{};
    for (var i = 0; i < gelesen.personen.length; i++) {
      neu[gelesen.personen[i].kennung] = kennungen[i];
    }
    var zaehler = 0;
    await db.uebernehmeGedcom(
      personen: [
        for (final p in gelesen.personen)
          PeopleCompanion.insert(
            id: neu[p.kennung]!,
            name: p.name,
            geburtsdatum: Value(p.geburt),
            sterbedatum: Value(p.tod),
          ),
      ],
      kanten: mitNeuenKennungen(gelesen.kanten, neu),
      ereignisse: [
        for (final p in gelesen.personen)
          for (final e in p.ereignisse)
            LebensereignisseCompanion.insert(
              id: 'e${zaehler++}',
              personId: neu[p.kennung]!,
              art: ereignisartZuText(e.art),
              datum: Value(e.datum),
              ort: Value(e.ort),
              notiz: Value(e.notiz),
            ),
      ],
    );
    return neu;
  }

  test('Personen, Verwandtschaften und Ereignisse landen zusammen', () async {
    await uebernimm(datei);
    expect(await db.select(db.people).get(), hasLength(3));
    expect(await db.alleBeziehungen(), hasLength(3));
    final ereignisse = await db.select(db.lebensereignisse).get();
    expect(ereignisse, hasLength(1));
    expect(ereignisse.single.ort, 'Hamburg',
        reason: 'der Geburtsort wäre sonst der Eintrag, der still verschwindet');
  });

  test('die Partnerzeile steht in ihrer gespeicherten Form', () async {
    // Der Fall, der ohne mitNeuenKennungen falsch herauskommt: In der
    // Datei ist I1 die kleinere Kennung, in der Datenbank ist es die
    // andere Person. Stünde die alte Reihenfolge in der Zeile, fände das
    // spätere Auflösen der Partnerschaft sie nicht mehr.
    final neu = await uebernimm(datei, kennungen: ['zzz', 'aaa', 'mmm']);
    final partner = (await db.alleBeziehungen())
        .firstWhere((z) => z.art == artZuText(Verwandtschaft.partner));
    expect(partner.personId, 'aaa');
    expect(partner.andereId, 'zzz');
    expect(neu['I2'], 'aaa');

    // Gegenprobe über den Weg, den die App wirklich geht.
    expect(await db.entferneBeziehung('zzz', 'aaa', Verwandtschaft.partner),
        isTrue);
  });

  test('die Kanten sind fuer den Stammbaum lesbar', () async {
    // Nicht nur „drei Zeilen da": Sie müssen durch dieselbe Umwandlung
    // laufen wie alles Übrige, sonst steht das Kind ohne Eltern im Baum.
    final neu = await uebernimm(datei);
    final zeilen = await db.alleBeziehungen();
    final netz = Verwandtschaftsnetz([
      for (final z in zeilen)
        if (artAusText(z.art) case final art?)
          kante(z.personId, z.andereId, art),
    ]);
    expect(netz.eltern(neu['I3']!), {neu['I1'], neu['I2']});
    expect(netz.partner(neu['I1']!), {neu['I2']});
  });

  test('eine Uebernahme laesst nichts Halbes zurueck', () async {
    // Personen ohne ihre Verwandtschaften sehen aus wie richtige
    // Einträge – niemand könnte hinterher sagen, wo der Abbruch war.
    // Eine doppelte Ereigniskennung bricht hier absichtlich ab.
    await expectLater(
      db.uebernehmeGedcom(
        personen: [PeopleCompanion.insert(id: 'p1', name: 'Anna')],
        kanten: const [],
        ereignisse: [
          LebensereignisseCompanion.insert(
              id: 'gleich', personId: 'p1', art: 'umzug'),
          LebensereignisseCompanion.insert(
              id: 'gleich', personId: 'p1', art: 'umzug'),
        ],
      ),
      throwsA(anything),
    );
    expect(await db.select(db.people).get(), isEmpty);
    expect(await db.select(db.lebensereignisse).get(), isEmpty);
  });

  test('eine grosse Datei bleibt in vertretbarer Zeit', () async {
    // Die Kreisprüfung lief einmal je Kante gegen ein jedes Mal neu
    // aufgebautes Netz – quadratisch, und bei dreitausend Personen
    // spürbar. Diese Zeile ist der Grund für `Verwandtschaftsnetz.ergaenze`.
    const paare = 1500;
    final zeilen = <String>['0 HEAD', '1 CHAR UTF-8'];
    for (var i = 0; i < paare; i++) {
      zeilen.addAll([
        '0 @V$i@ INDI',
        '1 NAME Vater$i /Reihe/',
        '0 @M$i@ INDI',
        '1 NAME Mutter$i /Reihe/',
      ]);
    }
    for (var i = 0; i < paare; i++) {
      zeilen.addAll(['0 @F$i@ FAM', '1 HUSB @V$i@', '1 WIFE @M$i@']);
      // Eine Kette über die Generationen, damit die Kreisprüfung
      // tatsächlich weit nach oben laufen muss.
      if (i > 0) zeilen.add('1 CHIL @V${i - 1}@');
    }
    zeilen.add('0 TRLR');
    final bytes = utf8.encode(zeilen.map((z) => '$z\r\n').join());

    final uhr = Stopwatch()..start();
    final gelesen = liesGedcom(bytes, texte: t);
    uhr.stop();

    expect(gelesen.personen, hasLength(paare * 2));
    expect(gelesen.kanten, hasLength(paare + (paare - 1) * 2));
    expect(gelesen.hinweiseMit(GedcomHinweisart.kreisVerhindert), 0);
    expect(uhr.elapsed, lessThan(const Duration(milliseconds: 500)),
        reason: 'gemessen: 36 ms mit `ergaenze`, 1550 ms ohne – das '
            'Dreiundvierzigfache. Die Grenze liegt zwischen beiden Werten '
            'und nicht bei „ein paar Sekunden": Eine Grenze oberhalb des '
            'Rückfalls wäre keine.');
  });
}
