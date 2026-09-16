import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/ortsvorschlag.dart';
import 'package:photo_vault/services/reverse_geocoder.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';

/// **Eine verworfene Messung gilt nur für ihren Datenstand.**
///
/// In der 6. Vergleichsauflage (30.08.2026) habe ich genau diese Rechnung
/// gemessen und abgelehnt: 68 Treffer, „verortete und unverortete stammen
/// aus verschiedenen Jahrzehnten, es gibt keine Nachbarn". Vier Tage und
/// zwei Arbeitsschritte später – 246 Videos haben ihren Ort aus der Datei
/// bekommen, 228 Aufnahmen einen von Hand – liefert dieselbe Rechnung an
/// derselben Bibliothek:
///
/// ```
///                                  30.08.   03.09.
/// ±30 min, Nachbarn einig ~2 km        68      286
/// ±2 h,    Nachbarn einig ~25 km        -      547   (35 uneinig)
/// ```
///
/// Was hier geprüft wird, ist deshalb nicht nur, dass die Rechnung etwas
/// findet, sondern **dass sie schweigt, wenn die Nachbarn sich nicht
/// einig sind**. Ohne diese Bedingung wäre sie ein Zufallsgenerator: Wer
/// am selben Nachmittag in Hannover und in Hamburg fotografiert hat,
/// bekäme für alles dazwischen den Ort, der zeitlich zufällig näher lag.
void main() {
  // Hannover, Hamburg und ein Punkt zwei Kilometer neben Hannover.
  const hannover = (52.37052, 9.73322);
  const hamburg = (53.55073, 9.99302);
  const nebenan = (52.38800, 9.73400);

  Ortsnachbar nachbar(DateTime wann, (double, double) ort) =>
      (wann: wann, breite: ort.$1, laenge: ort.$2);

  group('die Rechnung', () {
    test('erbt den Ort, wenn die Nachbarn sich einig sind', () {
      final v = ortsvorschlaege(
        [(id: 'a', wann: DateTime(2013, 7, 4, 12))],
        [
          nachbar(DateTime(2013, 7, 4, 11, 30), hannover),
          nachbar(DateTime(2013, 7, 4, 12, 40), nebenan),
        ],
      );
      expect(v, hasLength(1));
      expect(v.first.assetId, 'a');
      // Vom zeitlich naechsten Nachbarn: 30 Minuten gegen 40.
      expect(v.first.breite, closeTo(hannover.$1, 1e-9));
      expect(v.first.nachbarn, 2);
      expect(v.first.abstand, const Duration(minutes: 30));
      expect(v.first.spanneKm, lessThan(3));
    });

    test('schweigt, wenn die Nachbarn sich widersprechen', () {
      // **Der eigentliche Wert der Rechnung.** An der echten Bibliothek
      // fallen so 35 von 582 Kandidaten weg – und genau die waeren die
      // falschen gewesen.
      final v = ortsvorschlaege(
        [(id: 'a', wann: DateTime(2013, 7, 4, 12))],
        [
          nachbar(DateTime(2013, 7, 4, 11, 30), hannover),
          nachbar(DateTime(2013, 7, 4, 12, 40), hamburg),
        ],
      );
      expect(v, isEmpty,
          reason: 'Hannover und Hamburg sind 150 km auseinander');
    });

    test('schweigt, wenn kein Nachbar im Fenster liegt', () {
      final v = ortsvorschlaege(
        [(id: 'a', wann: DateTime(2013, 7, 4, 12))],
        [nachbar(DateTime(2013, 7, 4, 20), hannover)],
      );
      expect(v, isEmpty);
    });

    test('das Fenster gilt in beide Richtungen', () {
      // Ein Nachbar davor und einer danach muessen beide zaehlen –
      // sonst haenge das Ergebnis daran, in welcher Reihenfolge die
      // Aufnahmen entstanden.
      for (final versatz in [const Duration(hours: -1), const Duration(hours: 1)]) {
        final v = ortsvorschlaege(
          [(id: 'a', wann: DateTime(2013, 7, 4, 12))],
          [nachbar(DateTime(2013, 7, 4, 12).add(versatz), hannover)],
        );
        expect(v, hasLength(1), reason: 'Versatz $versatz');
      }
    });

    test('das Wanderfenster verrutscht bei vielen Aufnahmen nicht', () {
      // Beide Fensterraender wandern nur vorwaerts. Ein Fehler darin
      // faellt erst auf, wenn viele Aufnahmen nacheinander kommen –
      // deshalb hier hundert statt zwei.
      final ohneOrt = [
        for (var i = 0; i < 100; i++)
          (id: 'a$i', wann: DateTime(2013, 7, 4).add(Duration(minutes: i * 10))),
      ];
      final verortet = [
        for (var i = 0; i < 100; i++)
          nachbar(DateTime(2013, 7, 4).add(Duration(minutes: i * 10 + 5)),
              hannover),
      ];
      final v = ortsvorschlaege(ohneOrt, verortet);
      expect(v, hasLength(100));
      for (final e in v) {
        expect(e.abstand, const Duration(minutes: 5));
      }
    });

    test('ohne Nachbarn oder ohne Suchende kommt nichts', () {
      expect(ortsvorschlaege(const [], [nachbar(DateTime(2013), hannover)]),
          isEmpty);
      expect(
          ortsvorschlaege([(id: 'a', wann: DateTime(2013))], const []), isEmpty);
    });
  });

  group('die Bündelung', () {
    test('fasst denselben Tag am selben Ort zusammen', () {
      // 547 Vorschlaege einzeln zu bestaetigen waeren 547 Klicks –
      // derselbe Fehler, den die Serienerkennung bis Fassung 62 machte.
      final v = [
        for (var i = 0; i < 3; i++)
          Ortsvorschlag(
            assetId: 'a$i',
            breite: hannover.$1,
            laenge: hannover.$2,
            nachbarn: 2 + i,
            spanneKm: 1,
            abstand: Duration(minutes: 10 * (i + 1)),
          ),
      ];
      final zeiten = {
        'a0': DateTime(2013, 7, 4, 9),
        'a1': DateTime(2013, 7, 4, 15),
        // Anderer Tag – eigenes Buendel.
        'a2': DateTime(2013, 7, 5, 9),
      };
      final b = buendleOrtsvorschlaege(v, zeiten);
      expect(b, hasLength(2));
      // Neueste zuerst.
      expect(b.first.tag, DateTime(2013, 7, 5));
      expect(b.last.vorschlaege, hasLength(2));
      expect(b.last.groessterAbstand, const Duration(minutes: 20));
    });

    test('trennt denselben Tag an verschiedenen Orten', () {
      final v = [
        Ortsvorschlag(
            assetId: 'a',
            breite: hannover.$1,
            laenge: hannover.$2,
            nachbarn: 2,
            spanneKm: 1,
            abstand: const Duration(minutes: 5)),
        Ortsvorschlag(
            assetId: 'b',
            breite: hamburg.$1,
            laenge: hamburg.$2,
            nachbarn: 2,
            spanneKm: 1,
            abstand: const Duration(minutes: 5)),
      ];
      final zeiten = {
        'a': DateTime(2013, 7, 4, 9),
        'b': DateTime(2013, 7, 4, 20),
      };
      expect(buendleOrtsvorschlaege(v, zeiten), hasLength(2));
    });

    test('der Schlüssel ist die kleinste Kennung, nicht die erste', () {
      // Dieselbe Bildung wie bei Reisen, Aktivitaeten und Serien: Die
      // Reihenfolge der Mitglieder ist nicht zugesichert, der Schluessel
      // muss es sein – sonst faende ein „nein" beim naechsten Oeffnen
      // sein eigenes Buendel nicht wieder.
      Ortsvorschlag mach(String id) => Ortsvorschlag(
          assetId: id,
          breite: 1,
          laenge: 1,
          nachbarn: 1,
          spanneKm: 0,
          abstand: Duration.zero);
      final vorwaerts = Ortsbuendel(DateTime(2013), [mach('b'), mach('a')]);
      final rueckwaerts = Ortsbuendel(DateTime(2013), [mach('a'), mach('b')]);
      expect(vorwaerts.schluessel, 'a');
      expect(vorwaerts.schluessel, rueckwaerts.schluessel);
    });
  });

  group('an der Datenbank', () {
    late Directory wurzel;
    late AppDatabase db;
    late LibraryState library;

    setUp(() async {
      wurzel = Directory.systemTemp.createTempSync('pv_ortsvorschlag_');
      db = AppDatabase(NativeDatabase.memory());
      final staedte = File(p.join(wurzel.path, 'cities1000.txt'));
      await staedte.writeAsString('2910831\tHannover\tHannover\t\t52.37052\t'
          '9.73322\tP\tPPLA\tDE\t\t06\t\t\t\t515140\t\t55\tEurope/Berlin\t2023\n');
      final regionen = File(p.join(wurzel.path, 'admin1CodesASCII.txt'));
      await regionen
          .writeAsString('DE.06\tLower Saxony\tLower Saxony\t2862926\n');
      final laender = File(p.join(wurzel.path, 'countryInfo.txt'));
      await laender.writeAsString('# Kopf\nDE\tDEU\t276\tDE\tGermany\tBerlin\t'
          '357021\t82927922\tEU\t.de\tEUR\tEuro\t49\t\t\tde-DE\t2921044\t\t\n');
      library = LibraryState()
        ..db = db
        ..paths =
            await StoragePaths.forTesting(Directory(p.join(wurzel.path, 'l')))
        ..geocoder = await ReverseGeocoder.loadFromFiles(
            citiesFile: staedte, admin1File: regionen, countryFile: laender);
    });

    tearDown(() async {
      await db.close();
      wurzel.deleteSync(recursive: true);
    });

    Future<void> anlegen(String id, DateTime wann,
            {(double, double)? ort, bool gesperrt = false, bool papierkorb = false}) =>
        db.into(db.assets).insert(AssetsCompanion.insert(
              id: id,
              originalFileName: '$id.jpg',
              relativePath: 'originals/2013/07/$id.jpg',
              checksum: 'pruef-$id',
              type: 'IMAGE',
              fileCreatedAt: wann,
              importedAt: DateTime(2026),
              latitude: Value(ort?.$1),
              longitude: Value(ort?.$2),
              isLocked: Value(gesperrt),
              isTrashed: Value(papierkorb),
            ));

    test('die Abfrage trennt verortet von unverortet', () async {
      await anlegen('ohne', DateTime(2013, 7, 4, 12));
      await anlegen('mit', DateTime(2013, 7, 4, 12, 30), ort: hannover);
      final daten = await db.ortsvorschlagsdaten();
      expect([for (final o in daten.ohneOrt) o.id], ['ohne']);
      expect(daten.verortet, hasLength(1));
      expect(daten.verortet.first.breite, closeTo(hannover.$1, 1e-9));
    });

    test('Papierkorb und Tresor bleiben draussen', () async {
      // Ein geloeschtes Foto braucht keinen Ort, und ein gesperrtes soll
      // nicht ueber seine Nachbarn verraten, wo es entstand.
      await anlegen('geloescht', DateTime(2013, 7, 4, 12), papierkorb: true);
      await anlegen('gesperrt', DateTime(2013, 7, 4, 12), gesperrt: true);
      await anlegen('gesperrtMitOrt', DateTime(2013, 7, 4, 12, 5),
          ort: hannover, gesperrt: true);
      final daten = await db.ortsvorschlagsdaten();
      expect(daten.ohneOrt, isEmpty);
      expect(daten.verortet, isEmpty);
    });

    test('übernehmen setzt Ort, Ortsnamen und die Marke', () async {
      await anlegen('a', DateTime(2013, 7, 4, 12));
      await anlegen('b', DateTime(2013, 7, 4, 12, 10));
      await anlegen('n1', DateTime(2013, 7, 4, 11, 40), ort: hannover);
      await anlegen('n2', DateTime(2013, 7, 4, 12, 40), ort: nebenan);

      final buendel = await library.ortsvorschlagsbuendel();
      expect(buendel, hasLength(1));
      expect(buendel.first.vorschlaege, hasLength(2));

      await library.uebernimmOrtsbuendel(buendel.first);
      for (final id in ['a', 'b']) {
        final asset = (await db.assetById(id))!;
        expect(asset.latitude, closeTo(hannover.$1, 1e-9), reason: id);
        expect(asset.ortGeerbt, isTrue,
            reason: 'ein geerbter Ort ist kein gemessener');
        // Ohne die Ortsnamen staende die Aufnahme mit einer Koordinate
        // und ohne Namen da, und die Ortsgruppen saehen sie nicht.
        expect(asset.locationCity, 'Hannover', reason: id);
        expect(asset.locationCountry, 'Germany', reason: id);
      }
      // Und danach ist nichts mehr vorzuschlagen.
      expect(await library.ortsvorschlagsbuendel(), isEmpty);
    });

    test('ein neu gesetzter Ort nimmt die Marke zurück', () async {
      await anlegen('a', DateTime(2013, 7, 4, 12));
      await anlegen('n', DateTime(2013, 7, 4, 12, 10), ort: hannover);
      await library
          .uebernimmOrtsbuendel((await library.ortsvorschlagsbuendel()).first);
      expect((await db.assetById('a'))!.ortGeerbt, isTrue);

      await db.setLocation('a', 53.0, 10.0);
      expect((await db.assetById('a'))!.ortGeerbt, isFalse,
          reason: 'wer eine Koordinate setzt, ersetzt die Vermutung');
    });

    test('ein verworfenes Bündel kommt nicht wieder', () async {
      // Der Vorschlag entsteht bei jedem Aufruf neu aus den Daten. Ohne
      // Gedaechtnis stuende ein „nein" beim naechsten Oeffnen wieder da –
      // und anders als bei Serien gibt es keinen anderen Weg, es
      // festzuhalten: Eine abgelehnte Aufnahme bleibt unverortet.
      await anlegen('a', DateTime(2013, 7, 4, 12));
      await anlegen('n', DateTime(2013, 7, 4, 12, 10), ort: hannover);
      final buendel = await library.ortsvorschlagsbuendel();
      expect(buendel, hasLength(1));

      await db.verwirfOrtsvorschlag(buendel.first.schluessel);
      expect(await library.ortsvorschlagsbuendel(), isEmpty);
      // Und die Aufnahme ist unangetastet.
      expect((await db.assetById('a'))!.latitude, isNull);
    });

    test('uneinige Nachbarn erzeugen auch hier keinen Vorschlag', () async {
      await anlegen('a', DateTime(2013, 7, 4, 12));
      await anlegen('n1', DateTime(2013, 7, 4, 11, 30), ort: hannover);
      await anlegen('n2', DateTime(2013, 7, 4, 12, 30), ort: hamburg);
      expect(await library.ortsvorschlagsbuendel(), isEmpty);
    });
  });
}
