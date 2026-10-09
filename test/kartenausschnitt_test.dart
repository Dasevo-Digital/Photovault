import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/map_clustering.dart';

/// Die Fotos im sichtbaren Kartenausschnitt.
typedef P = ({String id, double breite, double laenge, int tag});

void main() {
  final punkte = <P>[
    (id: 'hannover', breite: 52.37, laenge: 9.73, tag: 1),
    (id: 'venedig', breite: 45.44, laenge: 12.33, tag: 3),
    (id: 'harz', breite: 51.80, laenge: 10.60, tag: 2),
    (id: 'fidschi', breite: -17.7, laenge: 178.0, tag: 4),
    (id: 'samoa', breite: -13.8, laenge: -172.1, tag: 5),
  ];
  List<String> ids(Iterable<P> l) => [for (final p in l) p.id];
  List<P> suche(double s, double n, double w, double o) => imAusschnitt(
    punkte,
    sued: s,
    nord: n,
    west: w,
    ost: o,
    lage: (p) => (breite: p.breite, laenge: p.laenge),
    wann: (p) => DateTime(2026, 1, p.tag),
  );

  test('Norddeutschland: nur was darin liegt, jüngstes zuerst', () {
    expect(ids(suche(50, 54, 8, 12)), ['harz', 'hannover']);
  });

  test('über die Datumsgrenze: Westrand östlich vom Ostrand', () {
    expect(ids(suche(-20, -10, 170, -170)), ['samoa', 'fidschi']);
  });

  test('leerer Ausschnitt', () {
    expect(suche(60, 70, 20, 30), isEmpty);
  });
}
