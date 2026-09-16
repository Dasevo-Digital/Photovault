import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/lebenslauf.dart';

/// Die Reihenfolge des Lebenslaufs.
///
/// Zwei Quellen laufen hier zusammen: Geburt und Tod stehen an der Person,
/// alles andere in einer eigenen Tabelle. Was leicht falsch wird: Einträge
/// ohne Datum vor die Geburt zu sortieren.
void main() {
  EreignisEingabe e(String id, Ereignisart art, DateTime? datum) =>
      (id: id, art: art, datum: datum, ort: null, notiz: null);

  test('sortiert nach Datum, das Frühere zuerst', () {
    final zeilen = lebenslauf(
      geburt: DateTime(1931, 4, 2),
      tod: DateTime(2004, 11, 9),
      ereignisse: [
        e('a', Ereignisart.umzug, DateTime(1975)),
        e('b', Ereignisart.hochzeit, DateTime(1958)),
      ],
    );
    expect(zeilen.map((z) => z.datum!.year), [1931, 1958, 1975, 2004]);
    expect(zeilen.first.istGeburt, isTrue);
    expect(zeilen.last.istTod, isTrue);
  });

  test('Einträge ohne Datum stehen am Ende, nicht am Anfang', () {
    // Ein Ereignis, von dem man nur weiß, dass es war, gehört nicht vor
    // die Geburt.
    final zeilen = lebenslauf(
      geburt: DateTime(1931),
      tod: null,
      ereignisse: [e('a', Ereignisart.beruf, null)],
    );
    expect(zeilen.first.istGeburt, isTrue);
    expect(zeilen.last.art, Ereignisart.beruf);
  });

  test('Geburt und Tod stehen an ihrer chronologischen Stelle', () {
    // Wer eine Umbettung nach dem Tod einträgt, soll das auch so sehen.
    final zeilen = lebenslauf(
      geburt: DateTime(1900),
      tod: DateTime(1970),
      ereignisse: [e('a', Ereignisart.umzug, DateTime(1980))],
    );
    expect(zeilen[1].istTod, isTrue);
    expect(zeilen[2].art, Ereignisart.umzug);
  });

  test('ohne alles bleibt die Liste leer', () {
    expect(lebenslauf(geburt: null, tod: null, ereignisse: []), isEmpty);
  });

  test('Geburt und Tod tragen keine Ereigniskennung', () {
    // Nur daran erkennt die Anzeige, dass sie sich hier nicht löschen
    // lassen – sie stehen an der Person.
    final zeilen = lebenslauf(
        geburt: DateTime(1931), tod: DateTime(2004), ereignisse: []);
    expect(zeilen.every((z) => z.ereignisId == null), isTrue);
  });

  group('Ereignisart', () {
    test('wandelt hin und zurück', () {
      for (final a in Ereignisart.values) {
        expect(ereignisartAusText(ereignisartZuText(a)), a);
      }
    });

    test('ein unbekannter Wert wird zu „Sonstiges“, nicht zum Absturz', () {
      // Etwa ein Eintrag aus einer neueren Fassung – der Eintrag bleibt
      // lesbar, statt die ganze Liste unbenutzbar zu machen.
      expect(ereignisartAusText('taufe'), Ereignisart.sonstiges);
    });
  });
}
