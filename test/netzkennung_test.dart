import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/netzkennung.dart';
import 'package:photo_vault/widgets/mini_location_map.dart';

/// Die Kennung, mit der sich die App bei den Kartenanbietern ausweist.
///
/// Bis 3.19.0 stand dort `com.example.photoVault`, der Platzhalter aus der
/// Flutter-Vorlage. flutter_map warnt nur, wenn GAR KEINE Kennung gesetzt
/// ist (`flutter_map (unknown)`); den Platzhalter hätte es durchgewinkt.
/// Deshalb prüft dieser Test den Inhalt und nicht nur, ob überhaupt etwas
/// gesetzt ist.
void main() {
  test('die Kennung ist kein Platzhalter', () {
    expect(netzkennung, isNot(contains('example')));
    expect(netzkennung, isNot(contains('unknown')));
    expect(
      netzkennung,
      isNot(contains('@')),
      reason: 'keine Adresse im Kopf, der an fremde Server geht',
    );
    expect(kartenNetzkennung, 'flutter_map ($netzkennung)');
  });

  for (final stil in Kartenstil.values) {
    testWidgets('die Kachelschicht ($stil) schickt die Kennung', (
      tester,
    ) async {
      // Ein eigener Anbieter statt des gemeinsamen: flutter_map setzt den
      // Kopf nur, wenn er noch fehlt (`putIfAbsent`). Ein Anbieter, den
      // vorher schon eine andere Schicht gefüllt hat, bewiese nichts.
      final anbieter = NetworkTileProvider();
      addTearDown(() => kachelAnbieterFuerTest = null);
      kachelAnbieterFuerTest = anbieter;

      late TileLayer gebaut;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(
            builder: (context) {
              gebaut = buildMapTileLayer(context, stil: stil);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(gebaut.tileProvider, same(anbieter));
      expect(anbieter.headers['User-Agent'], kartenNetzkennung);
    });
  }

  test('kein Netzaufruf in lib/ schreibt die Kennung von Hand', () {
    // Eine Kennung, die an fünf Stellen als Text steht, ist nach dem
    // nächsten Umbenennen an vier davon falsch. Jeder `User-Agent` in lib/
    // muss deshalb aus netzkennung.dart kommen.
    final vonHand = RegExp(r'''['"]User-Agent['"]\s*:\s*['"]''');
    final funde = <String>[];
    for (final datei
        in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))) {
      final zeilen = datei.readAsLinesSync();
      for (var i = 0; i < zeilen.length; i++) {
        if (vonHand.hasMatch(zeilen[i])) funde.add('${datei.path}:${i + 1}');
      }
    }
    expect(funde, isEmpty);
  });
}
