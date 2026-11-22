import 'dart:io';

import 'package:test/test.dart';

/// Abläufe der Weboberfläche, die am Quelltext von `web/app.js` geprüft
/// werden – wie in web_test.dart: Ein Browser läuft in diesen Tests nicht.
void main() {
  late String app;
  setUpAll(() => app = File('web/app.js').readAsStringSync());

  /// Der Körper der Funktion [name] bis zur nächsten Funktion auf oberster
  /// Ebene.
  String funktion(String name) {
    final beginn = app.indexOf(RegExp('(async )?function $name\\('));
    expect(beginn, isNonNegative, reason: name);
    final ende = app.indexOf(RegExp(r'\n(async )?function '), beginn + 1);
    return app.substring(beginn, ende < 0 ? app.length : ende);
  }

  test('die Frist des Papierkorbs geht nur als 1 bis 3650 Tage hinaus', () {
    // Ein geleertes Feld „nach … Tagen“ schickte Number('') = 0, und der
    // Server leerte daraufhin den ganzen Papierkorb endgültig.
    final einstellungen = funktion('zeigeEinstellungen');
    expect(einstellungen, isNot(contains('tage: Number(tage.value)')));
    final senden = RegExp(
      r"sende\('papierkorbFristSetzen', \{[^}]*tage: (\w+)",
    ).allMatches(einstellungen).map((m) => m[1]).toSet();
    expect(senden, isNotEmpty);
    expect(senden, everyElement(isIn({'n', 'tageGesendet'})));
    expect(einstellungen, contains('n >= 1 && n <= 3650'));
  });

  test('„Papierkorb leeren“ löscht genau die gezeigten Aufnahmen', () {
    // Mit {alle: true} löschte der Server alles, was in dem Moment im
    // Papierkorb lag – auch, was ein Telefon inzwischen hineingelegt hatte
    // und was die Rückfrage nicht mitzählte.
    expect(app, isNot(contains('alle: true')));
    expect(
      funktion('endgueltigLoeschen'),
      contains('json: { ids: aufnahmen.map((a) => a.id) }'),
    );
    expect(
      funktion('zeigePapierkorb'),
      contains('endgueltigLoeschen(d.aufnahmen)'),
    );
  });

  test(
    'nach einem Fehler beim Nachladen geht es erst nach einer Pause weiter',
    () {
      // Die Fehlermeldung steht in #ende, das damit sichtbar blieb; das
      // finally rief ladeMehr sofort wieder auf – Hunderte Anfragen je
      // Sekunde, solange der Server weg war oder 503 sagte.
      final lade = funktion('ladeMehr');
      final sofort = lade.indexOf('setTimeout(ladeMehr)');
      expect(sofort, isNonNegative);
      expect(lade.substring(0, sofort), contains('if (!gescheitert)'));
      expect(lade, contains('2 ** l.fehlversuche'));
      expect(lade, contains('liste.fehlversuche = 0'));
    },
  );

  test('die Suche zählt erst nach einem gelungenen Abruf weiter', () {
    // `pos` rückte vor der Anfrage vor: Jeder Fehlschlag übersprang 300
    // Treffer, und offline lief die Liste bis zum Ende aller Kennungen.
    final abruf = app.indexOf("await api('/api/v1/aufnahmen/liste'");
    expect(abruf, isNonNegative);
    final mehr = app.lastIndexOf('const mehr = async () => {', abruf);
    final weiter = app.indexOf('pos += stueck.length', mehr);
    expect(weiter, greaterThan(abruf));
  });

  test('wer sich nach einer abgelaufenen Sitzung anmeldet, bekommt eine '
      'frische Seite', () {
    // Nach einem 401 zeigte zeigeAnmeldung das Formular, und die neue
    // Anmeldung rief nur starte() auf: Zeitleiste, Suchfilter und
    // Duplikate des vorigen Kontos blieben stehen.
    expect(funktion('starte'), contains('warAngemeldet = true;'));
    final nach = funktion('nachAnmeldung');
    final neu = nach.indexOf(
      'if (warAngemeldet) { location.reload(); return; }',
    );
    expect(neu, isNonNegative);
    expect(nach.indexOf('await starte();'), greaterThan(neu));
  });
}
