import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/gedcom_export.dart';
import 'package:photo_vault/services/stammbaum.dart';
import 'package:photo_vault/services/verwandtschaftsgrad.dart';

/// Der GEDCOM-Export.
///
/// Das Format ist der Ausgang aus dieser App – wenn es fehlerhaft ist,
/// merkt man das erst in einem fremden Programm, und dann sind die
/// Eintragungen verloren. Geprüft wird deshalb die Struktur, nicht das
/// Aussehen: dass jede Person genau einmal steht, dass jede Verwandtschaft
/// in einem FAM-Datensatz ankommt und dass keine Verweisnummer ins Leere
/// zeigt.
void main() {
  GedcomPerson p(String id, String name,
          {Geschlecht? g, DateTime? geb, DateTime? tod}) =>
      (id: id, name: name, geschlecht: g, geburt: geb, tod: tod);

  final personen = [
    p('opa', 'Hans Meier', g: Geschlecht.maennlich, geb: DateTime(1931, 4, 2),
        tod: DateTime(2004, 11, 9)),
    p('oma', 'Grete Meier', g: Geschlecht.weiblich, geb: DateTime(1934, 7, 15)),
    p('vater', 'Karl Meier', g: Geschlecht.maennlich),
    p('mutter', 'Eva Meier', g: Geschlecht.weiblich),
    p('kind', 'Lena', g: Geschlecht.weiblich),
    p('offen', 'Niemand'),
  ];

  final netz = Verwandtschaftsnetz([
    partnerKanteFuer('opa', 'oma'),
    kante('vater', 'opa', Verwandtschaft.elternteil),
    kante('vater', 'oma', Verwandtschaft.elternteil),
    partnerKanteFuer('vater', 'mutter'),
    kante('kind', 'vater', Verwandtschaft.elternteil),
    kante('kind', 'mutter', Verwandtschaft.elternteil),
  ]);

  String datei() => schreibeGedcom(personen, netz,
      erzeuger: 'PhotoVault', version: '0.11.0');

  List<String> zeilen() => datei().split('\r\n')..removeLast();

  group('Kopf und Rumpf', () {
    test('beginnt mit HEAD und endet mit TRLR', () {
      final z = zeilen();
      expect(z.first, '0 HEAD');
      expect(z.last, '0 TRLR');
    });

    test('nennt Fassung und Kodierung', () {
      expect(zeilen(), containsAll(['2 VERS 5.5.1', '1 CHAR UTF-8']));
    });

    test('trennt Zeilen mit CR LF', () {
      // Manche Programme lesen auch nur LF – „manche" ist bei einem
      // Austauschformat zu wenig.
      expect(datei().contains('\r\n'), isTrue);
      expect(datei().split('\r\n').length, zeilen().length + 1);
    });
  });

  group('Personen', () {
    test('jede Person steht genau einmal', () {
      final indi = zeilen().where((z) => z.endsWith(' INDI'));
      expect(indi, hasLength(personen.length));
    });

    test('zerlegt den Namen in Vor- und Nachnamen', () {
      expect(gedcomName('Hans Meier'), 'Hans /Meier/');
      expect(gedcomName('Anna Maria Meier'), 'Anna Maria /Meier/');
    });

    test('kommt mit einem einzelnen Namen aus', () {
      // „Oma" ist ein zulässiger Eintrag in dieser App – der Nachname
      // bleibt dann leer, statt den Vornamen dorthin zu schieben.
      expect(gedcomName('Oma'), 'Oma //');
    });

    test('schreibt das Geschlecht in der Schreibweise des Formats', () {
      final z = zeilen();
      expect(z.where((l) => l == '1 SEX M'), hasLength(2));
      expect(z.where((l) => l == '1 SEX F'), hasLength(3));
      // GEDCOM kennt nur F, M und U – „nicht angegeben" wird U.
      expect(z.where((l) => l == '1 SEX U'), hasLength(1));
    });

    test('schreibt Daten mit englischem Monatskürzel', () {
      final z = zeilen();
      expect(z, contains('2 DATE 2 APR 1931'));
      expect(z, contains('2 DATE 9 NOV 2004'));
    });

    test('lässt fehlende Daten weg, statt sie zu erfinden', () {
      // Die Oma lebt – es darf kein DEAT für sie geben.
      expect(zeilen().where((l) => l == '1 DEAT'), hasLength(1));
    });
  });

  group('Familien', () {
    test('gruppiert Kinder nach ihrer Elternmenge', () {
      final f = familien(netz, [for (final x in personen) x.id]);
      final mitKindern = f.where((x) => x.kinder.isNotEmpty).toList();
      expect(mitKindern, hasLength(2));
      expect(
          mitKindern.map((x) => x.kinder.single), containsAll(['vater', 'kind']));
    });

    test('behält ein Paar ohne gemeinsame Kinder', () {
      final ohneKind = Verwandtschaftsnetz([partnerKanteFuer('a', 'b')]);
      final f = familien(ohneKind, ['a', 'b']);
      expect(f, hasLength(1));
      expect(f.single.eltern, ['a', 'b']);
      expect(f.single.kinder, isEmpty);
    });

    test('legt für dasselbe Paar nicht zwei Familien an', () {
      // Opa und Oma sind Partner UND gemeinsame Eltern – das ist eine
      // Familie, nicht zwei.
      final f = familien(netz, [for (final x in personen) x.id]);
      expect(f, hasLength(2));
    });

    test('verteilt HUSB und WIFE nach dem Geschlecht', () {
      final z = zeilen();
      expect(z.where((l) => l.startsWith('1 HUSB')), hasLength(2));
      expect(z.where((l) => l.startsWith('1 WIFE')), hasLength(2));
    });
  });

  group('Verweise', () {
    test('keine Verweisnummer zeigt ins Leere', () {
      final z = zeilen();
      final vergeben = <String>{
        for (final l in z)
          if (l.startsWith('0 @')) l.split('@')[1],
      };
      final benutzt = <String>{
        for (final l in z)
          if (l.contains('@') && !l.startsWith('0 ')) l.split('@')[1],
      };
      expect(benutzt.difference(vergeben), isEmpty,
          reason: 'ein Verweis ohne Datensatz macht die Datei unbrauchbar');
    });

    test('jede Verwandtschaft kommt an', () {
      final z = zeilen();
      // Zwei Kinder mit Eltern -> zwei FAMC; vier Personen sind
      // Elternteil oder Partner -> vier FAMS.
      expect(z.where((l) => l.startsWith('1 FAMC')), hasLength(2));
      expect(z.where((l) => l.startsWith('1 FAMS')), hasLength(4));
    });

    test('eine Person ohne Verwandtschaft steht trotzdem drin', () {
      // Sonst verschwände sie beim Export stillschweigend.
      final z = zeilen();
      final stelle = z.indexOf('1 NAME Niemand //');
      expect(stelle, greaterThan(-1));
      expect(z[stelle - 1], endsWith(' INDI'));
    });
  });

  test('leerer Bestand ergibt eine gültige, leere Datei', () {
    final leer = schreibeGedcom([], Verwandtschaftsnetz([]),
        erzeuger: 'PhotoVault', version: '0.11.0');
    expect(leer, startsWith('0 HEAD'));
    expect(leer.trimRight(), endsWith('0 TRLR'));
  });
}
