import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/ortsuebersicht.dart';
import 'package:photo_vault/services/reisefortschritt.dart';

/// Die Rechnung hinter der Ortsansicht.
///
/// Sie beantwortet dreimal dieselbe Frage – „was war hier?" – für Land,
/// Region und Ort. Geprüft wird an einer Lage, wie sie die echte
/// Bibliothek hat: viel aus Niedersachsen, etwas aus Polen, ein
/// Geisterland aus einer falsch gelesenen Kamera.
Besuchsangabe angabe(String? land, String? region, String? ort, int anzahl) =>
    (land: land, region: region, ort: ort, anzahl: anzahl);

Markeneintrag marke(String art, String schluessel, Markenart wert) =>
    (art: art, schluessel: schluessel, wert: wert);

void main() {
  final angaben = [
    angabe('Germany', 'Lower Saxony', 'Hannover', 400),
    angabe('Germany', 'Lower Saxony', 'Oldenburg', 237),
    angabe('Germany', 'Hamburg', 'Hamburg', 15),
    angabe('Poland', 'Lesser Poland', 'Kraków', 328),
  ];
  const nachIso = {'Germany': 'DE', 'Poland': 'PL'};
  const regionscodes = {
    'DE|Lower Saxony': 'DE.06',
    'DE|Hamburg': 'DE.04',
    'DE|Bavaria': 'DE.02',
    'PL|Lesser Poland': 'PL.77',
  };
  const regionenDe = [
    (schluessel: 'DE.06', name: 'Lower Saxony'),
    (schluessel: 'DE.04', name: 'Hamburg'),
    (schluessel: 'DE.02', name: 'Bavaria'),
  ];

  group('ein Land', () {
    Ortsuebersicht land({Iterable<Markeneintrag> marken = const []}) =>
        ortsuebersicht(
          ebene: Ortsebene.land,
          schluessel: 'DE',
          name: 'Germany',
          angaben: angaben,
          nachIso: nachIso,
          regionscodes: regionscodes,
          bekannteUnterorte: regionenDe,
          marken: marken,
        );

    test('zählt nur seine eigenen Aufnahmen', () {
      // 400 + 237 + 15, und keine einzige aus Polen.
      expect(land().aufnahmen, 652);
    });

    test('führt auch die Regionen, in denen niemand war', () {
      // Sonst wäre die Liste ein Spiegel der eigenen Fotos statt einer
      // Landkarte – und man sähe nie, was noch fehlt.
      final l = land();
      expect(l.unterorteGesamt, 3);
      expect(l.unterorteBesucht, 2);
      expect(l.unterorte.map((u) => u.name),
          ['Lower Saxony', 'Hamburg', 'Bavaria']);
    });

    test('besuchte zuerst, darin die mit den meisten Aufnahmen', () {
      final l = land();
      expect(l.unterorte[0].aufnahmen, 637); // Niedersachsen
      expect(l.unterorte[1].aufnahmen, 15); // Hamburg
      expect(l.unterorte[2].aufnahmen, 0); // Bayern
      expect(l.unterorte[2].besucht, isFalse);
    });

    test('ein Haken von Hand macht eine Region besucht', () {
      final l = land(marken: [marke('region', 'DE.02', Markenart.besucht)]);
      final bayern =
          l.unterorte.firstWhere((u) => u.schluessel == 'DE.02');
      expect(bayern.aufnahmen, 0);
      expect(bayern.besucht, isTrue);
      expect(l.unterorteBesucht, 3);
      // **Und rückt damit vor alles Unbesuchte.** Der Fall muss so
      // gewählt sein, dass er es zeigen kann: Der Haken liegt auf dem
      // Saarland, das alphabetisch HINTER Bayern steht. Ohne die Regel
      // „besuchte zuerst" käme Bayern zuerst — beide haben null
      // Aufnahmen, und dann entscheidet der Name. Mit einem Haken auf
      // Bayern liefen beide Regeln zufällig auf dieselbe Reihenfolge
      // hinaus, und der Test hätte nichts geprüft.
      final mitSaarland = ortsuebersicht(
        ebene: Ortsebene.land,
        schluessel: 'DE',
        name: 'Germany',
        angaben: angaben,
        nachIso: nachIso,
        regionscodes: regionscodes,
        bekannteUnterorte: const [
          ...regionenDe,
          (schluessel: 'DE.09', name: 'Saarland'),
        ],
        marken: [marke('region', 'DE.09', Markenart.besucht)],
      );
      expect(mitSaarland.unterorte.map((u) => u.name),
          ['Lower Saxony', 'Hamburg', 'Saarland', 'Bavaria']);
    });

    test('„geplant" zählt nicht als besucht', () {
      // Dieselbe Regel wie überall in der App: Ein Vorhaben ist kein
      // Besuch.
      final l = land(marken: [marke('region', 'DE.02', Markenart.geplant)]);
      expect(l.unterorteBesucht, 2);
      expect(l.unterorte.last.schluessel, 'DE.02');
      expect(l.unterorte.last.marke, Markenart.geplant);
    });

    test('die eigene Marke des Landes wird gefunden', () {
      expect(land().marke, isNull);
      expect(land(marken: [marke('land', 'DE', Markenart.besucht)]).marke,
          Markenart.besucht);
      // Eine Marke auf einer Region ist nicht die des Landes.
      expect(land(marken: [marke('region', 'DE.06', Markenart.besucht)]).marke,
          isNull);
    });

    test('ein Land ohne verzeichnete Region bleibt trotzdem auskunftsfähig',
        () {
      // 24 der 252 Länder haben keine – Monaco und der Vatikan etwa.
      final l = ortsuebersicht(
        ebene: Ortsebene.land,
        schluessel: 'MC',
        name: 'Monaco',
        angaben: [angabe('Monaco', null, 'Monte-Carlo', 4)],
        nachIso: const {'Monaco': 'MC'},
        regionscodes: const {},
      );
      expect(l.aufnahmen, 4);
      expect(l.unterorte, isEmpty);
      expect(l.besucht, isTrue);
    });

    test('ein Land ohne alles ist nicht besucht, aber auch kein Fehler', () {
      final l = ortsuebersicht(
        ebene: Ortsebene.land,
        schluessel: 'FR',
        name: 'France',
        angaben: angaben,
        nachIso: nachIso,
        regionscodes: regionscodes,
        bekannteUnterorte: const [
          (schluessel: 'FR.11', name: 'Île-de-France')
        ],
      );
      expect(l.aufnahmen, 0);
      expect(l.besucht, isFalse);
      expect(l.unterorteGesamt, 1);
    });
  });

  group('eine Region', () {
    Ortsuebersicht region() => ortsuebersicht(
          ebene: Ortsebene.region,
          schluessel: 'DE.06',
          name: 'Lower Saxony',
          angaben: angaben,
          nachIso: nachIso,
          regionscodes: regionscodes,
          bekannteUnterorte: const [
            (schluessel: 'Germany|Lower Saxony|Celle', name: 'Celle'),
          ],
        );

    test('zählt nur ihre eigenen Aufnahmen', () {
      expect(region().aufnahmen, 637);
    });

    test('führt ihre Orte, auch die aus den Fotos', () {
      // Hannover und Oldenburg stehen nicht in der übergebenen Liste des
      // Datensatzes – sie kommen aus den Fotos und müssen trotzdem
      // dastehen. Ein Ort, den `cities1000` nicht führt, ist kein Grund,
      // seine Bilder zu verstecken.
      final r = region();
      expect(r.unterorte.map((u) => u.name), ['Hannover', 'Oldenburg', 'Celle']);
      expect(r.unterorteBesucht, 2);
    });

    test('der Schlüssel eines Ortes passt zu dem der Ortsmarken', () {
      // „Land|Region|Ort" mit Namen – genau so, wie die Weltkarte eine
      // Marke schreibt. Zwei Schreibweisen wären zwei Orte.
      expect(region().unterorte.first.schluessel,
          'Germany|Lower Saxony|Hannover');
    });
  });

  group('ein Ort', () {
    test('zählt seine Aufnahmen und hat nichts mehr darunter', () {
      final o = ortsuebersicht(
        ebene: Ortsebene.ort,
        schluessel: 'Germany|Lower Saxony|Hannover',
        name: 'Hannover',
        angaben: angaben,
        nachIso: nachIso,
        regionscodes: regionscodes,
      );
      expect(o.aufnahmen, 400);
      expect(o.unterorte, isEmpty);
      expect(o.besucht, isTrue);
    });

    test('zwei gleichnamige Orte in verschiedenen Ländern bleiben getrennt',
        () {
      // „Springfield" gibt es über zwanzigmal. Ohne Land und Region im
      // Schlüssel wären es alle zusammen ein Ort.
      final zwei = [
        angabe('Germany', 'Hesse', 'Neustadt', 3),
        angabe('Poland', 'Lesser Poland', 'Neustadt', 7),
      ];
      final deutsch = ortsuebersicht(
        ebene: Ortsebene.ort,
        schluessel: 'Germany|Hesse|Neustadt',
        name: 'Neustadt',
        angaben: zwei,
        nachIso: nachIso,
        regionscodes: regionscodes,
      );
      expect(deutsch.aufnahmen, 3);
    });
  });

  group('was aus den Fotos nicht auflösbar ist', () {
    test('ein unbekanntes Land fällt weg statt zu werfen', () {
      // Kommt vor: Eine Kamera schreibt einen Ländernamen, den der
      // Datensatz nicht kennt.
      final l = ortsuebersicht(
        ebene: Ortsebene.land,
        schluessel: 'DE',
        name: 'Germany',
        angaben: [...angaben, angabe('Absurdistan', 'Irgendwo', 'X', 99)],
        nachIso: nachIso,
        regionscodes: regionscodes,
        bekannteUnterorte: regionenDe,
      );
      expect(l.aufnahmen, 652);
    });

    test('eine Region ohne auflösbaren Code erscheint nicht als Zeile', () {
      // Sie hätte keinen Schlüssel, unter dem eine Marke stehen könnte –
      // eine Zeile, die man ansieht und nicht anklicken kann.
      final l = ortsuebersicht(
        ebene: Ortsebene.land,
        schluessel: 'DE',
        name: 'Germany',
        angaben: [angabe('Germany', 'Erfundenland', 'Ort', 5)],
        nachIso: nachIso,
        regionscodes: regionscodes,
      );
      // Die Aufnahme zählt für das Land – nur die Region fehlt.
      expect(l.aufnahmen, 5);
      expect(l.unterorte, isEmpty);
    });

    test('eine Aufnahme ohne Ortsangabe zählt trotzdem für ihr Land', () {
      final l = ortsuebersicht(
        ebene: Ortsebene.land,
        schluessel: 'DE',
        name: 'Germany',
        angaben: [angabe('Germany', null, null, 12)],
        nachIso: nachIso,
        regionscodes: regionscodes,
      );
      expect(l.aufnahmen, 12);
      expect(l.unterorte, isEmpty);
    });
  });

  /// **Eine von Hand markierte Stadt färbt ihr Bundesland.**
  ///
  /// Der Befund, der das ausgelöst hat: In der echten Bibliothek stand
  /// `ort | Germany|Bremen|Bremen | besucht`, kein Foto und keine
  /// Regionsmarke. Die Länderliste zählte Bremen als besuchte Region, die
  /// Bundesländer-Übersicht zeigte es als nirgends. Zwei Bildschirme,
  /// dieselben Daten, gegenteilige Auskunft.
  ///
  /// Hier steht Bavaria für Bremen: die einzige Region der Vorlage ohne
  /// eine einzige Aufnahme.
  group('was eine Ebene tiefer steht', () {
    Unterort bayern({Iterable<Markeneintrag> marken = const []}) =>
        ortsuebersicht(
          ebene: Ortsebene.land,
          schluessel: 'DE',
          name: 'Germany',
          angaben: angaben,
          nachIso: nachIso,
          regionscodes: regionscodes,
          bekannteUnterorte: regionenDe,
          marken: marken,
        ).unterorte.firstWhere((u) => u.name == 'Bavaria');

    test('ohne Marke bleibt die Region leer', () {
      // Die Gegenprobe zuerst: Ohne sie prüfte der nächste Test nur, dass
      // irgendetwas wahr ist.
      final b = bayern();
      expect(b.besucht, isFalse);
      expect(b.abgeleitet, isFalse);
    });

    test('eine markierte Stadt macht ihre Region besucht', () {
      final b = bayern(marken: [
        marke('ort', 'Germany|Bavaria|Nürnberg', Markenart.besucht),
      ]);
      expect(b.besucht, isTrue);
      expect(b.abgeleitet, isTrue);
    });

    test('die Ableitung ist keine eigene Marke', () {
      // Sonst böte die Oberfläche einen Haken zum Wegnehmen an, den es an
      // dieser Zeile gar nicht gibt.
      final b = bayern(marken: [
        marke('ort', 'Germany|Bavaria|Nürnberg', Markenart.besucht),
      ]);
      expect(b.marke, isNull);
      expect(b.aufnahmen, 0);
    });

    test('eine geplante Stadt färbt nichts', () {
      final b = bayern(marken: [
        marke('ort', 'Germany|Bavaria|Nürnberg', Markenart.geplant),
      ]);
      expect(b.besucht, isFalse,
          reason: 'ein Vorhaben ist kein Besuch – wie überall in dieser App');
    });

    test('eine Stadt eines anderen Landes färbt nichts', () {
      final b = bayern(marken: [
        marke('ort', 'Poland|Lesser Poland|Kraków', Markenart.besucht),
      ]);
      expect(b.besucht, isFalse);
    });

    test('sie zählt auch für den Fortschritt der Übersicht', () {
      final ohne = ortsuebersicht(
        ebene: Ortsebene.land,
        schluessel: 'DE',
        name: 'Germany',
        angaben: angaben,
        nachIso: nachIso,
        regionscodes: regionscodes,
        bekannteUnterorte: regionenDe,
      );
      final mit = ortsuebersicht(
        ebene: Ortsebene.land,
        schluessel: 'DE',
        name: 'Germany',
        angaben: angaben,
        nachIso: nachIso,
        regionscodes: regionscodes,
        bekannteUnterorte: regionenDe,
        marken: [marke('ort', 'Germany|Bavaria|Nürnberg', Markenart.besucht)],
      );
      expect(ohne.unterorteBesucht, 2);
      expect(mit.unterorteBesucht, 3);
    });

    test('beide Rechnungen sagen dasselbe', () {
      // DAS ist der eigentliche Befund gewesen: nicht eine falsche Zahl,
      // sondern zwei Rechnungen, die auseinanderliefen. Diese Prüfung
      // fällt, sobald es wieder passiert – egal an welcher der beiden
      // Stellen.
      final marken = [
        marke('ort', 'Germany|Bavaria|Nürnberg', Markenart.besucht),
      ];
      final uebersicht = ortsuebersicht(
        ebene: Ortsebene.land,
        schluessel: 'DE',
        name: 'Germany',
        angaben: angaben,
        nachIso: nachIso,
        regionscodes: regionscodes,
        bekannteUnterorte: regionenDe,
        marken: marken,
      );
      final liste = laenderstand(
        angaben: angaben,
        katalog: const [
          (
            iso: 'DE',
            name: 'Germany',
            nameDe: 'Deutschland',
            hauptstadt: 'Berlin',
            kontinent: 'EU',
            regionen: 3,
          ),
        ],
        nachIso: nachIso,
        regionscodes: regionscodes,
        marken: marken,
      ).single;

      expect(uebersicht.unterorteBesucht, liste.regionenBesucht,
          reason: 'die Länderliste und die Regionenübersicht müssen '
              'dieselbe Zahl nennen');
    });
  });

  /// **Eine Marke ohne Zeile wäre eine Marke ohne Rückweg.**
  ///
  /// `orteIn` deckelt bei den sechzig grössten Orten einer Region. Auf der
  /// Weltkarte lässt sich aber jeder Fleck markieren, und die nächste Stadt
  /// ist dort oft ein Dorf. Ohne eigenes Zutun stünde die Marke dann in der
  /// Datenbank, ohne dass irgendein Bildschirm sie zeigte.
  group('ein markierter Ort abseits der bekannten', () {
    Ortsuebersicht region({Iterable<Markeneintrag> marken = const []}) =>
        ortsuebersicht(
          ebene: Ortsebene.region,
          schluessel: 'DE.04',
          name: 'Hamburg',
          angaben: angaben,
          nachIso: nachIso,
          regionscodes: regionscodes,
          // Der Datensatz kennt hier nur die grosse Stadt.
          bekannteUnterorte: const [
            (schluessel: 'Germany|Hamburg|Hamburg', name: 'Hamburg'),
          ],
          marken: marken,
        );

    test('ohne Marke steht nur, was der Datensatz kennt', () {
      expect(region().unterorte.map((u) => u.name), ['Hamburg']);
    });

    test('er bekommt eine eigene Zeile', () {
      final r = region(marken: [
        marke('ort', 'Germany|Hamburg|Neuenfelde', Markenart.besucht),
      ]);
      final zeile =
          r.unterorte.where((u) => u.name == 'Neuenfelde').singleOrNull;
      expect(zeile, isNotNull, reason: 'sonst liesse sie sich nie zurücknehmen');
      expect(zeile!.marke, Markenart.besucht);
      expect(zeile.besucht, isTrue);
    });

    test('auch ein geplanter – gerade der', () {
      final r = region(marken: [
        marke('ort', 'Germany|Hamburg|Neuenfelde', Markenart.geplant),
      ]);
      final zeile =
          r.unterorte.where((u) => u.name == 'Neuenfelde').singleOrNull;
      expect(zeile, isNotNull,
          reason: 'ein Vorhaben, das man nicht findet, kann man nicht abhaken');
      expect(zeile!.besucht, isFalse);
    });

    test('einer aus einer anderen Region bleibt draussen', () {
      final r = region(marken: [
        marke('ort', 'Germany|Bavaria|Nürnberg', Markenart.besucht),
      ]);
      expect(r.unterorte.map((u) => u.name), ['Hamburg']);
    });

    test('er verdoppelt eine bekannte Zeile nicht', () {
      final r = region(marken: [
        marke('ort', 'Germany|Hamburg|Hamburg', Markenart.besucht),
      ]);
      expect(r.unterorte.where((u) => u.name == 'Hamburg'), hasLength(1));
    });
  });
}
