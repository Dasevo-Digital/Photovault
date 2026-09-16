import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/screens/map_screen.dart';
import 'package:photo_vault/services/eigenkarte.dart';
import 'package:photo_vault/widgets/mini_location_map.dart';

void main() {
  group('die Adressvorlage', () {
    test('eine gewoehnliche Adresse geht durch', () {
      expect(
          Eigenkarte.adressfehler(
              'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
          isNull);
    });

    test('leer, ohne Schema, ohne Platzhalter', () {
      expect(Eigenkarte.adressfehler('   '), Adressfehler.leer);
      expect(Eigenkarte.adressfehler('tile.example.org/{z}/{x}/{y}.png'),
          Adressfehler.keinHttp);
      expect(Eigenkarte.adressfehler('https://example.org/{z}/{x}.png'),
          Adressfehler.platzhalterFehlt);
    });

    test('ein Platzhalter, den die Karte nicht kennt', () {
      // Der wichtigste Fall: flutter_map WIRFT bei einem unbekannten
      // Platzhalter, statt ihn stehen zu lassen – und zwar bei jeder
      // einzelnen Kachel.
      expect(
          Eigenkarte.adressfehler(
              'https://example.org/{z}/{x}/{y}.png?a={apikey}'),
          Adressfehler.platzhalterUnbekannt);
      // Die, die sie kennt, gehen durch.
      expect(
          Eigenkarte.adressfehler(
              'https://{s}.example.org/{z}/{x}/{y}{r}.png'),
          isNull);
    });

    test('die stehengebliebene Marke aus einer Vorlage', () {
      expect(
          Eigenkarte.adressfehler(
              'https://example.org/{z}/{x}/{y}.png?key=$schluesselMarke'),
          Adressfehler.schluesselFehlt);
      expect(
          Eigenkarte.adressfehler(
              'https://example.org/{z}/{x}/{y}.png?key=abc123'),
          isNull);
    });
  });

  group('die eigene Quelle entsteht nur vollstaendig', () {
    const gut = 'https://example.org/{z}/{x}/{y}.png';

    test('ohne Zustimmung gibt es keine', () {
      expect(Eigenkarte.aus(url: gut, nennung: '© X', zugestimmt: false), isNull);
    });

    test('ohne Namensnennung gibt es keine', () {
      // Sie ist eine Lizenzauflage, kein Schmuck.
      expect(Eigenkarte.aus(url: gut, nennung: '  ', zugestimmt: true), isNull);
    });

    test('mit fehlerhafter Adresse gibt es keine', () {
      expect(
          Eigenkarte.aus(
              url: 'https://example.org/{z}/{x}.png',
              nennung: '© X',
              zugestimmt: true),
          isNull);
    });

    test('vollstaendig ergibt eine', () {
      final k = Eigenkarte.aus(
          name: ' Meine ', url: gut, nennung: ' © X ', stufe: 20, zugestimmt: true);
      expect(k, isNotNull);
      expect(k!.name, 'Meine');
      expect(k.nennung, '© X');
      expect(k.hoechsteEchteStufe, 20);
    });

    test('ohne Stufenangabe gilt 19', () {
      expect(
          Eigenkarte.aus(url: gut, nennung: '© X', zugestimmt: true)!
              .hoechsteEchteStufe,
          19);
    });
  });

  group('die Vorlagen', () {
    test('jede ergibt nach dem Einsetzen eine brauchbare Adresse', () {
      for (final v in kartenvorlagen) {
        final fertig = vorlageMitSchluessel(v, 'abc123');
        expect(Eigenkarte.adressfehler(fertig), isNull,
            reason: '${v.name}: $fertig');
      }
    });

    test('die mit Schluessel tragen die Marke, die anderen nicht', () {
      for (final v in kartenvorlagen) {
        expect(v.url.contains(schluesselMarke), v.brauchtSchluessel,
            reason: v.name);
      }
    });

    test('unveraendert uebernommen faellt die Marke auf', () {
      for (final v in kartenvorlagen.where((v) => v.brauchtSchluessel)) {
        expect(Eigenkarte.adressfehler(v.url), Adressfehler.schluesselFehlt,
            reason: v.name);
      }
    });

    test('jede Namensnennung ist gefuellt', () {
      for (final v in kartenvorlagen) {
        expect(v.nennung.trim(), isNotEmpty, reason: v.name);
      }
    });

    test('nur Google braucht eine Sitzung, und seine Adresse zeigt das', () {
      final mitSitzung = kartenvorlagen.where((v) => v.sitzungNoetig).toList();
      expect(mitSitzung, hasLength(1));
      expect(mitSitzung.single.url, contains('session='));
    });
  });

  group('der Kartenstil der eigenen Quelle', () {
    tearDown(() => setzeEigeneKarte(null));

    test('ohne eingerichtete Quelle faellt er auf OpenStreetMap zurueck', () {
      setzeEigeneKarte(null);
      expect(Kartenstil.eigene.kachelUrl, contains('openstreetmap.org'));
      expect(Kartenstil.eigene.hoechsteEchteStufe, 19);
    });

    test('mit Quelle liefert er deren Angaben', () {
      setzeEigeneKarte(const Eigenkarte(
        name: 'Meine',
        url: 'https://beispiel.de/{z}/{x}/{y}.png',
        nennung: '© Beispiel',
        stufe: 21,
        zugestimmt: true,
      ));
      expect(Kartenstil.eigene.kachelUrl, 'https://beispiel.de/{z}/{x}/{y}.png');
      expect(Kartenstil.eigene.namensnennung, '© Beispiel');
      expect(Kartenstil.eigene.hoechsteEchteStufe, 21);
      // Zwei Stufen Vergroesserung obendrauf, wie bei allen Stilen.
      expect(Kartenstil.eigene.hoechsteAnzeigeStufe, 23);
    });

    test('die uebrigen Stile bleiben unberuehrt', () {
      setzeEigeneKarte(const Eigenkarte(
          name: 'Meine',
          url: 'https://beispiel.de/{z}/{x}/{y}.png',
          nennung: '© Beispiel',
          zugestimmt: true));
      expect(Kartenstil.hell.kachelUrl, contains('openstreetmap.org'));
      expect(Kartenstil.topo.hoechsteEchteStufe, 17);
      expect(Kartenstil.eigene.invertieren, isFalse);
    });
  });

  group('die Ansicht im Kartenmenue', () {
    test('ohne Quelle steht sie nicht zur Wahl', () {
      final da = Kartenansicht.verfuegbar(mitEigener: false);
      expect(da, isNot(contains(Kartenansicht.eigene)));
      expect(da, contains(Kartenansicht.topo));
    });

    test('mit Quelle schon', () {
      expect(Kartenansicht.verfuegbar(mitEigener: true),
          contains(Kartenansicht.eigene));
    });

    test('die gemerkte Wahl bleibt lesbar', () {
      expect(Kartenansicht.ausText('eigene'), Kartenansicht.eigene);
      expect(Kartenansicht.ausText('unbekannt'), Kartenansicht.dunkel);
    });
  });

  group('in der Datenbank', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('frisch ist keine eingerichtet', () async {
      expect(await db.eigeneKarteWert(), isNull);
    });

    test('speichern und wieder lesen', () async {
      await db.setzeEigeneKarteWert(const Eigenkarte(
        name: 'Meine',
        url: 'https://beispiel.de/{z}/{x}/{y}.png',
        nennung: '© Beispiel',
        stufe: 20,
        zugestimmt: true,
      ));
      final k = await db.eigeneKarteWert();
      expect(k, isNotNull);
      expect(k!.name, 'Meine');
      expect(k.stufe, 20);
      expect(k.zugestimmt, isTrue);
    });

    test('ohne Zustimmung kommt nichts zurueck', () async {
      // Die Spalten sind gefuellt, die Zustimmung fehlt – die Quelle gilt
      // damit als nicht eingerichtet.
      await db.setzeEigeneKarteWert(const Eigenkarte(
        name: 'Meine',
        url: 'https://beispiel.de/{z}/{x}/{y}.png',
        nennung: '© Beispiel',
        zugestimmt: false,
      ));
      expect(await db.eigeneKarteWert(), isNull);
    });

    test('entfernen loescht sie wirklich', () async {
      await db.setzeEigeneKarteWert(const Eigenkarte(
          name: 'Meine',
          url: 'https://beispiel.de/{z}/{x}/{y}.png',
          nennung: '© Beispiel',
          zugestimmt: true));
      await db.setzeEigeneKarteWert(null);
      expect(await db.eigeneKarteWert(), isNull);
      final zeile = await (db.select(db.appSettings)
            ..where((t) => t.id.equals(0)))
          .getSingle();
      expect(zeile.eigeneKarteUrl, isNull);
      expect(zeile.eigeneKarteZugestimmt, isFalse);
    });

    test('die uebrigen Einstellungen bleiben stehen', () async {
      await db.setzeCartoSchluesselWert('abc');
      await db.setzeEigeneKarteWert(const Eigenkarte(
          name: 'Meine',
          url: 'https://beispiel.de/{z}/{x}/{y}.png',
          nennung: '© Beispiel',
          zugestimmt: true));
      expect(await db.cartoSchluesselWert(), 'abc');
    });
  });

  group('die Google-Sitzung', () {
    final vorlage =
        kartenvorlagen.firstWhere((v) => v.sitzungNoetig).url;

    test('unveraendert steht dort noch die Marke, also kein Schluessel', () {
      expect(brauchtSitzung(vorlage), isTrue);
      expect(schluesselAusAdresse(vorlage), isNull);
    });

    test('mit eingesetztem Schluessel wird er gefunden', () {
      final fertig = vorlageMitSchluessel(
          kartenvorlagen.firstWhere((v) => v.sitzungNoetig), 'AIza-Beispiel');
      expect(schluesselAusAdresse(fertig), 'AIza-Beispiel');
    });

    test('die Sitzung wird eingesetzt, ohne den Rest anzuruehren', () {
      final fertig = sitzungEinsetzen(
          vorlageMitSchluessel(
              kartenvorlagen.firstWhere((v) => v.sitzungNoetig), 'k1'),
          'sitz-42');
      expect(fertig, contains('session=sitz-42'));
      expect(fertig, contains('key=k1'));
      // Und die Platzhalter der Karte bleiben stehen.
      expect(Eigenkarte.adressfehler(fertig), isNull);
    });

    test('ein zweites Holen ersetzt die alte Sitzung, statt anzuhaengen', () {
      var adresse = sitzungEinsetzen(
          vorlageMitSchluessel(
              kartenvorlagen.firstWhere((v) => v.sitzungNoetig), 'k1'),
          'alt');
      adresse = sitzungEinsetzen(adresse, 'neu');
      expect(adresse, contains('session=neu'));
      expect(adresse, isNot(contains('alt')));
      expect('session='.allMatches(adresse), hasLength(1));
    });

    test('die uebrigen Vorlagen brauchen keine', () {
      for (final v in kartenvorlagen.where((v) => !v.sitzungNoetig)) {
        expect(brauchtSitzung(v.url), isFalse, reason: v.name);
      }
    });
  });
}
