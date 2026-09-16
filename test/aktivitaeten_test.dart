import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/aktivitaeten.dart';

/// Die Rechnung hinter den Aktivitäten.
///
/// Geprüft wird an nachgestellten Tagen, wie sie in einer echten
/// Bibliothek vorkommen: eine Wanderung im Harz, ein Nachmittag im
/// eigenen Garten, ein Museumsbesuch in einer fremden Stadt.
///
/// Der Bezugspunkt für alle Entfernungen: Hannover, 52.37 / 9.73.
const zuhause = (breite: 52.37, laenge: 9.73);

/// Eine Aufnahme, [minuten] nach [start], [kmOst] östlich von Hannover.
///
/// Ein Grad Länge sind auf dieser Breite rund 68 km – ein Kilometer also
/// rund 0,0147 Grad. Das reicht: Geprüft werden Grössenordnungen, nicht
/// Vermessungsgenauigkeit.
Aktivitaetsaufnahme auf(String id, DateTime start, int minuten, double kmOst,
        {String? stadt, double kmNord = 0}) =>
    (
      id: id,
      zeit: start.add(Duration(minutes: minuten)),
      breite: 52.37 + kmNord / 111.0,
      laenge: 9.73 + kmOst / 68.0,
      stadt: stadt,
    );

void main() {
  final tag = DateTime(2026, 6, 14, 9);

  group('die zurückgelegte Strecke', () {
    test('ein einzelner Punkt ist kein Weg', () {
      expect(strecke([(breite: 52.0, laenge: 9.0, zeit: tag)]), 0);
      expect(strecke(const []), 0);
    });

    test('drei Kilometer geradeaus sind drei Kilometer', () {
      final weg = strecke([
        for (var i = 0; i < 4; i++)
          (
            breite: 52.37,
            laenge: 9.73 + i / 68.0,
            zeit: tag.add(Duration(minutes: i * 10))
          ),
      ]);
      expect(weg, closeTo(3.0, 0.1));
    });

    test('dreissig Bilder von derselben Bank ergeben keinen Weg', () {
      // Ohne Glättung summierte sich hier die Streuung des GPS-Empfängers
      // zu einigen hundert Metern, ohne dass jemand aufgestanden wäre.
      final weg = strecke([
        for (var i = 0; i < 30; i++)
          (
            breite: 52.37 + (i.isEven ? 0.0001 : -0.0001),
            laenge: 9.73 + (i % 3) * 0.0001,
            zeit: tag.add(Duration(minutes: i)),
          ),
      ]);
      expect(weg, 0);
    });

    test('die Reihenfolge macht den Weg nicht länger', () {
      // Rückwärts hereingegeben muss dieselbe Zahl herauskommen: sortiert
      // wird nach Zeit, nicht nach Eingabe.
      final punkte = [
        for (var i = 0; i < 5; i++)
          (
            breite: 52.37,
            laenge: 9.73 + i / 68.0,
            zeit: tag.add(Duration(minutes: i * 10))
          ),
      ];
      expect(strecke(punkte.reversed), closeTo(strecke(punkte), 0.001));
    });
  });

  group('die vermutete Art', () {
    test('ohne Weg, aber mit Zeit ist es eine Besichtigung', () {
      expect(vermuteArt(0.3, const Duration(hours: 2)),
          Aktivitaetsart.besichtigung);
    });

    test('acht Kilometer in drei Stunden sind eine Wanderung', () {
      expect(vermuteArt(8, const Duration(hours: 3)), Aktivitaetsart.wanderung);
    });

    test('vierzig Kilometer in drei Stunden sind eine Radtour', () {
      expect(vermuteArt(40, const Duration(hours: 3)), Aktivitaetsart.radtour);
    });

    test('hundertzwanzig Kilometer in zwei Stunden waren ein Fahrzeug', () {
      // **Das ist die einzige Richtung, die belegt ist.** Zwischen zwei
      // Aufnahmen liegt immer mehr Weg als die Luftlinie und meist eine
      // Pause – die gerechnete Geschwindigkeit ist eine Untergrenze. Wer
      // 60 km/h Untergrenze hat, ist nicht gelaufen.
      expect(vermuteArt(120, const Duration(hours: 2)), Aktivitaetsart.ausflug);
    });

    test('ohne Dauer wird nichts behauptet', () {
      expect(vermuteArt(5, Duration.zero), Aktivitaetsart.sonstiges);
    });
  });

  group('das Erkennen', () {
    List<Aktivitaetsvorschlag> erkenne(List<Aktivitaetsaufnahme> a,
            {Set<String> bekannt = const {},
            Set<String> verworfen = const {},
            bool mitWohnort = true}) =>
        erkenneAktivitaeten(a,
            ohneOrt: 'Unbekannt',
            wohnort: mitWohnort ? zuhause : null,
            bekannteIds: bekannt,
            verworfen: verworfen);

    /// Eine Wanderung: acht Bilder über vier Stunden, zwölf Kilometer.
    List<Aktivitaetsaufnahme> wanderung([DateTime? start]) => [
          for (var i = 0; i < 8; i++)
            auf('w$i', start ?? tag, i * 30, i * 1.5, stadt: 'Goslar'),
        ];

    test('eine Wanderung wird erkannt und benannt', () {
      final v = erkenne(wanderung()).single;
      expect(v.anzahl, 8);
      expect(v.name, 'Goslar');
      expect(v.art, Aktivitaetsart.wanderung);
      expect(v.streckeKm, closeTo(10.5, 0.5));
      expect(v.dauer, const Duration(hours: 3, minutes: 30));
    });

    test('zu wenige Bilder sind keine Aktivität', () {
      expect(erkenne(wanderung().take(3).toList()), isEmpty);
    });

    test('eine halbe Stunde ist keine Aktivität', () {
      final kurz = [
        for (var i = 0; i < 6; i++) auf('k$i', tag, i * 5, i * 1.0),
      ];
      expect(kurz.last.zeit.difference(kurz.first.zeit),
          lessThan(aktivitaetMindestdauer));
      expect(erkenne(kurz), isEmpty);
    });

    test('ein Nachmittag im eigenen Garten ist keine Aktivität', () {
      // Genug Bilder, genug Zeit – aber niemand ist losgegangen. Ohne
      // diese Regel wäre jeder Sonntag zu Hause eine Unternehmung.
      final garten = [
        for (var i = 0; i < 12; i++) auf('g$i', tag, i * 20, 0.02),
      ];
      expect(erkenne(garten), isEmpty);
    });

    test('aber derselbe Nachmittag hundert Kilometer weiter schon', () {
      // Kurzer Weg vor Ort, aber weit von zu Hause: die Fahrt zum
      // Wildpark. Ohne die zweite Bedingung fiele sie durch.
      final wildpark = [
        for (var i = 0; i < 12; i++) auf('p$i', tag, i * 20, 100 + i * 0.02),
      ];
      final v = erkenne(wildpark).single;
      expect(v.art, Aktivitaetsart.besichtigung);
    });

    test('ohne Wohnort entscheidet allein die Strecke', () {
      // „Weit weg" ist ohne Wohnort keine beantwortbare Frage – und eine
      // erfundene Antwort wäre schlechter als keine.
      final wildpark = [
        for (var i = 0; i < 12; i++) auf('p$i', tag, i * 20, 100 + i * 0.02),
      ];
      expect(erkenne(wildpark, mitWohnort: false), isEmpty);
      expect(erkenne(wanderung(), mitWohnort: false), hasLength(1));
    });

    test('eine Lücke von zwei Stunden trennt zwei Unternehmungen', () {
      // Vormittags gewandert, mittags eingekehrt, nachmittags ein
      // Museum: zwei Unternehmungen und nicht eine lange.
      final zwei = [
        ...wanderung(),
        for (var i = 0; i < 8; i++)
          auf('m$i', tag, 8 * 30 + 120 + i * 20, 12 + i * 1.5, stadt: 'Goslar'),
      ];
      expect(erkenne(zwei), hasLength(2));
    });

    test('eine Rast von einer Stunde trennt sie nicht', () {
      final mitRast = [
        for (var i = 0; i < 4; i++)
          auf('a$i', tag, i * 20, i * 1.5, stadt: 'Goslar'),
        for (var i = 0; i < 4; i++)
          auf('b$i', tag, 60 + 60 + i * 20, 6 + i * 1.5, stadt: 'Goslar'),
      ];
      expect(erkenne(mitRast), hasLength(1));
    });

    test('über Mitternacht wird getrennt', () {
      // „Am 14. Juni" ist die Überschrift, unter der man eine
      // Unternehmung sucht; eine, die über Mitternacht läuft, stünde
      // unter keiner. Zehn Bilder im Halbstundentakt ab 21 Uhr: sechs
      // vor Mitternacht, vier danach.
      final nacht = DateTime(2026, 6, 14, 21);
      final ueber = [
        for (var i = 0; i < 10; i++) auf('n\$i', nacht, i * 30, i * 2.0),
      ];
      expect(ueber.last.zeit.day, 15);

      final v = erkenne(ueber);
      expect(v, hasLength(2));
      // Und keine der beiden läuft über den Tageswechsel.
      for (final a in v) {
        expect(a.von.day, a.bis.day);
      }
      expect(v.first.anzahl, 4); // die jüngste zuerst: der 15.
      expect(v.last.anzahl, 6);
    });

    test('schon zugeordnete Aufnahmen kommen nicht noch einmal', () {
      expect(erkenne(wanderung(), bekannt: {'w0', 'w1', 'w2', 'w3', 'w4'}),
          isEmpty);
    });

    test('ein abgelehnter Vorschlag bleibt abgelehnt', () {
      // Der Schlüssel ist die erste Aufnahme, nicht der Zeitraum:
      // Kommen später Bilder aus einer zweiten Kamera dazu, verschiebt
      // sich das Ende – der Vorschlag ist derselbe.
      expect(erkenne(wanderung(), verworfen: {'w0'}), isEmpty);
    });

    test('ohne Ortsnamen steht der übergebene Ersatz da', () {
      final ohne = [
        for (var i = 0; i < 8; i++) auf('o$i', tag, i * 30, i * 1.5),
      ];
      expect(erkenne(ohne).single.name, 'Unbekannt');
    });

    test('die jüngste steht zuerst', () {
      final frueher = DateTime(2026, 5, 3, 9);
      final beide = [...wanderung(), ...wanderung(frueher)];
      final v = erkenne(beide);
      expect(v, hasLength(2));
      expect(v.first.von.isAfter(v.last.von), isTrue);
    });
  });

  group('zu welcher Reise sie gehört', () {
    test('ohne Reise und ohne Zeitraum: keine', () {
      expect(
          reiseFuerAktivitaet(
            aufnahmeIds: const ['a', 'b'],
            von: DateTime(2026, 6, 14),
            reiseJeAufnahme: const {},
          ),
          isNull);
    });

    test('die Fotos entscheiden', () {
      expect(
          reiseFuerAktivitaet(
            aufnahmeIds: const ['a', 'b', 'c'],
            von: DateTime(2026, 6, 14),
            reiseJeAufnahme: const {'a': 'italien', 'b': 'italien'},
          ),
          'italien');
    });

    test('bei zwei Reisen gewinnt die mit den meisten Bildern', () {
      expect(
          reiseFuerAktivitaet(
            aufnahmeIds: const ['a', 'b', 'c'],
            von: DateTime(2026, 6, 14),
            reiseJeAufnahme: const {
              'a': 'italien',
              'b': 'schweiz',
              'c': 'schweiz'
            },
          ),
          'schweiz');
    });

    test('ein Zeitraum, der über die Reise hinausragt, ändert nichts', () {
      // Der Zeitraum einer Reise ist selbst nur aus ihren Aufnahmen
      // abgeleitet. Die Zuordnung der Bilder ist die stärkere Auskunft.
      expect(
          reiseFuerAktivitaet(
            aufnahmeIds: const ['a', 'b'],
            von: DateTime(2026, 7, 20),
            reiseJeAufnahme: const {'a': 'italien', 'b': 'italien'},
            reisen: [
              (
                id: 'italien',
                von: DateTime(2026, 6, 1),
                bis: DateTime(2026, 6, 10)
              ),
            ],
          ),
          'italien');
    });

    test('ohne zugeordnete Bilder entscheidet die Zeit', () {
      expect(
          reiseFuerAktivitaet(
            aufnahmeIds: const ['a'],
            von: DateTime(2026, 6, 5),
            reiseJeAufnahme: const {},
            reisen: [
              (
                id: 'italien',
                von: DateTime(2026, 6, 1),
                bis: DateTime(2026, 6, 10)
              ),
            ],
          ),
          'italien');
    });

    test('und ausserhalb jeder Reise bleibt sie für sich', () {
      // Die Sonntagswanderung vor der Haustür braucht keine Reise.
      expect(
          reiseFuerAktivitaet(
            aufnahmeIds: const ['a'],
            von: DateTime(2026, 9, 5),
            reiseJeAufnahme: const {},
            reisen: [
              (
                id: 'italien',
                von: DateTime(2026, 6, 1),
                bis: DateTime(2026, 6, 10)
              ),
            ],
          ),
          isNull);
    });
  });
}
