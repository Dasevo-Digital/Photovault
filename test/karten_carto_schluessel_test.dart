import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/widgets/mini_location_map.dart';

/// Die dunkle Karte und ihr CARTO-Schlüssel.
///
/// **Woher das kommt.** CARTO hat die schlüssellose Nutzung beendet und
/// schreibt seither quer über jede ausgelieferte Kachel „API KEY
/// REQUIRED". An einer Kachel Berlin-Mitte nachgesehen: auf jeder Stufe
/// von 10 bis 20, auch über den alten Fastly-Namen. Die Karte war damit
/// nicht kaputt, sondern beschriftet – ein Fehler, den kein Statuscode
/// und kein Zeitmesser meldet, weil der Server brav mit 200 antwortet.
///
/// Der Ausweg ist zweistufig, und diese Prüfung hält beide Stufen fest:
/// ohne Schlüssel invertierte OpenStreetMap-Kacheln, mit Schlüssel das
/// gewohnte Dark Matter.
void main() {
  tearDown(() => setzeCartoSchluessel(null));

  group('ohne Schlüssel', () {
    test('die dunkle Karte fragt CARTO gar nicht erst', () {
      // Der eigentliche Kern. Solange kein Schlüssel hinterlegt ist,
      // darf keine Adresse dieser App bei CARTO landen - sonst käme
      // die gestempelte Kachel zurück.
      expect(Kartenstil.dunkel.kachelUrl, isNot(contains('cartocdn')));
      expect(Kartenstil.dunkel.kachelUrl, contains('tile.openstreetmap.org'));
    });

    test('die Kacheln werden umgefärbt', () {
      // Ohne das wäre die dunkle Karte hell - dieselben OSM-Kacheln wie
      // der helle Stil, nur unter anderem Namen.
      expect(Kartenstil.dunkel.invertieren, isTrue);
      expect(Kartenstil.hell.invertieren, isFalse);
      expect(Kartenstil.topo.invertieren, isFalse);
    });

    test('die Namensnennung nennt nur, was auch geliefert wird', () {
      // Eine Lizenzauflage, die ins Leere zeigt, ist keine: CARTO steht
      // nicht im Bild, also darf es auch nicht darunterstehen.
      expect(Kartenstil.dunkel.namensnennung, isNot(contains('CARTO')));
      expect(Kartenstil.dunkel.namensnennung, contains('OpenStreetMap'));
    });

    test('keine Unterbereiche, denn OSM hat keine', () {
      // {s} steht nur in der CARTO-Adresse. Bliebe die Liste stehen,
      // setzte flutter_map einen Buchstaben in eine Adresse, die gar
      // keinen Platz dafür hat.
      expect(Kartenstil.dunkel.unterbereiche, isEmpty);
    });
  });

  group('mit Schlüssel', () {
    setUp(() => setzeCartoSchluessel('probeschluessel'));

    test('die Adresse trägt den Schlüssel', () {
      expect(Kartenstil.dunkel.kachelUrl, contains('cartocdn'));
      expect(Kartenstil.dunkel.kachelUrl, endsWith('?key=probeschluessel'));
    });

    test('nichts wird mehr umgefärbt', () {
      // Dark Matter ist bereits dunkel. Ein zweites Invertieren machte
      // es wieder hell - der Fehler, den man erst am Bildschirm sähe.
      expect(Kartenstil.dunkel.invertieren, isFalse);
    });

    test('CARTO wird genannt, wie die Lizenz es verlangt', () {
      expect(Kartenstil.dunkel.namensnennung, contains('CARTO'));
      expect(Kartenstil.dunkel.namensnennung, contains('OpenStreetMap'));
    });

    test('die Unterbereiche kommen zurück', () {
      expect(Kartenstil.dunkel.unterbereiche, ['a', 'b', 'c', 'd']);
    });

    test('die anderen beiden Stile bleiben unberührt', () {
      // Der Schlüssel gehört zu einem Stil, nicht zur App.
      expect(Kartenstil.hell.kachelUrl, contains('tile.openstreetmap.org'));
      expect(Kartenstil.topo.kachelUrl, contains('opentopomap'));
      expect(Kartenstil.hell.namensnennung, isNot(contains('CARTO')));
    });
  });

  group('was als „kein Schlüssel" gilt', () {
    // Die Falle: Eine leere Zeichenkette ergäbe die Adresse `…?key=`,
    // und darauf antwortet CARTO mit derselben gestempelten Kachel wie
    // ganz ohne Schlüssel - nur dass die App dann glaubt, alles sei gut.
    for (final eingabe in <String?>[null, '', '   ', '\t']) {
      test('${eingabe == null ? 'null' : '"$eingabe"'} zählt als keiner', () {
        setzeCartoSchluessel(eingabe);
        expect(cartoSchluessel, isNull);
        expect(Kartenstil.dunkel.kachelUrl, isNot(contains('key=')));
        expect(Kartenstil.dunkel.invertieren, isTrue);
      });
    }

    test('Leerzeichen aussen werden abgeschnitten', () {
      // Aus der Zwischenablage kommt oft ein Zeilenumbruch mit.
      setzeCartoSchluessel('  abc123\n');
      expect(cartoSchluessel, 'abc123');
      expect(Kartenstil.dunkel.kachelUrl, endsWith('?key=abc123'));
    });
  });

  group('die Verdrahtung zur Kartenschicht', () {
    Future<TileLayer> schicht(WidgetTester tester, Kartenstil stil) async {
      late TileLayer gebaut;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          gebaut = buildMapTileLayer(context, stil: stil);
          return const SizedBox.shrink();
        }),
      ));
      return gebaut;
    }

    /// Die tiefste Stufe, die tatsächlich beim Server angefragt wird.
    ///
    /// **Nicht `maxNativeZoom` allein**, und das ist seit der doppelten
    /// Auflösung der Punkt: Bei nachgebildetem Retina senkt flutter_map
    /// `maxNativeZoom` um eins und rechnet dafür einen Zoomversatz auf
    /// die Adresse. Die Zahl, auf die es ankommt – „fragen wir Kacheln
    /// an, die es gar nicht gibt?" – ist die Summe.
    int tiefsteServerstufe(TileLayer l) =>
        l.maxNativeZoom + l.zoomOffset.round();

    testWidgets('ohne Schlüssel steht ein Umfärber davor', (tester) async {
      final l = await schicht(tester, Kartenstil.dunkel);
      // Genau der Umfärber von flutter_map und kein eigener: Die
      // Farbmatrix dort invertiert und dreht den Farbton um 180 Grad
      // zurück, damit Grün grün und Wasser blau bleibt. An einer echten
      // OSM-Kachel Berlin-Mitte nachgerechnet, bevor die Wahl fiel.
      expect(l.tileBuilder, same(darkModeTileBuilder));
      expect(l.urlTemplate, isNot(contains('cartocdn')));
      // Die Anzeigegrenze muss zur Quelle passen, sonst zoomt die Karte
      // über die vorhandenen Kacheln hinaus. OpenStreetMap antwortet ab
      // Stufe 20 mit 400 – nachgemessen.
      expect(tiefsteServerstufe(l), 19);
    });

    testWidgets('mit Schlüssel nicht', (tester) async {
      setzeCartoSchluessel('probeschluessel');
      final l = await schicht(tester, Kartenstil.dunkel);
      expect(l.tileBuilder, isNull);
      expect(l.urlTemplate, contains('cartocdn'));
      expect(l.subdomains, ['a', 'b', 'c', 'd']);
      // CARTO traegt bis 20 – und weil seine Adresse `{r}` enthaelt,
      // kommt die doppelte Auflösung vom Server und kostet keine Stufe.
      expect(tiefsteServerstufe(l), 20);
    });

    testWidgets('der helle Stil bekommt nie einen Umfärber', (tester) async {
      final l = await schicht(tester, Kartenstil.hell);
      expect(l.tileBuilder, isNull);
    });
  });

  group('der Schlüssel in der Datenbank', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('frisch ist keiner hinterlegt', () async {
      expect(await db.cartoSchluesselWert(), isNull);
    });

    test('speichern und wieder lesen', () async {
      await db.setzeCartoSchluesselWert('abc123');
      expect(await db.cartoSchluesselWert(), 'abc123');
    });

    test('leeren löscht ihn wirklich', () async {
      // Nicht als leere Zeichenkette liegen lassen: Die ergäbe beim
      // nächsten Start die Adresse `…?key=`.
      await db.setzeCartoSchluesselWert('abc123');
      await db.setzeCartoSchluesselWert('  ');
      expect(await db.cartoSchluesselWert(), isNull);
      final zeile = await db.customSelect(
              'SELECT carto_schluessel AS s FROM app_settings WHERE id = 0')
          .getSingle();
      expect(zeile.data['s'], isNull,
          reason: 'in der Spalte muss NULL stehen, nicht ""');
    });

    test('die anderen Einstellungen bleiben stehen', () async {
      // Eine Zeile, viele Spalten: `insertOnConflictUpdate` mit nur
      // einem Feld darf die Nachbarn nicht auf ihre Vorgabe zurücksetzen.
      await db.setzeKartenansicht('topo');
      await db.setzeCartoSchluesselWert('abc123');
      expect(await db.kartenansicht(), 'topo');
    });
  });

  test('im Quelltext steht kein Schlüssel', () {
    // Der Grund, warum der Schlüssel überhaupt in der Datenbank liegt:
    // Ein mitgelieferter wäre über den öffentlichen Spiegel für jeden
    // lesbar. Diese Prüfung fängt den bequemen Weg ab, ihn "nur zum
    // Ausprobieren" doch in den Quelltext zu schreiben.
    final verdacht = RegExp(r'key=[A-Za-z0-9_\-]{8,}');
    final treffer = <String>[];
    for (final datei in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      for (final zeile in datei.readAsLinesSync()) {
        if (verdacht.hasMatch(zeile)) treffer.add('${datei.path}: $zeile');
      }
    }
    expect(treffer, isEmpty);
  });
}
