import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/gelaendeflug.dart';
import 'package:photo_vault/services/gelaendesicht.dart';

/// **Der Flug über die Spur.**
///
/// Die Geländeansicht zeigte die Spur schon immer als Linie im Raum, die
/// Kamera stand aber still. Diese Prüfungen halten das fest, was man beim
/// Bauen eines Kamerawegs leicht falsch macht – und was man am fertigen
/// Bild nicht mehr sieht, sondern nur noch als „irgendwie ruckelig".
void main() {
  /// Eine gerade Spur nach Norden, 1000 m lang, mit ungleichen
  /// Abständen: dicht am Anfang, weit in der Mitte.
  Gelaendeflug geradeNachNorden() => Gelaendeflug([
        (x: 0, y: 0, z: 0),
        (x: 0, y: 10, z: 0),
        (x: 0, y: 20, z: 0),
        (x: 0, y: 500, z: 0),
        (x: 0, y: 1000, z: 0),
      ], glaettung: 50);

  group('Der Weg', () {
    test('die Länge ist die waagerechte Strecke', () {
      final flug = Gelaendeflug([
        (x: 0, y: 0, z: 0),
        (x: 300, y: 400, z: 9999),
      ]);
      // 3-4-5, und die Höhe zählt bewusst nicht mit: Sie steckt schon
      // mit der Überhöhung multipliziert im z.
      expect(flug.laengeMeter, closeTo(500, 0.001));
    });

    test('abgetastet wird nach Metern, nicht nach Punkten', () {
      final flug = geradeNachNorden();
      // Bei der Hälfte des Weges liegt y=500 – der VIERTE von fünf
      // Punkten. Liefe der Fortschritt über den Index, stünde die
      // Kamera hier bei y=20.
      expect(flug.bei(0.5).blickpunkt.y, closeTo(500, 0.001));
      expect(flug.bei(0.25).blickpunkt.y, closeTo(250, 0.001));
    });

    test('Anfang und Ende liegen genau auf der Spur', () {
      final flug = geradeNachNorden();
      expect(flug.bei(0).blickpunkt.y, 0);
      expect(flug.bei(1).blickpunkt.y, 1000);
    });

    test('ein Fortschritt ausserhalb 0..1 fällt auf die Enden', () {
      final flug = geradeNachNorden();
      expect(flug.bei(-3).blickpunkt.y, 0);
      expect(flug.bei(7).blickpunkt.y, 1000);
    });

    test('zwischen zwei Stützpunkten wird gemittelt, auch in der Höhe', () {
      final flug = Gelaendeflug([
        (x: 0, y: 0, z: 100),
        (x: 0, y: 100, z: 300),
      ]);
      final mitte = flug.bei(0.5).blickpunkt;
      expect(mitte.y, closeTo(50, 0.001));
      expect(mitte.z, closeTo(200, 0.001));
    });
  });

  group('Die Blickrichtung', () {
    /// Der Kern des Ganzen: Die Kamera muss so gedreht stehen, dass die
    /// Laufrichtung IN das Bild zeigt. `projiziere` schiebt die Richtung
    /// (sin d, cos d) in die Tiefe – dieser Test prüft das nicht am
    /// Winkel, sondern am Ergebnis, damit ein Vorzeichenfehler nicht
    /// durch zwei zueinander passende Irrtümer verdeckt wird.
    void erwarteVorausLiegtHinten(Gelaendeflug flug, double fortschritt) {
      final stand = flug.bei(fortschritt);
      final kamera = Gelaendekamera(
        drehung: stand.drehung,
        neigung: 1.2,
        entfernung: 500,
        brennweite: 800,
        mitte: const Offset(400, 300),
        blickpunkt: stand.blickpunkt,
      );
      final hier = kamera.projiziere(stand.blickpunkt);
      final voraus = kamera.projiziere(
          flug.punktBei(stand.gefahrenMeter + flug.laengeMeter * 0.1));
      expect(voraus.tiefe, greaterThan(hier.tiefe),
          reason: 'was vor mir liegt, muss weiter weg sein als ich');
    }

    test('nach Norden: die Strecke voraus liegt tiefer im Bild', () {
      erwarteVorausLiegtHinten(geradeNachNorden(), 0.3);
    });

    test('nach Osten ebenso', () {
      erwarteVorausLiegtHinten(
          Gelaendeflug([(x: 0, y: 0, z: 0), (x: 1000, y: 0, z: 0)]), 0.3);
    });

    test('nach Südwesten ebenso', () {
      erwarteVorausLiegtHinten(
          Gelaendeflug([(x: 0, y: 0, z: 0), (x: -700, y: -700, z: 0)]), 0.3);
    });

    test('nach Norden ist die Drehung null', () {
      // Die Blickrichtung (sin 0, cos 0) = (0, 1) ist Norden, und die
      // Kamera steht damit im Süden – dieselbe Vorgabe wie bei der
      // Handbedienung.
      expect(geradeNachNorden().bei(0.5).drehung, closeTo(0, 1e-9));
    });

    test('nach Osten ist sie ein rechter Winkel', () {
      final flug = Gelaendeflug([(x: 0, y: 0, z: 0), (x: 1000, y: 0, z: 0)]);
      expect(flug.bei(0.5).drehung, closeTo(math.pi / 2, 1e-9));
    });
  });

  group('Die Glättung', () {
    /// **Der Grund, warum es sie gibt.** Aufeinanderfolgende GPX-Punkte
    /// liegen wenige Meter auseinander, und genau so gross ist die
    /// Ungenauigkeit eines Geräts. Ohne Glättung folgte die Kamera dem
    /// Rauschen und nicht dem Weg.
    List<Raumpunkt> zickzack() => [
          for (var i = 0; i <= 200; i++)
            (x: (i.isEven ? 8.0 : -8.0), y: i * 10.0, z: 0)
        ];

    double groessterSprung(Gelaendeflug flug) {
      var groesst = 0.0;
      var vorher = flug.bei(0).drehung;
      for (var i = 1; i <= 400; i++) {
        final jetzt = flug.bei(i / 400).drehung;
        var d = (jetzt - vorher).abs();
        if (d > math.pi) d = 2 * math.pi - d;
        groesst = math.max(groesst, d);
        vorher = jetzt;
      }
      return groesst;
    }

    test('ein Zickzack reisst die Kamera nicht herum', () {
      final roh = Gelaendeflug(zickzack(), blickglaettung: 0.01);
      final glatt = Gelaendeflug(zickzack(), blickglaettung: 150);
      // Gemessen: 0,91 gegen 0,04 Bogenmass je Vierhundertstel Flug.
      expect(groessterSprung(roh), greaterThan(0.5),
          reason: 'ohne Glättung schlägt die Richtung wirklich aus');
      expect(groessterSprung(glatt), lessThan(0.1),
          reason: 'mit Glättung bleibt der Blick auf dem Weg');
    });

    /// **Eine Kehre, und sie ist der Fall, an dem das Zickzack vorbeisah.**
    ///
    /// Ein Zickzack schwankt um eine Richtung; eine Serpentine **kehrt
    /// um**. Wer dafür die Sehne über das Glättungsfenster nimmt – von
    /// 120 Meter zurück nach 120 Meter voraus –, bekommt an der Spitze
    /// zwei Enden, die fast aufeinanderliegen: Die Sehne wird kurz, und
    /// ihre Richtung ist dann nicht mehr die Bewegung, sondern das
    /// Rauschen. An der echten Spur durchs Ilsetal waren das 4783 Grad
    /// je Sekunde – die Kamera schlug in einem Bild um.
    List<Raumpunkt> kehre() => [
          for (var i = 0; i <= 60; i++) (x: 0, y: i * 10.0, z: 0),
          for (var i = 1; i <= 60; i++) (x: i * 10.0 * 0.17, y: 600 - i * 10.0, z: 0),
        ];

    test('eine Kehre wird ein Bogen, kein Umschlag', () {
      final flug = Gelaendeflug(kehre());
      expect(groessterSprung(flug), lessThan(0.1),
          reason: 'die Kamera dreht durch die Kehre, sie schlägt nicht um');
      // Und sie dreht wirklich um: Ein Blick, der einfach stehen bleibt,
      // wäre ruhig und falsch.
      final anfang = flug.bei(0.05).drehung;
      final ende = flug.bei(0.95).drehung;
      expect((ende - anfang).abs(), greaterThan(2.0),
          reason: 'am Ende geht es zurück, das muss sich zeigen');
    });

    test('mit kurzem Fenster schlaegt dieselbe Kehre um', () {
      // Die Gegenprobe: Ohne die breite Glättung ist der Ruck da.
      final flug = Gelaendeflug(kehre(), blickglaettung: 0.01);
      // Gemessen: 0,66 gegen 0,07 mit der vollen Glättung.
      expect(groessterSprung(flug), greaterThan(0.5));
    });

    test('am Anfang rutscht das Fenster nach innen, statt zu schrumpfen', () {
      // Sonst wäre die Richtung ausgerechnet beim Start am unruhigsten,
      // weil sie dort nur aus einem halben Fenster käme.
      final flug = Gelaendeflug(zickzack(), blickglaettung: 150);
      final start = flug.bei(0).drehung;
      final gleichDanach = flug.bei(0.01).drehung;
      expect((start - gleichDanach).abs(), lessThan(0.2));
    });

    test('eine Glättung länger als die Spur bricht nichts', () {
      final flug = Gelaendeflug(
          [(x: 0, y: 0, z: 0), (x: 0, y: 30, z: 0)],
          glaettung: 5000, blickglaettung: 5000);
      expect(flug.bei(0.5).drehung, closeTo(0, 1e-9));
    });
  });

  group('Die Grenzfälle, an denen so etwas stirbt', () {
    test('eine leere Spur', () {
      final flug = Gelaendeflug(const []);
      expect(flug.moeglich, isFalse);
      expect(flug.laengeMeter, 0);
      expect(flug.bei(0.5).blickpunkt, Gelaendekamera.nullpunkt);
    });

    test('ein einzelner Punkt', () {
      final flug = Gelaendeflug([(x: 5, y: 7, z: 9)]);
      expect(flug.moeglich, isFalse);
      expect(flug.bei(0.5).blickpunkt, (x: 5.0, y: 7.0, z: 9.0));
    });

    test('eine Spur, die auf der Stelle aufgezeichnet wurde', () {
      // Kommt wirklich vor: Ein Gerät, das im Rucksack lag. Es darf
      // keine Division durch null geben und keinen Flug zu nichts.
      final flug = Gelaendeflug(
          List.filled(50, (x: 100.0, y: 200.0, z: 3.0)));
      expect(flug.moeglich, isFalse);
      expect(flug.bei(0.4).drehung, 0);
      expect(flug.bei(0.4).blickpunkt, (x: 100.0, y: 200.0, z: 3.0));
    });

    test('doppelte Punkte mittendrin ergeben keine NaN', () {
      final flug = Gelaendeflug([
        (x: 0, y: 0, z: 0),
        (x: 0, y: 100, z: 0),
        (x: 0, y: 100, z: 0),
        (x: 0, y: 200, z: 0),
      ]);
      for (var i = 0; i <= 20; i++) {
        final stand = flug.bei(i / 20);
        expect(stand.blickpunkt.y.isNaN, isFalse);
        expect(stand.drehung.isNaN, isFalse);
      }
    });
  });

  group('Dauer und Abstand', () {
    test('die Dauer wächst mit der Länge', () {
      final kurz = Gelaendeflug([(x: 0, y: 0, z: 0), (x: 0, y: 3000, z: 0)]);
      final lang = Gelaendeflug([(x: 0, y: 0, z: 0), (x: 0, y: 30000, z: 0)]);
      expect(lang.dauerBei(300).inSeconds,
          greaterThan(kurz.dauerBei(300).inSeconds));
    });

    test('sie bleibt zwischen zehn Sekunden und drei Minuten', () {
      final winzig = Gelaendeflug([(x: 0, y: 0, z: 0), (x: 0, y: 20, z: 0)]);
      final riesig =
          Gelaendeflug([(x: 0, y: 0, z: 0), (x: 0, y: 900000, z: 0)]);
      expect(winzig.dauerBei(300).inSeconds, 10);
      expect(riesig.dauerBei(300).inSeconds, 180);
    });

    /// **Der Abstand richtet sich nach der Maschenweite.** Die erste
    /// Fassung nahm die Länge der Spur und setzte die Kamera auf ein paar
    /// hundert Meter. Am Bild waren daraufhin zwei graue Dreiecke zu
    /// sehen: Bei 96 Maschen über neun Kilometer ist eine Masche 94 m
    /// breit und aus 480 m Abstand 176 Bildpunkte gross.
    test('bei feinem Netz darf die Kamera näher heran', () {
      final grob = Gelaendeflug.flugabstand(
          ausdehnung: 9000, kante: 96, brennweite: 900);
      final fein = Gelaendeflug.flugabstand(
          ausdehnung: 9000, kante: 400, brennweite: 900);
      expect(fein, lessThan(grob));
    });

    test('eine Masche bleibt rund 30 Bildpunkte breit', () {
      const ausdehnung = 9000.0;
      const kante = 96;
      const brennweite = 900.0;
      final d = Gelaendeflug.flugabstand(
          ausdehnung: ausdehnung, kante: kante, brennweite: brennweite);
      final maschenpunkte = (ausdehnung / kante) * brennweite / d;
      expect(maschenpunkte, closeTo(30, 1));
    });

    test('der Abstand bleibt zwischen Flug und Übersicht', () {
      // Ein sehr grobes Netz triebe die Kamera sonst weiter weg als die
      // Übersicht, ein sehr feines mitten ins Gelände hinein.
      expect(
          Gelaendeflug.flugabstand(
              ausdehnung: 9000, kante: 4, brennweite: 900),
          9000 * 0.8);
      expect(
          Gelaendeflug.flugabstand(
              ausdehnung: 9000, kante: 5000, brennweite: 900),
          9000 * 0.15);
    });

    test('ein leeres Gelände ergibt keine Division durch null', () {
      expect(
          Gelaendeflug.flugabstand(ausdehnung: 0, kante: 96, brennweite: 900),
          0);
      expect(
          Gelaendeflug.flugabstand(
              ausdehnung: 9000, kante: 0, brennweite: 900),
          9000);
    });
  });

  group('Der Blickpunkt der Kamera', () {
    test('ohne Angabe kreist sie wie bisher um den Nullpunkt', () {
      const kamera = Gelaendekamera(
          drehung: 0.3,
          neigung: 0.9,
          entfernung: 1000,
          brennweite: 800,
          mitte: Offset(400, 300));
      // Der Nullpunkt landet in der Bildmitte – das war schon immer so
      // und darf sich für die Handbedienung nicht geändert haben.
      final mitte = kamera.projiziere(Gelaendekamera.nullpunkt);
      expect(mitte.stelle.dx, closeTo(400, 1e-9));
      expect(mitte.stelle.dy, closeTo(300, 1e-9));
    });

    test('mit Blickpunkt landet dieser in der Bildmitte', () {
      const kamera = Gelaendekamera(
        drehung: 0.3,
        neigung: 0.9,
        entfernung: 1000,
        brennweite: 800,
        mitte: Offset(400, 300),
        blickpunkt: (x: 1234.0, y: -567.0, z: 89.0),
      );
      final stelle = kamera.projiziere((x: 1234, y: -567, z: 89)).stelle;
      expect(stelle.dx, closeTo(400, 1e-9));
      expect(stelle.dy, closeTo(300, 1e-9));
    });

    test('das Verschieben dreht nichts – nur der Bezug wandert', () {
      const ohne = Gelaendekamera(
          drehung: 0.7,
          neigung: 1.1,
          entfernung: 900,
          brennweite: 700,
          mitte: Offset(0, 0));
      const mit = Gelaendekamera(
          drehung: 0.7,
          neigung: 1.1,
          entfernung: 900,
          brennweite: 700,
          mitte: Offset(0, 0),
          blickpunkt: (x: 50.0, y: 60.0, z: 70.0));
      final a = ohne.projiziere((x: 10, y: 20, z: 30));
      final b = mit.projiziere((x: 60, y: 80, z: 100));
      expect(b.stelle.dx, closeTo(a.stelle.dx, 1e-9));
      expect(b.stelle.dy, closeTo(a.stelle.dy, 1e-9));
      expect(b.tiefe, closeTo(a.tiefe, 1e-9));
    });
  });

  group('Die Messwerte', () {
    /// Eine Stunde bergauf: 3600 m Strecke, 360 Höhenmeter, gleichmässig.
    /// Also 1 m/s und 10 Prozent Steigung.
    Gelaendeflug bergauf() {
      final start = DateTime.utc(2026, 8, 30, 9);
      final spur = <Raumpunkt>[];
      final werte = <Flugwert>[];
      for (var i = 0; i <= 360; i++) {
        spur.add((x: 0, y: i * 10.0, z: i * 3.0));
        werte.add((
          hoehe: 500 + i * 1.0,
          zeit: start.add(Duration(seconds: i * 10)),
        ));
      }
      return Gelaendeflug(spur, werte: werte, glaettung: 120);
    }

    test('die Höhe ist die echte, nicht die überhöhte', () {
      final flug = bergauf();
      // Im z steckt die dreifache Überhöhung und die Verschiebung um den
      // Mittelwert. Wer die anzeigt, zeigt eine Zahl, die es nirgends
      // gibt.
      final stand = flug.bei(0.5);
      expect(stand.hoeheMeter, closeTo(680, 1));
      expect(stand.blickpunkt.z, closeTo(540, 1),
          reason: 'das z ist bewusst etwas anderes');
    });

    test('das Tempo kommt aus den Zeitstempeln', () {
      expect(bergauf().bei(0.5).tempoMeterJeSekunde, closeTo(1.0, 0.01));
    });

    test('die Steigung kommt aus der echten Höhe', () {
      expect(bergauf().bei(0.5).steigungProzent, closeTo(10.0, 0.1));
    });

    test('bergab ist die Steigung negativ', () {
      final start = DateTime.utc(2026);
      final flug = Gelaendeflug(
        [for (var i = 0; i <= 100; i++) (x: 0, y: i * 10.0, z: -i * 3.0)],
        werte: [
          for (var i = 0; i <= 100; i++)
            (hoehe: 1000 - i * 1.0, zeit: start.add(Duration(seconds: i * 5)))
        ],
      );
      expect(flug.bei(0.5).steigungProzent, lessThan(-5));
    });

    test('die verstrichene Zeit zählt ab dem ersten Punkt', () {
      final flug = bergauf();
      expect(flug.bei(0).seitStart, Duration.zero);
      expect(flug.bei(1).seitStart, const Duration(seconds: 3600));
      expect(flug.bei(0.5).seitStart!.inSeconds, closeTo(1800, 20));
    });

    test('ohne Werte bleiben die Zahlen leer statt falsch', () {
      final flug = Gelaendeflug(
          [(x: 0, y: 0, z: 0), (x: 0, y: 1000, z: 0)]);
      final stand = flug.bei(0.5);
      expect(stand.hoeheMeter, isNull);
      expect(stand.tempoMeterJeSekunde, isNull);
      expect(stand.steigungProzent, isNull);
      expect(stand.seitStart, isNull);
      // Der Flug selbst muss trotzdem gehen – eine geplante Route hat
      // weder Zeiten noch immer Höhen.
      expect(flug.moeglich, isTrue);
      expect(stand.blickpunkt.y, closeTo(500, 0.001));
    });

    test('eine Rast ergibt Tempo null und keine Division durch null', () {
      // Zwanzig Punkte an derselben Stelle, die Uhr läuft weiter. Genau
      // so sieht eine Mittagspause in einer GPX-Datei aus.
      final start = DateTime.utc(2026);
      final spur = <Raumpunkt>[];
      final werte = <Flugwert>[];
      for (var i = 0; i <= 100; i++) {
        final y = i < 40 ? i * 10.0 : (i < 60 ? 400.0 : (i - 20) * 10.0);
        spur.add((x: 0, y: y, z: 0));
        werte.add((hoehe: 700, zeit: start.add(Duration(seconds: i * 30))));
      }
      final flug = Gelaendeflug(spur, werte: werte, glaettung: 60);
      for (var i = 0; i <= 40; i++) {
        final stand = flug.bei(i / 40);
        expect(stand.tempoMeterJeSekunde?.isNaN ?? false, isFalse);
        expect(stand.tempoMeterJeSekunde ?? 0, greaterThanOrEqualTo(0));
      }
    });

    test('eine stehende Uhr ergibt kein Tempo statt unendlich', () {
      // Kommt in echten Dateien vor: Alle Punkte tragen denselben
      // Zeitstempel. Eine Division durch null gäbe hier `Infinity`, und
      // das stünde dann als Tempo auf dem Bildschirm.
      final fest = DateTime.utc(2026);
      final flug = Gelaendeflug(
        [for (var i = 0; i <= 50; i++) (x: 0, y: i * 20.0, z: 0)],
        werte: [for (var i = 0; i <= 50; i++) (hoehe: 300, zeit: fest)],
      );
      expect(flug.bei(0.5).tempoMeterJeSekunde, isNull);
    });

    test('eine rückwärts laufende Uhr ergibt kein Tempo', () {
      final start = DateTime.utc(2026);
      final flug = Gelaendeflug(
        [for (var i = 0; i <= 50; i++) (x: 0, y: i * 20.0, z: 0)],
        werte: [
          for (var i = 0; i <= 50; i++)
            (hoehe: 300, zeit: start.subtract(Duration(seconds: i * 10)))
        ],
      );
      expect(flug.bei(0.5).tempoMeterJeSekunde, isNull);
      expect(flug.bei(0.5).seitStart, Duration.zero,
          reason: 'negative Dauer wäre schlimmer als keine');
    });

    test('ein Loch in den Höhen macht die Stelle nicht stumm', () {
      // Dieselbe Regel wie bei `profilpunkte`: Ein Loch in den
      // Höhenangaben ist kein Loch im Weg.
      final flug = Gelaendeflug(
        [
          (x: 0, y: 0, z: 0),
          (x: 0, y: 100, z: 0),
          (x: 0, y: 200, z: 0),
        ],
        werte: const [
          (hoehe: 100, zeit: null),
          (hoehe: null, zeit: null),
          (hoehe: 300, zeit: null),
        ],
      );
      expect(flug.hoeheBei(50), 100, reason: 'gilt die des Nachbarn');
      expect(flug.hoeheBei(150), 300);
    });

    test('Werte und Punkte müssen gleich lang sein', () {
      expect(
          () => Gelaendeflug(
                [(x: 0, y: 0, z: 0), (x: 0, y: 1, z: 0)],
                werte: const [(hoehe: 1, zeit: null)],
              ),
          throwsA(isA<AssertionError>()),
          reason: 'ein Versatz um eins verschöbe jede Zahl lautlos');
    });
  });

  group('Der Blickpunkt wird geglaettet', () {
    // Gemeldet als „der Flug scheint jeden Meter Abweichung zu fliegen,
    // so dass es sehr unruhig scheint". Richtung, Tempo und Steigung
    // waren von Anfang an geglaettet - der Blickpunkt nicht.

    /// Eine gerade Wanderung von 2 km mit GPS-Rauschen von +/- 4 m, so
    /// viel, wie ein Handy unter Baeumen danebenliegt. Fester Startwert,
    /// damit die Zahlen unten wiederholbar sind.
    Gelaendeflug rauschspur({double rauschen = 4.0}) {
      final zufall = math.Random(42);
      return Gelaendeflug([
        for (var i = 0; i <= 400; i++)
          (
            x: i * 5.0 + (zufall.nextDouble() - 0.5) * 2 * rauschen,
            y: (zufall.nextDouble() - 0.5) * 2 * rauschen,
            z: 400 + (zufall.nextDouble() - 0.5) * 2 * rauschen,
          ),
      ]);
    }

    /// Der mittlere Ruck: Betrag der zweiten Differenz der Kameraposition
    /// ueber einen Flug mit 600 Bildern. Genau das, was das Auge als
    /// Zittern sieht - eine Position allein sieht niemand, ihre
    /// Beschleunigung schon.
    double ruck(Gelaendeflug flug, Raumpunkt Function(double) punkt) {
      const bilder = 600;
      final p = [
        for (var i = 0; i <= bilder; i++) punkt(flug.laengeMeter * i / bilder)
      ];
      var summe = 0.0;
      for (var i = 1; i < p.length - 1; i++) {
        final dx = p[i + 1].x - 2 * p[i].x + p[i - 1].x;
        final dy = p[i + 1].y - 2 * p[i].y + p[i - 1].y;
        final dz = p[i + 1].z - 2 * p[i].z + p[i - 1].z;
        summe += math.sqrt(dx * dx + dy * dy + dz * dz);
      }
      return summe / (p.length - 2);
    }

    test('das Zittern der Kamera sinkt deutlich', () {
      final flug = rauschspur();
      final roh = ruck(flug, flug.punktBei);
      final glatt = ruck(flug, flug.blickpunktBei);
      // Gemessen ueber die ganze Spur: roh 2,831 m, geglaettet 0,078 m -
      // Faktor 36. Und gleichmaessig: Das Profil in Fuenfteln liegt roh
      // bei 2,74/2,72/2,79/3,32/2,80 und geglaettet bei
      // 0,20/0,05/0,05/0,06/0,16. Die etwas hoeheren Werte an den beiden
      // Enden sind das auslaufende Fenster und gehoeren so.
      //
      // Die Schwelle steht bei 10 und nicht bei 30: Sie soll den Rueckbau
      // auf eine Stichprobenmittelung fangen (die schaffte 2,8), nicht
      // jede dritte Nachkommastelle einer kuenftigen Fassung.
      expect(glatt, lessThan(roh / 10),
          reason: 'roh $roh, geglaettet $glatt');
    });

    test('die gezeichnete Spur bleibt unberuehrt', () {
      // Die Aufzeichnung soll aussehen wie die Aufzeichnung; geglaettet
      // wird nur, wohin die Kamera schaut.
      final flug = rauschspur();
      for (final m in [0.0, 250.0, 1000.0, flug.laengeMeter]) {
        final p = flug.punktBei(m);
        final s = flug.spur;
        expect(s.any((q) => (q.x - p.x).abs() < 6), isTrue,
            reason: 'punktBei liegt weiter auf der rohen Spur');
      }
    });

    test('ohne Rauschen verschiebt die Glaettung fast nichts', () {
      // Gegenprobe: Auf einer geraden Spur duerfen beide Wege dasselbe
      // liefern - sonst waere die Glaettung ein Versatz und keine
      // Glaettung.
      final gerade = Gelaendeflug([
        for (var i = 0; i <= 400; i++) (x: i * 5.0, y: 0.0, z: 400.0),
      ]);
      for (final m in [200.0, 900.0, 1500.0]) {
        final a = gerade.punktBei(m);
        final b = gerade.blickpunktBei(m);
        expect((a.x - b.x).abs(), lessThan(0.5));
        expect((a.y - b.y).abs(), lessThan(0.001));
        expect((a.z - b.z).abs(), lessThan(0.001));
      }
    });

    test('an den Enden bleibt der Blickpunkt auf der Spur', () {
      // Das Fenster rutscht an den Raendern nach innen; der gemittelte
      // Punkt darf trotzdem nicht vor den Anfang oder hinter das Ende
      // rutschen.
      final flug = rauschspur();
      final anfang = flug.blickpunktBei(0);
      final ende = flug.blickpunktBei(flug.laengeMeter);
      expect(anfang.x, greaterThan(flug.spur.first.x - 10));
      expect(ende.x, lessThan(flug.spur.last.x + 10));
    });

    test('eine Spur ohne Ausdehnung wirft nicht', () {
      final punkt = Gelaendeflug([(x: 5, y: 5, z: 5), (x: 5, y: 5, z: 5)]);
      expect(punkt.blickpunktBei(0).x, 5);
    });
  });
}
