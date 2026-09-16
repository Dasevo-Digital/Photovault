/// **Die stehende Menüleiste als Bild.**
///
/// Kein Teil der Prüfsuite; liegt deshalb unter `tool/`. Dass die Leiste
/// im Baum steht, sagt `test/menueleiste_test.dart`. Ob das Ergebnis
/// aussieht wie eine Anwendung und nicht wie ein Unfall, sagt nur das Bild.
///
/// Zwei Aufnahmen derselben Lage, damit der Unterschied sichtbar ist:
/// einmal im Bereich neben der Leiste (so ist es jetzt), einmal auf dem
/// Navigator des Fensters (so war es vorher – und so bleibt es für
/// Vollbild: 3D-Flug, Vollbildansicht, Entwickeln).
///
/// ```sh
/// PV_BILDER=~/Desktop/pv_menue flutter test tool/menueleiste_bilder_test.dart
/// ```
///
/// Die Schrift erscheint als Kästchen: Die Testbühne rechnet mit einer
/// Ersatzschrift. Für die Frage nach der Anordnung ist das gleichgültig –
/// wer Beschriftungen lesen will, nimmt ein Bildschirmfoto der App.
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/home_shell.dart';
import 'package:photo_vault/screens/timeline_screen.dart';
import 'package:photo_vault/screens/trash_screen.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/theme/app_theme.dart';

void main() {
  final ziel = Platform.environment['PV_BILDER'];

  testWidgets('die Leiste, mit einer offenen Unterseite', (tester) async {
    if (ziel == null) {
      markTestSkipped('PV_BILDER nicht gesetzt');
      return;
    }
    final wurzel = Directory.systemTemp.createTempSync('pv_menue_bilder_');
    addTearDown(() => wurzel.deleteSync(recursive: true));
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    late final LibraryState library;
    await tester.runAsync(() async {
      // forTesting ist für Tests gedacht, und das hier ist eines – es
      // liegt nur unter tool/, weil es kein Teil der Suite sein soll.
      // ignore: invalid_use_of_visible_for_testing_member
      final paths = await StoragePaths.forTesting(
          Directory(p.join(wurzel.path, 'lib')));
      library = LibraryState()
        ..db = db
        ..paths = paths;
    });

    for (final ganzesFenster in [false, true]) {
      // Frisch anfangen: Beim zweiten Durchgang stünde sonst noch die
      // Unterseite des ersten offen, und die Zeitleiste läge beiseite –
      // der Griff nach ihrem Kontext ginge ins Leere.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 1));

      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        theme: buildDarkTheme(),
        home: RepaintBoundary(child: HomeShell(library: library)),
      ));
      await tester.pump();

      // Ein echter Bildschirm der App, nicht ein gestellter Kasten: Der
      // Papierkorb bringt eine eigene Titelzeile mit, und genau an der
      // Naht zwischen Leiste und fremder Titelzeile entscheidet sich, ob
      // das Ganze aussieht wie gewollt.
      final kontext = tester.element(find.byType(TimelineScreen));
      unawaited(Navigator.of(kontext, rootNavigator: ganzesFenster).push(
        MaterialPageRoute<void>(
          builder: (_) => TrashScreen(library: library),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      final grenze = tester
          .firstElement(find.byType(RepaintBoundary))
          .renderObject! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final bild = await grenze.toImage(pixelRatio: 1.0);
        final daten = await bild.toByteData(format: ui.ImageByteFormat.png);
        bild.dispose();
        final name = ganzesFenster ? 'vollbild' : 'bereich';
        final datei = File(p.join(ziel, 'menueleiste_$name.png'));
        await datei.parent.create(recursive: true);
        await datei.writeAsBytes(daten!.buffer.asUint8List());
        // ignore: avoid_print
        print('geschrieben: ${datei.path} '
            '(${daten.lengthInBytes ~/ 1024} KB)');
      });
    }

    // Den Baum abbauen und den Aufräum-Timer von drift auslaufen lassen –
    // sonst endet der Lauf mit „A Timer is still pending".
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 1));
  });
}
