import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/aktivitaeten.dart';

/// Die Arten einer Aktivität – die mitgelieferten und die eigenen.
///
/// **Warum eigene Arten überhaupt gehen.** Die Spalte `art` ist Text und
/// speichert den Namen der Aufzählung, nicht ihren Index. Eine selbst
/// eingetragene Art kostet deshalb keinen Schemaschritt – aber sie
/// braucht zwei Vorkehrungen: Sie darf nicht als „Sonstiges" angezeigt
/// werden (dafür [istBekannteArt]), und sie darf keine mitgelieferte
/// doppeln (dafür [eigeneArtKennung]).
void main() {
  /// Die Namen, wie die Oberfläche sie zeigt – im Prüfstand von Hand,
  /// damit er ohne Übersetzungsapparat auskommt.
  const namen = {
    Aktivitaetsart.spaziergang: 'Spaziergang',
    Aktivitaetsart.wanderung: 'Wanderung',
    Aktivitaetsart.radtour: 'Radtour',
    Aktivitaetsart.ausflug: 'Ausflug',
    Aktivitaetsart.besichtigung: 'Besichtigung',
    Aktivitaetsart.bootsfahrt: 'Bootsfahrt',
    Aktivitaetsart.sonstiges: 'Sonstiges',
  };

  group('Spaziergang', () {
    test('ist eine mitgelieferte Art', () {
      expect(istBekannteArt('spaziergang'), isTrue);
      expect(Aktivitaetsart.aus('spaziergang'), Aktivitaetsart.spaziergang);
    });

    test('verschiebt keine gespeicherte Zeile', () {
      // Die neue Art steht VOR der Wanderung in der Aufzählung. Würde
      // der Index gespeichert, hiesse jede gespeicherte Wanderung jetzt
      // Radtour. Gespeichert wird der Name.
      expect(Aktivitaetsart.wanderung.kennung, 'wanderung');
      expect(Aktivitaetsart.aus('wanderung'), Aktivitaetsart.wanderung);
    });

    test('wird nicht geraten', () {
      // Bewusst nicht in [vermuteArt]: Die gerechnete Strecke ist eine
      // UNTERgrenze (Luftlinie zwischen Fotos, Pausen dazwischen). Eine
      // kurze gemessene Strecke belegt keinen kurzen Weg – ein
      // Spaziergang liesse sich also nur behaupten, nicht zeigen.
      expect(vermuteArt(3, const Duration(hours: 1)), Aktivitaetsart.wanderung);
      expect(vermuteArt(0.3, const Duration(hours: 1)),
          Aktivitaetsart.besichtigung);
    });
  });

  group('eine eigene Art eintragen', () {
    test('behält ihren Namen', () {
      expect(eigeneArtKennung('Konzert', namen), 'Konzert');
      expect(istBekannteArt('Konzert'), isFalse);
    });

    test('Leerzeichen ringsum fallen weg, Leeres wird nichts', () {
      expect(eigeneArtKennung('  Konzert  ', namen), 'Konzert');
      expect(eigeneArtKennung('   ', namen), isNull);
      expect(eigeneArtKennung('', namen), isNull);
    });

    test('wer eine mitgelieferte eintippt, bekommt die mitgelieferte', () {
      // Sonst stünden zwei Einträge namens „Wanderung" nebeneinander,
      // einer davon ohne Symbol und ohne Übersetzung.
      for (final eingabe in ['Wanderung', 'wanderung', 'WANDERUNG']) {
        expect(eigeneArtKennung(eingabe, namen), 'wanderung', reason: eingabe);
      }
      expect(eigeneArtKennung('Spaziergang', namen), 'spaziergang');
    });
  });

  group('welche eigenen Arten es gibt', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<void> aktivitaet(String id, String art) =>
        db.aktivitaetAnlegen(
            AktivitaetenCompanion.insert(
              id: id,
              name: id,
              art: art,
              von: DateTime(2026, 6, 1, 9),
              bis: DateTime(2026, 6, 1, 12),
              angelegtAm: DateTime(2026),
            ),
            const []);

    test('nur die, die keine mitgelieferte sind', () async {
      await aktivitaet('a', 'wanderung');
      await aktivitaet('b', 'Konzert');
      await aktivitaet('c', 'Spaziergang mit Hund');
      expect(await db.eigeneAktivitaetsarten(),
          ['Konzert', 'Spaziergang mit Hund']);
    });

    test('jede nur einmal', () async {
      await aktivitaet('a', 'Konzert');
      await aktivitaet('b', 'Konzert');
      expect(await db.eigeneAktivitaetsarten(), ['Konzert']);
    });

    test('ohne eigene Arten bleibt die Liste leer', () async {
      await aktivitaet('a', 'radtour');
      expect(await db.eigeneAktivitaetsarten(), isEmpty);
    });

    test('sie verschwindet mit ihrer letzten Aktivität', () async {
      // Der Preis dafür, dass es keine eigene Tabelle gibt – und der
      // Grund, warum er hier steht statt in einem Kommentar allein.
      await aktivitaet('a', 'Konzert');
      await db.aktivitaetAendern(
          'a', const AktivitaetenCompanion(art: Value('ausflug')));
      expect(await db.eigeneAktivitaetsarten(), isEmpty);
    });
  });
}
