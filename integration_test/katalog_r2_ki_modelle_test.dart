// ignore_for_file: avoid_print
// Zweite Prüfrunde, Prüfer r2-ki: KI-003, KI-007 und KI-023 – die Modelle
// über die Oberfläche aus den Katalog-Adressen laden (rund 2,1 GB, einmal
// jedes Modell, in die Wegwerf-Bibliothek der Prüfung).
//
// Nur hier ist das Netz offen ([r2.Netzweiche.offen]); jeder andere Abruf
// geht an die Attrappe.
//
//   …/tools/e2e_queue.sh r2-ki integration_test/katalog_r2_ki_modelle_test.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kern/services/model_catalog.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/screens/settings_screen.dart';
import 'package:photo_vault/services/meldungsdienst.dart' show melde;
import 'package:photo_vault/services/modelltexte.dart';

import 'katalog_ki_test.dart' as ki;
import 'katalog_kit.dart';
import 'katalog_r2_ki_test.dart' as r2;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  r2.netzAufAttrappe();
  setUp(melde.alleSchliessen);

  testWidgets(
    timeout: const Timeout(Duration(minutes: 38)),
    'KI-003 KI-007 KI-023 Netzlauf Modelle ueber die Oberflaeche laden',
    (tester) async {
      await startApp(tester);
      r2.netzweiche.offen = true;
      addTearDown(() => r2.netzweiche.offen = false);
      await ki.einstellungsgruppe(tester, de.einstAbschnittModelle);
      final katalog = ModelCatalog.fuerSprache(
        'de',
        istInstalliert: (_) => false,
      );
      expect(katalog, hasLength(15));
      Finder knopf(String text) => find.ancestor(
        of: find.text(text),
        matching: find.byType(FilledButton),
      );
      await ki.sichtbar(
        tester,
        find.text(de.einstAlleModelleLaden(15)),
        SettingsScreen,
      );

      // KI-003: CLIP (vier Dateien) einzeln.
      const clip = 'clip_vit_b32';
      final titel = modellTitel(de, clip);
      await ki.sichtbar(tester, find.text(titel), SettingsScreen);
      await tester.tap(
        find.descendant(
          of: ki.modellkarte(clip),
          matching: find.text(de.allgHerunterladen),
        ),
      );
      final blatt = find.byType(BottomSheet);
      final laedt = find.text(de.einstModellLaedt(titel));
      final prozente = <int>[];
      var balken = false, knopfImBlatt = false, blieb = true, versuche = 0;
      var letzterVersuch = DateTime.now();
      final ende = DateTime.now().add(const Duration(minutes: 15));
      while (DateTime.now().isBefore(ende)) {
        await tester.pump(const Duration(milliseconds: 30));
        if (r2.findet(laedt)) {
          final t = find.descendant(
            of: blatt,
            matching: find.textContaining(RegExp(r'^\d+ %$')),
          );
          if (r2.findet(t)) {
            final w = int.parse(
              (tester.widget<Text>(t.first).data!).split(' ').first,
            );
            if (prozente.isEmpty || prozente.last != w) prozente.add(w);
          }
          if (r2.findet(
            find.descendant(
              of: blatt,
              matching: find.byType(LinearProgressIndicator),
            ),
          )) {
            balken = true;
          }
          if (r2.findet(
            find.descendant(
              of: blatt,
              matching: find.byWidgetPredicate(
                (w) => w is ButtonStyleButton || w is IconButton,
              ),
            ),
          )) {
            knopfImBlatt = true;
          }
          // Escape und ein Klick neben das Blatt, etwa alle zwei Sekunden.
          if (DateTime.now().difference(letzterVersuch).inMilliseconds > 2000) {
            letzterVersuch = DateTime.now();
            versuche++;
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await tester.tapAt(const Offset(1300, 40));
            await tester.pump(const Duration(milliseconds: 60));
            if (!r2.findet(laedt) &&
                !bibliothek.isModelInstalled(ModelCatalog.clip)) {
              blieb = false;
            }
          }
        }
        if (bibliothek.isModelInstalled(ModelCatalog.clip) &&
            !r2.findet(laedt)) {
          break;
        }
      }
      final ruecksprung = [
        for (var i = 1; i < prozente.length; i++)
          if (prozente[i] < prozente[i - 1])
            '${prozente[i - 1]}→${prozente[i]}',
      ];
      print(
        'KI-003 Prozent: ${prozente.length} Stände, Rücksprünge $ruecksprung, '
        'Wegklickversuche $versuche',
      );
      expect(bibliothek.isModelInstalled(ModelCatalog.clip), isTrue);
      expect(prozente, isNotEmpty);
      expect(balken, isTrue);
      expect(knopfImBlatt, isFalse, reason: 'kein Abbrechen-Knopf');
      expect(versuche, greaterThan(0));
      expect(blieb, isTrue, reason: 'Escape/Klick daneben schloss das Blatt');
      await settle(tester);
      expect(
        find.descendant(
          of: ki.modellkarte(clip),
          matching: find.byIcon(Icons.check_circle),
        ),
        findsOneWidget,
      );

      // KI-007: YuNet scheitert (an seiner Teildatei liegt ein Ordner), die
      // übrigen laden weiter.
      final sperre = Directory(
        p.join(
          ki.modellordnerDerPruefung.path,
          'face_detection_yunet.onnx.part',
        ),
      )..createSync(recursive: true);
      await ki.sichtbar(
        tester,
        find.text(de.einstAlleModelleLaden(14)),
        SettingsScreen,
      );
      await tester.tap(knopf(de.einstAlleModelleLaden(14)));
      final gesehen = <int>{};
      final titelGesehen = <String>{};
      var fehlerGesehen = false;
      final bis = DateTime.now().add(const Duration(minutes: 20));
      while (DateTime.now().isBefore(bis)) {
        await tester.pump(const Duration(milliseconds: 40));
        for (var i = 1; i <= 14; i++) {
          if (r2.findet(find.text(de.einstAlleModelleLaeuft(i, 14)))) {
            gesehen.add(i);
          }
        }
        for (final e in katalog) {
          if (r2.findet(
            find.text(de.einstModellLaedt(modellTitel(de, e.id))),
          )) {
            titelGesehen.add(e.id);
          }
        }
        if (r2.findet(find.textContaining('face_detection_yunet.onnx'))) {
          fehlerGesehen = true;
        }
        if (r2.findet(find.text(de.einstAlleModelleLaden(1))) &&
            !r2.findet(blatt)) {
          break;
        }
      }
      print(
        'KI-007 Reihe: gesehen $gesehen, Titel ${titelGesehen.length}, '
        'Fehler zu YuNet $fehlerGesehen',
      );
      expect(gesehen, {for (var i = 1; i <= 14; i++) i});
      expect(fehlerGesehen, isTrue, reason: 'Fehlermeldung zu YuNet');
      for (final e in katalog) {
        expect(
          bibliothek.isModelInstalled(e),
          e.id != 'face_detection_yunet',
          reason: e.id,
        );
      }
      melde.alleSchliessen();
      await ki.pumpe(tester, 800);
      sperre.deleteSync();
      await ki.sichtbar(
        tester,
        find.text(de.einstAlleModelleLaden(1)),
        SettingsScreen,
      );
      await tester.tap(knopf(de.einstAlleModelleLaden(1)));
      var einsVonEins = false;
      final bis2 = DateTime.now().add(const Duration(minutes: 3));
      while (DateTime.now().isBefore(bis2)) {
        await tester.pump(const Duration(milliseconds: 40));
        if (r2.findet(find.text(de.einstAlleModelleLaeuft(1, 1)))) {
          einsVonEins = true;
        }
        if (r2.findet(find.text(de.einstAlleModelleDa)) && !r2.findet(blatt)) {
          break;
        }
      }
      await settle(tester);
      expect(einsVonEins, isTrue);
      for (final e in katalog) {
        expect(bibliothek.isModelInstalled(e), isTrue, reason: e.id);
      }
      final fertig = knopf(de.einstAlleModelleDa);
      await ki.sichtbar(tester, fertig, SettingsScreen);
      expect(tester.widget<FilledButton>(fertig).onPressed, isNull);
      for (final e in katalog) {
        await ki.sichtbar(
          tester,
          find.text(modellTitel(de, e.id)),
          SettingsScreen,
        );
        expect(
          find.descendant(
            of: ki.modellkarte(e.id),
            matching: find.byIcon(Icons.check_circle),
          ),
          findsOneWidget,
          reason: e.id,
        );
      }

      // KI-023: Nachrechnen über alle Dateien.
      final dateien = ModelCatalog.all.fold<int>(
        0,
        (n, e) => n + e.files.length,
      );
      await ki.sichtbar(
        tester,
        find.text(de.einstModellePruefenTitel),
        SettingsScreen,
      );
      await tester.tap(find.text(de.einstModellePruefenTitel));
      await waitFor(
        tester,
        find.text(de.einstModellePruefenAlleGut(dateien)),
        timeout: const Duration(minutes: 3),
      );
      final belegt = ki.modellordnerDerPruefung
          .listSync()
          .whereType<File>()
          .fold<int>(0, (n, f) => n + f.lengthSync());
      print('KI-023 $dateien Dateien, ${belegt ~/ 1000000} MB geladen');
      expect(
        ki.modellordnerDerPruefung.listSync().whereType<Link>(),
        isEmpty,
        reason: 'echte Downloads, keine Verknüpfungen',
      );
      await finish(tester);
    },
  );
}
