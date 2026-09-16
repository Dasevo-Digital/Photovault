import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/gpx.dart';

/// GPX einlesen und Aufnahmen nachträglich verorten.
///
/// Der Gewinn liegt nicht bei den Wanderungen, sondern hier: An der
/// echten Bibliothek tragen nur 1092 von 7988 Aufnahmen eine Koordinate.
/// Ob ein Foto dabei an der richtigen Stelle landet, ist eine Rechnung
/// und keine Ansichtssache.
void main() {
  String gpx(String inneres) =>
      '<?xml version="1.0"?><gpx version="1.1"><trk><trkseg>$inneres'
      '</trkseg></trk></gpx>';

  String punkt(double b, double l, String? zeit, {double? hoehe}) =>
      '<trkpt lat="$b" lon="$l">'
      '${hoehe == null ? '' : '<ele>$hoehe</ele>'}'
      '${zeit == null ? '' : '<time>$zeit</time>'}'
      '</trkpt>';

  group('Einlesen', () {
    test('liest Punkte mit Zeitstempel', () {
      final spur = liesGpx(gpx(
        '${punkt(52.5, 13.4, '2024-06-03T09:00:00Z')}'
        '${punkt(52.6, 13.5, '2024-06-03T10:00:00Z')}',
      ));
      expect(spur, hasLength(2));
      expect(spur.first.breite, closeTo(52.5, 0.001));
      expect(spur.first.zeit, DateTime.utc(2024, 6, 3, 9));
    });

    test('sortiert nach Zeit', () {
      final spur = liesGpx(gpx(
        '${punkt(52.6, 13.5, '2024-06-03T10:00:00Z')}'
        '${punkt(52.5, 13.4, '2024-06-03T09:00:00Z')}',
      ));
      expect(spur.first.zeit.hour, 9);
    });

    test('rechnet Ortszeit in UTC um', () {
      // Eine Spur mit Zonenangabe – manche Geraete schreiben sie.
      final spur = liesGpx(gpx(punkt(52.5, 13.4, '2024-06-03T11:00:00+02:00')));
      expect(spur.single.zeit, DateTime.utc(2024, 6, 3, 9));
    });

    test('nimmt auch Routen- und Wegpunkte', () {
      // Welches Programm welche Art schreibt, ist nicht vorherzusehen.
      final spur = liesGpx('<?xml version="1.0"?><gpx>'
          '<wpt lat="1" lon="2"><time>2024-06-03T09:00:00Z</time></wpt>'
          '<rte><rtept lat="3" lon="4">'
          '<time>2024-06-03T10:00:00Z</time></rtept></rte>'
          '</gpx>');
      expect(spur, hasLength(2));
    });

    test('Punkte ohne Zeit fallen weg, der Rest bleibt', () {
      final spur = liesGpx(gpx(
        '${punkt(52.5, 13.4, '2024-06-03T09:00:00Z')}${punkt(52.6, 13.5, null)}',
      ));
      expect(spur, hasLength(1));
    });

    test('eine Spur ganz ohne Zeitstempel wird abgelehnt', () {
      // Ohne Zeit laesst sich nichts zuordnen; die Spur waere nur eine
      // Linie. Das gehoert gesagt, nicht stillschweigend uebergangen.
      expect(
          () => liesGpx(gpx(punkt(52.5, 13.4, null))),
          throwsA(isA<GpxFehler>()
              .having((e) => e.grund, 'grund', GpxAbbruch.ohneZeit)));
    });

    test('eine leere Datei wird abgelehnt', () {
      expect(
          () => liesGpx('<?xml version="1.0"?><gpx></gpx>'),
          throwsA(isA<GpxFehler>()
              .having((e) => e.grund, 'grund', GpxAbbruch.leer)));
    });

    test('etwas anderes als GPX wird abgelehnt', () {
      expect(
          () => liesGpx('<?xml version="1.0"?><html><body/></html>'),
          throwsA(isA<GpxFehler>()
              .having((e) => e.grund, 'grund', GpxAbbruch.keinGpx)));
      expect(
          () => liesGpx('Das ist ein Brief.'),
          throwsA(isA<GpxFehler>()
              .having((e) => e.grund, 'grund', GpxAbbruch.keinGpx)));
    });
  });

  group('Ort zur Zeit', () {
    // Zehn Minuten Abstand – so zeichnen Geraete wirklich auf. Eine
    // ganze Stunde laege ueber [gpxHoechsteLuecke], und dazwischen wird
    // absichtlich nicht gerechnet.
    final spur = liesGpx(gpx(
      '${punkt(52.0, 13.0, '2024-06-03T09:00:00Z')}'
      '${punkt(52.2, 13.0, '2024-06-03T09:10:00Z')}',
    ));

    test('trifft einen Punkt genau', () {
      final ort = ortZurZeit(spur, DateTime.utc(2024, 6, 3, 9))!;
      expect(ort.breite, closeTo(52.0, 0.0001));
    });

    test('rechnet dazwischen linear', () {
      // Eine Annahme, aber die einzige, die eine Aufzeichnung zulaesst.
      final ort = ortZurZeit(spur, DateTime.utc(2024, 6, 3, 9, 5))!;
      expect(ort.breite, closeTo(52.1, 0.0001));
    });

    test('ueber eine grosse Luecke wird nicht gerechnet', () {
      // Bei einer laengeren Luecke stand das Geraet still oder hatte
      // keinen Empfang – dazwischen zu rechnen hiesse, eine Bewegung zu
      // erfinden, die niemand aufgezeichnet hat.
      final weit = liesGpx(gpx(
        '${punkt(52.0, 13.0, '2024-06-03T09:00:00Z')}'
        '${punkt(48.0, 11.0, '2024-06-03T15:00:00Z')}',
      ));
      expect(ortZurZeit(weit, DateTime.utc(2024, 6, 3, 12)), isNull);
    });

    test('kurz vor dem Start und kurz nach dem Ende zaehlt noch', () {
      expect(ortZurZeit(spur, DateTime.utc(2024, 6, 3, 8, 57)), isNotNull);
      expect(ortZurZeit(spur, DateTime.utc(2024, 6, 3, 9, 13)), isNotNull);
    });

    test('weit davor und weit danach nicht mehr', () {
      expect(ortZurZeit(spur, DateTime.utc(2024, 6, 3, 8)), isNull);
      expect(ortZurZeit(spur, DateTime.utc(2024, 6, 3, 12)), isNull);
    });

    test('eine leere Spur liefert nichts statt zu werfen', () {
      expect(ortZurZeit(const [], DateTime.utc(2024)), isNull);
    });
  });

  group('Der Zeitversatz', () {
    // Eine Spur von 09:00 bis 11:00 UTC, alle zehn Minuten ein Punkt.
    final spur = liesGpx(gpx([
      for (var m = 0; m <= 120; m += 10)
        punkt(52.0 + m / 1000, 13.0,
            DateTime.utc(2024, 6, 3, 9).add(Duration(minutes: m))
                .toIso8601String()),
    ].join()));

    test('findet die Zeitzone, die die meisten Fotos trifft', () {
      // EXIF schreibt ohne Zeitzone, GPX schreibt UTC. Die Kamera stand
      // hier auf MESZ, also zwei Stunden vor.
      final zeiten = [
        for (var m = 0; m <= 120; m += 15)
          DateTime.utc(2024, 6, 3, 11).add(Duration(minutes: m)),
      ];
      expect(besterVersatz(spur, zeiten), const Duration(hours: -2));
    });

    test('findet auch eine falsch gehende Kamerauhr', () {
      // Er ist nicht immer die Zeitzone: Eine Uhr, die seit zwei Jahren
      // falsch geht, verschiebt alles um denselben Betrag.
      final zeiten = [
        for (var m = 0; m <= 120; m += 15)
          DateTime.utc(2024, 6, 3, 9, 30).add(Duration(minutes: m)),
      ];
      expect(besterVersatz(spur, zeiten), const Duration(minutes: -30));
    });

    test('ohne jeden Treffer bleibt es beim Nullversatz', () {
      // Ein Vorschlag von "irgendwas" waere schlechter als keiner.
      expect(
          besterVersatz(spur, [DateTime.utc(2020, 1, 1)]), Duration.zero);
    });

    test('bei Gleichstand gewinnt der kleinere Versatz', () {
      // Wenn zwei Erklaerungen gleich viele Fotos treffen, ist die
      // harmlosere die wahrscheinlichere.
      expect(besterVersatz(spur, [DateTime.utc(2024, 6, 3, 10)]),
          Duration.zero);
    });
  });

  group('Verorten', () {
    // Zehn Minuten Abstand – so zeichnen Geraete wirklich auf. Eine
    // ganze Stunde laege ueber [gpxHoechsteLuecke], und dazwischen wird
    // absichtlich nicht gerechnet.
    final spur = liesGpx(gpx(
      '${punkt(52.0, 13.0, '2024-06-03T09:00:00Z')}'
      '${punkt(52.2, 13.0, '2024-06-03T09:10:00Z')}',
    ));

    test('ordnet zu, was sich zuordnen laesst', () {
      final ergebnis = verorteAusSpur(spur, [
        (id: 'passt', zeit: DateTime.utc(2024, 6, 3, 9, 5)),
        (id: 'passt nicht', zeit: DateTime.utc(2024, 6, 3, 20)),
      ]);
      expect(ergebnis, hasLength(1));
      expect(ergebnis.single.assetId, 'passt');
      expect(ergebnis.single.breite, closeTo(52.1, 0.0001));
    });

    test('der Versatz wird angewandt', () {
      final ergebnis = verorteAusSpur(
        spur,
        [(id: 'a', zeit: DateTime.utc(2024, 6, 3, 11, 5))],
        versatz: const Duration(hours: -2),
      );
      expect(ergebnis, hasLength(1));
    });
  });

  group('Die Höhe', () {
    test('wird gelesen, wo sie dasteht', () {
      // Bis zu dieser Stufe wurde `<ele>` gelesen und weggeworfen.
      final spur = liesGpx(gpx(
        '${punkt(52.5, 13.4, '2024-06-03T09:00:00Z', hoehe: 340.5)}'
        '${punkt(52.6, 13.5, '2024-06-03T10:00:00Z')}',
      ));
      expect(spur.first.hoehe, closeTo(340.5, 0.01));
      // Und wo sie fehlt, steht null – keine erfundene Null, die wie
      // eine Messung aussähe.
      expect(spur.last.hoehe, isNull);
    });

    test('alle Punkte, auch die ohne Zeit', () {
      // Für die Linie und das Profil taugt auch ein Punkt ohne Zeit; nur
      // zum Zuordnen von Fotos taugt er nicht.
      final alle = liesGpxPunkte(gpx(
        '${punkt(52.5, 13.4, null, hoehe: 100)}'
        '${punkt(52.6, 13.5, '2024-06-03T10:00:00Z', hoehe: 200)}',
      ));
      expect(alle, hasLength(2));
      expect(alle.first.zeit, isNull);
      expect(alle.first.hoehe, 100);
      // liesGpx sieht davon nur einen.
      expect(
          liesGpx(gpx(
            '${punkt(52.5, 13.4, null, hoehe: 100)}'
            '${punkt(52.6, 13.5, '2024-06-03T10:00:00Z', hoehe: 200)}',
          )),
          hasLength(1));
    });

    test('die Reihenfolge der Datei bleibt', () {
      // Für eine Linie ist die aufgezeichnete Folge die Aussage – anders
      // als beim Zuordnen, wo nach Zeit sortiert wird.
      final alle = liesGpxPunkte(gpx(
        '${punkt(52.6, 13.5, '2024-06-03T10:00:00Z')}'
        '${punkt(52.5, 13.4, '2024-06-03T09:00:00Z')}',
      ));
      expect(alle.first.breite, closeTo(52.6, 0.001));
    });

    test('eine Datei ganz ohne Punkte bleibt ein Fehler', () {
      expect(() => liesGpxPunkte(gpx('')),
          throwsA(isA<GpxFehler>()));
    });
  });

  group('Die Länge einer Spur', () {
    test('ist die Summe der Luftlinien', () {
      // Vier Punkte im Abstand von je einem Kilometer nach Osten.
      final punkte = [
        for (var i = 0; i < 4; i++)
          (breite: 52.37, laenge: 9.73 + i / 68.0),
      ];
      expect(spurlaengeKm(punkte), closeTo(3.0, 0.1));
    });

    test('ohne Glättung – sonst verschwände jede Serpentine', () {
      // Ein Zickzack aus zehn Metern hin und her: bei den Aktivitäten
      // wird so etwas geglättet, hier nicht. Eine Aufzeichnung ist eine
      // Folge gemessener Punkte, keine Sammlung zufällig benachbarter
      // Fotos.
      final zickzack = [
        for (var i = 0; i < 20; i++)
          (breite: 52.37 + (i.isEven ? 0.0001 : -0.0001), laenge: 9.73),
      ];
      expect(spurlaengeKm(zickzack), greaterThan(0.3));
    });

    test('ein einzelner Punkt hat keine Länge', () {
      expect(spurlaengeKm([(breite: 52.37, laenge: 9.73)]), 0);
      expect(spurlaengeKm(const []), 0);
    });
  });

  group('Auf- und Abstieg', () {
    test('hundert Meter hinauf und wieder hinunter', () {
      // Eine Länge, wie eine Aufzeichnung sie hat: zwanzig Punkte
      // hinauf, ein kurzes Stück oben, zwanzig hinunter. An einem
      // einzelnen Gipfelpunkt kostete das Glätten Meter – an einem
      // Grat, den man ein paar Punkte lang geht, nicht.
      final wanderung = [
        for (var i = 0; i <= 20; i++) 100.0 + i * 5,
        for (var i = 0; i < 5; i++) 200.0,
        for (var i = 20; i >= 0; i--) 100.0 + i * 5,
      ];
      // Das Glätten kostet an scharfen Knicken ein paar Meter – hier
      // drei von hundert. Das ist der Preis dafür, dass eine flache
      // Runde nicht hundert erfundene Höhenmeter bekommt.
      final bilanz = hoehenbilanz(wanderung);
      expect(bilanz.aufstieg, closeTo(100, 5));
      expect(bilanz.abstieg, closeTo(100, 5));
    });

    test('das Rauschen einer flachen Runde zählt nicht', () {
      // **Der Grund für Glättung UND Schwelle.** Ein Gerät, das um ±3 m
      // schwankt, springt zwischen zwei Messungen um 6 m – über der
      // Schwelle von 5. Die Schwelle allein fängt es also nicht; erst
      // das Mitteln nimmt dem Rauschen die Spitzen.
      final rauschen = [
        for (var i = 0; i < 60; i++) 100.0 + (i.isEven ? 3.0 : -3.0),
      ];
      final bilanz = hoehenbilanz(rauschen);
      // Nicht null, sondern klein: An den beiden Enden ist das Fenster
      // kurz, dort bleibt ein Rest. Sechs Meter auf einer Stunde flacher
      // Runde sind ehrlich; hundert wären eine Behauptung.
      expect(bilanz.aufstieg, lessThan(10));
      expect(bilanz.abstieg, lessThan(10));

      // Die Gegenprobe: ohne Glättung summiert dieselbe flache Runde
      // über hundert Höhenmeter, die es nie gab.
      expect(hoehenbilanz(rauschen, glaettung: 1).aufstieg,
          greaterThan(100));
      // Und ohne beides das Doppelte davon.
      expect(hoehenbilanz(rauschen, glaettung: 1, schwelle: 0).aufstieg,
          greaterThan(150));
    });

    test('das Glätten kürzt eine gleichmässige Steigung nicht', () {
      // Ein symmetrisch schrumpfendes Fenster lässt die Enden stehen und
      // ändert auf einer Geraden gar nichts.
      final rampe = [for (var i = 0; i <= 20; i++) 100.0 + i * 10];
      expect(geglaetteteHoehen(rampe), rampe);
    });

    test('ein Anstieg in kleinen Schritten geht nicht verloren', () {
      // Zwanzigmal je zehn Meter: jeder Schritt über der Schwelle, also
      // zweihundert Meter Aufstieg – weder Hysterese noch Glättung
      // dürfen kürzen.
      final treppe = [for (var i = 0; i <= 20; i++) 100.0 + i * 10];
      expect(hoehenbilanz(treppe).aufstieg, closeTo(200, 0.01));
      expect(hoehenbilanz(treppe).abstieg, 0);
    });

    test('Punkte ohne Höhe werden übersprungen, nicht genullt', () {
      // Eine fehlende Höhe als Null zu lesen ergäbe einen Absturz auf
      // Meereshöhe und einen Wiederaufstieg. Hier ohne Glättung, damit
      // der Test nur diese eine Sache prüft.
      final bilanz =
          hoehenbilanz([100.0, null, 150.0, null, 100.0], glaettung: 1);
      expect(bilanz.aufstieg, closeTo(50, 0.01));
      expect(bilanz.abstieg, closeTo(50, 0.01));
      // Genullt käme ein Absturz auf 0 und ein Aufstieg auf 150 heraus.
      expect(hoehenbilanz([100.0, 0.0, 150.0, 0.0, 100.0], glaettung: 1).abstieg,
          greaterThan(200));
    });

    test('ganz ohne Höhen kommt null heraus', () {
      final bilanz = hoehenbilanz([null, null]);
      expect(bilanz.aufstieg, 0);
      expect(bilanz.abstieg, 0);
    });
  });

  group('Die Kennzahlen einer Spur', () {
    List<Rohpunkt> spur({bool mitHoehe = true, bool mitZeit = true}) => [
          for (var i = 0; i < 5; i++)
            (
              zeit: mitZeit
                  ? DateTime.utc(2024, 6, 3, 9).add(Duration(minutes: i * 10))
                  : null,
              breite: 52.37,
              laenge: 9.73 + i / 68.0,
              hoehe: mitHoehe ? 100.0 + i * 20 : null,
            ),
        ];

    test('Zeitraum, Punktzahl und Länge', () {
      final z = spurkennzahlen(spur());
      expect(z.punktzahl, 5);
      expect(z.laengeKm, closeTo(4.0, 0.2));
      expect(z.von, DateTime.utc(2024, 6, 3, 9));
      expect(z.bis, DateTime.utc(2024, 6, 3, 9, 40));
    });

    test('ohne Zeitstempel bleibt der Zeitraum leer statt geraten', () {
      // Eine geplante Route hat keine Zeit. Ein erfundener Zeitraum wäre
      // eine Behauptung über einen Tag, an dem niemand unterwegs war.
      final z = spurkennzahlen(spur(mitZeit: false));
      expect(z.von, isNull);
      expect(z.bis, isNull);
      expect(z.punktzahl, 5);
    });

    test('ohne Höhen ist der Aufstieg null – und das heisst nicht „flach"',
        () {
      // Null Meter Aufstieg und „keine Höhenangabe" sind zweierlei: das
      // eine ist eine flache Runde, das andere ein Gerät ohne Barometer.
      expect(spurkennzahlen(spur(mitHoehe: false)).aufstieg, isNull);
      expect(spurkennzahlen(spur()).aufstieg, isNotNull);
    });
  });

  group('Das Höhenprofil', () {
    test('trägt die Strecke auf, nicht die Zeit', () {
      // Drei Punkte im Kilometerabstand.
      final profil = profilpunkte([
        for (var i = 0; i < 4; i++)
          (breite: 52.37, laenge: 9.73 + i / 68.0, hoehe: 100.0 + i * 10),
      ]);
      expect(profil, hasLength(4));
      expect(profil.first.km, 0);
      expect(profil.last.km, closeTo(3.0, 0.2));
      expect(profil.last.hoehe, 130);
    });

    test('ein Loch in den Höhen ist kein Loch im Weg', () {
      // Der Punkt ohne Höhe fällt aus dem Profil – seine Strecke zählt
      // trotzdem, sonst rückte alles danach zusammen.
      final profil = profilpunkte([
        (breite: 52.37, laenge: 9.73, hoehe: 100),
        (breite: 52.37, laenge: 9.73 + 1 / 68.0, hoehe: null),
        (breite: 52.37, laenge: 9.73 + 2 / 68.0, hoehe: 120),
      ]);
      expect(profil, hasLength(2));
      expect(profil.last.km, closeTo(2.0, 0.2));
    });

    test('jeder Profilpunkt weiss, welcher Spurpunkt er war', () {
      // Daran hängt die Marke auf der Karte: Der Index des Profils ist
      // nicht der Index der Spur.
      final profil = profilpunkte([
        (breite: 52.37, laenge: 9.73, hoehe: null),
        (breite: 52.37, laenge: 9.74, hoehe: 100),
        (breite: 52.37, laenge: 9.75, hoehe: 110),
      ]);
      expect(profil.map((p) => p.index), [1, 2]);
    });

    test('ganz ohne Höhen bleibt das Profil leer', () {
      expect(
          profilpunkte([
            (breite: 52.37, laenge: 9.73, hoehe: null),
            (breite: 52.37, laenge: 9.74, hoehe: null),
          ]),
          isEmpty);
    });
  });
}
