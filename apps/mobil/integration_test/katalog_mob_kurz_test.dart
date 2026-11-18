import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

import 'katalog_hilfen.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('MOB-001: Start und leere Anmeldung ohne Server', (tester) async {
    try {
      final app = await starteApp(tester);
      await warte(tester, find.text(de.anmeldenTitel));
      expect(app.sitzung.verbindung, isNull);
      await tippe(
        tester,
        find.widgetWithText(FilledButton, de.anmeldenAnmelden),
      );
      await warte(tester, find.text(de.anmeldenNichtErreichbar));
      expect(
        File(p.join(app.bibliothek.path, 'library.sqlite')).existsSync(),
        isFalse,
      );
    } finally {
      await appBeenden(tester);
    }
  });
}
