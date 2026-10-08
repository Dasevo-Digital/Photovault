import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/familientage.dart';

/// Familientage: was der Stammbaum über heute weiss.
void main() {
  final heute = DateTime(2026, 10, 8, 14, 30);

  Familienmitglied person(String id, {DateTime? geburt, DateTime? tod}) =>
      (id: id, geburtsdatum: geburt, sterbedatum: tod);

  List<Familientag> rechne(
    List<Familienmitglied> personen, {
    List<Hochzeit> hochzeiten = const [],
    DateTime? am,
  }) => familientage(
    personen: personen,
    hochzeiten: hochzeiten,
    heute: am ?? heute,
  );

  test('ein Geburtstag heute, mit dem Alter, das jemand wird', () {
    final t = rechne([person('a', geburt: DateTime(1980, 10, 8))]).single;
    expect(t.art, Familientagart.geburtstag);
    expect(t.jahre, 46);
    expect(t.inTagen, 0);
    expect(t.verstorben, isFalse);
  });

  test('wer gestorben ist, „wäre geworden"; dazu sein Todestag', () {
    final tage = rechne([
      person('oma', geburt: DateTime(1926, 10, 10), tod: DateTime(2010, 10, 9)),
    ]);
    expect(tage, hasLength(2));
    final todestag = tage.first;
    expect(todestag.art, Familientagart.todestag);
    expect(todestag.inTagen, 1);
    expect(todestag.jahre, 16);
    final geburtstag = tage.last;
    expect(geburtstag.art, Familientagart.geburtstag);
    expect(geburtstag.jahre, 100);
    expect(geburtstag.verstorben, isTrue);
    expect(geburtstag.rund, isTrue);
  });

  test('nur der Vorausblick: in acht Tagen ist zu weit', () {
    expect(rechne([person('a', geburt: DateTime(1980, 10, 15))]), hasLength(1));
    expect(rechne([person('a', geburt: DateTime(1980, 10, 16))]), isEmpty);
    expect(rechne([person('a', geburt: DateTime(1980, 10, 7))]), isEmpty);
  });

  test('über den Jahreswechsel: am 28.12. sieht man den 2.1.', () {
    final t = rechne([
      person('a', geburt: DateTime(1990, 1, 2)),
    ], am: DateTime(2026, 12, 28)).single;
    expect(t.inTagen, 5);
    expect(t.jahre, 37);
  });

  test('am 29. Februar Geborene feiern in Gemeinjahren am 28.', () {
    final t = rechne([
      person('a', geburt: DateTime(2000, 2, 29)),
    ], am: DateTime(2027, 2, 28)).single;
    expect(t.inTagen, 0);
    expect(t.jahre, 27);
    expect(
      rechne([
        person('a', geburt: DateTime(2000, 2, 29)),
      ], am: DateTime(2028, 2, 28)).single.inTagen,
      1,
    );
  });

  test('wer vor drei Tagen geboren ist, hat noch keinen Geburtstag', () {
    expect(rechne([person('baby', geburt: DateTime(2026, 10, 5))]), isEmpty);
    // Und auch nicht am Tag der Geburt selbst.
    expect(rechne([person('baby', geburt: DateTime(2026, 10, 8))]), isEmpty);
  });

  test('eine Hochzeit, bei beiden Partnern eingetragen, zählt einmal', () {
    final datum = DateTime(2001, 10, 12);
    final tage = rechne(
      [],
      hochzeiten: [
        (datum: datum, personId: 'a', partnerId: 'b'),
        (datum: datum, personId: 'b', partnerId: 'a'),
      ],
    );
    expect(tage, hasLength(1));
    expect(tage.single.art, Familientagart.hochzeitstag);
    expect(tage.single.personen.toSet(), {'a', 'b'});
    expect(tage.single.jahre, 25);
    expect(tage.single.rund, isTrue, reason: 'Silberhochzeit');
  });

  test('sortiert: früher zuerst, am selben Tag runde zuerst', () {
    final tage = rechne([
      person('morgen', geburt: DateTime(1981, 10, 9)),
      person('heute', geburt: DateTime(1983, 10, 8)),
      person('rund', geburt: DateTime(1986, 10, 8)),
    ]);
    expect(
      [for (final t in tage) t.personen.single],
      ['rund', 'heute', 'morgen'],
    );
  });

  test('über hundert Jahre alte Gedenktage nur, wenn sie rund sind', () {
    final ahn = person(
      'ahn',
      geburt: DateTime(1850, 10, 8),
      tod: DateTime(1919, 10, 9),
    );
    expect(rechne([ahn]), isEmpty, reason: '176 und 107 Jahre');
    final rund = rechne([ahn], am: DateTime(2050, 10, 8));
    expect([for (final t in rund) t.jahre], [200]);
  });
}
