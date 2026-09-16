import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/reisefortschritt.dart';

/// Der Länder- und Ortszähler.
///
/// Am fertigen Balken sieht man nicht, ob „Bayern" einmal oder zweimal
/// gezählt wurde – deshalb steht die Rechnung hier.
void main() {
  Besuchsangabe a(String? land, String? region, String? ort, int anzahl) =>
      (land: land, region: region, ort: ort, anzahl: anzahl);

  test('zaehlt Laender, Regionen und Orte', () {
    final f = reisefortschritt([
      a('Deutschland', 'Bayern', 'München', 30),
      a('Deutschland', 'Bayern', 'Nürnberg', 5),
      a('Italien', 'Lazio', 'Roma', 20),
    ], laenderGesamt: 252);
    expect(f.laenderBesucht, 2);
    expect(f.regionen, 2);
    expect(f.orte, 3);
    expect(f.aufnahmen, 55);
  });

  test('gleiche Ortsnamen in verschiedenen Laendern zaehlen doppelt', () {
    // Der eigentliche Grund fuer den Laenderschluessel: „Springfield"
    // gibt es in den USA ueber zwanzigmal, und ohne das Land davor waere
    // der Zaehler die Zahl der verschiedenen Ortsnamen statt der Zahl
    // der besuchten Orte. Das ist nicht dasselbe und immer zu klein.
    final f = reisefortschritt([
      a('Vereinigte Staaten', 'Illinois', 'Springfield', 3),
      a('Vereinigte Staaten', 'Missouri', 'Springfield', 4),
    ], laenderGesamt: 252);
    expect(f.orte, 2);
    expect(f.regionen, 2);
    expect(f.laenderBesucht, 1);
  });

  test('das haeufigste Land steht oben', () {
    final f = reisefortschritt([
      a('Italien', 'Lazio', 'Roma', 20),
      a('Deutschland', 'Bayern', 'München', 30),
    ], laenderGesamt: 252);
    expect(f.laender.first.name, 'Deutschland');
    expect(f.laender.first.aufnahmen, 30);
  });

  test('bei Gleichstand entscheidet der Name', () {
    // Ohne feste zweite Ordnung sprangen die Zeilen bei jedem Aufbau.
    final f = reisefortschritt([
      a('Zypern', null, null, 5),
      a('Andorra', null, null, 5),
    ], laenderGesamt: 252);
    expect(f.laender.map((l) => l.name), ['Andorra', 'Zypern']);
  });

  test('Aufnahmen ohne Land zaehlen bei den Aufnahmen, nicht bei den Laendern',
      () {
    // Eine Aufnahme mitten auf dem Meer hat eine Koordinate, aber kein
    // Land. Sie zu verschweigen waere falsch, sie als Land zu zaehlen
    // auch.
    final f = reisefortschritt([
      a('Deutschland', 'Bayern', 'München', 30),
      a(null, null, null, 7),
    ], laenderGesamt: 252);
    expect(f.laenderBesucht, 1);
    expect(f.aufnahmen, 37);
  });

  test('eine fehlende Region macht den Ort nicht zunichte', () {
    final f = reisefortschritt([
      a('Monaco', null, 'Monte-Carlo', 4),
    ], laenderGesamt: 252);
    expect(f.orte, 1);
    expect(f.regionen, 0);
  });

  test('der Anteil bezieht sich auf den Datensatz', () {
    // 252 und nicht 195: countryInfo.txt fuehrt neben den souveraenen
    // Staaten auch Gebiete. Eine gepflegte Liste der 195 waere eine
    // zweite Wahrheit neben der, nach der die Fotos eingeordnet werden.
    final f = reisefortschritt([
      for (var i = 0; i < 63; i++) a('Land$i', null, null, 1),
    ], laenderGesamt: 252);
    expect(f.anteil, closeTo(0.25, 0.001));
  });

  test('ohne Aufnahmen ist der Fortschritt leer', () {
    final f = reisefortschritt(const [], laenderGesamt: 252);
    expect(f.istLeer, isTrue);
    expect(f.anteil, 0);
  });

  test('ohne Datensatz gibt es keinen Anteil statt einer Division durch null',
      () {
    final f = reisefortschritt([a('Italien', null, null, 1)],
        laenderGesamt: 0);
    expect(f.anteil, 0);
    expect(f.laenderBesucht, 1);
  });
}
