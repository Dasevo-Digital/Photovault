// Was auf der Landschaft liegt – Grund, Ebenen, Namensnennung.
//
// Zwei Dinge lassen sich hier ohne Netz prüfen und sind beide keine
// Formsache: dass jede Adresse die drei Platzhalter trägt (eine
// Kacheladresse ohne `{z}` holt für immer dieselbe Kachel), und dass die
// Namensnennung genau die Quellen nennt, die tatsächlich im Bild stehen.
// Das zweite ist eine Lizenzauflage.
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/gelaendeebenen.dart';
import 'package:photo_vault/services/gelaendetextur.dart';

void main() {
  test('jede Ebene traegt die drei Platzhalter', () {
    for (final grund in Gelaendegrund.values) {
      for (final e in Gelaendekarte(
        grund: grund,
        wege: true,
        beschriftung: true,
      ).ebenen) {
        for (final platz in ['{z}', '{x}', '{y}']) {
          expect(e.urlVorlage, contains(platz),
              reason: '${e.name} kennt $platz nicht');
        }
      }
      // Und keine unaufgelösten Reste - ein `{s}` in der Adresse ergibt
      // eine Anfrage an einen Rechner, den es nicht gibt.
      expect(grund.ebene.urlVorlage, isNot(contains('{s}')));
      expect(grund.ebene.urlVorlage, isNot(contains('{r}')));
    }
  });

  test('keine Ebene wird feiner geladen, als ein Block gross werden darf', () {
    // Eine Ebene, die feiner liefert als [texturHoechsteStufe], wuerde nie
    // so weit abgefragt - die Angabe waere dann eine Behauptung ohne
    // Wirkung. Umgekehrt darf keine hoeher stehen als das, was der
    // Anbieter vertraegt.
    for (final e in [
      luftbildEbene,
      wanderwegeEbene,
      strassenEbene,
      orteEbene
    ]) {
      expect(e.hoechsteStufe, lessThanOrEqualTo(texturHoechsteStufe),
          reason: e.name);
      expect(e.hoechsteStufe, greaterThanOrEqualTo(texturGrundstufe),
          reason: '${e.name} bliebe unter der Blockgroesse');
    }
  });

  test('Waymarked Trails wird zurueckhaltender abgefragt als Esri', () {
    // Ein ehrenamtlicher Dienst gegen ein Auslieferungsnetz: Bei Stufe
    // 18 beruehrte ein Ueberflug sechzehnmal so viele Kacheln wie bei
    // 16. Eine Linienzeichnung vertraegt das Hochskalieren, ein Luftbild
    // nicht.
    expect(wanderwegeEbene.hoechsteStufe,
        lessThan(luftbildEbene.hoechsteStufe));
  });

  test('OpenTopoMap bekommt weniger zugemutet als Esri', () {
    // Gemessen: OpenTopoMap rendert bei Bedarf, ein Ueberflug wollte 88
    // Bloecke auf Stufe 17 und bekam in zwei Minuten 31 davon.
    expect(Gelaendegrund.wanderkarte.hoechsteStufe,
        lessThan(Gelaendegrund.luftbild.hoechsteStufe));
  });

  group('Die Namensnennung', () {
    test('nennt jede beteiligte Quelle genau einmal', () {
      const karte = Gelaendekarte(
          grund: Gelaendegrund.luftbild, wege: true, beschriftung: true);
      final n = karte.nennung;
      expect(n, contains('Esri'));
      expect(n, contains('waymarkedtrails'));
      // Esri steht in drei Ebenen; die Nennung darf nicht dreimal
      // dasselbe wiederholen.
      final teile = n.split(' · ');
      expect(teile.toSet().length, teile.length);
    });

    test('nennt nichts, was nicht im Bild steht', () {
      const nurLuft = Gelaendekarte(grund: Gelaendegrund.luftbild);
      expect(nurLuft.nennung, isNot(contains('waymarkedtrails')));
      const mitWegen =
          Gelaendekarte(grund: Gelaendegrund.luftbild, wege: true);
      expect(mitWegen.nennung, contains('waymarkedtrails'));
    });

    test('wechselt mit dem Grund', () {
      const topo = Gelaendekarte(grund: Gelaendegrund.wanderkarte);
      expect(topo.nennung, contains('opentopomap'));
      expect(topo.nennung, isNot(contains('Esri')));
    });
  });

  test('eine Nummer ausserhalb der Reihe faellt auf die Wanderkarte zurueck',
      () {
    // Der Grund, warum in der Datenbank eine Zahl steht und kein Name:
    // Ein Name aus einer aelteren Fassung koennte einer sein, den es
    // nicht mehr gibt.
    expect(gelaendegrundAus(-1), Gelaendegrund.wanderkarte);
    expect(gelaendegrundAus(99), Gelaendegrund.wanderkarte);
    for (var i = 0; i < Gelaendegrund.values.length; i++) {
      expect(gelaendegrundAus(i), Gelaendegrund.values[i]);
    }
  });
}
