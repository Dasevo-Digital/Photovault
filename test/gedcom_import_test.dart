import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/gedcom_export.dart';
import 'package:photo_vault/services/gedcom_import.dart';
import 'package:photo_vault/services/lebenslauf.dart';
import 'package:photo_vault/services/stammbaum.dart';
import 'package:photo_vault/services/verwandtschaftsgrad.dart';

/// Das Einlesen von GEDCOM.
///
/// Der Export war der Ausgang aus dieser App; dies ist der Eingang. Wer
/// schon geforscht hat, hat eine Datei – und musste bisher alles von Hand
/// abtippen.
///
/// Geprüft wird das, was man einer eingelesenen Bibliothek später nicht
/// mehr ansieht: dass Namen zusammengesetzt statt zerschnitten werden,
/// dass aus „etwa 1900" kein Datum wird, dass eine kaputte Datei keinen
/// Kreis in die Datenbank trägt – und dass Unbekanntes übersprungen und
/// nicht zum Abbruch wird.
void main() {
  const t = gedcomBezeichnungenTest;

  GedcomEingelesen lies(String inhalt) =>
      liesGedcom(utf8.encode(inhalt), texte: t);

  /// Baut eine Datei aus Zeilen – mit dem Kopf, den jede echte hat.
  String datei(List<String> zeilen, {String kodierung = 'UTF-8'}) =>
      ['0 HEAD', '1 CHAR $kodierung', ...zeilen, '0 TRLR']
          .map((z) => '$z\r\n')
          .join();

  const einfach = [
    '0 @I1@ INDI',
    '1 NAME Hans /Meier/',
    '1 SEX M',
    '1 BIRT',
    '2 DATE 2 APR 1931',
    '2 PLAC Hamburg',
    '1 DEAT',
    '2 DATE 9 NOV 2004',
    '0 @I2@ INDI',
    '1 NAME Grete /Meier/',
    '1 SEX F',
    '0 @I3@ INDI',
    '1 NAME Karl /Meier/',
    '0 @F1@ FAM',
    '1 HUSB @I1@',
    '1 WIFE @I2@',
    '1 CHIL @I3@',
    '1 MARR',
    '2 DATE 14 MAY 1955',
    '2 PLAC Lübeck',
  ];

  group('Grundgerüst', () {
    test('liest Personen, Geschlecht und Lebensdaten', () {
      final e = lies(datei(einfach));
      expect(e.personen, hasLength(3));
      final hans = e.personen.first;
      expect(hans.kennung, 'I1');
      expect(hans.name, 'Hans Meier');
      expect(hans.geschlecht, Geschlecht.maennlich);
      expect(hans.geburt, DateTime(1931, 4, 2));
      expect(hans.tod, DateTime(2004, 11, 9));
      expect(e.personen[1].geschlecht, Geschlecht.weiblich);
      expect(e.personen[2].geschlecht, isNull,
          reason: 'ohne SEX bleibt es offen, statt zu raten');
    });

    test('macht aus der Familie wieder Kanten', () {
      final e = lies(datei(einfach));
      expect(
          e.kanten,
          containsAll([
            partnerKanteFuer('I1', 'I2'),
            kante('I3', 'I1', Verwandtschaft.elternteil),
            kante('I3', 'I2', Verwandtschaft.elternteil),
          ]));
      expect(e.kanten, hasLength(3));
    });

    test('die Partnerkante steht in ihrer gespeicherten Form', () {
      // Sonst entstünden für dasselbe Paar je nach Reihenfolge in der
      // Datei zwei verschiedene Zeilen.
      final e = lies(datei([
        '0 @I2@ INDI',
        '1 NAME B /B/',
        '0 @I1@ INDI',
        '1 NAME A /A/',
        '0 @F1@ FAM',
        '1 HUSB @I2@',
        '1 WIFE @I1@',
      ]));
      expect(e.kanten.single.personId, 'I1');
    });

    test('ein Verweis ins Leere wird uebersprungen, nicht geworfen', () {
      final e = lies(datei([
        '0 @I1@ INDI',
        '1 NAME A /A/',
        '0 @F1@ FAM',
        '1 HUSB @I1@',
        '1 WIFE @I99@',
        '1 CHIL @I98@',
      ]));
      expect(e.kanten, isEmpty);
      expect(e.personen, hasLength(1));
    });
  });

  group('Namen', () {
    test('setzt die Schraegstrichform wieder zusammen', () {
      expect(deuteName('Anna /Meier/'), 'Anna Meier');
      expect(deuteName('Anna Maria /Meier/'), 'Anna Maria Meier');
    });

    test('kommt mit einem einzelnen Namen aus', () {
      // Der Gegenpart zu `gedcomName('Oma') == 'Oma //'`.
      expect(deuteName('Oma //'), 'Oma');
      expect(deuteName('Oma'), 'Oma');
    });

    test('behaelt, was hinter dem Nachnamen steht', () {
      // Manche Programme setzen Namenszusätze dahinter.
      expect(deuteName('Karl /von Stein/ jun.'), 'Karl von Stein jun.');
    });

    test('GIVN und SURN gelten nur, wenn die Zeile leer blieb', () {
      // Fremde Programme schreiben oft beides. Beides zu nehmen ergäbe
      // „Anna Meier Anna Meier".
      final e = lies(datei([
        '0 @I1@ INDI',
        '1 NAME Anna /Meier/',
        '2 GIVN Anna',
        '2 SURN Meier',
        '0 @I2@ INDI',
        '1 NAME',
        '2 GIVN Berta',
        '2 SURN Schulz',
      ]));
      expect(e.personen[0].name, 'Anna Meier');
      expect(e.personen[1].name, 'Berta Schulz');
    });

    test('eine Person ohne Namen wird trotzdem angelegt', () {
      // Sie hängt an Verwandtschaften, die sonst mitverschwänden.
      final e = lies(datei([
        '0 @I1@ INDI',
        '1 SEX M',
      ]));
      expect(e.personen.single.name, t.ohneNamen);
      expect(e.hinweiseMit(GedcomHinweisart.ohneNamen), 1);
    });
  });

  group('Daten', () {
    test('nimmt volle Datumsangaben', () {
      expect(deuteDatum('2 APR 1931').datum, DateTime(1931, 4, 2));
    });

    test('ergaenzt Fehlendes auf den Ersten', () {
      // Dieselbe Regel, nach der die App Jahresangaben ohnehin speichert.
      expect(deuteDatum('APR 1931').datum, DateTime(1931, 4, 1));
      expect(deuteDatum('1931').datum, DateTime(1931, 1, 1));
    });

    test('uebernimmt ungenaue Angaben NICHT', () {
      // Der wichtigste Test der Gruppe. Aus „etwa 1900" ein Datum zu
      // machen wäre erfundene Genauigkeit – und niemand könnte die
      // Erfindung später von einer Angabe unterscheiden.
      for (final roh in [
        'ABT 1900',
        'BEF 1912',
        'AFT 1912',
        'BET 1900 AND 1910',
        'FROM 1900 TO 1910',
        'EST 1880',
        'CAL 1880',
      ]) {
        final d = deuteDatum(roh);
        expect(d.datum, isNull, reason: roh);
        expect(d.ungenau, isTrue, reason: roh);
      }
    });

    test('ein ungenaues Datum kommt in den Bericht', () {
      final e = lies(datei([
        '0 @I1@ INDI',
        '1 NAME Anna /Meier/',
        '1 BIRT',
        '2 DATE ABT 1900',
      ]));
      expect(e.personen.single.geburt, isNull);
      expect(e.hinweiseMit(GedcomHinweisart.ungenauesDatum), 1);
      expect(e.hinweise.single.einzelheit, contains('ABT 1900'));
    });

    test('eine vorangestellte Kalenderangabe stoert nicht', () {
      expect(deuteDatum('@#DGREGORIAN@ 12 MAY 1875').datum,
          DateTime(1875, 5, 12));
    });

    test('Doppeljahre gelten als ungenau', () {
      // „1750/51" stammt aus der Umstellung des Jahresanfangs. Eines der
      // beiden zu wählen wäre geraten.
      expect(deuteDatum('12 MAR 1750/51').ungenau, isTrue);
    });

    test('ein leeres Datum ist kein Hinweis', () {
      final d = deuteDatum('   ');
      expect(d.datum, isNull);
      expect(d.ungenau, isFalse,
          reason: 'nichts anzugeben ist keine ungenaue Angabe');
    });
  });

  group('Ereignisse', () {
    test('der Geburtsort wird als Ereignis gerettet', () {
      // Die App führt Geburt und Tod als Datum an der Person, ohne Ort.
      // Ohne diesen Weg ginge gerade der Ortsname verloren, der in
      // fremden Dateien am häufigsten steht.
      final e = lies(datei(einfach));
      final geburtsort = e.personen.first.ereignisse
          .firstWhere((x) => x.notiz == t.geburtsort);
      expect(geburtsort.ort, 'Hamburg');
      expect(geburtsort.datum, DateTime(1931, 4, 2));
      expect(geburtsort.art, Ereignisart.sonstiges);
    });

    test('ohne PLAC entsteht kein Ereignis', () {
      // Sonst stünde neben jeder Geburt eine leere zweite Zeile.
      final e = lies(datei(einfach));
      expect(
          e.personen.first.ereignisse.where((x) => x.notiz == t.sterbeort),
          isEmpty);
    });

    test('die Hochzeit geht an beide Partner', () {
      // In GEDCOM hängt sie an der Familie, in dieser App an der Person.
      // Sie einem der beiden zuzuschlagen hiesse zu entscheiden, welchem.
      final e = lies(datei(einfach));
      for (final k in ['I1', 'I2']) {
        final p = e.personen.firstWhere((x) => x.kennung == k);
        final h = p.ereignisse.where((x) => x.art == Ereignisart.hochzeit);
        expect(h, hasLength(1), reason: k);
        expect(h.single.ort, 'Lübeck');
        expect(h.single.datum, DateTime(1955, 5, 14));
      }
      final kind = e.personen.firstWhere((x) => x.kennung == 'I3');
      expect(kind.ereignisse, isEmpty);
    });

    test('Beruf und Ausbildung bekommen ihre Art', () {
      final e = lies(datei([
        '0 @I1@ INDI',
        '1 NAME A /A/',
        '1 OCCU Schmied',
        '2 PLAC Kiel',
        '1 EDUC Volksschule',
        '1 RESI',
        '2 DATE 1962',
        '2 PLAC Bremen',
      ]));
      final arten = {for (final x in e.personen.single.ereignisse) x.art};
      expect(arten, {
        Ereignisart.beruf,
        Ereignisart.ausbildung,
        Ereignisart.umzug,
      });
      final beruf = e.personen.single.ereignisse
          .firstWhere((x) => x.art == Ereignisart.beruf);
      expect(beruf.notiz, 'Schmied');
      expect(beruf.ort, 'Kiel');
    });
  });

  group('Adoptiv- und Pflegekanten', () {
    test('PEDI wird gelesen', () {
      final e = lies(datei([
        '0 @I1@ INDI',
        '1 NAME Vater /V/',
        '0 @I2@ INDI',
        '1 NAME Kind /K/',
        '1 FAMC @F1@',
        '2 PEDI adopted',
        '0 @F1@ FAM',
        '1 HUSB @I1@',
        '1 CHIL @I2@',
      ]));
      expect(e.kanten.single.art, Verwandtschaft.adoptivelternteil);
    });

    test('ohne PEDI ist es die leibliche Verbindung', () {
      final e = lies(datei([
        '0 @I1@ INDI',
        '1 NAME Vater /V/',
        '0 @I2@ INDI',
        '1 NAME Kind /K/',
        '0 @F1@ FAM',
        '1 HUSB @I1@',
        '1 CHIL @I2@',
      ]));
      expect(e.kanten.single.art, Verwandtschaft.elternteil);
    });
  });

  group('Kaputte Dateien', () {
    test('ein Kreis wird verhindert und gemeldet', () {
      // Der Fall, der ohne Prüfung erst viel später auffällt: Jede
      // Auswertung nach oben liefe endlos, und die Datei ist dann längst
      // eingelesen.
      final e = lies(datei([
        '0 @I1@ INDI',
        '1 NAME A /A/',
        '0 @I2@ INDI',
        '1 NAME B /B/',
        '0 @F1@ FAM',
        '1 HUSB @I1@',
        '1 CHIL @I2@',
        '0 @F2@ FAM',
        '1 HUSB @I2@',
        '1 CHIL @I1@',
      ]));
      expect(e.kanten, hasLength(1),
          reason: 'die erste Kante steht, die schliessende nicht');
      expect(e.hinweiseMit(GedcomHinweisart.kreisVerhindert), 1);
    });

    test('eine Person als eigenes Kind wird abgewiesen', () {
      final e = lies(datei([
        '0 @I1@ INDI',
        '1 NAME A /A/',
        '0 @F1@ FAM',
        '1 HUSB @I1@',
        '1 CHIL @I1@',
      ]));
      expect(e.kanten, isEmpty);
      expect(e.hinweiseMit(GedcomHinweisart.kreisVerhindert), 1);
    });

    test('Unbekanntes wird uebersprungen, nicht geworfen', () {
      // Eine fremde Datei wegen eines einzigen Sondertags abzulehnen
      // hiesse, die brauchbaren dreihundert Personen mit wegzuwerfen.
      final e = lies(datei([
        '0 @I1@ INDI',
        '1 NAME A /A/',
        '1 _FSID KWZQ-1234',
        '1 SOUR @S1@',
        '0 @S1@ SOUR',
        '1 TITL Kirchenbuch',
      ]));
      expect(e.personen, hasLength(1));
      expect(e.hinweiseMit(GedcomHinweisart.uebersprungen), 2);
    });

    test('doppelte Kennungen zaehlen einmal', () {
      // Zwei Datensätze mit derselben Verweisnummer: Die zweite Person
      // wäre über ihre Kennung nicht mehr erreichbar, und jeder Verweis
      // darauf zeigte auf die erste.
      final e = lies(datei([
        '0 @I1@ INDI',
        '1 NAME Anna /Meier/',
        '0 @I1@ INDI',
        '1 NAME Berta /Schulz/',
      ]));
      expect(e.personen, hasLength(1));
      expect(e.personen.single.name, 'Anna Meier');
    });

    test('ohne HEAD wird abgelehnt', () {
      expect(
          () => liesGedcom(utf8.encode('0 @I1@ INDI\r\n0 TRLR\r\n'), texte: t),
          throwsA(isA<GedcomAbbruchFehler>().having(
              (e) => e.grund, 'grund', GedcomAbbruch.keinKopf)));
    });

    test('eine Datei ohne Personen wird abgelehnt', () {
      expect(
          () => lies(datei(['0 @S1@ SOUR', '1 TITL Nichts'])),
          throwsA(isA<GedcomAbbruchFehler>().having(
              (e) => e.grund, 'grund', GedcomAbbruch.keinePersonen)));
    });
  });

  group('Kodierung', () {
    test('UTF-8 mit Byte-Marke', () {
      final bytes = [0xEF, 0xBB, 0xBF, ...utf8.encode(datei(einfach))];
      expect(liesGedcom(bytes, texte: t).personen, hasLength(3));
    });

    test('CP1252 wird an der Kopfzeile erkannt', () {
      // Umlaute aus Windows-Programmen. Als UTF-8 gelesen wäre der Name
      // „Müller" zerschossen – und das fiele erst in der Datenbank auf.
      final bytes = <int>[];
      for (final zeichen in datei([
        '0 @I1@ INDI',
        '1 NAME Franz /Müller/',
      ], kodierung: 'ANSI')
          .codeUnits) {
        bytes.add(zeichen <= 0xFF ? zeichen : 0x3F);
      }
      expect(liesGedcom(bytes, texte: t).personen.single.name, 'Franz Müller');
    });

    test('CP1252 rettet die zweiunddreissig Sonderzeichen', () {
      // Der Bereich 0x80–0x9F, in dem sich CP1252 von Latin-1
      // unterscheidet. Ohne die Tabelle würde daraus ein Steuerzeichen.
      final kopf = '0 HEAD\r\n1 CHAR ANSI\r\n0 @I1@ INDI\r\n1 NAME O'.codeUnits;
      final bytes = [...kopf, 0x92, ...'Brien //\r\n0 TRLR\r\n'.codeUnits];
      expect(liesGedcom(bytes, texte: t).personen.single.name, 'O’Brien');
    });

    test('ANSEL wird abgelehnt statt halb geraten', () {
      // Eine Bibliothekskodierung aus den Achtzigern, die diakritische
      // Zeichen VOR den Buchstaben stellt. Ein zerschossener Nachname
      // fällt niemandem mehr auf, wenn er erst in der Datenbank steht.
      expect(
          () => lies(datei(einfach, kodierung: 'ANSEL')),
          throwsA(isA<GedcomAbbruchFehler>()
              .having((e) => e.grund, 'grund', GedcomAbbruch.kodierung)
              .having((e) => e.einzelheit, 'einzelheit', 'ANSEL')));
    });

    test('UTF-16 wird an der Byte-Marke abgelehnt', () {
      expect(
          () => liesGedcom([0xFF, 0xFE, 0x30, 0x00], texte: t),
          throwsA(isA<GedcomAbbruchFehler>()
              .having((e) => e.grund, 'grund', GedcomAbbruch.kodierung)));
    });

    test('eine falsche Kopfangabe fuehrt nicht zum Absturz', () {
      // Der Kopf sagt UTF-8, die Bytes sind es nicht. Dann ist CP1252 die
      // einzige Deutung, die nirgends wirft.
      final bytes = [
        ...'0 HEAD\r\n1 CHAR UTF-8\r\n0 @I1@ INDI\r\n1 NAME Franz /M'.codeUnits,
        0xFC,
        ...'ller/\r\n0 TRLR\r\n'.codeUnits,
      ];
      expect(liesGedcom(bytes, texte: t).personen.single.name, 'Franz Müller');
    });
  });

  group('Fortsetzungszeilen', () {
    test('CONT und CONC setzen den Wert fort', () {
      final e = lies(datei([
        '0 @I1@ INDI',
        '1 NAME Anna /Meier-',
        '2 CONC Schulz/',
        '1 OCCU Lehrerin',
        '2 CONT an der Volksschule',
      ]));
      expect(e.personen.single.name, 'Anna Meier-Schulz');
      expect(e.personen.single.ereignisse.single.notiz,
          'Lehrerin\nan der Volksschule');
    });
  });

  group('Rundlauf', () {
    // Der Test, den kein einzelner Fall ersetzt: ausgeben, wieder
    // einlesen, vergleichen. Er prüft beide Seiten gegeneinander, und er
    // läuft ohne fremde Datei.
    GedcomPerson p(String id, String name,
            {Geschlecht? g, DateTime? geb, DateTime? tod}) =>
        (id: id, name: name, geschlecht: g, geburt: geb, tod: tod);

    final personen = [
      p('opa', 'Hans Meier',
          g: Geschlecht.maennlich,
          geb: DateTime(1931, 4, 2),
          tod: DateTime(2004, 11, 9)),
      p('oma', 'Grete Meier', g: Geschlecht.weiblich, geb: DateTime(1934, 7, 15)),
      p('vater', 'Karl Meier', g: Geschlecht.maennlich),
      p('mutter', 'Eva Meier', g: Geschlecht.weiblich),
      p('kind', 'Lena', g: Geschlecht.weiblich),
      p('pflege', 'Jonas', g: Geschlecht.maennlich),
      p('offen', 'Niemand'),
    ];

    final netz = Verwandtschaftsnetz([
      partnerKanteFuer('opa', 'oma'),
      kante('vater', 'opa', Verwandtschaft.elternteil),
      kante('vater', 'oma', Verwandtschaft.elternteil),
      partnerKanteFuer('vater', 'mutter'),
      kante('kind', 'vater', Verwandtschaft.elternteil),
      kante('kind', 'mutter', Verwandtschaft.elternteil),
      kante('pflege', 'vater', Verwandtschaft.pflegeelternteil),
      kante('pflege', 'mutter', Verwandtschaft.pflegeelternteil),
    ]);

    GedcomEingelesen rundlauf() => lies(schreibeGedcom(personen, netz,
        erzeuger: gedcomErzeuger, version: '1.10.5'));

    test('alle Personen kommen zurueck', () {
      final e = rundlauf();
      expect(e.personen.map((x) => x.name).toSet(),
          personen.map((x) => x.name).toSet());
    });

    test('Geschlecht und Lebensdaten bleiben erhalten', () {
      final e = rundlauf();
      final nach = {for (final x in e.personen) x.name: x};
      expect(nach['Hans Meier']!.geburt, DateTime(1931, 4, 2));
      expect(nach['Hans Meier']!.tod, DateTime(2004, 11, 9));
      expect(nach['Grete Meier']!.geschlecht, Geschlecht.weiblich);
      expect(nach['Niemand']!.geschlecht, isNull,
          reason: 'GEDCOM kennt nur F, M und U – aus U wird wieder nichts');
    });

    test('jede Verwandtschaft kommt zurueck', () {
      final e = rundlauf();
      final name = {for (final x in e.personen) x.kennung: x.name};
      // Bei der Partnerkante werden die Namen sortiert verglichen. Ihre
      // gespeicherte Richtung hängt an der kleineren **Kennung**, und die
      // vergibt der Import neu – aus „Eva vor Karl" wird dabei „Karl vor
      // Eva". Eine ungerichtete Verbindung trägt in ihrer Richtung keine
      // Angabe; hier darauf zu bestehen hiesse, eine Belanglosigkeit zu
      // prüfen und die eigentliche Aussage zu verfehlen.
      final nach = {
        for (final k in e.kanten)
          if (k.art == Verwandtschaft.partner)
            '${([name[k.personId]!, name[k.andereId]!]..sort()).join('|')}|partner'
          else
            '${name[k.personId]}|${name[k.andereId]}|${k.art.name}'
      };
      expect(nach, {
        'Grete Meier|Hans Meier|partner',
        'Karl Meier|Hans Meier|elternteil',
        'Karl Meier|Grete Meier|elternteil',
        'Eva Meier|Karl Meier|partner',
        'Lena|Karl Meier|elternteil',
        'Lena|Eva Meier|elternteil',
        'Jonas|Karl Meier|pflegeelternteil',
        'Jonas|Eva Meier|pflegeelternteil',
      });
    });

    test('die Pflegekante ueberlebt den Rundlauf', () {
      // Gegenprobe zur vorigen Zeile, mit dem Grund davor: Ohne `2 PEDI`
      // im Export käme Jonas als leibliches Kind zurück – und niemand
      // sähe der Bibliothek an, dass die Angabe verändert wurde.
      final ausgabe = schreibeGedcom(personen, netz,
          erzeuger: gedcomErzeuger, version: '1.10.5');
      expect(ausgabe, contains('2 PEDI foster'));
    });

    test('meldet nichts Ungenaues und nichts Uebersprungenes', () {
      // Die eigene Ausgabe darf im eigenen Einleser keinen Hinweis
      // erzeugen. Täte sie es, wäre eine der beiden Seiten falsch.
      final e = rundlauf();
      expect(e.hinweise, isEmpty);
    });
  });

  group('Eine Datei aus fremder Hand', () {
    // Nachgebaut, nicht echt – das sei gesagt. Zusammengetragen ist,
    // was Dateien anderer Programme regelmässig mitbringen und was diese
    // App einzeln schon prüft: Windows-Kodierung, GIVN/SURN neben NAME,
    // Quellen- und Bildverweise, programmeigene Sondertags mit
    // Unterstrich, ungefähre Daten, eine Adoption. Der Wert liegt darin,
    // dass alles zugleich auftritt: Ein Einleser, der jeden Fall für
    // sich beherrscht, kann am Zusammentreffen scheitern.
    final zeilen = [
      '0 HEAD',
      '1 SOUR FremdesProgramm',
      '2 NAME Ein anderes Programm',
      '1 CHAR ANSI',
      '1 GEDC',
      '2 VERS 5.5.1',
      '0 @I100@ INDI',
      '1 NAME Franz /Müller/',
      '2 GIVN Franz',
      '2 SURN Müller',
      '1 SEX M',
      '1 BIRT',
      '2 DATE ABT 1878',
      '2 PLAC Königsberg',
      '2 SOUR @S1@',
      '1 DEAT',
      '2 DATE 3 FEB 1945',
      '1 OCCU Schlosser',
      '1 _MILT Landsturm',
      '1 OBJE @O1@',
      '1 CHAN',
      '2 DATE 1 JAN 2020',
      '0 @I101@ INDI',
      '1 NAME',
      '2 GIVN Elisabeth',
      '2 SURN Müller',
      '1 SEX F',
      '0 @I102@ INDI',
      '1 NAME Werner /Müller/',
      '1 SEX M',
      '1 FAMC @F10@',
      '2 PEDI adopted',
      '0 @F10@ FAM',
      '1 HUSB @I100@',
      '1 WIFE @I101@',
      '1 CHIL @I102@',
      '1 MARR',
      '2 DATE 8 SEP 1910',
      '2 PLAC Königsberg',
      '0 @S1@ SOUR',
      '1 TITL Kirchenbuch St. Nikolai',
      '0 @O1@ OBJE',
      '1 FILE bild.jpg',
      '0 TRLR',
    ];
    // Windows-Kodierung: alles über 0xFF käme in einer echten Datei
    // nicht vor, alles darunter steht als einzelnes Byte.
    final bytes = [
      for (final z in zeilen)
        for (final c in '$z\r\n'.codeUnits) c <= 0xFF ? c : 0x3F,
    ];

    GedcomEingelesen fremd() => liesGedcom(bytes, texte: t);

    test('die Umlaute ueberstehen die Windows-Kodierung', () {
      expect(fremd().personen.first.name, 'Franz Müller');
    });

    test('GIVN und SURN springen ein, wo NAME leer blieb', () {
      expect(fremd().personen[1].name, 'Elisabeth Müller');
    });

    test('das ungefaehre Geburtsjahr bleibt leer und wird gemeldet', () {
      final e = fremd();
      expect(e.personen.first.geburt, isNull);
      expect(e.personen.first.tod, DateTime(1945, 2, 3),
          reason: 'das genaue Sterbedatum daneben wird sehr wohl übernommen');
      expect(e.hinweiseMit(GedcomHinweisart.ungenauesDatum), 1);
    });

    test('der Geburtsort ueberlebt, obwohl das Datum es nicht tut', () {
      // Der Fall, den man beim Bauen leicht verliert: Ort und Datum
      // hängen an derselben Zeile, aber nur eines von beiden ist
      // unbrauchbar. Königsberg heisst heute anders – umso mehr Grund,
      // den aufgeschriebenen Namen zu behalten.
      final ort = fremd()
          .personen
          .first
          .ereignisse
          .firstWhere((x) => x.notiz == t.geburtsort);
      expect(ort.ort, 'Königsberg');
      expect(ort.datum, isNull);
    });

    test('die Adoption kommt an', () {
      final e = fremd();
      final adoptiv = e.kanten
          .where((k) => k.art == Verwandtschaft.adoptivelternteil);
      expect(adoptiv, hasLength(2), reason: 'beide Elternteile der Familie');
    });

    test('Quellen, Bilder und Sondertags halten nichts auf', () {
      final e = fremd();
      expect(e.personen, hasLength(3));
      expect(e.hinweiseMit(GedcomHinweisart.uebersprungen), greaterThan(0));
      // CHAN ist Verwaltung des fremden Programms und steht bewusst
      // NICHT im Bericht – sonst verdeckte das Erwartbare das
      // Bemerkenswerte.
      expect(
          e.hinweise.where((h) => h.einzelheit.endsWith('CHAN')), isEmpty);
    });
  });

  group('Neue Kennungen', () {
    test('richtet die Partnerkante neu aus', () {
      // Der Fall, der stillschweigend falsch herauskommt: Die
      // gespeicherte Form hat die kleinere Kennung vorn. Nach dem
      // Umsetzen ist das eine andere als in der Datei – bliebe die alte
      // Reihenfolge stehen, fände das spätere Auflösen der Partnerschaft
      // die Zeile nicht mehr.
      final um = mitNeuenKennungen(
        [partnerKanteFuer('I1', 'I2')],
        {'I1': 'zzz', 'I2': 'aaa'},
      );
      expect(um.single, partnerKanteFuer('aaa', 'zzz'));
      expect(um.single.personId, 'aaa');
    });

    test('Elternkanten behalten ihre Richtung', () {
      // Sie sind gerichtet: personId ist das Kind. Sie zu sortieren
      // machte aus einem Kind einen Elternteil.
      final um = mitNeuenKennungen(
        [kante('I2', 'I1', Verwandtschaft.elternteil)],
        {'I1': 'zzz', 'I2': 'aaa'},
      );
      expect(um.single.personId, 'aaa');
      expect(um.single.andereId, 'zzz');
    });

    test('eine Kante ohne beide Enden faellt weg', () {
      expect(
          mitNeuenKennungen(
              [kante('I2', 'I9', Verwandtschaft.elternteil)], {'I2': 'aaa'}),
          isEmpty);
    });
  });

  group('Doppelte', () {
    ({String kennung, String name, DateTime? geburt}) v(
            String kennung, String name, [int? jahr]) =>
        (kennung: kennung, name: name, geburt: jahr == null ? null : DateTime(jahr));

    test('gleicher Name und gleiches Jahr gelten als Verdacht', () {
      final treffer = moeglicheDoppelte(
        [v('n1', 'Hans Meier', 1931)],
        [v('b1', 'hans  meier', 1931), v('b2', 'Hans Meier', 1940)],
      );
      expect(treffer, hasLength(1));
      expect(treffer.single.bestehendeKennung, 'b1');
    });

    test('gleicher Name ohne jedes Jahr zaehlt auch', () {
      // Bei Urgroßeltern kennt kaum jemand das Jahr – und genau dort
      // passiert das doppelte Anlegen.
      expect(moeglicheDoppelte([v('n1', 'Oma')], [v('b1', 'Oma')]),
          hasLength(1));
    });

    test('ein bekanntes gegen ein unbekanntes Jahr ist kein Verdacht', () {
      expect(moeglicheDoppelte([v('n1', 'Oma', 1900)], [v('b1', 'Oma')]),
          isEmpty);
    });

    test('verschiedene Namen bleiben ungenannt', () {
      expect(
          moeglicheDoppelte([v('n1', 'Hans Meier', 1931)],
              [v('b1', 'Hans Meyer', 1931)]),
          isEmpty);
    });
  });
}
