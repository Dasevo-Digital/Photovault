// Prüft das Gerüst der Katalog-Prüfungen selbst: App mit frischer
// Bibliothek im Temp-Ordner, Import über die Oberfläche, Ansicht.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'katalog_kit.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Gerüst: leere Bibliothek im Temp-Ordner, Import, Zeitleiste', (
    tester,
  ) async {
    await startApp(tester);
    expect(bibliothek.paths.root.path, startsWith(anker.path));
    await waitFor(tester, find.text(de.timelineLeer));

    final fotos = [
      testfoto(
        'a.jpg',
        datum: DateTime(2024, 5, 1, 10),
        breitengrad: 48.137,
        laengengrad: 11.575,
        kamera: 'Testkamera',
        modell: 'T1',
      ),
      testfoto('b.jpg', datum: DateTime(2023, 8, 15, 14, 30)),
      testfoto('c.jpg', datum: DateTime(2022, 1, 2, 9)),
    ];
    await importiereUeberUi(tester, fotos);
    final assets = await tester.runAsync(
      () => bibliothek.db.select(bibliothek.db.assets).get(),
    );
    expect(assets!.length, 3);
    final a = assets.firstWhere((x) => x.originalFileName == 'a.jpg');
    expect(a.fileCreatedAt.year, 2024);
    expect(a.latitude, closeTo(48.137, 0.001));
    await waitGone(tester, find.text(de.timelineLeer));
    await finish(tester);
  });

  testWidgets('Gerüst: zweite Prüfung bekommt wieder eine leere Bibliothek', (
    tester,
  ) async {
    await startApp(tester, fotos: [testfoto('d.jpg')]);
    final assets = await tester.runAsync(
      () => bibliothek.db.select(bibliothek.db.assets).get(),
    );
    expect(assets!.length, 1);
    await openSection(tester, Hauptbereich.alben);
    await openSection(tester, Hauptbereich.zeitleiste);
    expect(find.byType(Scaffold), findsWidgets);
    await finish(tester);
  });
}
