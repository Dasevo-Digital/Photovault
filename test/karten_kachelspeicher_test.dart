import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/widgets/mini_location_map.dart';

/// Der Kachelspeicher der Karte.
///
/// Warum das überhaupt geprüft wird: Ohne eigene Angabe richtet sich
/// flutter_map nach dem `max-age` der Antwort – und OpenTopoMap gibt
/// ausgerechnet den frisch gerenderten, also teuersten Kacheln die
/// kürzeste Haltbarkeit (3,5 h gegenüber 7 Tagen bei vorgerenderten).
/// Läuft eine Kachel ab, macht flutter_map vor der Anzeige einen
/// blockierenden Rückfrage-Umlauf. Am selben Ort einen Tag später
/// wartet man also erneut.
void main() {
  test('die Frische ist lang genug, um den Zweck zu erfuellen', () {
    // Die kuerzeste beobachtete Haltbarkeit von OpenTopoMap lag bei rund
    // 3,5 Stunden. Alles darunter waere wirkungslos; ein Tag waere
    // besser, aber immer noch bei jedem zweiten Besuch teuer.
    expect(kartenKachelFrische.inDays, greaterThanOrEqualTo(7),
        reason: 'unter einer Woche greift die Massnahme kaum');
    // Nach oben ebenfalls begrenzt: Strassen aendern sich, und die
    // Kacheln sollen nicht auf Dauer veralten.
    expect(kartenKachelFrische.inDays, lessThanOrEqualTo(90));
  });

  test('die Speichergrenze traegt einen vorgeladenen Vorrat', () {
    // Bis 2.2.2 galten 300 MB, weil die Karte nur nachlud, was gerade
    // angesehen wurde. Seit sich Gebiete vorladen lassen, ist das zu
    // wenig: Die neun Gebiete der echten Bibliothek sind bis Stufe 14
    // rund 850 MB, und der Aufraeumer haette weggeworfen, was gerade
    // erst geholt wurde.
    expect(kartenSpeicherGrenze, greaterThanOrEqualTo(2 * 1024 * 1024 * 1024),
        reason: 'ein Vorrat muss hineinpassen, sonst ist er sinnlos');
    // Eine Obergrenze braucht es trotzdem: Ohne sie waechst der
    // Zwischenspeicher unbegrenzt.
    expect(kartenSpeicherGrenze, lessThanOrEqualTo(8 * 1024 * 1024 * 1024));
  });

  group('Die Verdrahtung', () {
    // Beides sind Quelltext-Pruefungen nach dem Muster von
    // keine_festen_texte_test.dart. Sie sehen etwas, das weder `analyze`
    // noch ein Laufzeittest sieht - und im Unittest laesst sich der
    // Speicher gar nicht anlegen, weil path_provider keine
    // Plattformkanaele hat.
    final quellen = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .map((f) => (f.path, f.readAsStringSync()))
        .toList();

    test('der Speicher wird an genau EINER Stelle angelegt', () {
      // `getOrCreateInstance` ist ein Einzelstueck: Die Angaben wirken
      // nur beim ERSTEN Aufruf. Ein zweiter Aufruf mit anderen Werten
      // waere wirkungslos - und der Fehler zeigte sich erst Wochen
      // spaeter als "die Karte ist wieder langsam".
      final stellen = [
        for (final (pfad, inhalt) in quellen)
          if (inhalt.contains('BuiltInMapCachingProvider.getOrCreateInstance'))
            pfad
      ];
      expect(stellen, hasLength(1), reason: 'gefunden in: $stellen');
      expect(stellen.single, endsWith('mini_location_map.dart'));
    });

    test('der Kachelanbieter wird an genau EINER Stelle gebaut', () {
      // Dieselbe Falle wie beim Speicher, nur schaerfer:
      // buildMapTileLayer laeuft bei JEDEM Neuaufbau, und
      // TileLayer.didUpdateWidget entsorgt den alten Anbieter NICHT -
      // ein Anbieter je Aufbau hinterliesse jedes Mal einen offenen
      // HTTP-Client. Deshalb gibt es genau ein Exemplar.
      final stellen = [
        for (final (pfad, inhalt) in quellen)
          if (inhalt.contains('Nachfassanbieter(')) pfad
      ];
      expect(stellen, hasLength(1), reason: 'gefunden in: $stellen');
      expect(stellen.single, endsWith('mini_location_map.dart'));

      // Und niemand baut sich am Nachfassanbieter vorbei einen blanken:
      // Der Anhang an gescheiterte Adressen sitzt in dessen
      // `getTileUrl`, und ohne ihn wird eine fehlende Kachel nur ein
      // einziges Mal wiederholt.
      final blanke = [
        for (final (pfad, inhalt) in quellen)
          if (inhalt.contains('NetworkTileProvider(')) pfad
      ];
      expect(blanke, isEmpty, reason: 'gefunden in: $blanke');
    });

    test('das Einzelstueck wird wirklich wiederverwendet', () {
      // Der Unterschied zwischen „einmal geschrieben" und „einmal
      // erzeugt": Stuende dort `=>  NetworkTileProvider(...)` ohne
      // Zwischenspeicher, faende der Test oben trotzdem eine Stelle -
      // und es entstuende bei jedem Aufbau ein neuer Anbieter.
      final quelle = quellen
          .firstWhere((q) => q.$1.endsWith('mini_location_map.dart')).$2;
      expect(quelle, contains('_kachelAnbieter ??='),
          reason: 'sonst ist es kein Einzelstueck, sondern eine Fabrik');
    });

    test('die Landschaft benutzt denselben Speicher', () {
      // Befund der 15. Pruefrunde: Sie holte ihre Kacheln mit einem
      // blanken http.Client - dieselben OpenTopoMap-Bilder, die die
      // Routenkarte einen Knopfdruck vorher schon geholt hatte. Beim
      // zweiten Oeffnen derselben Wanderung lud sie alles noch einmal,
      // und ohne Netz gar nichts.
      final quelle = quellen
          .firstWhere((q) => q.$1.endsWith('gelaende_laden.dart')).$2;
      expect(quelle, contains('kartenKachelspeicher()'),
          reason: 'sonst geht die Landschaft am Speicher vorbei');
      expect(quelle, contains('kachelNochmalVersuchen'),
          reason: 'ein 404 von OpenTopoMap heisst „noch nicht gerendert" '
              'und wurde hier zu einem dauerhaften Loch im Gelaende');
    });
  });
}
