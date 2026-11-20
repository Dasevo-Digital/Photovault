// Plattformabfrage ausschließlich im eigenen temporären Ordner.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/services/platform/speicherlaufwerk.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Betriebssystem liefert das Dateisystem eines eigenen Testordners',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('Laufwerksprüfung'))),
      );
      await tester.runAsync(() async {
        final temp = await Directory.systemTemp.createTemp('pv_laufwerk_');
        try {
          final pfad = await temp.resolveSymbolicLinks();
          final info = await Laufwerksauskunft.fuer(pfad);
          expect(info, isNotNull);
          expect(info!.id, isNotEmpty);
          expect(info.name, isNotEmpty);
          expect(p.isAbsolute(info.pfad), isTrue);
          expect(
            p.equals(info.pfad, pfad) || p.isWithin(info.pfad, pfad),
            isTrue,
          );
          expect(await Laufwerksauskunft.fuer('relativ'), isNull);
        } finally {
          await temp.delete(recursive: true);
        }
      });
    },
  );
}
