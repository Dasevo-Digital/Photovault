// Der Lader, der den Blöcken ihre scharfen Bilder holt.
//
// Was hier geprüft wird, ist nicht das Bild, sondern das **Verhalten am
// Netz**: Wird das Nächste zuerst geholt? Wird ein Block, der nicht
// kommt, endlos nachgefragt? Bleibt der Speicher unter der Grenze? Genau
// die zweite Frage hat beim Bauen zugeschlagen – der Lader drehte sich
// im Kreis, sobald ein Server nichts lieferte, und der Testlauf lief in
// die Zeitgrenze statt abzustürzen.
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' show DisabledMapCachingProvider;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:photo_vault/services/blocktexturen.dart';
import 'package:photo_vault/services/gelaendetextur.dart';
import 'package:photo_vault/services/gelaendeebenen.dart';

/// Eine einfarbige Kachel als PNG – Inhalt egal, Grösse nicht.
Future<Uint8List> _kachel(Color farbe) async {
  const kante = 256;
  final rgba = Uint8List(kante * kante * 4);
  for (var i = 0; i < kante * kante; i++) {
    rgba[i * 4] = (farbe.r * 255).round();
    rgba[i * 4 + 1] = (farbe.g * 255).round();
    rgba[i * 4 + 2] = (farbe.b * 255).round();
    rgba[i * 4 + 3] = 255;
  }
  final fertig = Completer<ui.Image>();
  ui.decodeImageFromPixels(
      rgba, kante, kante, ui.PixelFormat.rgba8888, fertig.complete);
  final bild = await fertig.future;
  final daten = await bild.toByteData(format: ui.ImageByteFormat.png);
  bild.dispose();
  return daten!.buffer.asUint8List();
}

void main() {
  late Uint8List kachel;
  setUpAll(() async => kachel = await _kachel(const Color(0xFF3F7F3F)));

  /// Drei Blöcke nebeneinander im Harz.
  List<Texturblock> bloecke() => texturbloecke(
      sued: 51.83, west: 10.61, nord: 51.835, ost: 10.625,
      grundstufe: texturGrundstufe);

  Blocktexturlader lader(
    http.Client netz, {
    int grundstufe = texturGrundstufe,
    int hoechstensBytes = blocktexturSpeicher,
    Gelaendegrund grund = Gelaendegrund.luftbild,
  }) =>
      Blocktexturlader(
        karte: Gelaendekarte(grund: grund),
        grundstufe: grundstufe,
        netz: netz,
        speicher: const DisabledMapCachingProvider(),
        hoechstensBytes: hoechstensBytes,
      );

  testWidgets('ein Block bekommt seine Textur in der gewünschten Grösse',
      (tester) async {
    await tester.runAsync(() async {
      final netz = MockClient((_) async => http.Response.bytes(kachel, 200));
      final l = lader(netz);
      addTearDown(l.schliessen);
      final b = bloecke().first;
      // Stufe 17 heisst zwei Kacheln je Kante, also 512 Bildpunkte.
      l.brauche([(block: b, stufe: 17, entfernung: 300.0)]);
      await _bisFertig(() => l.bei(b) != null);
      expect(l.bei(b)!.width, 512);
      expect(l.bei(b)!.height, 512);
      expect(l.belegt, b.speicherBytes(17));
    });
  });

  testWidgets('das Nächste zuerst', (tester) async {
    await tester.runAsync(() async {
      final reihenfolge = <String>[];
      final netz = MockClient((anfrage) async {
        reihenfolge.add(anfrage.url.path);
        return http.Response.bytes(kachel, 200);
      });
      final l = lader(netz);
      addTearDown(l.schliessen);
      final bs = bloecke();
      expect(bs.length, greaterThanOrEqualTo(3));
      // Absichtlich in der falschen Reihenfolge gewünscht: Der ferne
      // zuerst, der nahe zuletzt.
      l.brauche([
        (block: bs[2], stufe: 16, entfernung: 3000.0),
        (block: bs[0], stufe: 16, entfernung: 2000.0),
        (block: bs[1], stufe: 16, entfernung: 100.0),
      ]);
      await _bisFertig(() => reihenfolge.length >= 3);
      // Die erste Anfrage muss zum nächstgelegenen Block gehören. Bei
      // Esri stehen Zeile und Spalte vertauscht in der Adresse – deshalb
      // wird auf beide geprüft und nicht auf eine Reihenfolge.
      expect(reihenfolge.first, contains('/${bs[1].spalte}'));
      expect(reihenfolge.first, contains('/${bs[1].zeile}'));
    });
  });

  testWidgets('ein Block, der nicht kommt, wird nicht endlos nachgefragt',
      (tester) async {
    // Der Fund beim Bauen: Ohne Merkposten für Fehlschläge fragte der
    // Lader denselben Block wieder und wieder, weil der Wunsch
    // unverändert offen stand. Kein Absturz, keine Meldung – nur ein
    // Kern, der bei hundert Prozent läuft.
    await tester.runAsync(() async {
      var anfragen = 0;
      final netz = MockClient((_) async {
        anfragen++;
        return http.Response('weg', 500);
      });
      final l = lader(netz);
      addTearDown(l.schliessen);
      final b = bloecke().first;
      l.brauche([(block: b, stufe: 16, entfernung: 100.0)]);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      // Eine Kachel, zwei Versuche (siehe `holeKachelRoh`) – und dann
      // Ruhe. Alles darüber wäre die Endlosschleife.
      expect(anfragen, lessThanOrEqualTo(4),
          reason: 'der Lader dreht sich im Kreis: $anfragen Anfragen');
      expect(l.bei(b), isNull);

      // Gegenprobe: Ein anderer Block wird trotzdem noch bedient – der
      // Merkposten gilt dem Fehlschlag, nicht dem Lader.
      final vorher = anfragen;
      l.brauche([(block: bloecke()[1], stufe: 16, entfernung: 100.0)]);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(anfragen, greaterThan(vorher));
    });
  });

  testWidgets('was nicht ins Budget passt, bekommt gar keine eigene Textur',
      (tester) async {
    // **Der erste Anlauf holte alles und liess den Vorrat aufräumen.**
    // Das ergab entweder gar keine Verdrängung – acht Blöcke in einem
    // Vorrat für zwei, hier gemessen – oder einen Kreislauf: Der fernste
    // Block verdrängt sich selbst und wird sofort wieder gewünscht.
    // Deshalb rechnet der Lader das Budget vorher aus.
    await tester.runAsync(() async {
      final netz = MockClient((_) async => http.Response.bytes(kachel, 200));
      final bs = bloecke();
      expect(bs.length, greaterThanOrEqualTo(3));
      // Platz für zwei Blöcke auf Stufe 16 (256² · 4 = 256 KB).
      const grenze = 2 * 256 * 256 * 4;
      final l = lader(netz, hoechstensBytes: grenze);
      addTearDown(l.schliessen);
      l.brauche([
        for (var i = 0; i < bs.length; i++)
          (block: bs[i], stufe: 16, entfernung: 100.0 + i * 1000)
      ]);
      await _bisFertig(() => l.bei(bs[1]) != null);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(l.belegt, lessThanOrEqualTo(grenze));
      // Die beiden nächstgelegenen bekommen ihre Textur, der Rest bleibt
      // bei der Übersichtskarte.
      expect(l.bei(bs[0]), isNotNull);
      expect(l.bei(bs[1]), isNotNull);
      expect(l.bei(bs[2]), isNull);
    });
  });

  testWidgets('was nicht mehr gewünscht wird, gibt seinen Platz her',
      (tester) async {
    await tester.runAsync(() async {
      final netz = MockClient((_) async => http.Response.bytes(kachel, 200));
      final bs = bloecke();
      final l = lader(netz, hoechstensBytes: 2 * 256 * 256 * 4);
      addTearDown(l.schliessen);
      l.brauche([(block: bs[0], stufe: 16, entfernung: 100.0)]);
      await _bisFertig(() => l.bei(bs[0]) != null);

      // Die Kamera ist weitergeflogen: Der erste Block steht nicht mehr
      // im Bild, dafür zwei andere.
      l.brauche([
        (block: bs[1], stufe: 16, entfernung: 100.0),
        (block: bs[2], stufe: 16, entfernung: 200.0),
      ]);
      await _bisFertig(() => l.bei(bs[2]) != null);
      expect(l.bei(bs[0]), isNull,
          reason: 'was hinter der Kamera liegt, ist frisch benutzt und '
              'trotzdem am wenigsten wert');
      expect(l.belegt, 2 * 256 * 256 * 4);
    });
  });

  testWidgets('ruhe wartet, bis alles da ist – aber nicht ewig',
      (tester) async {
    // Fuer den Videoexport: Was beim Aufzeichnen eines Bildes nicht da
    // ist, fehlt darin fuer immer. Am Bildschirm holt der Lader nach,
    // ein Video hat dafuer keine Gelegenheit mehr.
    await tester.runAsync(() async {
      final netz = MockClient((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 60));
        return http.Response.bytes(kachel, 200);
      });
      final l = lader(netz);
      addTearDown(l.schliessen);
      final bs = bloecke();
      l.brauche([
        for (var i = 0; i < bs.length; i++)
          (block: bs[i], stufe: 16, entfernung: 100.0 + i)
      ]);
      await l.ruhe();
      for (final b in bs) {
        expect(l.bei(b), isNotNull, reason: '$b fehlt nach `ruhe`');
      }
    });
  });

  testWidgets('ruhe haelt keine Ausgabe an, wenn ein Server schweigt',
      (tester) async {
    await tester.runAsync(() async {
      final netz = MockClient((_) async {
        await Future<void>.delayed(const Duration(seconds: 5));
        return http.Response('', 500);
      });
      final l = lader(netz);
      addTearDown(l.schliessen);
      l.brauche([(block: bloecke().first, stufe: 16, entfernung: 100.0)]);
      final uhr = Stopwatch()..start();
      await l.ruhe(hoechstens: const Duration(milliseconds: 200));
      uhr.stop();
      expect(uhr.elapsedMilliseconds, lessThan(1500),
          reason: 'ein schweigender Server haelt die Ausgabe an');
    });
  });

  test('die feinste Stufe kennt drei Grenzen', () {
    final netz = MockClient((_) async => http.Response('', 404));

    // 1. Was dem Anbieter zuzumuten ist. OpenTopoMap rendert bei Bedarf
    //    und braucht dafür Sekunden – ein Überflug wollte 88 Blöcke auf
    //    Stufe 17 und bekam in zwei Minuten 31 davon.
    expect(
        lader(netz, grund: Gelaendegrund.wanderkarte).hoechsteStufeFuer, 16);

    // 2. Die eigene Obergrenze – darüber belegte ein Block 16 MB.
    expect(lader(netz, grund: Gelaendegrund.luftbild).hoechsteStufeFuer,
        texturHoechsteStufe);

    // 3. Zwei Stufen über der Grundstufe. Bei einer grossen Tour steht
    //    die Grundstufe gröber, und ohne diese Grenze bräuchte ein
    //    einzelner Block 64 MB.
    expect(
        lader(netz, grundstufe: 13, grund: Gelaendegrund.luftbild)
            .hoechsteStufeFuer,
        15);
  });

  testWidgets('geschlossen wird nichts mehr geholt und nichts mehr gehalten',
      (tester) async {
    await tester.runAsync(() async {
      var anfragen = 0;
      final netz = MockClient((_) async {
        anfragen++;
        return http.Response.bytes(kachel, 200);
      });
      final l = lader(netz);
      final b = bloecke().first;
      l.brauche([(block: b, stufe: 16, entfernung: 100.0)]);
      await _bisFertig(() => l.bei(b) != null);
      l.schliessen();
      expect(l.belegt, 0);
      expect(l.bilder, isEmpty);
      final vorher = anfragen;
      l.brauche([(block: bloecke()[1], stufe: 16, entfernung: 100.0)]);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(anfragen, vorher);
    });
  });

  testWidgets('ruheNah wartet auf das Nahe, nicht auf alles', (tester) async {
    // **Der Unterschied, um den es geht.** `ruhe` wartet, bis der Lader
    // gar nichts mehr zu tun hat. Im Flug tritt das nie ein: Ein Bild
    // will mehr Bloecke, als in den Vorrat passen, und mit jedem Bild
    // verschiebt sich die Zuteilung. Die Videoausgabe wartete deshalb
    // jedes Mal die volle Frist ab - gemessen 666 ms je Bild, bei einem
    // Server, der SOFORT antwortet.
    //
    // Hier wird ein langsamer Server gestellt: Jede Kachel braucht
    // 60 ms. `ruheNah(naechste: 1)` darf zurueckkommen, sobald der
    // naechstgelegene Block seine Stufe hat - `ruhe` erst, wenn alle
    // durch sind.
    await tester.runAsync(() async {
      final l = lader(MockClient((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 60));
        return http.Response.bytes(kachel, 200);
      }));
      addTearDown(l.schliessen);
      final b = bloecke();
      // Entfernung aufsteigend: Der erste ist der naechste.
      l.brauche([
        for (final (i, block) in b.indexed)
          (block: block, stufe: 1, entfernung: 100.0 + i * 100),
      ]);

      final uhr = Stopwatch()..start();
      await l.ruheNah(naechste: 1, hoechstens: const Duration(seconds: 5));
      final nah = uhr.elapsedMilliseconds;
      expect(l.bei(b.first), isNotNull,
          reason: 'auf den naechsten Block wurde ja gewartet');
      await l.ruhe(hoechstens: const Duration(seconds: 5));
      final ganz = uhr.elapsedMilliseconds;
      expect(nah, lessThan(ganz),
          reason: 'sonst wartet ruheNah genauso lange wie ruhe');
    });
  });

  testWidgets('ruheNah kehrt sofort zurueck, wenn das Nahe schon da ist',
      (tester) async {
    await tester.runAsync(() async {
      final l = lader(MockClient((_) async => http.Response.bytes(kachel, 200)));
      addTearDown(l.schliessen);
      final b = bloecke();
      l.brauche([
        for (final (i, block) in b.indexed)
          (block: block, stufe: 1, entfernung: 100.0 + i * 100),
      ]);
      await l.ruhe(hoechstens: const Duration(seconds: 5));
      final uhr = Stopwatch()..start();
      await l.ruheNah(hoechstens: const Duration(milliseconds: 800));
      expect(uhr.elapsedMilliseconds, lessThan(120),
          reason: 'nichts offen heisst nicht warten');
    });
  });

  testWidgets('eine vergebliche Kachel haelt das Warten nicht auf',
      (tester) async {
    // Sonst stuende die Videoausgabe bei jedem Bild die volle Frist vor
    // einem Block, der nie kommt.
    await tester.runAsync(() async {
      final l = lader(MockClient((_) async => http.Response('weg', 404)));
      addTearDown(l.schliessen);
      final b = bloecke();
      l.brauche([
        for (final (i, block) in b.indexed)
          (block: block, stufe: 1, entfernung: 100.0 + i * 100),
      ]);
      await l.ruhe(hoechstens: const Duration(seconds: 3));
      final uhr = Stopwatch()..start();
      await l.ruheNah(hoechstens: const Duration(milliseconds: 800));
      expect(uhr.elapsedMilliseconds, lessThan(200));
    });
  });

}

/// Wartet, bis [fertig] wahr ist – höchstens zwei Sekunden.
///
/// `pumpAndSettle` hilft hier nicht: Der Lader hängt an echter Ein- und
/// Ausgabe und nicht am Bildtakt.
Future<void> _bisFertig(bool Function() fertig) async {
  final uhr = Stopwatch()..start();
  while (!fertig() && uhr.elapsedMilliseconds < 2000) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(fertig(), isTrue, reason: 'nach zwei Sekunden immer noch nicht da');
}
