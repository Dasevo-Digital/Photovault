// ignore_for_file: avoid_print
// Katalog-Prüfungen IMP-114 bis IMP-224 (Aufnahmedaten, Datierung,
// Bibliothekspflege, Duplikate, ähnliche Fotos, Serien, Vergleich, Archiv,
// Papierkorb, gesperrter Ordner, Integrität, Bibliothekszustand) – Ende zu
// Ende in der echten App mit Wegwerf-Bibliothek (siehe katalog_kit.dart).
//
// **Zum CLIP-Modell.** Das echte Modell wiegt rund 250 MB und wird hier
// nicht geladen. Wo eine Prüfung die Bildsuche braucht (Duplikate,
// ähnliche Fotos, Serien, Datierung), steht stattdessen ein Halter, der
// „installiert" meldet, und die Einbettungen kommen über die Datenbank:
// berechnet aus den Bildpunkten der Testfotos (verkleinert auf 12×12, je
// Farbkanal zentriert). Verkleinerte Kopien eines Fotos liegen damit nah
// beieinander, verschiedene Fotos weit auseinander. Geprüft wird die
// Oberfläche und was sie mit der Bibliothek tut, nicht das Modell.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:drift/drift.dart' show BooleanExpressionOperators, Value;
import 'package:drift/native.dart' show NativeDatabase;
import 'package:flutter/gestures.dart' show kSecondaryButton, PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:intl/intl.dart';
import 'package:kern/abgleich/anmeldung.dart';
import 'package:kern/abgleich/umzug.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:kern/abgleich/verbindungsdatei.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/asset_format.dart' show aufnahmewerte;
import 'package:kern/services/clip_service.dart';
import 'package:kern/services/import_service.dart';
import 'package:kern/services/modell_halter.dart';
import 'package:kern/services/search_filters.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/main.dart' show PhotoVaultApp;
import 'package:photo_vault/screens/background_tasks_screen.dart';
import 'package:photo_vault/screens/duplicates_screen.dart';
import 'package:photo_vault/screens/home_shell.dart' show HomeShell;
import 'package:photo_vault/screens/integrity_check_screen.dart';
import 'package:photo_vault/screens/library_health_screen.dart';
import 'package:photo_vault/screens/locked_folder_screen.dart';
import 'package:photo_vault/screens/serienvergleich_screen.dart';
import 'package:photo_vault/screens/settings_screen.dart';
import 'package:photo_vault/screens/similar_photos_screen.dart';
import 'package:photo_vault/screens/stack_review_screen.dart';
import 'package:photo_vault/screens/timeline_screen.dart';
import 'package:photo_vault/screens/tools_screen.dart';
import 'package:photo_vault/screens/trash_screen.dart';
import 'package:photo_vault/services/library_location.dart';
import 'package:photo_vault/services/meldungsdienst.dart';
import 'package:photo_vault/services/serversperre.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/widgets/asset_info_sheet.dart';
import 'package:photo_vault/widgets/asset_thumbnail_tile.dart';
import 'package:photo_vault/widgets/selection_action_bar.dart';
import 'package:photo_vault/widgets/star_rating.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import 'katalog_kit.dart';

const _pin = '12345678';
const _pinNeu = '87654321';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // ---------------------------------------------------------------------
  // Aufnahmedaten ansehen und korrigieren
  // ---------------------------------------------------------------------

  testWidgets('IMP-114 IMP-115 IMP-117 Aufnahmedaten aus dem Dateinamen', (
    tester,
  ) async {
    await startApp(tester);
    await importiereDirekt(tester, [
      testfoto('urlaub.jpg', datum: DateTime(2023, 8, 15, 14, 30)),
    ]);
    // IMP-114: alles passt.
    await oeffneWerkzeug(tester, de.aufnahmedatenTitel);
    await waitFor(tester, find.text(de.aufnahmedatenKeine));
    await alleZurueck(tester);

    // IMP-115/117: zwei Fotos ohne EXIF-Datum, das Datum steht im Namen.
    final mitZeit = testfoto('24-11-13 10-48-28.jpg');
    final nurTag = testfoto('IMG-20240301-WA0001.jpg');
    final bytesVorher = mitZeit.readAsBytesSync();
    await importiereDirekt(tester, [mitZeit, nurTag]);
    await alsKopierdatum(tester, [
      '24-11-13 10-48-28.jpg',
      'IMG-20240301-WA0001.jpg',
    ]);
    final vorher = await aufnahme(tester, '24-11-13 10-48-28.jpg');
    expect(vorher.datumGeschaetzt, isTrue);

    await oeffneWerkzeug(tester, de.aufnahmedatenTitel);
    final zeile1 = find.ancestor(
      of: find.text('24-11-13 10-48-28.jpg'),
      matching: find.byType(CheckboxListTile),
    );
    final zeile2 = find.ancestor(
      of: find.text('IMG-20240301-WA0001.jpg'),
      matching: find.byType(CheckboxListTile),
    );
    await waitFor(tester, zeile1);
    await waitFor(tester, zeile2);
    final dz = DateFormat.yMMMd('de').add_Hm();
    final bisher =
        '${dz.format(vorher.fileCreatedAt.toLocal())} '
        '(${de.aufnahmedatenGeschaetzt})';
    final neu = dz.format(DateTime(2024, 11, 13, 10, 48));
    expect(
      find.descendant(
        of: zeile1,
        matching: find.textContaining('$bisher → $neu', findRichText: true),
      ),
      findsWidgets,
      reason: 'Zeile nennt bisher (geschätzt) → 13. Nov. 2024 10:48',
    );
    expect(
      find.descendant(
        of: zeile1,
        matching: find.textContaining(
          de.aufnahmedatenLautName,
          findRichText: true,
        ),
      ),
      findsWidgets,
    );
    // IMP-117: nur der Tag, ohne Uhrzeit, bleibt geschätzt.
    final nurTagText = DateFormat.yMMMd('de').format(DateTime(2024, 3, 1));
    expect(
      find.descendant(
        of: zeile2,
        matching: find.textContaining('→ $nurTagText\n', findRichText: true),
      ),
      findsWidgets,
      reason: 'Vorschlag ohne Uhrzeit',
    );
    expect(
      find.descendant(
        of: zeile2,
        matching: find.textContaining(
          '${de.aufnahmedatenLautName} · ${de.aufnahmedatenNurTag}',
          findRichText: true,
        ),
      ),
      findsWidgets,
    );

    // Nur die erste Zeile übernehmen.
    await tapFrei(
      tester,
      find.descendant(of: zeile2, matching: find.byType(Checkbox)),
    );
    await tapFrei(tester, find.text(de.aufnahmedatenUebernehmen(1)));
    await meldungGesehen(tester, de.aufnahmedatenUebernommen(1));
    final nachher = await aufnahme(tester, '24-11-13 10-48-28.jpg');
    expect(nachher.fileCreatedAt.year, 2024);
    expect(nachher.fileCreatedAt.month, 11);
    expect(nachher.fileCreatedAt.day, 13);
    expect(nachher.fileCreatedAt.hour, 10);
    expect(nachher.fileCreatedAt.minute, 48);
    expect(nachher.datumGeschaetzt, isFalse);
    expect(
      datei(nachher).readAsBytesSync(),
      bytesVorher,
      reason: 'Die Datei selbst bleibt unverändert',
    );
    print(
      'IMP-115 Ordner: vorher ${vorher.relativePath}, '
      'nachher ${nachher.relativePath}',
    );
    // Der Hinweis im Katalog: die Datei bleibt im alten Monatsordner.
    expect(nachher.relativePath, vorher.relativePath);

    await alleZurueck(tester);
    await openSection(tester, Hauptbereich.zeitleiste);
    await waitFor(tester, find.text('November 2024'));
    await ende(tester);
  });

  testWidgets('IMP-119 IMP-120 IMP-218 Datum im Info-Blatt', (tester) async {
    await startApp(tester);
    final ohne = testfoto('24-11-13 10-48-28.jpg');
    final sommer = testfoto('sommer.jpg', datum: DateTime(2023, 8, 15, 14, 30));
    final sommerBytes = sommer.readAsBytesSync();
    await importiereDirekt(tester, [ohne, sommer]);
    await alsKopierdatum(tester, ['24-11-13 10-48-28.jpg']);
    final a = await aufnahme(tester, '24-11-13 10-48-28.jpg');
    final b = await aufnahme(tester, 'sommer.jpg');
    // Beilage neben dem Original.
    final xmpAlt = bibliothek.paths.absolute(
      bibliothek.paths.xmpSidecarPath(b.relativePath),
    )..writeAsStringSync('<x:xmpmeta xmlns:x="adobe:ns:meta/"/>');

    // IMP-119: Vorschlag im Info-Blatt übernehmen.
    await oeffneFoto(tester, a.id);
    await tapFrei(tester, find.byTooltip(de.viewerInfo));
    final vorschlag = de.infoNameNennt(
      DateFormat.yMMMd('de').add_Hm().format(DateTime(2024, 11, 13, 10, 48)),
    );
    await waitFor(tester, find.text(vorschlag));
    await tapFrei(
      tester,
      find.descendant(
        of: find.byType(AssetInfoSheet),
        matching: find.widgetWithText(TextButton, de.infoDatumUebernehmen),
      ),
    );
    await waitFor(
      tester,
      find.descendant(
        of: find.byType(AssetInfoSheet),
        matching: find.text(
          DateFormat.yMMMd('de').format(DateTime(2024, 11, 13)),
        ),
      ),
    );
    await waitGone(tester, find.text(vorschlag));
    final aNachher = await aufnahme(tester, '24-11-13 10-48-28.jpg');
    print(
      'IMP-119 Ordner: vorher ${a.relativePath}, '
      'nachher ${aNachher.relativePath}',
    );
    await alleZurueck(tester);

    // IMP-120: Datum von Hand, die Datei zieht um.
    await oeffneFoto(tester, b.id);
    await tapFrei(tester, find.byTooltip(de.viewerInfo));
    final datumAlt = DateFormat.yMMMd('de').format(DateTime(2023, 8, 15));
    await tapFrei(tester, bearbeitenBeiDatum(datumAlt));
    await datumWaehlen(tester, DateTime(2021, 2, 3));
    final datumNeu = DateFormat.yMMMd('de').format(DateTime(2021, 2, 3));
    await waitFor(
      tester,
      find.descendant(
        of: find.byType(AssetInfoSheet),
        matching: find.text(datumNeu),
      ),
    );
    expect(
      find.descendant(
        of: find.byType(AssetInfoSheet),
        matching: find.text(de.infoDatumGeschaetzt),
      ),
      findsNothing,
    );
    late AssetData bNeu;
    await eventually(tester, () async {
      bNeu = (await bibliothek.db.assetById(b.id))!;
      return bNeu.relativePath.startsWith('originals/2021/02/');
    }, was: 'Original liegt unter originals/2021/02/');
    expect(bNeu.fileCreatedAt.year, 2021);
    expect(datei(bNeu).readAsBytesSync(), sommerBytes);
    expect(xmpAlt.existsSync(), isFalse, reason: 'alte Beilage ist weg');
    expect(
      bibliothek.paths
          .absolute(bibliothek.paths.xmpSidecarPath(bNeu.relativePath))
          .existsSync(),
      isTrue,
      reason: 'die .xmp zieht mit',
    );
    await alleZurueck(tester);

    // IMP-218: in den Papierkorb und zurück, dann Prüfsummen prüfen.
    await mitDb(tester, () => bibliothek.db.fuehreAus(InDenPapierkorb([b.id])));
    await mitDb(tester, () => bibliothek.ausPapierkorbHolen([b.id]));
    await oeffneWerkzeug(tester, de.werkzIntegritaetTitel);
    await warteIntegritaet(tester);
    await tapFrei(tester, find.text(de.integPruefsummen));
    await warteIntegritaet(tester);
    await waitFor(tester, find.textContaining('Keine Probleme gefunden'));
    expect(find.textContaining('Prüfsummen-Abweichungen'), findsNothing);
    await ende(tester);
  });

  // ---------------------------------------------------------------------
  // Ohne CLIP-Modell
  // ---------------------------------------------------------------------

  testWidgets('IMP-123 IMP-136 IMP-160 Ohne CLIP-Modell', (tester) async {
    await startApp(tester);
    final basis = testfoto('serie_1.jpg', datum: DateTime(2024, 7, 10, 10));
    await importiereDirekt(tester, [
      basis,
      variante(
        basis,
        'serie_2.jpg',
        breite: 780,
        hoehe: 585,
        datum: DateTime(2024, 7, 10, 10, 0, 3),
      ),
    ]);
    expect(bibliothek.clipAvailable, isFalse);
    // IMP-123
    await oeffneWerkzeug(tester, de.datierungTitel);
    await waitFor(tester, find.text(de.datierungOhneModell));
    await alleZurueck(tester);
    // IMP-160
    await oeffneWerkzeug(tester, de.werkzStapelTitel);
    await waitFor(
      tester,
      find.descendant(
        of: find.byType(StackReviewScreen),
        matching: find.text(de.allgClipNoetigKurz),
      ),
    );
    await alleZurueck(tester);
    // IMP-136
    await openSection(tester, Hauptbereich.duplikate);
    await waitFor(
      tester,
      find.descendant(
        of: find.byType(DuplicatesScreen),
        matching: find.text(de.allgClipNoetigKurz),
      ),
    );
    await ende(tester);
  });

  // Behoben in #409: Die Zeile steht auch bei 0 Serien, mit „Keine Serien
  // gefunden“.
  testWidgets('IMP-154 Ohne Serien steht „Keine Serien gefunden"', (
    tester,
  ) async {
    await startApp(tester);
    await importiereDirekt(tester, [testfoto('einzeln.jpg')]);
    await openSection(tester, Hauptbereich.werkzeuge);
    final titel = find.descendant(
      of: find.byType(ToolsScreen),
      matching: find.text(de.werkzStapelTitel),
    );
    await sichtbar(tester, titel, ToolsScreen);
    await settle(tester);
    expect(find.text(de.werkzStapelGefunden(0)), findsOneWidget);
    await ende(tester);
  });

  // ---------------------------------------------------------------------
  // Alte Fotos zeitlich einordnen (mit nachgestelltem CLIP)
  // ---------------------------------------------------------------------

  testWidgets('IMP-124 Alte Fotos zeitlich einordnen', (tester) async {
    await startApp(tester);
    await importiereDirekt(tester, [
      testfoto('scan_alt.jpg'),
      testfoto('modern.jpg', datum: DateTime(2023, 5, 1, 12, 13, 14)),
    ]);
    clipNachstellen();
    final scan = await aufnahme(tester, 'scan_alt.jpg');
    expect(scan.datumGeschaetzt, isTrue);
    await einbettungenSetzen(tester, fest: {scan.id: jahrzehntVektor(1960)});

    await oeffneWerkzeug(tester, de.datierungTitel);
    await waitFor(tester, find.text(de.datierungUm('1965')));
    expect(find.text(de.datierungSpanne('1960', '1969')), findsOneWidget);
    await tapFrei(
      tester,
      find.widgetWithText(TextButton, de.datierungUebernehmen),
    );
    await waitFor(tester, find.text(de.datierungIstUebernommen));
    await meldungGesehen(tester, de.datierungUebernommen(1));
    final nachher = (await mitDb(
      tester,
      () => bibliothek.db.assetById(scan.id),
    ))!;
    expect(nachher.fileCreatedAt, DateTime(1965, 7, 1, 12));
    expect(nachher.datumGeschaetzt, isTrue, reason: 'bleibt geschätzt');
    print(
      'IMP-124 Ordner: vorher ${scan.relativePath}, '
      'nachher ${nachher.relativePath}',
    );
    await alleZurueck(tester);
    await openSection(tester, Hauptbereich.zeitleiste);
    await waitFor(tester, find.text('Juli 1965'));
    await ende(tester);
  });

  // Befund: Übernommene Daten aus dem Dateinamen (aufnahmedaten_screen.dart:58),
  // aus dem Info-Blatt (asset_info_sheet.dart:176) und aus der Datierung
  // (datierung_screen.dart:48) gehen nur in die Datenbank. Das Original
  // bleibt im Monatsordner des alten Datums – anders als beim Datum von
  // Hand (library_state.dart:2834, setzeAufnahmedatumVonHand).
  testWidgets('IMP-115 IMP-119 IMP-124 Übernommenes Datum legt die Datei um', (
    tester,
  ) async {
    await zweimal(tester, () async {
      await importiereDirekt(tester, [
        testfoto('24-11-13 10-48-28.jpg'),
        testfoto('2019-03-04 08-09-10.jpg'),
        testfoto('scan_alt.jpg'),
      ]);
      clipNachstellen();
      await alsKopierdatum(tester, [
        '24-11-13 10-48-28.jpg',
        '2019-03-04 08-09-10.jpg',
      ]);
      final a = await aufnahme(tester, '24-11-13 10-48-28.jpg');
      final b = await aufnahme(tester, '2019-03-04 08-09-10.jpg');
      final c = await aufnahme(tester, 'scan_alt.jpg');
      await einbettungenSetzen(tester, fest: {c.id: jahrzehntVektor(1960)});
      final probleme = <String>[];

      // Aufnahmedaten-Bildschirm (nur a übernehmen).
      await oeffneWerkzeug(tester, de.aufnahmedatenTitel);
      final zeileB = find.ancestor(
        of: find.text('2019-03-04 08-09-10.jpg'),
        matching: find.byType(CheckboxListTile),
      );
      await waitFor(tester, zeileB);
      await tapFrei(
        tester,
        find.descendant(of: zeileB, matching: find.byType(Checkbox)),
      );
      await tapFrei(tester, find.text(de.aufnahmedatenUebernehmen(1)));
      await meldungGesehen(tester, de.aufnahmedatenUebernommen(1));
      final a2 = await aufnahme(tester, '24-11-13 10-48-28.jpg');
      if (!a2.relativePath.startsWith('originals/2024/11/')) {
        probleme.add('Aufnahmedaten: ${a.relativePath} → ${a2.relativePath}');
      }
      await alleZurueck(tester);

      // Info-Blatt (b).
      await oeffneFoto(tester, b.id);
      await tapFrei(tester, find.byTooltip(de.viewerInfo));
      await tapFrei(
        tester,
        find.descendant(
          of: find.byType(AssetInfoSheet),
          matching: find.widgetWithText(TextButton, de.infoDatumUebernehmen),
        ),
      );
      await settle(tester);
      final b2 = await aufnahme(tester, '2019-03-04 08-09-10.jpg');
      if (!b2.relativePath.startsWith('originals/2019/03/')) {
        probleme.add('Info-Blatt: ${b.relativePath} → ${b2.relativePath}');
      }
      await alleZurueck(tester);

      // Datierung (c).
      await oeffneWerkzeug(tester, de.datierungTitel);
      await tapFrei(
        tester,
        find.widgetWithText(TextButton, de.datierungUebernehmen),
      );
      await waitFor(tester, find.text(de.datierungIstUebernommen));
      final c2 = await aufnahme(tester, 'scan_alt.jpg');
      if (!c2.relativePath.startsWith('originals/1965/07/')) {
        probleme.add('Datierung: ${c.relativePath} → ${c2.relativePath}');
      }
      await alleZurueck(tester);

      // Danach meldet die Ablage-Aufgabe genau diese drei.
      final offen = await mitDb(tester, () => bibliothek.zaehleAblageordnung());
      print('IMP-115/119/124: Ablage offen: $offen; $probleme');
      expect(probleme, isEmpty);
    });
  }, skip: true);

  // ---------------------------------------------------------------------
  // Duplikate & ähnliche Fotos
  // ---------------------------------------------------------------------

  testWidgets(
    'IMP-137 IMP-138 IMP-143 IMP-144 IMP-139 Duplikate finden, übergehen, behalten',
    (tester) async {
      await startApp(tester);
      final a = testfoto('a.jpg', datum: DateTime(2024, 5, 1, 10, 0, 0));
      final b = variante(
        a,
        'b.jpg',
        breite: 640,
        hoehe: 480,
        datum: DateTime(2024, 5, 1, 10, 0, 5),
      );
      final c = testfoto('c.jpg', datum: DateTime(2024, 6, 1, 11, 0, 0));
      await importiereDirekt(tester, [a, b, c]);
      clipNachstellen();
      await einbettungenSetzen(tester);
      final fa = await aufnahme(tester, 'a.jpg');
      final fb = await aufnahme(tester, 'b.jpg');
      final albumId = const Uuid().v4();
      await mitDb(tester, () async {
        await bibliothek.db.fuehreAus(SchlagwortAnheften([fa.id], 'Tag A'));
        await bibliothek.db.fuehreAus(
          AlbumAnlegen(albumId, 'Album A', DateTime.now()),
        );
        await bibliothek.db.fuehreAus(AlbumFuellen(albumId, [fa.id]));
        await bibliothek.db.fuehreAus(BewertungSetzen([fb.id], 3));
      });

      // IMP-137
      await openSection(tester, Hauptbereich.duplikate);
      await waitFor(tester, find.text(de.duplGefunden(1, 2)));
      expect(find.text(de.duplAufnahmen(2)), findsOneWidget);
      expect(find.text('a.jpg'), findsWidgets);
      expect(find.text('b.jpg'), findsWidgets);
      expect(find.textContaining('800 × 600'), findsOneWidget);
      expect(find.textContaining('640 × 480'), findsOneWidget);
      expect(
        find.textContaining(
          DateFormat.yMMMd('de').add_Hm().format(DateTime(2024, 5, 1, 10)),
        ),
        findsWidgets,
      );
      expect(find.text(de.duplBehalten), findsNWidgets(2));
      // Umrandet und mit gefülltem Knopf: b (3 Sterne).
      expect(
        find.descendant(
          of: dupSpalte('b.jpg'),
          matching: find.widgetWithText(FilledButton, de.duplBehalten),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: dupSpalte('a.jpg'),
          matching: find.widgetWithText(OutlinedButton, de.duplBehalten),
        ),
        findsOneWidget,
      );

      // IMP-138: Regler auf 80 %.
      final regler = find.descendant(
        of: find.byType(DuplicatesScreen),
        matching: find.byType(Slider),
      );
      final r = tester.getRect(regler);
      await tester.tapAt(Offset(r.left + 1, r.center.dy));
      await settle(tester);
      await waitFor(tester, find.text('80 %'));
      await waitGone(
        tester,
        find.descendant(
          of: find.byType(DuplicatesScreen),
          matching: find.byType(CircularProgressIndicator),
        ),
      );
      expect(find.textContaining(' Gruppen mit '), findsWidgets);
      // Neu öffnen: wieder 92 %.
      await openSection(tester, Hauptbereich.zeitleiste);
      await openSection(tester, Hauptbereich.duplikate);
      await waitFor(tester, find.text(de.duplGefunden(1, 2)));
      expect(find.text('92 %'), findsOneWidget);

      // IMP-143: „Keine Duplikate" und Rückgängig.
      await tippe(tester, find.text(de.duplGruppeIgnorieren));
      await waitGone(tester, find.text(de.duplAufnahmen(2)));
      await meldungGesehen(tester, de.duplGruppeIgnoriert(2));
      await tap(tester, find.text(de.allgRueckgaengig).last);
      await waitFor(tester, find.text(de.duplAufnahmen(2)));

      // IMP-144: übergangen und wieder anzeigen.
      await tapFrei(tester, find.text(de.duplGruppeIgnorieren));
      await waitGone(tester, find.text(de.duplAufnahmen(2)));
      await tapFrei(tester, find.text(de.duplAusnahmenZahl(1)));
      await waitFor(tester, find.text(de.duplAusnahmenTitel));
      await tapFrei(tester, find.text(de.duplAusnahmenLoeschen));
      await waitFor(tester, find.text(de.duplAufnahmen(2)));
      expect(find.text(de.duplAusnahmenZahl(1)), findsNothing);

      // IMP-139: a behalten führt zusammen.
      await tapFrei(
        tester,
        find.descendant(
          of: dupSpalte('a.jpg'),
          matching: find.text(de.duplBehalten),
        ),
      );
      await waitFor(tester, find.text(de.duplBehaltenEine('a.jpg')));
      await tapFrei(
        tester,
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(de.duplBehalten),
        ),
      );
      await meldungGesehen(tester, de.duplZusammengefuehrt(1));
      await eventually(tester, () async {
        final fb2 = await bibliothek.db.assetById(fb.id);
        return fb2!.isTrashed;
      }, was: 'b liegt im Papierkorb');
      final fa2 = (await mitDb(tester, () => bibliothek.db.assetById(fa.id)))!;
      expect(fa2.isTrashed, isFalse);
      expect(fa2.rating, 3);
      final tags = await mitDb(tester, () => bibliothek.db.tagsForAsset(fa.id));
      expect([for (final t in tags) t.name], contains('Tag A'));
      final imAlbum = await mitDb(
        tester,
        () =>
            (bibliothek.db.select(bibliothek.db.albumAssets)..where(
                  (t) => t.albumId.equals(albumId) & t.assetId.equals(fa.id),
                ))
                .get(),
      );
      expect(imAlbum, hasLength(1));
      await ende(tester);
    },
  );

  testWidgets('IMP-140 IMP-141 Kopien in den Papierkorb, Favoriten-Gruppen', (
    tester,
  ) async {
    await startApp(tester);
    final g1a = testfoto('g1a.jpg', datum: DateTime(2024, 1, 1, 9, 0, 1));
    final g1b = variante(g1a, 'g1b.jpg', breite: 400, hoehe: 300);
    final g2a = testfoto('g2a.jpg', datum: DateTime(2024, 2, 1, 9, 0, 1));
    final g2b = variante(g2a, 'g2b.jpg', breite: 400, hoehe: 300);
    await importiereDirekt(tester, [g1a, g1b, g2a, g2b]);
    clipNachstellen();
    await einbettungenSetzen(tester);
    await analyseAbwarten(tester);
    // Die kleine Kopie ist schärfer als das Original.
    final a2 = await aufnahme(tester, 'g2a.jpg');
    final b2 = await aufnahme(tester, 'g2b.jpg');
    await schaerfeSetzen(tester, {a2.id: 100, b2.id: 500});

    await openSection(tester, Hauptbereich.duplikate);
    await waitFor(tester, find.text(de.duplGefunden(2, 4)));
    // Umrandet ist in g2 das Original (volle Auflösung), nicht die schärfere
    // Kopie – siehe den Befund-Test zum Regeltext.
    expect(
      find.descendant(
        of: dupSpalte('g2a.jpg'),
        matching: find.widgetWithText(FilledButton, de.duplBehalten),
      ),
      findsOneWidget,
    );
    await tapFrei(tester, find.text(de.duplKopienInPapierkorb(2)));
    await waitFor(tester, find.text(de.duplPapierkorbTitel));
    expect(find.text(de.duplPapierkorbAnzahl(2, 2)), findsOneWidget);
    expect(find.text(de.duplRueckgaengig), findsOneWidget);
    print('IMP-140 Regeltext im Dialog: ${de.duplBehaltenRegel}');
    await tapFrei(tester, find.text(de.duplInPapierkorb));
    await meldungGesehen(tester, de.duplVerschoben(2));
    final nachher = {
      for (final a in await alleAufnahmen(tester)) a.originalFileName: a,
    };
    expect(nachher['g1a.jpg']!.isTrashed, isFalse);
    expect(nachher['g2a.jpg']!.isTrashed, isFalse);
    expect(nachher['g1b.jpg']!.isTrashed, isTrue);
    expect(nachher['g2b.jpg']!.isTrashed, isTrue);

    // IMP-141: eine Gruppe mit zwei Favoriten und eine normale.
    final f1 = testfoto('f1.jpg', datum: DateTime(2024, 3, 1, 9, 0, 1));
    final f2 = variante(f1, 'f2.jpg', breite: 700, hoehe: 525);
    final g3a = testfoto('g3a.jpg', datum: DateTime(2024, 4, 1, 9, 0, 1));
    final g3b = variante(g3a, 'g3b.jpg', breite: 400, hoehe: 300);
    await importiereDirekt(tester, [f1, f2, g3a, g3b]);
    await einbettungenSetzen(tester);
    final ff1 = await aufnahme(tester, 'f1.jpg');
    final ff2 = await aufnahme(tester, 'f2.jpg');
    await mitDb(
      tester,
      () => bibliothek.db.fuehreAus(FavoritSetzen([ff1.id, ff2.id], true)),
    );
    await openSection(tester, Hauptbereich.zeitleiste);
    await openSection(tester, Hauptbereich.duplikate);
    await waitFor(tester, find.text(de.duplNurVonHand(2)));
    await tapFrei(tester, find.text(de.duplKopienInPapierkorb(1)));
    await waitFor(tester, find.text(de.duplUebersprungen(1)));
    await tapFrei(
      tester,
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(de.allgAbbrechen),
      ),
    );
    // g3 von Hand erledigen – danach bleibt nur die Favoriten-Gruppe.
    await tapFrei(
      tester,
      find.descendant(
        of: dupSpalte('g3a.jpg'),
        matching: find.text(de.duplBehalten),
      ),
    );
    await tapFrei(
      tester,
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(de.duplBehalten),
      ),
    );
    await waitGone(tester, find.text('g3a.jpg'));
    expect(find.text(de.duplNurVonHand(2)), findsOneWidget);
    expect(
      find.textContaining(RegExp(r'Kopien? in den Papierkorb')),
      findsNothing,
    );
    await ende(tester);
  });

  // Behoben in #409: Der Regeltext nennt die volle Auflösung (und RAW) vor
  // der Schärfe, wie duplicate_selection.dart seit #249 auswählt. Bei einer
  // schärferen, verkleinerten Kopie bleibt das Original – und so steht es
  // auch im Dialog.
  testWidgets('IMP-140 Regeltext im Dialog stimmt mit der Auswahl überein', (
    tester,
  ) async {
    await startApp(tester);
    final g = testfoto('gross.jpg', datum: DateTime(2024, 2, 1, 9, 0, 1));
    final k = variante(g, 'klein.jpg', breite: 400, hoehe: 300);
    await importiereDirekt(tester, [g, k]);
    clipNachstellen();
    await einbettungenSetzen(tester);
    await analyseAbwarten(tester);
    final gg = await aufnahme(tester, 'gross.jpg');
    final kk = await aufnahme(tester, 'klein.jpg');
    await schaerfeSetzen(tester, {gg.id: 100, kk.id: 500});
    await openSection(tester, Hauptbereich.duplikate);
    await waitFor(tester, find.text(de.duplGefunden(1, 2)));
    await tapFrei(tester, find.text(de.duplKopienInPapierkorb(1)));
    await waitFor(tester, find.text(de.duplBehaltenRegel));
    final regel = de.duplBehaltenRegel;
    expect(
      regel.indexOf('voller Auflösung'),
      allOf(isNonNegative, lessThan(regel.indexOf('schärfste'))),
      reason: 'der Text nennt die volle Auflösung vor der Schärfe',
    );
    // Und so wählt die App auch: das Original, nicht die schärfere Kopie.
    expect(
      find.descendant(
        of: dupSpalte('gross.jpg'),
        matching: find.widgetWithText(FilledButton, de.duplBehalten),
      ),
      findsOneWidget,
      reason: 'laut Dialog bleibt die Fassung in voller Auflösung',
    );
    await ende(tester);
  });

  testWidgets('IMP-147 Aus der Gruppe in Papierkorb und gesperrten Ordner', (
    tester,
  ) async {
    await startApp(tester);
    final h1 = testfoto('h1.jpg', datum: DateTime(2024, 5, 5, 10, 0, 0));
    final h2 = variante(h1, 'h2.jpg', breite: 700, hoehe: 525);
    final h3 = variante(h1, 'h3.jpg', breite: 600, hoehe: 450);
    await importiereDirekt(tester, [h1, h2, h3]);
    clipNachstellen();
    await einbettungenSetzen(tester);
    await mitDb(tester, () async {
      await bibliothek.setupVaultPin(_pin);
      await bibliothek.sperreTresor();
    });
    final a3 = await aufnahme(tester, 'h3.jpg');
    final a2 = await aufnahme(tester, 'h2.jpg');

    await openSection(tester, Hauptbereich.duplikate);
    await waitFor(tester, find.text(de.duplAufnahmen(3)));
    await tapFrei(tester, kachel(a3.id));
    await tapFrei(tester, find.byTooltip(de.viewerInPapierkorb));
    await tapFrei(
      tester,
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(de.allgLoeschen),
      ),
    );
    await waitFor(tester, find.text(de.duplAufnahmen(2)));
    expect(
      (await mitDb(tester, () => bibliothek.db.assetById(a3.id)))!.isTrashed,
      isTrue,
    );

    await tapFrei(tester, kachel(a2.id));
    await tapFrei(tester, find.byTooltip(de.viewerInGesperrtenOrdner));
    await waitFor(tester, find.text(de.pinEingebenTitel));
    await enter(tester, field(de.pinFeld), _pin);
    await tapFrei(tester, find.text('OK'));
    await waitFor(tester, find.text(de.duplKeineGruppen));
    await eventually(tester, () async {
      return (await bibliothek.db.assetById(a2.id))!.isLocked;
    }, was: 'h2 ist gesperrt');
    await ende(tester);
  });

  testWidgets('IMP-149 IMP-150 Zweite Bibliothek vergleichen', (tester) async {
    await startApp(tester);
    final eigen = testfoto('eigen.jpg', datum: DateTime(2024, 3, 3, 3, 3, 3));
    await importiereDirekt(tester, [eigen]);
    clipNachstellen();
    await einbettungenSetzen(tester);

    // Die zweite Bibliothek: library.sqlite + library/.
    final zweite = Directory(p.join(anker.path, 'zweite'))..createSync();
    final treffer = variante(eigen, 'treffer.jpg', breite: 640, hoehe: 480);
    final geheim = variante(eigen, 'geheim.jpg', breite: 600, hoehe: 450);
    final anders = testfoto('anders.jpg');
    final dbDatei = File(p.join(zweite.path, 'library.sqlite'));
    await tester.runAsync(() async {
      final db2 = AppDatabase(NativeDatabase(dbDatei));
      final paths2 = await StoragePaths.forTesting(
        Directory(p.join(zweite.path, 'library')),
      );
      final import2 = ImportService(db2, paths2);
      for (final f in [treffer, geheim, anders]) {
        final r = await import2.importFile(f.path);
        await db2.saveEmbedding(
          r.assetId!,
          bildmerkmal(img.decodeJpg(f.readAsBytesSync())!),
        );
        if (f == geheim) await db2.setAssetsLocked([r.assetId!], true);
      }
      await db2.close();
    });
    final dbVorher = dbDatei.readAsBytesSync();

    await openSection(tester, Hauptbereich.duplikate);
    await tapFrei(tester, find.text(de.duplZweiteBibliothek));
    await waitFor(tester, find.text(de.zweitTitel));
    ordnerwahlNachstellen(tester, zweite.path);
    await tapFrei(tester, find.text(de.zweitOrdnerKnopf));
    await waitFor(
      tester,
      find.text(de.zweitTreffer(1)),
      timeout: const Duration(seconds: 40),
    );
    expect(find.textContaining('% ähnlich'), findsWidgets);
    expect(find.textContaining('treffer.jpg'), findsWidgets);
    expect(find.textContaining('geheim.jpg'), findsNothing);
    expect(dbDatei.readAsBytesSync(), dbVorher, reason: 'byte-gleich');

    // IMP-150: Ordner ohne library.sqlite.
    final leer = Directory(p.join(anker.path, 'leer'))..createSync();
    ordnerwahlNachstellen(tester, leer.path);
    await tapFrei(tester, find.text(de.zweitAndererOrdner));
    await waitFor(tester, find.textContaining('Vergleich fehlgeschlagen'));
    expect(find.text(de.allgErneutVersuchen), findsOneWidget);
    ordnerwahlNachstellen(tester, null);
    await ende(tester);
  });

  testWidgets('IMP-151 IMP-152 IMP-153 Ähnliche Fotos', (tester) async {
    await startApp(tester);
    final quelle = testfoto('quelle.jpg', datum: DateTime(2024, 9, 1, 9, 1, 1));
    final nah = variante(quelle, 'nah.jpg', breite: 700, hoehe: 525);
    final mittel = variante(
      quelle,
      'mittel.jpg',
      breite: 800,
      hoehe: 600,
      zeichne: (b) => img.fillRect(
        b,
        x1: 0,
        y1: 0,
        x2: 330,
        y2: 599,
        color: img.ColorRgb8(250, 250, 250),
      ),
    );
    final gesperrt = variante(quelle, 'gesperrt.jpg', breite: 760, hoehe: 570);
    final fremd = testfoto('fremd.jpg', datum: DateTime(2024, 9, 2, 9, 1, 1));
    final ohne = testfoto('ohne.jpg', datum: DateTime(2024, 9, 3, 9, 1, 1));
    await importiereDirekt(tester, [
      quelle,
      nah,
      mittel,
      gesperrt,
      fremd,
      ohne,
    ]);
    clipNachstellen();
    final o = await aufnahme(tester, 'ohne.jpg');
    await einbettungenSetzen(tester, ohne: {o.id});
    final g = await aufnahme(tester, 'gesperrt.jpg');
    await mitDb(tester, () async {
      await bibliothek.setupVaultPin(_pin);
      await bibliothek.lockAsset(g);
    });
    final q = await aufnahme(tester, 'quelle.jpg');
    final n = await aufnahme(tester, 'nah.jpg');
    final m = await aufnahme(tester, 'mittel.jpg');

    await oeffneFoto(tester, q.id);
    await rechtsklickImBild(tester);
    await tapFrei(tester, find.text(de.viewerAehnlicheZeigen));
    await waitFor(tester, find.text(de.aehnlTitel));
    final kacheln = find.descendant(
      of: find.byType(SimilarPhotosScreen),
      matching: find.byType(AssetThumbnailTile),
    );
    await waitFor(tester, kacheln);
    final ids = [
      for (final k in tester.widgetList<AssetThumbnailTile>(kacheln))
        k.asset.id,
    ];
    print('IMP-151 Reihenfolge: $ids');
    expect(ids.first, n.id, reason: 'das ähnlichste zuerst');
    expect(ids, contains(m.id));
    expect(ids, isNot(contains(q.id)), reason: 'das Ausgangsfoto fehlt');
    expect(ids, isNot(contains(g.id)), reason: 'IMP-153: gesperrt fehlt');
    expect(ids.length, lessThanOrEqualTo(60));
    await alleZurueck(tester);

    // IMP-152: Foto ohne Einbettung.
    await oeffneFoto(tester, o.id);
    await rechtsklickImBild(tester);
    await tapFrei(tester, find.text(de.viewerAehnlicheZeigen));
    await waitFor(tester, find.text(de.aehnlKeineTreffer));
    await ende(tester);
  });

  // Behoben in #409: Beide Texte nennen Werkzeuge → Aufgaben und den Namen
  // der Aufgabe; geprüft wird, dass es diese Einträge dort gibt.
  testWidgets('IMP-152 IMP-211 Wegweiser in Texten führen zum Ziel', (
    tester,
  ) async {
    await startApp(tester);
    await importiereDirekt(tester, [testfoto('x.jpg')]);
    final weg = '${de.navWerkzeuge} → ${de.aufgTitel}';
    final ziele = {
      de.aehnlKeineTreffer: de.aufgEmbeddingsTitel,
      de.integPfadEntfernt: de.aufgVorschauTitel,
    };
    final fehlt = <String>[];
    for (final MapEntry(key: text, value: aufgabe) in ziele.entries) {
      if (!text.contains(weg) || !text.contains(aufgabe)) fehlt.add(text);
    }
    await oeffneAufgaben(tester);
    for (final aufgabe in ziele.values) {
      final f = find.descendant(
        of: find.byType(BackgroundTasksScreen),
        matching: find.text(aufgabe),
      );
      try {
        await sichtbar(tester, f, BackgroundTasksScreen);
      } catch (_) {
        fehlt.add(aufgabe);
      }
    }
    print('Wegweiser ohne Ziel: $fehlt');
    expect(fehlt, isEmpty);
    await ende(tester);
  });

  // ---------------------------------------------------------------------
  // Serien
  // ---------------------------------------------------------------------

  testWidgets(
    'IMP-154 IMP-155 IMP-156 IMP-158 IMP-161 IMP-162 IMP-163 IMP-164 Serien',
    (tester) async {
      await startApp(tester);
      final s1 = serie('s1', DateTime(2024, 7, 10, 10, 0, 0));
      await importiereDirekt(tester, s1);
      clipNachstellen();
      await einbettungenSetzen(tester);

      // IMP-154
      await openSection(tester, Hauptbereich.werkzeuge);
      final stapelTitel = find.descendant(
        of: find.byType(ToolsScreen),
        matching: find.text(de.werkzStapelTitel),
      );
      await sichtbar(tester, stapelTitel, ToolsScreen);
      await waitFor(tester, find.text(de.werkzStapelGefunden(1)));

      // Zweite Serie ohne Gesichter.
      await importiereDirekt(tester, serie('s2', DateTime(2024, 8, 1, 12)));
      await einbettungenSetzen(tester);
      final a = await aufnahme(tester, 's1_1.jpg');
      final b = await aufnahme(tester, 's1_2.jpg');
      final c = await aufnahme(tester, 's1_3.jpg');
      final s2erstes = await aufnahme(tester, 's2_1.jpg');
      // Gesichter für s1: b ist das schärfste.
      await gesichtSetzen(tester, a.id, schaerfe: 40, augen: 0.9);
      await gesichtSetzen(tester, b.id, schaerfe: 90, augen: 0.2);
      await gesichtSetzen(tester, c.id, schaerfe: 60, augen: 0.8);

      await oeffneWerkzeug(tester, de.werkzStapelTitel);
      await waitFor(tester, find.text(de.stapelSerie(2, 3)));
      final block1 = serienblock(kachel(a.id));
      final block2 = serienblock(kachel(s2erstes.id));

      // IMP-162: Serie ohne Gesichter.
      await tapFrei(
        tester,
        find.descendant(
          of: block2,
          matching: find.text(de.serienvergleichOeffnen),
        ),
      );
      await waitFor(tester, find.text(de.serienvergleichTitel));
      await waitFor(tester, find.text(de.serienvergleichOhneGesichter));
      await zurueck(tester);

      // IMP-161: Serie mit Gesichtern.
      await tapFrei(
        tester,
        find.descendant(
          of: block1,
          matching: find.text(de.serienvergleichOeffnen),
        ),
      );
      await waitFor(tester, find.text(de.serienvergleichErklaerung));
      final vergleich = find.byType(SerienvergleichScreen);
      expect(
        find.descendant(of: vergleich, matching: find.byType(StarRating)),
        findsNWidgets(3),
      );
      for (final w in [40, 90, 60]) {
        expect(find.text(de.serienvergleichSchaerfe(w)), findsOneWidget);
      }
      expect(find.text(de.serienvergleichAugen(20)), findsOneWidget);
      expect(find.text(de.serienvergleichSchaerfstes), findsOneWidget);
      expect(
        find.descendant(
          of: vergleichsspalte(b.id),
          matching: find.text(de.serienvergleichSchaerfstes),
        ),
        findsOneWidget,
      );
      // IMP-163: 4 Sterne in der Spalte von a.
      await tapFrei(
        tester,
        find
            .descendant(
              of: find.descendant(
                of: vergleichsspalte(a.id),
                matching: find.byType(StarRating),
              ),
              matching: find.byType(InkWell),
            )
            .at(3),
      );
      await eventually(tester, () async {
        return (await bibliothek.db.assetById(a.id))!.rating == 4;
      }, was: 'Bewertung 4 gespeichert');
      await zurueck(tester);

      // IMP-156: zweite Serie verwerfen, Bildschirm neu öffnen.
      await tapFrei(
        tester,
        find.descendant(of: block2, matching: find.text(de.allgVerwerfen)),
      );
      await waitGone(tester, kachel(s2erstes.id));
      await alleZurueck(tester);
      await oeffneWerkzeug(tester, de.werkzStapelTitel);
      await waitFor(tester, find.text(de.stapelSerie(1, 3)));
      expect(kachel(s2erstes.id), findsNothing);

      // IMP-155: drittes Foto als Titelbild, übernehmen.
      final block = serienblock(kachel(a.id));
      final kachelnImBlock = find.descendant(
        of: block,
        matching: find.byType(AssetThumbnailTile),
      );
      final drittes = tester
          .widgetList<AssetThumbnailTile>(kachelnImBlock)
          .elementAt(2)
          .asset
          .id;
      await tapFrei(tester, kachelnImBlock.at(2));
      expect(
        find.descendant(
          of: find.ancestor(of: kachel(drittes), matching: find.byType(Stack)),
          matching: find.byIcon(Icons.star),
        ),
        findsWidgets,
      );
      await tapFrei(
        tester,
        find.descendant(
          of: block,
          matching: find.widgetWithText(FilledButton, de.allgUebernehmen),
        ),
      );
      await waitFor(tester, find.text(de.stapelKeine));
      final nachStapel = {
        for (final x in await alleAufnahmen(tester))
          if (x.originalFileName.startsWith('s1_')) x.id: x,
      };
      expect(nachStapel, hasLength(3), reason: 'nichts gelöscht');
      expect(nachStapel.values.every((x) => !x.isTrashed), isTrue);
      expect(nachStapel[drittes]!.isStackCover, isTrue);
      expect(nachStapel.values.map((x) => x.stackId).toSet(), hasLength(1));
      await alleZurueck(tester);
      await openSection(tester, Hauptbereich.zeitleiste);
      await waitFor(tester, kachel(drittes));
      for (final id in nachStapel.keys) {
        if (id != drittes) expect(kachel(id), findsNothing);
      }

      // IMP-164: Vergleich aus dem Info-Blatt, in Aufnahmereihenfolge.
      await oeffneFoto(tester, drittes);
      await tapFrei(tester, find.byTooltip(de.viewerInfo));
      await waitFor(tester, find.text(de.infoSerie(3)));
      await tapFrei(
        tester,
        find.descendant(
          of: find.byType(AssetInfoSheet),
          matching: find.text(de.serienvergleichOeffnen),
        ),
      );
      await waitFor(tester, find.text(de.serienvergleichTitel));
      final reihenfolge = [
        for (final k in tester.widgetList<AssetThumbnailTile>(
          find.descendant(
            of: find.byType(SerienvergleichScreen),
            matching: find.byType(AssetThumbnailTile),
          ),
        ))
          k.asset.id,
      ];
      expect(reihenfolge, [a.id, b.id, c.id]);
      await zurueck(tester);

      // IMP-158: Serie auflösen.
      await tapFrei(tester, find.byTooltip(de.infoSerieAufloesen));
      await alleZurueck(tester);
      for (final id in nachStapel.keys) {
        await waitFor(tester, kachel(id));
      }

      // IMP-163 (Rest): die Bewertung steht im Info-Blatt.
      await oeffneFoto(tester, a.id);
      await tapFrei(tester, find.byTooltip(de.viewerInfo));
      await waitFor(tester, find.byType(AssetInfoSheet));
      final sterne = tester.widget<StarRating>(
        find
            .descendant(
              of: find.byType(AssetInfoSheet),
              matching: find.byType(StarRating),
            )
            .first,
      );
      expect(sterne.value, 4);
      await ende(tester);
    },
  );

  testWidgets('IMP-157 Alle Serien übernehmen', (tester) async {
    await startApp(tester);
    await importiereDirekt(tester, [
      ...serie('s1', DateTime(2024, 7, 10, 10)),
      ...serie('s2', DateTime(2024, 8, 1, 12)),
    ]);
    clipNachstellen();
    await einbettungenSetzen(tester);
    await oeffneWerkzeug(tester, de.werkzStapelTitel);
    await tapFrei(tester, find.text(de.stapelAlleUebernehmen(2)));
    await waitFor(tester, find.text(de.stapelAlleFrageTitel));
    final knopf = tester.widget<FilledButton>(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(FilledButton),
      ),
    );
    print('IMP-157 Bestätigungsknopf: ${(knopf.child as Text).data}');
    await tapFrei(
      tester,
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(FilledButton),
      ),
    );
    await waitFor(tester, find.text(de.stapelKeine));
    final stapel = {
      for (final x in await alleAufnahmen(tester))
        if (x.stackId != null) x.stackId,
    };
    expect(stapel, hasLength(2));
    await ende(tester);
  });

  // Behoben in #409: Der Knopf in „Alle Serien übernehmen?“ heisst
  // „Übernehmen“.
  testWidgets('IMP-157 Bestätigungsknopf heisst nicht „Löschen"', (
    tester,
  ) async {
    await startApp(tester);
    await importiereDirekt(tester, [
      ...serie('s1', DateTime(2024, 7, 10, 10)),
      ...serie('s2', DateTime(2024, 8, 1, 12)),
    ]);
    clipNachstellen();
    await einbettungenSetzen(tester);
    await oeffneWerkzeug(tester, de.werkzStapelTitel);
    await tapFrei(tester, find.text(de.stapelAlleUebernehmen(2)));
    await waitFor(tester, find.text(de.stapelAlleFrageTitel));
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(de.allgLoeschen),
      ),
      findsNothing,
    );
    await ende(tester);
  });

  testWidgets('IMP-165 Hauptversion eines Variantenstapels', (tester) async {
    await startApp(tester);
    final v1 = testfoto('fassung_a.jpg', datum: DateTime(2024, 4, 4, 4, 4, 4));
    final v2 = variante(v1, 'fassung_b.jpg', breite: 640, hoehe: 480);
    await importiereDirekt(tester, [v1, v2]);
    final a = await aufnahme(tester, 'fassung_a.jpg');
    final b = await aufnahme(tester, 'fassung_b.jpg');
    await mitDb(
      tester,
      () => bibliothek.db.fuehreAus(
        VariantenBilden(const Uuid().v4(), [a.id, b.id], a.id),
      ),
    );
    await settle(tester);
    await waitFor(tester, kachel(a.id));
    expect(kachel(b.id), findsNothing);
    await oeffneFoto(tester, a.id);
    await tapFrei(tester, find.byTooltip(de.viewerInfo));
    await waitFor(tester, find.text(de.infoVarianten(2)));
    await tapFrei(tester, find.text(de.variantenvergleichOeffnen));
    await waitFor(tester, find.text(de.variantenvergleichTitel));
    expect(
      find.descendant(
        of: vergleichsspalte(a.id),
        matching: find.text(de.variantenvergleichHaupt),
      ),
      findsOneWidget,
    );
    await tapFrei(
      tester,
      find.descendant(
        of: vergleichsspalte(b.id),
        matching: find.text(de.variantenvergleichAlsHaupt),
      ),
    );
    await waitFor(
      tester,
      find.descendant(
        of: vergleichsspalte(b.id),
        matching: find.text(de.variantenvergleichHaupt),
      ),
    );
    await alleZurueck(tester);
    await openSection(tester, Hauptbereich.zeitleiste);
    await waitFor(tester, kachel(b.id));
    expect(kachel(a.id), findsNothing);
    expect(
      (await mitDb(tester, () => bibliothek.db.assetById(b.id)))!.isStackCover,
      isTrue,
    );
    await ende(tester);
  });

  // ---------------------------------------------------------------------
  // Zwei Fotos vergleichen, Archiv
  // ---------------------------------------------------------------------

  testWidgets('IMP-166 Zwei Fotos vergleichen', (tester) async {
    await startApp(tester);
    await importiereDirekt(tester, [
      testfoto('links.jpg', datum: DateTime(2024, 1, 1, 9, 1, 1)),
      testfoto('rechts.jpg', datum: DateTime(2024, 1, 2, 9, 1, 1)),
      testfoto('dritte.jpg', datum: DateTime(2024, 1, 3, 9, 1, 1)),
    ]);
    final l = await aufnahme(tester, 'links.jpg');
    final r = await aufnahme(tester, 'rechts.jpg');
    final d = await aufnahme(tester, 'dritte.jpg');
    final vergleichen = find.byTooltip(de.auswVergleichen);
    await waitFor(tester, kachel(l.id));
    await tester.longPress(kachel(l.id));
    await settle(tester);
    await waitFor(tester, find.byType(SelectionActionBar));
    expect(vergleichen, findsNothing, reason: 'ein Foto: kein Knopf');
    await tester.longPress(kachel(r.id));
    await settle(tester);
    expect(vergleichen, findsOneWidget);
    await tapFrei(tester, kachel(d.id));
    expect(vergleichen, findsNothing, reason: 'drei Fotos: kein Knopf');
    await tapFrei(tester, kachel(d.id));
    await tapFrei(tester, vergleichen);
    await waitFor(tester, find.text(de.vergleichTitel));
    expect(find.text('links.jpg'), findsWidgets);
    expect(find.text('rechts.jpg'), findsWidgets);
    await ende(tester);
  });

  testWidgets('IMP-169 IMP-170 IMP-171 Archiv', (tester) async {
    await startApp(tester);
    await importiereDirekt(tester, [
      testfoto('liebling.jpg', datum: DateTime(2024, 6, 6, 6, 6, 6)),
      testfoto('anderes.jpg', datum: DateTime(2024, 6, 7, 6, 6, 6)),
    ]);
    final a = await aufnahme(tester, 'liebling.jpg');
    final b = await aufnahme(tester, 'anderes.jpg');
    final albumId = const Uuid().v4();
    await mitDb(tester, () async {
      await bibliothek.db.fuehreAus(FavoritSetzen([a.id], true));
      await bibliothek.db.fuehreAus(
        AlbumAnlegen(albumId, 'Album A', DateTime.now()),
      );
      await bibliothek.db.fuehreAus(AlbumFuellen(albumId, [a.id]));
    });

    // IMP-169
    await waitFor(tester, kachel(a.id));
    await tester.longPress(kachel(a.id));
    await settle(tester);
    await tapFrei(tester, find.byTooltip(de.auswArchiv));
    await meldungGesehen(tester, de.auswRueckArchiviert(1));
    expect(find.text(de.allgRueckgaengig), findsWidgets);
    await waitGone(tester, kachel(a.id));
    await openSection(tester, Hauptbereich.archiv);
    await waitFor(tester, kachel(a.id));
    await openSection(tester, Hauptbereich.favoriten);
    await waitFor(tester, kachel(a.id));
    await openSection(tester, Hauptbereich.alben);
    await tapFrei(tester, find.text('Album A').first);
    await waitFor(tester, kachel(a.id));
    await alleZurueck(tester);

    // IMP-171: archivieren und rückgängig.
    await openSection(tester, Hauptbereich.zeitleiste);
    await waitFor(tester, kachel(b.id));
    await tester.longPress(kachel(b.id));
    await settle(tester);
    await tippe(tester, find.byTooltip(de.auswArchiv));
    await meldungGesehen(tester, de.auswRueckArchiviert(1));
    await tap(tester, find.text(de.allgRueckgaengig).last);
    await waitFor(tester, kachel(b.id));
    expect(
      (await mitDb(tester, () => bibliothek.db.assetById(b.id)))!.isArchived,
      isFalse,
    );

    // IMP-170: aus dem Archiv holen.
    await openSection(tester, Hauptbereich.archiv);
    await waitFor(tester, kachel(a.id));
    await tester.longPress(kachel(a.id));
    await settle(tester);
    await tapFrei(tester, find.byTooltip(de.auswArchiv));
    await meldungGesehen(tester, de.auswRueckAusArchiv(1));
    await openSection(tester, Hauptbereich.zeitleiste);
    await waitFor(tester, kachel(a.id));
    await ende(tester);
  });

  // ---------------------------------------------------------------------
  // Papierkorb
  // ---------------------------------------------------------------------

  testWidgets(
    'IMP-173 IMP-176 IMP-177 IMP-178 IMP-179 IMP-180 IMP-184 IMP-186 Papierkorb',
    (tester) async {
      await startApp(tester);
      await importiereDirekt(tester, [
        for (var i = 1; i <= 7; i++)
          testfoto('p$i.jpg', datum: DateTime(2024, 3, i, 10, i, i)),
      ]);
      final p = {
        for (var i = 1; i <= 7; i++) i: await aufnahme(tester, 'p$i.jpg'),
      };
      await mitDb(
        tester,
        () =>
            bibliothek.db.fuehreAus(FavoritSetzen([p[1]!.id, p[2]!.id], true)),
      );

      // IMP-173
      await waitFor(tester, kachel(p[1]!.id));
      await tester.longPress(kachel(p[1]!.id));
      await settle(tester);
      await tester.longPress(kachel(p[2]!.id));
      await settle(tester);
      await tapFrei(
        tester,
        find.descendant(
          of: find.byType(SelectionActionBar),
          matching: find.byTooltip(de.allgLoeschen),
        ),
      );
      await waitFor(tester, find.text(de.loeschenTitel(2)));
      expect(find.text(de.loeschenHinweis(2)), findsOneWidget);
      await tapFrei(
        tester,
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(de.allgLoeschen),
        ),
      );
      await waitGone(tester, kachel(p[1]!.id));
      expect(kachel(p[2]!.id), findsNothing);
      await openSection(tester, Hauptbereich.favoriten);
      await settle(tester);
      expect(kachel(p[1]!.id), findsNothing);
      expect(kachel(p[2]!.id), findsNothing);
      final suche = await mitDb(
        tester,
        () => bibliothek.db.searchAssets(
          const SearchFilters(
            textMode: SearchTextMode.filename,
            query: 'p1.jpg',
          ),
        ),
      );
      expect(suche, isEmpty, reason: 'nicht in der Suche');
      expect(datei(p[1]!).existsSync(), isTrue);
      expect(datei(p[2]!).existsSync(), isTrue);
      await openSection(tester, Hauptbereich.papierkorb);
      await waitFor(tester, find.byTooltip(de.einstWiederherstellen));
      expect(find.byTooltip(de.einstWiederherstellen), findsNWidgets(2));

      // IMP-176: einzeln wiederherstellen.
      await tapFrei(tester, find.byTooltip(de.einstWiederherstellen).first);
      late AssetData zurueckGeholt;
      await eventually(tester, () async {
        final x = await bibliothek.db.assetsByIds([p[1]!.id, p[2]!.id]);
        final zurueck = x.where((a) => !a.isTrashed).toList();
        if (zurueck.length != 1) return false;
        zurueckGeholt = zurueck.single;
        return true;
      }, was: 'genau ein Foto zurück');
      expect(zurueckGeholt.isFavorite, isTrue, reason: 'mit allen Angaben');
      expect(zurueckGeholt.fileCreatedAt.year, 2024);
      expect(find.byTooltip(de.einstWiederherstellen), findsOneWidget);
      await openSection(tester, Hauptbereich.zeitleiste);
      await waitFor(tester, kachel(zurueckGeholt.id));

      // IMP-184: über die Einstellungen.
      await openSection(tester, Hauptbereich.einstellungen);
      await einstellungsgruppe(tester, de.einstAbschnittPapierkorb);
      final eintrag = find.ancestor(
        of: find.textContaining('ein Foto · '),
        matching: find.byType(ListTile),
      );
      await waitFor(tester, eintrag);
      await tapFrei(tester, eintrag);
      await waitFor(tester, find.byType(TrashScreen));
      expect(find.byTooltip(de.einstWiederherstellen), findsOneWidget);
      await alleZurueck(tester);

      // IMP-177: zwei von dreien wiederherstellen.
      await mitDb(tester, () async {
        await bibliothek.db.fuehreAus(
          InDenPapierkorb([p[3]!.id], zeit: vorMinuten(3)),
        );
        await bibliothek.db.fuehreAus(
          InDenPapierkorb([p[4]!.id], zeit: vorMinuten(2)),
        );
      });
      await openSection(tester, Hauptbereich.papierkorb);
      await warteAufAnzahl(tester, find.byTooltip(de.einstWiederherstellen), 3);
      final orte = papierkorbKacheln(tester);
      final reihe3 = await papierkorbReihe(tester);
      await tester.longPressAt(orte[0]);
      await settle(tester);
      await waitFor(tester, find.text(de.papierkorbAusgewaehlt(1)));
      await tester.tapAt(orte[1]);
      await settle(tester);
      await waitFor(tester, find.text(de.papierkorbAusgewaehlt(2)));
      // Nur noch der Knopf oben, die Kachelknöpfe sind weg.
      expect(find.byTooltip(de.einstWiederherstellen), findsOneWidget);
      await tapFrei(tester, find.byTooltip(de.einstWiederherstellen));
      await eventually(tester, () async {
        final x = await bibliothek.db.assetsByIds(reihe3);
        return x.where((a) => a.isTrashed).length == 1;
      }, was: 'zwei zurück, eines bleibt');
      final bleibt = (await mitDb(
        tester,
        () => bibliothek.db.assetsByIds(reihe3),
      )).where((a) => a.isTrashed).single;
      expect(bleibt.id, reihe3[2]);

      // IMP-179 und IMP-178: endgültig löschen.
      await mitDb(
        tester,
        () => bibliothek.db.fuehreAus(
          InDenPapierkorb([p[5]!.id], zeit: vorMinuten(1)),
        ),
      );
      await settle(tester);
      await warteAufAnzahl(tester, find.byTooltip(de.einstWiederherstellen), 2);
      final orte2 = papierkorbKacheln(tester);
      final reihe2 = await papierkorbReihe(tester);
      await tester.longPressAt(orte2[0]);
      await settle(tester);
      await tapFrei(tester, find.byTooltip(de.bestaetigEndgueltigLoeschen));
      await waitFor(tester, find.text(de.papierkorbEndgueltigText(1)));
      expect(find.text(de.papierkorbEndgueltigTitel), findsOneWidget);
      await tapFrei(
        tester,
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(de.allgAbbrechen),
        ),
      );
      final nochDa = await mitDb(
        tester,
        () => bibliothek.db.assetsByIds(reihe2),
      );
      expect(nochDa, hasLength(2), reason: 'IMP-179: nichts gelöscht');
      final weg = nochDa.firstWhere((a) => a.id == reihe2[0]);
      final wegDateien = [
        weg.relativePath,
        ?weg.thumbnailRelativePath,
        ?weg.previewRelativePath,
      ];
      await tapFrei(tester, find.byTooltip(de.bestaetigEndgueltigLoeschen));
      await waitFor(tester, find.text(de.papierkorbEndgueltigText(1)));
      await tapFrei(
        tester,
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(de.allgLoeschen),
        ),
      );
      await eventually(tester, () async {
        return await bibliothek.db.assetById(weg.id) == null;
      }, was: 'IMP-178: Foto ist weg');
      for (final d in wegDateien) {
        expect(
          bibliothek.paths.absolute(d).existsSync(),
          isFalse,
          reason: 'IMP-178: $d entfernt',
        );
      }
      expect(
        (await mitDb(
          tester,
          () => bibliothek.db.assetById(reihe2[1]),
        ))!.isTrashed,
        isTrue,
      );

      // IMP-186 und IMP-180: gesperrt-gelöschtes Foto bleibt draussen.
      final p7 = p[7]!;
      await mitDb(tester, () async {
        await bibliothek.setupVaultPin(_pin);
        await bibliothek.lockAsset(p7);
        await bibliothek.db.fuehreAus(InDenPapierkorb([p7.id]));
      });
      final p7gesperrt = (await mitDb(
        tester,
        () => bibliothek.db.assetById(p7.id),
      ))!;
      expect(p7gesperrt.isLocked && p7gesperrt.isTrashed, isTrue);
      // Zwei weitere in den normalen Papierkorb: dann liegen dort drei.
      final normal = [
        for (final a in await alleAufnahmen(tester))
          if (!a.isTrashed && !a.isLocked) a.id,
      ].take(2).toList();
      await mitDb(
        tester,
        () => bibliothek.db.fuehreAus(InDenPapierkorb(normal)),
      );
      await openSection(tester, Hauptbereich.zeitleiste);
      await openSection(tester, Hauptbereich.papierkorb);
      await warteAufAnzahl(tester, find.byTooltip(de.einstWiederherstellen), 3);
      expect(
        find.byTooltip(de.einstWiederherstellen),
        findsNWidgets(3),
        reason: 'IMP-186: das gesperrte fehlt im normalen Papierkorb',
      );
      final imKorb = await papierkorbReihe(tester);
      expect(imKorb, isNot(contains(p7.id)));
      final korbDateien = <String>[
        for (final a in await mitDb(
          tester,
          () => bibliothek.db.assetsByIds(imKorb),
        ))
          a.relativePath,
      ];
      await tapFrei(tester, find.byTooltip(de.papierkorbLeeren));
      await waitFor(tester, find.text(de.papierkorbLeerenText(3)));
      await tapFrei(
        tester,
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(de.allgLoeschen),
        ),
      );
      await waitFor(tester, find.text(de.papierkorbLeer));
      expect(
        await mitDb(tester, () => bibliothek.db.assetsByIds(imKorb)),
        isEmpty,
      );
      for (final d in korbDateien) {
        expect(bibliothek.paths.absolute(d).existsSync(), isFalse);
      }
      final p7nachher = await mitDb(
        tester,
        () => bibliothek.db.assetById(p7.id),
      );
      expect(p7nachher, isNotNull, reason: 'gesperrtes bleibt');
      expect(p7nachher!.isTrashed && p7nachher.isLocked, isTrue);
      expect(datei(p7nachher).existsSync(), isTrue);
      await ende(tester);
    },
  );

  testWidgets('IMP-187 IMP-188 Papierkorb-Ablauf einstellen', (tester) async {
    await startApp(tester);
    await importiereDirekt(tester, [testfoto('x.jpg')]);
    await openSection(tester, Hauptbereich.einstellungen);
    await einstellungsgruppe(tester, de.einstAbschnittPapierkorb);
    final schalter = find.descendant(
      of: find.byType(SettingsScreen),
      matching: find.widgetWithText(SwitchListTile, de.allgAktiv),
    );
    await waitFor(tester, schalter);
    expect(tester.widget<SwitchListTile>(schalter).value, isFalse);
    expect(find.text(de.einstTageDropdown(30)), findsOneWidget);
    expect(find.text(de.einstNieAusgefuehrt), findsOneWidget);

    // IMP-188
    await tapFrei(tester, schalter);
    await eventually(tester, () async {
      return (await bibliothek.db.trashSettingsRow())?.autoDeleteEnabled ??
          false;
    });
    await settle(tester);
    await tapFrei(tester, find.text(de.einstTageDropdown(30)));
    await tapFrei(tester, find.text(de.einstTageDropdown(7)).last);
    await eventually(tester, () async {
      return (await bibliothek.db.trashSettingsRow())?.autoDeleteAfterDays == 7;
    });
    await openSection(tester, Hauptbereich.zeitleiste);
    await openSection(tester, Hauptbereich.einstellungen);
    await einstellungsgruppe(tester, de.einstAbschnittPapierkorb);
    await waitFor(tester, find.text(de.einstTageDropdown(7)));
    expect(tester.widget<SwitchListTile>(schalter).value, isTrue);
    await ende(tester);
  });

  testWidgets('IMP-189 IMP-190 Papierkorb automatisch leeren', (tester) async {
    await startApp(tester);
    await importiereDirekt(tester, [
      testfoto('alt100.jpg'),
      testfoto('alt8.jpg'),
      testfoto('neu1.jpg'),
      testfoto('gesperrt8.jpg'),
    ]);
    final a100 = await aufnahme(tester, 'alt100.jpg');
    final a8 = await aufnahme(tester, 'alt8.jpg');
    final n1 = await aufnahme(tester, 'neu1.jpg');
    final g8 = await aufnahme(tester, 'gesperrt8.jpg');

    // IMP-190: Ablauf aus, Foto seit 100 Tagen im Papierkorb.
    await mitDb(tester, () async {
      await bibliothek.db.fuehreAus(
        InDenPapierkorb([a100.id], zeit: vorTagen(100)),
      );
      await bibliothek.purgeExpiredTrashIfDue();
    });
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 3)),
    );
    expect(
      (await mitDb(tester, () => bibliothek.db.assetById(a100.id)))?.isTrashed,
      isTrue,
      reason: 'ohne aktiven Ablauf wird nichts gelöscht',
    );

    // IMP-189: 7 Tage, dann die Prüfung, die beim Start läuft.
    await mitDb(tester, () async {
      await bibliothek.db.fuehreAus(
        const PapierkorbFristSetzen(an: true, tage: 7),
      );
      await bibliothek.db.fuehreAus(
        InDenPapierkorb([a8.id], zeit: vorTagen(8)),
      );
      await bibliothek.db.fuehreAus(
        InDenPapierkorb([n1.id], zeit: vorTagen(1)),
      );
      await bibliothek.setupVaultPin(_pin);
      await bibliothek.lockAsset(g8);
      await bibliothek.db.fuehreAus(
        InDenPapierkorb([g8.id], zeit: vorTagen(8)),
      );
    });
    final g8vorher = (await mitDb(
      tester,
      () => bibliothek.db.assetById(g8.id),
    ))!;
    final start = DateTime.now();
    await mitDb(tester, () => bibliothek.purgeExpiredTrashIfDue());
    for (final x in [a100, a8, g8vorher]) {
      expect(
        await mitDb(tester, () => bibliothek.db.assetById(x.id)),
        isNull,
        reason: '${x.originalFileName} endgültig gelöscht',
      );
      expect(datei(x).existsSync(), isFalse);
    }
    expect(
      (await mitDb(tester, () => bibliothek.db.assetById(n1.id)))?.isTrashed,
      isTrue,
      reason: 'das 1 Tag alte bleibt',
    );
    final lauf = (await mitDb(
      tester,
      () => bibliothek.db.trashSettingsRow(),
    ))!.lastPurgeAt;
    expect(lauf, isNotNull);
    expect(lauf!.isBefore(start.subtract(const Duration(seconds: 2))), isFalse);
    await openSection(tester, Hauptbereich.einstellungen);
    await einstellungsgruppe(tester, de.einstAbschnittPapierkorb);
    await waitFor(tester, find.text(de.einstLetzterLauf));
    expect(find.text(de.einstNieAusgefuehrt), findsNothing);
    await ende(tester);
  });

  // ---------------------------------------------------------------------
  // Gesperrter Ordner
  // ---------------------------------------------------------------------

  testWidgets(
    'IMP-191 IMP-198 IMP-193 IMP-206 IMP-204 IMP-197 IMP-200 IMP-199 IMP-201 Gesperrter Ordner',
    (tester) async {
      await startApp(tester);
      final g1 = testfoto(
        'geheim1.jpg',
        datum: DateTime(2024, 2, 2, 2, 2, 2),
        breitengrad: 47.5,
        laengengrad: 9.7,
      );
      final g2 = testfoto('geheim2.jpg', datum: DateTime(2024, 2, 3, 2, 2, 2));
      final g1Bytes = g1.readAsBytesSync();
      await importiereDirekt(tester, [
        g1,
        g2,
        testfoto('offen.jpg', datum: DateTime(2024, 2, 4, 2, 2, 2)),
      ]);
      final a1 = await aufnahme(tester, 'geheim1.jpg');
      final a2 = await aufnahme(tester, 'geheim2.jpg');
      final albumId = const Uuid().v4();
      await mitDb(tester, () async {
        await bibliothek.db.fuehreAus(
          AlbumAnlegen(albumId, 'Album A', DateTime.now()),
        );
        await bibliothek.db.fuehreAus(AlbumFuellen(albumId, [a1.id]));
      });

      // IMP-191: PIN einrichten.
      await openSection(tester, Hauptbereich.einstellungen);
      await einstellungsgruppe(tester, de.einstAbschnittGesperrterOrdner);
      await waitFor(tester, find.text(de.einstPinEinrichten));
      await tapFrei(
        tester,
        find.widgetWithText(FilledButton, de.allgEinrichten),
      );
      await waitFor(tester, find.text(de.pinFestlegenTitel));
      expect(find.text(de.pinWarnung), findsOneWidget);
      await enter(tester, field(de.pinNeuFeld), _pin);
      await enter(tester, field(de.pinWiederholen), _pin);
      await tapFrei(tester, find.text(de.allgFestlegen));
      await waitFor(tester, find.text(de.einstGesperrtEntsperrt));
      expect(find.text(de.einstGesperrtOeffnen), findsOneWidget);

      // IMP-198: leer.
      await tapFrei(tester, find.text(de.einstGesperrtOeffnen));
      await waitFor(tester, find.byType(LockedFolderScreen));
      await waitFor(tester, find.text(de.gesperrtLeer));
      await tapFrei(
        tester,
        find.descendant(
          of: find.byType(LockedFolderScreen),
          matching: find.text(de.gesperrtTabPapierkorb),
        ),
      );
      await waitFor(tester, find.text(de.gesperrtPapierkorbLeer));
      await alleZurueck(tester);

      // IMP-193: Foto sperren.
      await openSection(tester, Hauptbereich.zeitleiste);
      await oeffneFoto(tester, a1.id);
      await tapFrei(tester, find.byTooltip(de.viewerInGesperrtenOrdner));
      await eventually(tester, () async {
        return (await bibliothek.db.assetById(a1.id))!.isLocked;
      }, was: 'gesperrt');
      await settle(tester);
      await waitGone(tester, kachel(a1.id));
      final gesperrt = (await mitDb(
        tester,
        () => bibliothek.db.assetById(a1.id),
      ))!;
      final kopf = datei(gesperrt).readAsBytesSync().take(3).toList();
      expect(kopf, [0x50, 0x56, 0x45], reason: 'Original verschlüsselt (PVE)');
      expect(
        datei(gesperrt).readAsBytesSync().take(2).toList(),
        isNot([0xFF, 0xD8]),
        reason: 'nicht als JPEG lesbar',
      );
      final suche = await mitDb(
        tester,
        () => bibliothek.db.searchAssets(
          const SearchFilters(
            textMode: SearchTextMode.filename,
            query: 'geheim1',
          ),
        ),
      );
      expect(suche, isEmpty, reason: 'nicht in der Suche');
      final karte = await mitDb(
        tester,
        () => bibliothek.db.assetsWithLocation(),
      );
      expect([for (final x in karte) x.id], isNot(contains(a1.id)));
      await openSection(tester, Hauptbereich.alben);
      await tapFrei(tester, find.text('Album A').first);
      await settle(tester);
      expect(kachel(a1.id), findsNothing, reason: 'nicht im Album');
      await alleZurueck(tester);

      // Im gesperrten Ordner unter „Fotos" – IMP-206: Klartextkopien.
      final klartext = Directory(
        p.join(Directory.systemTemp.path, 'photovault_decrypt'),
      );
      await openSection(tester, Hauptbereich.einstellungen);
      await einstellungsgruppe(tester, de.einstAbschnittGesperrterOrdner);
      await tapFrei(tester, find.text(de.einstGesperrtOeffnen));
      await waitFor(tester, find.byType(LockedFolderScreen));
      await waitFor(
        tester,
        find.descendant(
          of: find.byType(LockedFolderScreen),
          matching: find.byTooltip(de.gesperrtEntfernen),
        ),
      );
      await eventually(tester, () async {
        return klartext.existsSync() &&
            klartext.listSync(recursive: true).whereType<File>().isNotEmpty;
      }, was: 'IMP-206: entschlüsselte Kopien während der Ansicht');
      await alleZurueck(tester);
      await eventually(tester, () async {
        return !klartext.existsSync() ||
            klartext.listSync(recursive: true).whereType<File>().isEmpty;
      }, was: 'IMP-206: nach dem Verlassen leer');

      // IMP-204 und IMP-197: Sitzung sperren, falscher und richtiger PIN.
      await waitFor(tester, find.text(de.einstSitzungSperren));
      await tapFrei(tester, find.text(de.einstSitzungSperren));
      await waitFor(tester, find.text(de.einstPinEingerichtet));
      expect(bibliothek.vaultUnlockedThisSession, isFalse);
      await tapFrei(tester, find.text(de.einstGesperrtOeffnen));
      await waitFor(tester, find.text(de.pinEingebenTitel));
      await enter(tester, field(de.pinFeld), '00000000');
      await tapFrei(tester, find.text('OK'));
      await meldungGesehen(tester, de.pinFalsch);
      expect(find.byType(LockedFolderScreen), findsNothing);
      await tapFrei(tester, find.text(de.einstGesperrtOeffnen));
      await waitFor(tester, find.text(de.pinEingebenTitel));
      await enter(tester, field(de.pinFeld), _pin);
      await tapFrei(tester, find.text('OK'));
      await waitFor(tester, find.byType(LockedFolderScreen));
      expect(
        find.descendant(
          of: find.byType(LockedFolderScreen),
          matching: find.text(de.gesperrtTabFotos),
        ),
        findsOneWidget,
      );
      await eventually(tester, () async {
        return find
            .descendant(
              of: find.byType(LockedFolderScreen),
              matching: find.byType(Image),
            )
            .evaluate()
            .isNotEmpty;
      }, was: 'entschlüsselte Miniatur');

      // IMP-200: im gesperrten Ordner löschen und wiederherstellen.
      await tapFrei(
        tester,
        find
            .descendant(
              of: find.byType(LockedFolderScreen),
              matching: find.byType(Image),
            )
            .first,
      );
      await tapFrei(tester, find.byTooltip(de.viewerInPapierkorb));
      await tapFrei(
        tester,
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(de.allgLoeschen),
        ),
      );
      await waitFor(tester, find.text(de.gesperrtLeer));
      final imKorb = await mitDb(tester, () => bibliothek.db.papierkorb());
      expect([for (final x in imKorb) x.id], isNot(contains(a1.id)));
      await tapFrei(
        tester,
        find.descendant(
          of: find.byType(LockedFolderScreen),
          matching: find.text(de.gesperrtTabPapierkorb),
        ),
      );
      await tapFrei(tester, find.byTooltip(de.gesperrtWiederherstellen));
      await eventually(tester, () async {
        final x = (await bibliothek.db.assetById(a1.id))!;
        return !x.isTrashed && x.isLocked;
      }, was: 'wieder unter Fotos, weiter gesperrt');
      expect(datei(gesperrt).readAsBytesSync().take(3).toList(), [
        0x50,
        0x56,
        0x45,
      ]);
      await tapFrei(
        tester,
        find.descendant(
          of: find.byType(LockedFolderScreen),
          matching: find.text(de.gesperrtTabFotos),
        ),
      );

      // IMP-199: entsperren, byte-gleich.
      await tapFrei(tester, find.byTooltip(de.gesperrtEntfernen));
      await eventually(tester, () async {
        return !(await bibliothek.db.assetById(a1.id))!.isLocked;
      }, was: 'entsperrt');
      final offen = (await mitDb(
        tester,
        () => bibliothek.db.assetById(a1.id),
      ))!;
      expect(datei(offen).readAsBytesSync(), g1Bytes);
      await alleZurueck(tester);
      await openSection(tester, Hauptbereich.zeitleiste);
      await waitFor(tester, kachel(a1.id));

      // IMP-201: aus dem gesperrten Papierkorb endgültig löschen.
      await mitDb(tester, () async {
        final x = (await bibliothek.db.assetById(a2.id))!;
        await bibliothek.lockAsset(x);
        await bibliothek.db.fuehreAus(InDenPapierkorb([a2.id]));
      });
      final a2gesperrt = (await mitDb(
        tester,
        () => bibliothek.db.assetById(a2.id),
      ))!;
      final dateien = [
        ...await mitDb(tester, () => bibliothek.dateienVon(a2gesperrt)),
        bibliothek.paths.vaultMetadataRelativePath(a2.id),
      ];
      print('IMP-201 Dateien: $dateien');
      await openSection(tester, Hauptbereich.einstellungen);
      await einstellungsgruppe(tester, de.einstAbschnittGesperrterOrdner);
      await tapFrei(tester, find.text(de.einstGesperrtOeffnen));
      await waitFor(tester, find.byType(LockedFolderScreen));
      await tapFrei(
        tester,
        find.descendant(
          of: find.byType(LockedFolderScreen),
          matching: find.text(de.gesperrtTabPapierkorb),
        ),
      );
      await tapFrei(tester, find.byTooltip(de.bestaetigEndgueltigLoeschen));
      await waitFor(tester, find.text(de.gesperrtEndgueltigText));
      await tapFrei(
        tester,
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(de.bestaetigEndgueltigLoeschen),
        ),
      );
      await eventually(tester, () async {
        return await bibliothek.db.assetById(a2.id) == null;
      }, was: 'Datenbankzeile entfernt');
      for (final d in dateien) {
        expect(
          bibliothek.paths.absolute(d).existsSync(),
          isFalse,
          reason: '$d entfernt',
        );
      }
      await ende(tester);
    },
  );

  testWidgets('IMP-202 IMP-203 PIN ändern und entfernen', (tester) async {
    await startApp(tester);
    final k1 = testfoto('k1.jpg', datum: DateTime(2024, 5, 1, 1, 1, 1));
    final k2 = testfoto('k2.jpg', datum: DateTime(2024, 5, 2, 1, 1, 1));
    final bytes = {
      'k1.jpg': k1.readAsBytesSync(),
      'k2.jpg': k2.readAsBytesSync(),
    };
    await importiereDirekt(tester, [k1, k2]);
    final a1 = await aufnahme(tester, 'k1.jpg');
    final a2 = await aufnahme(tester, 'k2.jpg');
    await mitDb(tester, () async {
      await bibliothek.setupVaultPin(_pin);
      await bibliothek.lockAsset(a1);
      await bibliothek.lockAsset(a2);
    });

    // IMP-202
    await openSection(tester, Hauptbereich.einstellungen);
    await einstellungsgruppe(tester, de.einstAbschnittGesperrterOrdner);
    await tapFrei(tester, find.text(de.einstPinAendern));
    await waitFor(tester, find.text(de.pinFestlegenTitel));
    await enter(tester, field(de.pinNeuFeld), _pinNeu);
    await enter(tester, field(de.pinWiederholen), _pinNeu);
    await tapFrei(tester, find.text(de.allgFestlegen));
    await waitGone(tester, find.text(de.pinFestlegenTitel));
    // „Neustart" nachgestellt: Sitzung sperren, dann neu öffnen.
    await tapFrei(tester, find.text(de.einstSitzungSperren));
    await waitFor(tester, find.text(de.einstPinEingerichtet));
    await tapFrei(tester, find.text(de.einstGesperrtOeffnen));
    await enter(tester, field(de.pinFeld), _pin);
    await tapFrei(tester, find.text('OK'));
    await meldungGesehen(tester, de.pinFalsch);
    expect(find.byType(LockedFolderScreen), findsNothing);
    await tapFrei(tester, find.text(de.einstGesperrtOeffnen));
    await enter(tester, field(de.pinFeld), _pinNeu);
    await tapFrei(tester, find.text('OK'));
    await waitFor(tester, find.byType(LockedFolderScreen));
    await eventually(tester, () async {
      return find
              .descendant(
                of: find.byType(LockedFolderScreen),
                matching: find.byType(Image),
              )
              .evaluate()
              .length >=
          2;
    }, was: 'alle gesperrten Fotos lesbar');
    await alleZurueck(tester);

    // IMP-203: erst Abbrechen, dann Entfernen.
    await waitFor(tester, find.text(de.einstPinEntfernen));
    await tapFrei(tester, find.text(de.einstPinEntfernen));
    await waitFor(tester, find.text(de.einstGesperrtAufloesenTitel));
    await tapFrei(
      tester,
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(de.allgAbbrechen),
      ),
    );
    expect(
      (await mitDb(tester, () => bibliothek.db.assetById(a1.id)))!.isLocked,
      isTrue,
    );
    await tapFrei(tester, find.text(de.einstPinEntfernen));
    await waitFor(tester, find.text(de.einstGesperrtAufloesenTitel));
    await tapFrei(
      tester,
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(de.allgEntfernen),
      ),
    );
    await waitFor(tester, find.text(de.einstPinEinrichten));
    for (final a in [a1, a2]) {
      final x = (await mitDb(tester, () => bibliothek.db.assetById(a.id)))!;
      expect(x.isLocked, isFalse);
      expect(datei(x).readAsBytesSync(), bytes[a.originalFileName]);
    }
    await openSection(tester, Hauptbereich.zeitleiste);
    await waitFor(tester, kachel(a1.id));
    await waitFor(tester, kachel(a2.id));
    await ende(tester);
  });

  // Behoben in #400 (der Tresorwächter horchte nie).
  testWidgets('IMP-205 Verbergen des Fensters sperrt', (tester) async {
    await zweimal(tester, () async {
      await importiereDirekt(tester, [testfoto('w.jpg')]);
      final a = await aufnahme(tester, 'w.jpg');
      await mitDb(tester, () async {
        await bibliothek.setupVaultPin(_pin);
        await bibliothek.lockAsset(a);
      });
      await openSection(tester, Hauptbereich.einstellungen);
      await einstellungsgruppe(tester, de.einstAbschnittGesperrterOrdner);
      await tapFrei(tester, find.text(de.einstGesperrtOeffnen));
      await waitFor(tester, find.byType(LockedFolderScreen));
      // Ohne zu pumpen: Verborgen zeichnet die App keine Bilder, und ein
      // Warten auf das nächste Bild käme nie zurück. Der Wächter antwortet
      // im selben Zug (AppLifecycleListener ruft synchron).
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      final nachFokus = bibliothek.vaultUnlockedThisSession;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      final nachVerbergen = bibliothek.vaultUnlockedThisSession;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(tester);
      expect(nachFokus, isTrue, reason: 'nur Fokusverlust sperrt nicht');
      expect(nachVerbergen, isFalse, reason: 'Verbergen sperrt die Sitzung');
      await waitGone(tester, find.byType(LockedFolderScreen));
    });
  });

  // ---------------------------------------------------------------------
  // Integritätsprüfung
  // ---------------------------------------------------------------------

  testWidgets(
    'IMP-209 IMP-216 IMP-210 IMP-211 IMP-212 IMP-213 Integritätsprüfung',
    (tester) async {
      await startApp(tester);
      await importiereDirekt(tester, [
        testfoto('i_a.jpg', datum: DateTime(2024, 1, 5, 5, 5, 5)),
        testfoto('i_b.jpg', datum: DateTime(2024, 1, 6, 5, 5, 5)),
        testfoto('i_c.jpg', datum: DateTime(2024, 1, 7, 5, 5, 5)),
      ]);
      final a = await aufnahme(tester, 'i_a.jpg');
      final b = await aufnahme(tester, 'i_b.jpg');
      final c = await aufnahme(tester, 'i_c.jpg');

      // IMP-209
      await oeffneWerkzeug(tester, de.werkzIntegritaetTitel);
      await warteIntegritaet(tester);
      await waitFor(tester, find.textContaining('Keine Probleme gefunden ('));

      // Schäden anrichten.
      datei(a).deleteSync();
      bibliothek.paths.absolute(b.thumbnailRelativePath!).deleteSync();
      final fremd = bibliothek.paths.absolute('originals/2024/01/fremd.jpg')
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(testfoto('fremd_quelle.jpg').readAsBytesSync())
        ..setLastModifiedSync(
          DateTime.now().subtract(const Duration(hours: 1)),
        );
      datei(c).writeAsBytesSync([1, 2, 3, 4], mode: FileMode.append);

      await tapFrei(tester, find.byTooltip(de.integErneutPruefen));
      await warteIntegritaet(tester);
      await waitFor(tester, find.text(de.integFehlendeDateien(2)));
      expect(find.text(de.integVerwaisteDateien(1)), findsOneWidget);
      // IMP-216: ohne Haken keine Abweichung.
      expect(find.textContaining('Prüfsummen-Abweichungen'), findsNothing);
      await tapFrei(tester, find.text(de.integPruefsummen));
      await warteIntegritaet(tester);
      await waitFor(tester, find.text(de.integAbweichungen(1)));
      expect(find.text(de.integInhaltGeaendert), findsOneWidget);
      expect(find.text(de.integFotoOeffnen), findsOneWidget);

      // IMP-210: fehlendes Original ansehen und austragen.
      final zeileA = integZeile(a.relativePath);
      await tapFrei(
        tester,
        find.descendant(of: zeileA, matching: find.text(de.integAnsehen)),
      );
      await waitFor(tester, find.text(de.integVorschauTitel));
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(Image),
        ),
        findsOneWidget,
      );
      await tapFrei(tester, find.text(de.allgSchliessen));
      await tapFrei(
        tester,
        find.descendant(
          of: zeileA,
          matching: find.text(de.integAusDbEntfernen),
        ),
      );
      await waitFor(tester, find.text(de.integAusDbEntfernenTitel));
      expect(find.text(de.integOriginalFehlt), findsOneWidget);
      await tapFrei(
        tester,
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(FilledButton),
        ),
      );
      await eventually(tester, () async {
        return await bibliothek.db.assetById(a.id) == null;
      }, was: 'IMP-210: Foto aus der Bibliothek entfernt');
      await waitGone(tester, zeileA);

      // IMP-211: fehlende Miniatur austragen.
      final zeileB = integZeile(b.thumbnailRelativePath!);
      await tapFrei(
        tester,
        find.descendant(
          of: zeileB,
          matching: find.text(de.integAusDbEntfernen),
        ),
      );
      await waitFor(tester, find.text(de.integPfadEntfernt));
      await tapFrei(
        tester,
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(FilledButton),
        ),
      );
      await eventually(tester, () async {
        final x = await bibliothek.db.assetById(b.id);
        return x != null && x.thumbnailRelativePath == null;
      }, was: 'IMP-211: nur der Pfad ist weg, das Foto bleibt');

      // IMP-212: verwaiste Datei ansehen und löschen.
      final zeileF = integZeile('originals/2024/01/fremd.jpg');
      await tapFrei(
        tester,
        find.descendant(of: zeileF, matching: find.text(de.integAnsehen)),
      );
      await waitFor(tester, find.text(de.integVorschauTitel));
      await tapFrei(tester, find.text(de.allgSchliessen));
      await tapFrei(
        tester,
        find.descendant(of: zeileF, matching: find.text(de.integDateiLoeschen)),
      );
      await waitFor(tester, find.text(de.integDateiLoeschenTitel));
      await tapFrei(
        tester,
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(FilledButton),
        ),
      );
      await waitGone(tester, zeileF);
      expect(fremd.existsSync(), isFalse);
      expect(find.textContaining('Verwaiste Dateien'), findsNothing);

      // IMP-213: mehr als 100 verwaiste Dateien.
      final alt = DateTime.now().subtract(const Duration(hours: 1));
      final waisen = [
        for (var i = 0; i < 105; i++)
          bibliothek.paths.absolute('originals/2023/02/waise_$i.jpg')
            ..parent.createSync(recursive: true)
            ..writeAsBytesSync([0xFF, 0xD8, i, 0xFF, 0xD9])
            ..setLastModifiedSync(alt),
      ];
      await tapFrei(tester, find.byTooltip(de.integErneutPruefen));
      await warteIntegritaet(tester);
      await waitFor(tester, find.text(de.integVerwaisteDateien(105)));
      expect(find.text(de.integWeitereEintraege(5, 100)), findsOneWidget);
      await tapFrei(tester, find.text(de.integAlleVerwaistenLoeschen));
      await waitFor(tester, find.text(de.integAlleVerwaistenTitel));
      await tapFrei(
        tester,
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(FilledButton),
        ),
      );
      await meldungGesehen(tester, de.integVerwaisteGeloescht(105));
      expect(waisen.where((f) => f.existsSync()), isEmpty);
      await ende(tester);
    },
  );

  testWidgets('IMP-217 Gesperrte Fotos in der Integritätsprüfung', (
    tester,
  ) async {
    await startApp(tester);
    await importiereDirekt(tester, [
      testfoto('l1.jpg', datum: DateTime(2024, 1, 1, 1, 1, 1)),
      testfoto('l2.jpg', datum: DateTime(2024, 1, 2, 1, 1, 1)),
      testfoto('u.jpg', datum: DateTime(2024, 1, 3, 1, 1, 1)),
    ]);
    final l1 = await aufnahme(tester, 'l1.jpg');
    final l2 = await aufnahme(tester, 'l2.jpg');
    await mitDb(tester, () async {
      await bibliothek.setupVaultPin(_pin);
      await bibliothek.lockAsset(l1);
      await bibliothek.lockAsset(l2);
    });
    final l2g = (await mitDb(tester, () => bibliothek.db.assetById(l2.id)))!;
    final roh = datei(l2g).readAsBytesSync();
    roh.setRange(0, 8, List.filled(8, 0));
    datei(l2g).writeAsBytesSync(roh);

    await oeffneWerkzeug(tester, de.werkzIntegritaetTitel);
    await warteIntegritaet(tester);
    await tapFrei(tester, find.text(de.integPruefsummen));
    await warteIntegritaet(tester);
    await waitFor(tester, find.text(de.integHeaderProbleme(1)));
    expect(find.text(l2g.relativePath), findsOneWidget);
    expect(find.text(de.integBeschaedigt), findsOneWidget);
    expect(
      find.textContaining('Prüfsummen-Abweichungen'),
      findsNothing,
      reason: 'das gesperrte Foto meldet keine Prüfsummen-Abweichung',
    );
    await ende(tester);
  });

  // Befund: integrity_check_screen.dart:199 (_ansehenKnopf) gibt bei
  // gesperrten Aufnahmen gar keinen „Ansehen"-Knopf aus. Der Text
  // integVorschauVerschluesselt („Das Foto ist gesperrt – die Vorschau ist
  // mitverschlüsselt.") ist damit unerreichbar.
  testWidgets('IMP-217 Ansehen bei gesperrtem Foto nennt die Verschlüsselung', (
    tester,
  ) async {
    await zweimal(tester, () async {
      await importiereDirekt(tester, [testfoto('l3.jpg')]);
      final l3 = await aufnahme(tester, 'l3.jpg');
      await mitDb(tester, () async {
        await bibliothek.setupVaultPin(_pin);
        await bibliothek.lockAsset(l3);
      });
      final g = (await mitDb(tester, () => bibliothek.db.assetById(l3.id)))!;
      datei(g).deleteSync();
      await oeffneWerkzeug(tester, de.werkzIntegritaetTitel);
      await warteIntegritaet(tester);
      await waitFor(tester, find.text(de.integFehlendeDateien(1)));
      final zeile = integZeile(g.relativePath);
      await tapFrei(
        tester,
        find.descendant(of: zeile, matching: find.text(de.integAnsehen)),
      );
      await waitFor(tester, find.text(de.integVorschauVerschluesselt));
    });
  }, skip: true);

  // ---------------------------------------------------------------------
  // Bibliothekszustand
  // ---------------------------------------------------------------------

  testWidgets('IMP-220 IMP-221 IMP-222 IMP-223 IMP-224 Bibliothekszustand', (
    tester,
  ) async {
    await startApp(tester);
    await importiereDirekt(tester, [
      testfoto('stunde1.jpg', datum: DateTime(2022, 5, 5, 10, 0, 0)),
      testfoto('stunde2.jpg', datum: DateTime(2022, 5, 6, 11, 0, 0)),
      fixture('video_5s.mp4'),
    ]);
    // „noch nicht geprüft"
    await mitDb(tester, () async {
      final db = bibliothek.db;
      await (db.update(db.assets)..where(
            (t) => t.originalFileName.isIn(['stunde1.jpg', 'stunde2.jpg']),
          ))
          .write(const AssetsCompanion(datumGeprueft: Value(false)));
    });
    final zahl = await mitDb(
      tester,
      () => bibliothek.db.countAuffaelligeAufnahmedaten(),
    );

    // IMP-220
    await oeffneWerkzeug(tester, de.gesundheitTitel);
    await waitFor(tester, find.byType(LibraryHealthScreen));
    await waitFor(tester, find.text(de.gesundheitDatenbankOk));
    expect(find.text(de.gesundheitDatenbank), findsOneWidget);
    expect(find.text(de.gesundheitSicherung), findsOneWidget);
    expect(find.text(de.gesundheitSpeicher), findsOneWidget);
    await waitFor(tester, find.textContaining(de.gesundheitMedien(2, 1)));
    expect(find.text(de.gesundheitModelle), findsOneWidget);

    // IMP-223
    expect(zahl, 2);
    await sichtbar(
      tester,
      find.text(de.gesundheitDatumOffen(zahl)),
      LibraryHealthScreen,
    );
    await tapFrei(tester, find.text(de.gesundheitDatumPruefen));
    await waitFor(tester, find.byType(BackgroundTasksScreen));
    await waitFor(tester, find.text(de.aufgDatumsherkunftTitel));
    await zurueck(tester);

    // IMP-221
    final pruefen = find.text(de.gesundheitIntegritaetOeffnen);
    await sichtbar(tester, pruefen, LibraryHealthScreen);
    await tapFrei(tester, pruefen);
    await waitFor(tester, find.byType(IntegrityCheckScreen));
    await zurueck(tester);

    // IMP-222: erst leeren, dann genau einen Rest anlegen.
    final bereinigen = find.text(de.gesundheitBereinigen);
    await sichtbar(tester, bereinigen, LibraryHealthScreen);
    await tapFrei(tester, bereinigen);
    await settle(tester, max: const Duration(seconds: 2));
    final bibliotheksdateien = _dateienUnter(bibliothek.paths.root);
    final rest =
        File(p.join(bibliothek.paths.root.path, 'originals', 'rest.jpg.part'))
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync(List.filled(1234, 7))
          ..setLastModifiedSync(
            DateTime.now().subtract(const Duration(days: 2)),
          );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 5)),
    );
    // Hier eine SnackBar, keine Meldung des Meldungsdienstes.
    await tippe(tester, bereinigen);
    await waitFor(tester, find.text(de.gesundheitBereinigt(1, '1.2 KB')));
    expect(rest.existsSync(), isFalse);
    expect(_dateienUnter(bibliothek.paths.root), bibliotheksdateien);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 5)),
    );
    await tippe(tester, bereinigen);
    await waitFor(tester, find.text(de.gesundheitBereinigt(0, '0 B')));

    // IMP-224
    await importiereDirekt(tester, [testfoto('neu.jpg')]);
    await tapFrei(tester, find.byTooltip(de.gesundheitAktualisieren));
    await waitFor(tester, find.textContaining(de.gesundheitMedien(3, 1)));
    await ende(tester);
  });

  // ---------------------------------------------------------------------
  // Bibliothekspflege – Aufgaben
  // ---------------------------------------------------------------------

  testWidgets('IMP-128 IMP-127 Aufnahmedatum aus Videos nachtragen', (
    tester,
  ) async {
    await startApp(tester);
    final video = mitVideozeit(
      fixture('video_5s.mp4'),
      DateTime(2019, 5, 4, 10, 0, 0),
    );
    final videoBytes = video.readAsBytesSync();
    await importiereDirekt(tester, [video]);
    final v = await aufnahme(tester, 'video_5s.mp4');
    print('IMP-127 Import: ${v.fileCreatedAt} ${v.relativePath}');
    // Das falsche Datum einer älteren Fassung: die Kopierzeit.
    final kopierzeit = DateTime.now().subtract(const Duration(minutes: 5));
    await mitDb(
      tester,
      () => bibliothek.setzeAufnahmedatumVonHand([v.id], kopierzeit),
    );
    final falsch = (await mitDb(tester, () => bibliothek.db.assetById(v.id)))!;
    expect(falsch.fileCreatedAt.year, kopierzeit.year);

    // IMP-128: Rückfrage abbrechen.
    await oeffneAufgaben(tester);
    await aufgabeStarten(tester, de.werkzDatumTitel, de.aufgModusAlle);
    await waitFor(tester, find.text(de.werkzDatumFrageTitel));
    await tapFrei(
      tester,
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(de.allgAbbrechen),
      ),
    );
    await settle(tester);
    expect(bibliothek.lauf('aufnahmedatum'), isNull, reason: 'kein Lauf');
    expect(
      (await mitDb(tester, () => bibliothek.db.assetById(v.id)))!.relativePath,
      falsch.relativePath,
    );

    // IMP-127
    await aufgabeStarten(tester, de.werkzDatumTitel, de.aufgModusAlle);
    await tapFrei(tester, find.text(de.werkzDatumStarten));
    await waitFor(
      tester,
      find.descendant(
        of: aufgabenkarte(de.werkzDatumTitel),
        matching: find.text(de.aufgFertigMit(1)),
      ),
      timeout: const Duration(seconds: 60),
    );
    final richtig = (await mitDb(tester, () => bibliothek.db.assetById(v.id)))!;
    expect(richtig.fileCreatedAt, DateTime(2019, 5, 4, 10));
    expect(richtig.relativePath, startsWith('originals/2019/05/'));
    expect(datei(richtig).readAsBytesSync(), videoBytes);
    await ende(tester);
  });

  testWidgets(
    'IMP-129 IMP-130 IMP-132 IMP-134 Herkunft, Ablage, Dateiarten, Kamera',
    (tester) async {
      await startApp(tester);
      await importiereDirekt(tester, [
        testfoto('ohne_datum.jpg'),
        testfoto('mit_datum.jpg', datum: DateTime(2022, 3, 4, 11, 22, 33)),
        testfoto('ablage.jpg', datum: DateTime(2021, 6, 10, 8, 1, 2)),
        testfoto('standbild.jpg', datum: DateTime(2021, 7, 1, 8, 1, 2)),
        kamerafoto('kamera.jpg'),
        fixture('video_5s.mp4'),
      ]);
      final ohne = await aufnahme(tester, 'ohne_datum.jpg');
      final mit = await aufnahme(tester, 'mit_datum.jpg');
      final ablage = await aufnahme(tester, 'ablage.jpg');
      final stand = await aufnahme(tester, 'standbild.jpg');
      final kam = await aufnahme(tester, 'kamera.jpg');
      final vid = await aufnahme(tester, 'video_5s.mp4');
      final kamWerte = aufnahmewerte(kam);
      print('IMP-134 beim Import: ${kam.cameraModel} $kamWerte');

      // Zustand einer älteren Fassung herstellen.
      await mitDb(tester, () async {
        final db = bibliothek.db;
        await (db.update(
          db.assets,
        )..where((t) => t.id.isIn([ohne.id, mit.id]))).write(
          const AssetsCompanion(
            datumGeschaetzt: Value(false),
            datumGeprueft: Value(false),
          ),
        );
        await (db.update(db.assets)..where((t) => t.id.equals(stand.id))).write(
          const AssetsCompanion(
            type: Value('VIDEO'),
            thumbnailRelativePath: Value(null),
            previewRelativePath: Value(null),
          ),
        );
        await (db.update(db.assets)..where((t) => t.id.equals(kam.id))).write(
          const AssetsCompanion(
            cameraMake: Value(null),
            cameraModel: Value(null),
            lensModel: Value(null),
            fNumber: Value(null),
            iso: Value(null),
            exposureTimeSeconds: Value(null),
            focalLengthMm: Value(null),
            focalLength35mm: Value(null),
          ),
        );
        await db.fuehreAus(
          AufnahmedatenSetzen([
            (
              id: ablage.id,
              zeitpunkt: DateTime(2020, 3, 5, 9),
              geschaetzt: false,
            ),
          ]),
        );
      });
      final xmpAlt = bibliothek.paths.absolute(
        bibliothek.paths.xmpSidecarPath(ablage.relativePath),
      )..writeAsStringSync('<x:xmpmeta xmlns:x="adobe:ns:meta/"/>');

      await oeffneAufgaben(tester);

      // IMP-129
      await aufgabeStarten(tester, de.aufgDatumsherkunftTitel, de.aufgFehlende);
      await waitFor(
        tester,
        find.descendant(
          of: aufgabenkarte(de.aufgDatumsherkunftTitel),
          matching: find.text(de.allgSchliessen),
        ),
        timeout: const Duration(seconds: 60),
      );
      final ohne2 = (await mitDb(
        tester,
        () => bibliothek.db.assetById(ohne.id),
      ))!;
      final mit2 = (await mitDb(
        tester,
        () => bibliothek.db.assetById(mit.id),
      ))!;
      expect(ohne2.datumGeschaetzt, isTrue);
      expect(mit2.datumGeschaetzt, isFalse);

      // IMP-130
      final ablageKarte = aufgabenkarte(de.aufgAblageTitel);
      await sichtbar(
        tester,
        find.text(de.aufgAblageTitel),
        BackgroundTasksScreen,
      );
      await waitFor(
        tester,
        find.descendant(
          of: ablageKarte,
          matching: find.text('${de.aufgBetrifft}: 1'),
        ),
      );
      await aufgabeStarten(tester, de.aufgAblageTitel, de.aufgModusAlle);
      await waitFor(tester, find.text(de.werkzAblageFrageTitel));
      await tapFrei(tester, find.text(de.werkzAblageStarten));
      await waitFor(
        tester,
        find.descendant(
          of: ablageKarte,
          matching: find.textContaining(' umgelegt'),
        ),
        timeout: const Duration(seconds: 60),
      );
      print('IMP-130 Bilanz: ${onScreen(tester)}');
      expect(
        find.descendant(
          of: ablageKarte,
          matching: find.text(de.werkzAblageBilanz(1, 1)),
        ),
        findsOneWidget,
      );
      final umgelegt = (await mitDb(
        tester,
        () => bibliothek.db.assetById(ablage.id),
      ))!;
      expect(umgelegt.relativePath, startsWith('originals/2020/03/'));
      expect(umgelegt.fileCreatedAt, DateTime(2020, 3, 5, 9));
      expect(xmpAlt.existsSync(), isFalse);
      expect(
        bibliothek.paths
            .absolute(bibliothek.paths.xmpSidecarPath(umgelegt.relativePath))
            .existsSync(),
        isTrue,
      );
      await tapFrei(
        tester,
        find.descendant(
          of: ablageKarte,
          matching: find.text(de.allgSchliessen),
        ),
      );
      await aufgabeStarten(tester, de.aufgAblageTitel, de.aufgModusAlle);
      await tapFrei(tester, find.text(de.werkzAblageStarten));
      await waitFor(
        tester,
        find.descendant(
          of: ablageKarte,
          matching: find.text(de.werkzAblageStimmt),
        ),
        timeout: const Duration(seconds: 60),
      );

      // IMP-132
      await aufgabeStarten(tester, de.aufgDateiartTitel, de.aufgFehlende);
      await waitFor(
        tester,
        find.descendant(
          of: aufgabenkarte(de.aufgDateiartTitel),
          matching: find.text(de.allgSchliessen),
        ),
        timeout: const Duration(seconds: 60),
      );
      expect(
        (await mitDb(tester, () => bibliothek.db.assetById(stand.id)))!.type,
        'IMAGE',
      );
      expect(
        (await mitDb(tester, () => bibliothek.db.assetById(vid.id)))!.type,
        'VIDEO',
      );
      final standNach = await mitDb(
        tester,
        () => bibliothek.db.assetById(stand.id),
      );
      print('IMP-132 Vorschaubild: ${standNach!.thumbnailRelativePath}');

      // IMP-134
      await aufgabeStarten(tester, de.aufgKameraTitel, de.aufgFehlende);
      await waitFor(
        tester,
        find.descendant(
          of: aufgabenkarte(de.aufgKameraTitel),
          matching: find.text(de.allgSchliessen),
        ),
        timeout: const Duration(seconds: 60),
      );
      final kam2 = (await mitDb(
        tester,
        () => bibliothek.db.assetById(kam.id),
      ))!;
      expect(kam2.cameraMake, 'Testkamera');
      expect(kam2.cameraModel, 'T1');
      expect(kam2.lensModel, 'Testobjektiv 35mm');
      expect(kam2.fNumber, closeTo(2.8, 0.01));
      expect(kam2.iso, 200);
      expect(kam2.exposureTimeSeconds, closeTo(1 / 250, 0.0001));
      expect(kam2.focalLengthMm, closeTo(35, 0.01));
      await alleZurueck(tester);
      await openSection(tester, Hauptbereich.zeitleiste);
      await oeffneFoto(tester, kam.id);
      await tapFrei(tester, find.byTooltip(de.viewerInfo));
      final blatt = find.byType(AssetInfoSheet);
      await waitFor(
        tester,
        find.descendant(of: blatt, matching: find.textContaining('T1')),
      );
      expect(
        find.descendant(
          of: blatt,
          matching: find.textContaining('Testobjektiv 35mm'),
        ),
        findsWidgets,
      );
      for (final w in aufnahmewerte(kam2)) {
        expect(
          find.descendant(of: blatt, matching: find.textContaining(w)),
          findsWidgets,
          reason: 'Info-Blatt zeigt $w',
        );
      }
      await zurueck(tester);

      // IMP-129 (Rest): Info-Blatt des Fotos ohne Datum.
      await oeffneFoto(tester, ohne.id);
      await tapFrei(tester, find.byTooltip(de.viewerInfo));
      await waitFor(tester, find.text(de.infoDatumGeschaetzt));
      await ende(tester);
    },
  );

  // Befund: setzeDateiart (packages/kern/lib/db/abfragen/serien.dart:452)
  // verwirft beim Berichtigen Miniatur und Vorschau. Nach „Dateiarten
  // prüfen" ist das Standbild ein Foto ohne Vorschaubild, bis jemand
  // „Vorschaubilder erzeugen" anstösst.
  testWidgets('IMP-132 nach Dateiarten-Lauf hat das Foto ein Vorschaubild', (
    tester,
  ) async {
    await zweimal(tester, () async {
      await importiereDirekt(tester, [testfoto('standbild.jpg')]);
      final stand = await aufnahme(tester, 'standbild.jpg');
      await mitDb(tester, () async {
        final db = bibliothek.db;
        await (db.update(db.assets)..where((t) => t.id.equals(stand.id))).write(
          const AssetsCompanion(type: Value('VIDEO')),
        );
      });
      await oeffneAufgaben(tester);
      await aufgabeStarten(tester, de.aufgDateiartTitel, de.aufgFehlende);
      await waitFor(
        tester,
        find.descendant(
          of: aufgabenkarte(de.aufgDateiartTitel),
          matching: find.text(de.allgSchliessen),
        ),
        timeout: const Duration(seconds: 60),
      );
      await eventually(
        tester,
        () async {
          final x = (await bibliothek.db.assetById(stand.id))!;
          return x.type == 'IMAGE' && x.thumbnailRelativePath != null;
        },
        timeout: const Duration(seconds: 30),
        was: 'Foto mit Vorschaubild',
      );
    });
  }, skip: true);

  testWidgets('IMP-133 Live-Photo-Paare prüfen', (tester) async {
    await startApp(tester);
    final zeit = DateTime(2024, 6, 1, 12, 30, 15);
    final foto = testfoto('IMG_0001.JPG', datum: zeit);
    final mov = mitVideozeit(
      _umbenannt(fixture('video_hoch_3s.mov'), 'IMG_0001.MOV'),
      zeit,
    );
    final foto2 = testfoto('IMG_0002.JPG', datum: DateTime(2015, 1, 1, 9));
    final mov2 = mitVideozeit(
      _umbenannt(
        File(
          p.join(fixturesOrdner, 'video_hoch_3s.mov'),
        ).copySync(p.join(eingang.path, 'zwischen.mov')),
        'IMG_0002.MOV',
      ),
      DateTime(2024, 6, 1, 9),
    );
    await importiereDirekt(tester, [foto, mov, foto2, mov2]);
    final f = await aufnahme(tester, 'IMG_0001.JPG');
    final m = await aufnahme(tester, 'IMG_0001.MOV');
    final f2 = await aufnahme(tester, 'IMG_0002.JPG');
    final m2 = await aufnahme(tester, 'IMG_0002.MOV');
    print('IMP-133 nach Import: ${f.linkedAssetId} ${f2.linkedAssetId}');
    // Paar 1 unverknüpft, Paar 2 falsch verknüpft (Jahre auseinander).
    await mitDb(tester, () async {
      final db = bibliothek.db;
      await (db.update(db.assets)..where((t) => t.id.isIn([f.id, m.id]))).write(
        const AssetsCompanion(linkedAssetId: Value(null)),
      );
      await (db.update(db.assets)..where((t) => t.id.equals(f2.id))).write(
        AssetsCompanion(linkedAssetId: Value(m2.id)),
      );
      await (db.update(db.assets)..where((t) => t.id.equals(m2.id))).write(
        AssetsCompanion(linkedAssetId: Value(f2.id)),
      );
    });
    await oeffneAufgaben(tester);
    await aufgabeStarten(tester, de.aufgLivePhotoTitel, de.aufgFehlende);
    await waitFor(
      tester,
      find.descendant(
        of: aufgabenkarte(de.aufgLivePhotoTitel),
        matching: find.text(de.allgSchliessen),
      ),
      timeout: const Duration(seconds: 60),
    );
    final f1n = (await mitDb(tester, () => bibliothek.db.assetById(f.id)))!;
    final f2n = (await mitDb(tester, () => bibliothek.db.assetById(f2.id)))!;
    print('IMP-133 nach dem Lauf: ${f1n.linkedAssetId} ${f2n.linkedAssetId}');
    expect(f1n.linkedAssetId, m.id, reason: 'passendes Paar verknüpft');
    await ende(tester);
  });

  // Befund: relinkLivePhotos (library_state.dart:2329-2342) sieht nur
  // unverknüpfte Fotos an. Ein falsch verknüpftes Paar (Jahre auseinander)
  // löst die Aufgabe nicht – das tut nur der einmalige Startnachlauf
  // repariereLivePhotoPaare (library_state.dart:366-369).
  testWidgets('IMP-133 falsch verknüpfte Paare werden gelöst', (tester) async {
    await zweimal(tester, () async {
      final foto2 = testfoto('IMG_0002.JPG', datum: DateTime(2015, 1, 1, 9));
      final mov2 = mitVideozeit(
        _umbenannt(fixture('video_hoch_3s.mov'), 'IMG_0002.MOV'),
        DateTime(2024, 6, 1, 9),
      );
      await importiereDirekt(tester, [foto2, mov2]);
      final f2 = await aufnahme(tester, 'IMG_0002.JPG');
      final m2 = await aufnahme(tester, 'IMG_0002.MOV');
      await mitDb(tester, () async {
        final db = bibliothek.db;
        await (db.update(db.assets)..where((t) => t.id.equals(f2.id))).write(
          AssetsCompanion(linkedAssetId: Value(m2.id)),
        );
        await (db.update(db.assets)..where((t) => t.id.equals(m2.id))).write(
          AssetsCompanion(linkedAssetId: Value(f2.id)),
        );
      });
      await oeffneAufgaben(tester);
      await aufgabeStarten(tester, de.aufgLivePhotoTitel, de.aufgFehlende);
      await waitFor(
        tester,
        find.descendant(
          of: aufgabenkarte(de.aufgLivePhotoTitel),
          matching: find.text(de.allgSchliessen),
        ),
        timeout: const Duration(seconds: 60),
      );
      final f2n = (await mitDb(tester, () => bibliothek.db.assetById(f2.id)))!;
      expect(f2n.linkedAssetId, isNull, reason: 'falsches Paar gelöst');
    });
  }, skip: true);

  // Befund: „Vorschaubilder erzeugen → Fehlende" findet eine gelöschte
  // Miniaturdatei nicht. Die Abfrage (packages/kern/lib/db/abfragen/
  // serien.dart:376, _fehlendeVorschau) prüft nur, ob der Pfad in der
  // Datenbank leer ist, nicht, ob die Datei da ist.
  testWidgets('IMP-135 Vorschaubilder erzeugen nach gelöschter Miniatur', (
    tester,
  ) async {
    await zweimal(tester, () async {
      await importiereDirekt(tester, [testfoto('miniatur.jpg')]);
      final a = await aufnahme(tester, 'miniatur.jpg');
      final miniatur = bibliothek.paths.absolute(a.thumbnailRelativePath!)
        ..deleteSync();
      await oeffneAufgaben(tester);
      await aufgabeStarten(tester, de.aufgVorschauTitel, de.aufgFehlende);
      await waitFor(
        tester,
        find.descendant(
          of: aufgabenkarte(de.aufgVorschauTitel),
          matching: find.text(de.allgSchliessen),
        ),
        timeout: const Duration(seconds: 60),
      );
      await eventually(tester, () async {
        final x = (await bibliothek.db.assetById(a.id))!;
        final pfad = x.thumbnailRelativePath;
        return pfad != null && bibliothek.paths.absolute(pfad).existsSync();
      }, was: 'Miniatur wieder da (${miniatur.path})');
    });
  }, skip: true);

  testWidgets('IMP-135 Vorschaubilder erzeugen nach ausgetragenem Pfad', (
    tester,
  ) async {
    await startApp(tester);
    await importiereDirekt(tester, [testfoto('miniatur.jpg')]);
    final a = await aufnahme(tester, 'miniatur.jpg');
    bibliothek.paths.absolute(a.thumbnailRelativePath!).deleteSync();
    await mitDb(tester, () => bibliothek.db.clearMissingThumbnailPath(a.id));
    await oeffneAufgaben(tester);
    await aufgabeStarten(tester, de.aufgVorschauTitel, de.aufgFehlende);
    await waitFor(
      tester,
      find.descendant(
        of: aufgabenkarte(de.aufgVorschauTitel),
        matching: find.text(de.aufgFertigMit(1)),
      ),
      timeout: const Duration(seconds: 60),
    );
    await eventually(tester, () async {
      final x = (await bibliothek.db.assetById(a.id))!;
      final pfad = x.thumbnailRelativePath;
      return pfad != null && bibliothek.paths.absolute(pfad).existsSync();
    }, was: 'Miniatur wieder da');
    await ende(tester);
  });

  // ---------------------------------------------------------------------
  // Mit dem Wegwerf-Server (PV_E2E_SERVER=1, sonst übersprungen)
  // ---------------------------------------------------------------------

  testWidgets(
    'IMP-131 IMP-207 IMP-219 IMP-122 IMP-185 mitServer verbundene Bibliothek',
    (tester) async {
      await startApp(tester);
      await importiereDirekt(tester, [
        testfoto('s_a.jpg', datum: DateTime(2023, 8, 15, 14, 30)),
        testfoto('s_b.jpg', datum: DateTime(2023, 8, 16, 14, 30)),
        testfoto('s_c.jpg', datum: DateTime(2023, 8, 17, 14, 30)),
        testfoto('s_d.jpg', datum: DateTime(2023, 8, 18, 14, 30)),
      ]);
      final a = await aufnahme(tester, 's_a.jpg');
      final b = await aufnahme(tester, 's_b.jpg');
      final c = await aufnahme(tester, 's_c.jpg');
      final d = await aufnahme(tester, 's_d.jpg');
      final (server, token) = await verbindeMitServer(tester);
      final v = Serververbindung(server, token);
      Future<Map<String, Object?>> amServer(String id) =>
          mitDb(tester, () => v.hole('api/v1/aufnahmen/$id'));

      // IMP-131: Ablage ordnen geht verbunden nicht.
      await mitDb(
        tester,
        () => bibliothek.db.fuehreAus(
          AufnahmedatenSetzen([
            (id: d.id, zeitpunkt: DateTime(2020, 3, 5, 9), geschaetzt: false),
          ]),
        ),
      );
      final dVorher = (await mitDb(
        tester,
        () => bibliothek.db.assetById(d.id),
      ))!;
      await oeffneAufgaben(tester);
      await aufgabeStarten(tester, de.aufgAblageTitel, de.aufgModusAlle);
      if (find.text(de.werkzAblageFrageTitel).evaluate().isNotEmpty) {
        await tapFrei(tester, find.text(de.werkzAblageStarten));
      }
      await settle(tester);
      await meldungGesehen(tester, 'Server verbunden');
      print(
        'IMP-131 Hinweis: '
        '${Meldungsdienst.zentral.verlauf.first.text}',
      );
      expect(
        (await mitDb(
          tester,
          () => bibliothek.db.assetById(d.id),
        ))!.relativePath,
        dVorher.relativePath,
        reason: 'keine Datei verschoben',
      );
      await alleZurueck(tester);

      // IMP-207: Sperren geht verbunden nicht (der Schutz greift).
      Object? fehler207;
      await mitDb(tester, () async {
        try {
          await bibliothek.setupVaultPin(_pin);
          await bibliothek.lockAsset(a);
        } catch (e) {
          fehler207 = e;
        }
      });
      print('IMP-207 Fehler: $fehler207');
      expect(istServersperre(fehler207 ?? ''), isTrue);
      final a207 = (await mitDb(tester, () => bibliothek.db.assetById(a.id)))!;
      expect(a207.isLocked, isFalse, reason: 'Foto bleibt unverändert');
      await openSection(tester, Hauptbereich.zeitleiste);
      await waitFor(tester, kachel(a.id));

      // IMP-219: Original nicht geholt (lokal fehlt die Datei).
      final cLokal = (await mitDb(
        tester,
        () => bibliothek.db.assetById(c.id),
      ))!;
      if (datei(cLokal).existsSync()) datei(cLokal).deleteSync();
      await oeffneWerkzeug(tester, de.werkzIntegritaetTitel);
      await warteIntegritaet(tester);
      print('IMP-219 Anzeige: ${onScreen(tester)}');
      final irrefuehrend = find
          .text(de.integFehlendeDateien(1))
          .evaluate()
          .isNotEmpty;
      print(
        'IMP-219 „Fehlende Dateien" für nicht geholtes Original: $irrefuehrend',
      );
      await alleZurueck(tester);

      // IMP-122: Datum ändern, die Datei am Server bleibt, wo sie ist.
      final bServerVorher = await amServer(b.id);
      await oeffneFoto(tester, b.id);
      await tapFrei(tester, find.byTooltip(de.viewerInfo));
      await tapFrei(
        tester,
        bearbeitenBeiDatum(
          DateFormat.yMMMd('de').format(DateTime(2023, 8, 16)),
        ),
      );
      await datumWaehlen(tester, DateTime(2021, 2, 3));
      await waitFor(
        tester,
        find.descendant(
          of: find.byType(AssetInfoSheet),
          matching: find.text(
            DateFormat.yMMMd('de').format(DateTime(2021, 2, 3)),
          ),
        ),
      );
      late Map<String, Object?> bServerNachher;
      await eventually(
        tester,
        () async {
          bServerNachher = await v.hole('api/v1/aufnahmen/${b.id}');
          return '${bServerNachher['fileCreatedAt']}' !=
              '${bServerVorher['fileCreatedAt']}';
        },
        timeout: const Duration(seconds: 60),
        was: 'neues Datum am Server',
      );
      print('IMP-122 Server: $bServerVorher → $bServerNachher');
      expect(bServerNachher['relativePath'], bServerVorher['relativePath']);
      await alleZurueck(tester);

      // IMP-185: Papierkorb leeren – der Server löscht.
      await mitDb(
        tester,
        () => bibliothek.db.fuehreAus(InDenPapierkorb([c.id])),
      );
      await eventually(
        tester,
        () async {
          final k = await v.hole('api/v1/papierkorb');
          return (k['aufnahmen']! as List).isNotEmpty;
        },
        timeout: const Duration(seconds: 60),
        was: 'Foto im Papierkorb des Servers',
      );
      await openSection(tester, Hauptbereich.papierkorb);
      await tapFrei(tester, find.byTooltip(de.papierkorbLeeren));
      await waitFor(tester, find.text(de.papierkorbLeerenText(1)));
      await tapFrei(
        tester,
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(de.allgLoeschen),
        ),
      );
      await eventually(
        tester,
        () async {
          final k = await v.hole('api/v1/papierkorb');
          return (k['aufnahmen']! as List).isEmpty;
        },
        timeout: const Duration(seconds: 60),
        was: 'Server-Papierkorb leer',
      );
      await waitFor(tester, find.text(de.papierkorbLeer));
      v.schliesse();
      await ende(tester);
    },
    skip: serverAdresse.isEmpty,
  );

  // Befund (beide nur mit frischem Wegwerf-Server, einzeln:
  // PV_E2E_SERVER=1 … --plain-name mitServerBefund):
  // – IMP-131: Verbunden weist pruefeStart (library_state.dart:1849) jede
  //   Aufgabe mit aufgAmServer ab („… dort läuft diese Arbeit."). Für die
  //   Ablage stimmt das nicht: Der Server ordnet die Ablage nie um (kein
  //   Gegenstück in packages/server); erwartet war nurOhneServer.
  // – IMP-219: Die Integritätsprüfung (integrity_check_screen.dart:54ff)
  //   fragt nicht, ob die Bibliothek verbunden ist, und meldet ein nicht
  //   geholtes Original als „Fehlende Dateien (1)" mit „Aus DB entfernen".
  testWidgets(
    'IMP-131 IMP-219 mitServerBefund Hinweise in verbundener Bibliothek',
    (tester) async {
      await startApp(tester);
      await importiereDirekt(tester, [
        testfoto('s_c.jpg', datum: DateTime(2023, 8, 17, 14, 30)),
        testfoto('s_d.jpg', datum: DateTime(2023, 8, 18, 14, 30)),
      ]);
      final c = await aufnahme(tester, 's_c.jpg');
      final d = await aufnahme(tester, 's_d.jpg');
      await verbindeMitServer(tester);
      await mitDb(
        tester,
        () => bibliothek.db.fuehreAus(
          AufnahmedatenSetzen([
            (id: d.id, zeitpunkt: DateTime(2020, 3, 5, 9), geschaetzt: false),
          ]),
        ),
      );
      await oeffneAufgaben(tester);
      await aufgabeStarten(tester, de.aufgAblageTitel, de.aufgModusAlle);
      if (find.text(de.werkzAblageFrageTitel).evaluate().isNotEmpty) {
        await tapFrei(tester, find.text(de.werkzAblageStarten));
      }
      await meldungGesehen(tester, de.nurOhneServer);
      await alleZurueck(tester);
      final cLokal = (await mitDb(
        tester,
        () => bibliothek.db.assetById(c.id),
      ))!;
      if (datei(cLokal).existsSync()) datei(cLokal).deleteSync();
      await oeffneWerkzeug(tester, de.werkzIntegritaetTitel);
      await warteIntegritaet(tester);
      expect(find.text(de.integFehlendeDateien(1)), findsNothing);
      await ende(tester);
    },
    skip: true,
  );

  // Befund: asset_info_sheet.dart:367 setzt firstDate fest auf 1990. Steht
  // das Datum davor (hier 1975), verletzt initialDate die Vorbedingung von
  // showDatePicker – der Kalender öffnet sich nicht, und ein Datum vor 1990
  // ist von Hand ohnehin nicht wählbar.
  testWidgets('IMP-121 Datum vor 1990 von Hand', (tester) async {
    await startApp(tester);
    await importiereDirekt(tester, [testfoto('scan_1975.jpg')]);
    final a = await aufnahme(tester, 'scan_1975.jpg');
    await mitDb(
      tester,
      () => bibliothek.db.fuehreAus(JahrSchaetzen(a.id, 1975)),
    );
    await oeffneFoto(tester, a.id);
    await tapFrei(tester, find.byTooltip(de.viewerInfo));
    final titel = DateFormat.yMMMd('de').format(DateTime(1975, 7, 1));
    await waitFor(tester, find.text(titel));
    await tester.tap(bearbeitenBeiDatum(titel));
    await settle(tester);
    final fehler = tester.takeException();
    expect(fehler, isNull, reason: 'Kalender öffnet ohne Fehler: $fehler');
    expect(find.byType(DatePickerDialog), findsOneWidget);
    final dialog = tester.widget<DatePickerDialog>(
      find.byType(DatePickerDialog),
    );
    expect(dialog.firstDate.isBefore(DateTime(1975)), isTrue);
    await ende(tester);
  });
}

// ---------------------------------------------------------------------------
// Eigene Hilfen
// ---------------------------------------------------------------------------

/// Wartet die Hintergrundanalyse ab und beendet die Prüfung – sonst
/// meldet die Analyse nach dem Abbau noch an den entsorgten Zustand.
///
/// Dazu wird die Leerlaufuhr der Restaurierungs-Warteschlange stillgelegt:
/// Jeder Klick stellt sie auf 20 s, und liefe sie nach [finish] ab, fragte
/// sie die schon geschlossene Datenbank – das schlüge der längst
/// beendeten Prüfung als Fehler zu.
Future<void> ende(WidgetTester tester) async {
  try {
    await analyseAbwarten(tester);
  } catch (e) {
    print('ende: $e');
  }
  runZoned(
    () => bibliothek.restoreQueue.noteUserInteraction(),
    zoneSpecification: ZoneSpecification(
      createTimer: (self, parent, zone, dauer, f) =>
          parent.createTimer(zone, const Duration(days: 365), () {}),
    ),
  );
  await finish(tester);
}

/// Ob die Meldung [text] erschienen ist. Über den Verlauf des
/// Meldungsdienstes: Eine Meldung steht vier Sekunden, und das Warten auf
/// Ruhe nach einem Klick dauert bis zu fünf – auf dem Bildschirm wäre sie
/// dann schon wieder weg.
Future<void> meldungGesehen(WidgetTester tester, String text) => eventually(
  tester,
  () async => Meldungsdienst.zentral.verlauf.any(
    (m) =>
        m.text.contains(text) &&
        DateTime.now().difference(m.zeit) < const Duration(seconds: 40),
  ),
  timeout: const Duration(seconds: 20),
  was: 'Meldung „$text"',
);

/// Tippt ohne langes Warten danach (für Meldungen mit „Rückgängig").
Future<void> tippe(WidgetTester tester, Finder finder) async {
  await waitFor(tester, finder);
  await tester.ensureVisible(finder.first);
  await tester.pump();
  await tester.tap(finder.first);
  await tester.pump(const Duration(milliseconds: 300));
}

/// Zustand einer älteren Fassung: Datum = Zeitpunkt des Kopierens
/// (geschätzt), das Original im Ordner dieses Monats.
Future<void> alsKopierdatum(WidgetTester tester, List<String> namen) =>
    mitDb(tester, () async {
      final jetzt = DateTime.now();
      final kopierzeit = DateTime(
        jetzt.year,
        jetzt.month,
        jetzt.day,
        jetzt.hour,
        jetzt.minute,
      ).subtract(const Duration(minutes: 5));
      final db = bibliothek.db;
      for (final name in namen) {
        final a = await (db.select(
          db.assets,
        )..where((t) => t.originalFileName.equals(name))).getSingle();
        await bibliothek.setzeAufnahmedatumVonHand([a.id], kopierzeit);
        await (db.update(db.assets)..where((t) => t.id.equals(a.id))).write(
          const AssetsCompanion(datumGeschaetzt: Value(true)),
        );
      }
    });

/// Startet die App neu – in derselben Wegwerf-Bibliothek (die Umlenkung
/// aus [startApp] bleibt bestehen), wie nach „Bitte neu starten".
Future<void> neuStarten(WidgetTester tester) async {
  await tester.runAsync(() => bibliothek.vorDemBeenden());
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpWidget(const PhotoVaultApp());
  await waitFor(
    tester,
    find.byType(HomeShell),
    timeout: const Duration(seconds: 90),
  );
  bibliothek = Provider.of<LibraryState>(
    tester.element(find.byType(HomeShell)),
    listen: false,
  );
  expect(bibliothek.paths.root.path, startsWith(anker.path));
  await settle(tester);
}

/// Der Ordnerdialog unter macOS geht nicht über file_picker (den das Kit
/// nachstellt), sondern über den Kanal `photo_vault/library_location`
/// (NSOpenPanel mit Lesezeichen). Hier nachgestellt; [pfad] `null` nimmt
/// die Nachstellung zurück.
void ordnerwahlNachstellen(WidgetTester tester, String? pfad) {
  const kanal = MethodChannel('photo_vault/library_location');
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    kanal,
    pfad == null
        ? null
        : (call) async => call.method == 'pickFolderAndCreateBookmark'
              ? {'path': pfad, 'bookmark': 'pruefstand'}
              : null,
  );
}

/// Wartet, bis [finder] mindestens [anzahl] Treffer hat.
Future<void> warteAufAnzahl(
  WidgetTester tester,
  Finder finder,
  int anzahl, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final ende = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(ende)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().length >= anzahl) return;
  }
  throw TimeoutException(
    'Nicht $anzahl Treffer: $finder\nAuf dem Bildschirm: ${onScreen(tester)}',
  );
}

/// Spielt einen Befund zweimal durch, jedes Mal mit frischer Bibliothek –
/// die zweite Reproduktion im selben Lauf. Schlägt nur fehl, wenn das
/// Erwartete ausbleibt; was genau, steht für beide Durchgänge da.
Future<void> zweimal(
  WidgetTester tester,
  Future<void> Function() szenario,
) async {
  final fehler = <String>[];
  for (var durchgang = 1; durchgang <= 2; durchgang++) {
    await startApp(tester);
    try {
      await szenario();
    } on TestFailure catch (e) {
      fehler.add('Durchgang $durchgang: ${e.message}');
    } on TimeoutException catch (e) {
      fehler.add('Durchgang $durchgang: ${e.message?.split('\n').first}');
    }
    await ende(tester);
  }
  print('Befund-Durchgänge: $fehler');
  expect(fehler, isEmpty);
}

/// Tippt wie [tap], schliesst aber vorher die Meldungen oben rechts – sie
/// liegen über der App und fingen sonst den Klick auf einen Knopf darunter
/// ab (so traf ein Klick auf „1 übergangen" das „Rückgängig" der Meldung).
Future<void> tapFrei(WidgetTester tester, Finder finder) async {
  if (Meldungsdienst.zentral.sichtbare.isNotEmpty) {
    Meldungsdienst.zentral.alleSchliessen();
    await tester.pump(const Duration(milliseconds: 300));
  }
  await tap(tester, finder);
}

/// Legt am Wegwerf-Server das erste Konto an, zieht die Bibliothek
/// dorthin und schreibt die Verbindungsdatei – was „Mit Server verbinden"
/// → „Diese Bibliothek auf den Server ziehen" tut –, dann Neustart. Danach
/// ist die Bibliothek die Kopie der Serverbibliothek.
Future<(Uri, String)> verbindeMitServer(WidgetTester tester) async {
  final server = Uri.parse(serverAdresse);
  late String token;
  await tester.runAsync(() async {
    final anmeldung = Anmeldung(server);
    final schritt = await anmeldung.einrichten(
      'verwalter',
      'pruefpasswort-123',
      geraet: 'Rechner A',
    );
    anmeldung.schliesse();
    token = (schritt as AnmeldungFertig).token;
    final v = Serververbindung(server, token);
    try {
      await for (final _ in Umzug(
        v,
        bibliothek.db,
        bibliothek.paths.root,
      ).laufe()) {}
    } finally {
      v.schliesse();
    }
    await Verbindungsdatei(
      server: server,
      konto: 'verwalter',
      geraet: 'Rechner A',
      token: token,
    ).schreibe(await LibraryLocation.currentRoot());
  });
  await neuStarten(tester);
  expect(bibliothek.verbunden, isTrue);
  await eventually(
    tester,
    () async => bibliothek.abgleichszustand?.erreichbar ?? false,
    timeout: const Duration(seconds: 60),
    was: 'Server erreichbar',
  );
  return (server, token);
}

/// Datenbankarbeit in echter Zeit.
Future<T> mitDb<T>(WidgetTester tester, Future<T> Function() arbeit) async =>
    (await tester.runAsync(arbeit)) as T;

Future<List<AssetData>> alleAufnahmen(WidgetTester tester) =>
    mitDb(tester, () => bibliothek.db.select(bibliothek.db.assets).get());

Future<AssetData> aufnahme(WidgetTester tester, String name) => mitDb(
  tester,
  () => (bibliothek.db.select(
    bibliothek.db.assets,
  )..where((t) => t.originalFileName.equals(name))).getSingle(),
);

File datei(AssetData a) => bibliothek.paths.absolute(a.relativePath);

DateTime vorMinuten(int n) => DateTime.now().subtract(Duration(minutes: n));

/// Die Kachel einer Aufnahme (Zeitleiste, Suche, Duplikate, Serien …).
Finder kachel(String id) =>
    find.byWidgetPredicate((w) => w is AssetThumbnailTile && w.asset.id == id);

/// Alle offenen Seiten schliessen (Zurück-Pfeil, sonst Escape).
Future<void> alleZurueck(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    final b = find.byType(BackButton);
    if (b.evaluate().isEmpty) return;
    await tester.tap(b.last);
    await settle(tester);
  }
}

/// Eine Seite zurück.
Future<void> zurueck(WidgetTester tester) async {
  final b = find.byType(BackButton);
  if (b.evaluate().isNotEmpty) {
    await tester.tap(b.last);
    await settle(tester);
  } else {
    await key(tester, LogicalKeyboardKey.escape);
  }
}

/// Scrollt im ersten Scrollbereich von [bildschirm], bis [ziel] sichtbar ist.
Future<void> sichtbar(WidgetTester tester, Finder ziel, Type bildschirm) async {
  await waitFor(tester, find.byType(bildschirm));
  final bereich = find
      .descendant(
        of: find.byType(bildschirm),
        matching: find.byType(Scrollable),
      )
      .first;
  // Von oben an suchen: Liegt das Ziel über der aktuellen Stelle, fände
  // ein Blättern nach unten es nie.
  if (ziel.evaluate().isEmpty) {
    tester.state<ScrollableState>(bereich).position.jumpTo(0);
    await tester.pump();
  }
  await tester.scrollUntilVisible(
    ziel,
    250,
    scrollable: bereich,
    maxScrolls: 60,
  );
  await settle(tester);
}

/// Werkzeuge öffnen und dort einen Eintrag antippen.
Future<void> oeffneWerkzeug(WidgetTester tester, String titel) async {
  await alleZurueck(tester);
  await openSection(tester, Hauptbereich.werkzeuge);
  final ziel = find.descendant(
    of: find.byType(ToolsScreen),
    matching: find.text(titel),
  );
  await sichtbar(tester, ziel, ToolsScreen);
  await tapFrei(tester, ziel);
}

Future<void> oeffneAufgaben(WidgetTester tester) async {
  await oeffneWerkzeug(tester, de.aufgTitel);
  await waitFor(tester, find.byType(BackgroundTasksScreen));
}

Finder aufgabenkarte(String titel) => find
    .ancestor(
      of: find.descendant(
        of: find.byType(BackgroundTasksScreen),
        matching: find.text(titel),
      ),
      matching: find.byType(Card),
    )
    .first;

Future<void> aufgabeStarten(
  WidgetTester tester,
  String titel,
  String modus,
) async {
  final t = find.descendant(
    of: find.byType(BackgroundTasksScreen),
    matching: find.text(titel),
  );
  await sichtbar(tester, t, BackgroundTasksScreen);
  await tapFrei(
    tester,
    find.descendant(of: aufgabenkarte(titel), matching: find.text(modus)),
  );
}

/// Eine Gruppe der Einstellungen aufklappen.
Future<void> einstellungsgruppe(WidgetTester tester, String titel) async {
  final t = find.descendant(
    of: find.byType(SettingsScreen),
    matching: find.text(titel),
  );
  await sichtbar(tester, t, SettingsScreen);
  await tapFrei(tester, t.first);
  await settle(tester);
}

/// Öffnet ein Foto aus der Zeitleiste im Vollbild.
Future<void> oeffneFoto(WidgetTester tester, String id) async {
  await alleZurueck(tester);
  await openSection(tester, Hauptbereich.zeitleiste);
  try {
    await waitFor(tester, kachel(id), timeout: const Duration(seconds: 5));
  } on TimeoutException {
    // Die Zeitleiste baut nur, was zu sehen ist – sonst dorthin blättern.
    await sichtbar(tester, kachel(id), TimelineScreen);
  }
  await tapFrei(tester, kachel(id));
  await waitFor(tester, find.byTooltip(de.viewerInfo));
}

Future<void> rechtsklickImBild(WidgetTester tester) async {
  final mitte = tester.getCenter(find.byType(Scaffold).last);
  await tester.tapAt(
    mitte,
    buttons: kSecondaryButton,
    kind: PointerDeviceKind.mouse,
  );
  await settle(tester);
}

/// Der Bearbeiten-Knopf in der Datumszeile des Info-Blatts.
Finder bearbeitenBeiDatum(String datumTitel) => find
    .descendant(
      of: find
          .ancestor(
            of: find.descendant(
              of: find.byType(AssetInfoSheet),
              matching: find.text(datumTitel),
            ),
            matching: find.byType(Row),
          )
          .first,
      matching: find.byType(IconButton),
    )
    .first;

/// Im Datumswähler auf Eingabe wechseln, [datum] eintippen, Uhrzeit
/// bestätigen.
Future<void> datumWaehlen(WidgetTester tester, DateTime datum) async {
  await waitFor(tester, find.byType(DatePickerDialog));
  final loc = MaterialLocalizations.of(
    tester.element(find.byType(DatePickerDialog)),
  );
  await tapFrei(tester, find.byTooltip(loc.inputDateModeButtonLabel));
  await enter(
    tester,
    find.descendant(
      of: find.byType(DatePickerDialog),
      matching: find.byType(TextField),
    ),
    loc.formatCompactDate(datum),
  );
  await tapFrei(
    tester,
    find.descendant(
      of: find.byType(DatePickerDialog),
      matching: find.text(loc.okButtonLabel),
    ),
  );
  await waitFor(tester, find.byType(TimePickerDialog));
  await tapFrei(
    tester,
    find.descendant(
      of: find.byType(TimePickerDialog),
      matching: find.text(loc.okButtonLabel),
    ),
  );
  await settle(tester);
}

/// Wartet, bis die Integritätsprüfung durch ist.
Future<void> warteIntegritaet(WidgetTester tester) async {
  await waitFor(tester, find.byType(IntegrityCheckScreen));
  await tester.pump(const Duration(milliseconds: 300));
  await waitGone(
    tester,
    find.descendant(
      of: find.byType(IntegrityCheckScreen),
      matching: find.byType(CircularProgressIndicator),
    ),
    timeout: const Duration(seconds: 60),
  );
  await settle(tester);
}

/// Die Zeile der Integritätsprüfung mit dem Pfad [pfad].
Finder integZeile(String pfad) => find.ancestor(
  of: find.descendant(
    of: find.byType(IntegrityCheckScreen),
    matching: find.text(pfad),
  ),
  matching: find.byType(ListTile),
);

/// Die Spalte einer Aufnahme in der Duplikatkarte.
Finder dupSpalte(String dateiname) => find
    .ancestor(
      of: find.descendant(
        of: find.byType(DuplicatesScreen),
        matching: find.text(dateiname),
      ),
      matching: find.byWidgetPredicate((w) => w is SizedBox && w.width == 150),
    )
    .first;

/// Die Spalte einer Aufnahme im Serien-/Variantenvergleich.
Finder vergleichsspalte(String id) => find
    .ancestor(
      of: find.descendant(
        of: find.byType(SerienvergleichScreen),
        matching: kachel(id),
      ),
      matching: find.byWidgetPredicate(
        (w) => w is Container && w.constraints?.maxWidth == 200,
      ),
    )
    .first;

/// Der Block einer Serie im Serienbildschirm, der [innen] enthält.
Finder serienblock(Finder innen) {
  final kandidaten = find
      .ancestor(of: innen, matching: find.byType(Column))
      .evaluate()
      .toList();
  for (final e in kandidaten) {
    final block = find.byElementPredicate((x) => x == e);
    final hatKnopf = find
        .descendant(
          of: block,
          matching: find.widgetWithText(FilledButton, de.allgUebernehmen),
        )
        .evaluate()
        .isNotEmpty;
    if (hatKnopf) return block;
  }
  throw StateError('Kein Serienblock gefunden');
}

/// Die Mittelpunkte der Papierkorb-Kacheln, in Anzeigereihenfolge.
List<Offset> papierkorbKacheln(WidgetTester tester) => [
  for (final e
      in find
          .descendant(
            of: find.byType(TrashScreen),
            matching: find.byTooltip(de.einstWiederherstellen),
          )
          .evaluate())
    tester.getCenter(
      find
          .ancestor(
            of: find.byElementPredicate((x) => x == e),
            matching: find.byType(Stack),
          )
          .first,
    ),
];

/// Kennungen im Papierkorb, wie der Bildschirm sie ordnet.
Future<List<String>> papierkorbReihe(WidgetTester tester) => mitDb(
  tester,
  () async => [for (final a in await bibliothek.db.papierkorb()) a.id],
);

Future<void> schaerfeSetzen(WidgetTester tester, Map<String, double> werte) =>
    mitDb(tester, () async {
      final db = bibliothek.db;
      for (final e in werte.entries) {
        await (db.update(db.assets)..where((t) => t.id.equals(e.key))).write(
          AssetsCompanion(sharpnessScore: Value(e.value)),
        );
      }
    });

/// Wartet, bis die Hintergrundanalyse nach dem Import ruht.
Future<void> analyseAbwarten(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 2)));
  await eventually(
    tester,
    () async => bibliothek.analyse == null,
    timeout: const Duration(seconds: 60),
    was: 'Hintergrundanalyse ruht',
  );
}

/// Ein Gesicht mit Ausschnitt in der Datenbank – Vorbedingung für den
/// Serienvergleich (die Gesichtserkennung selbst ist nicht geladen).
Future<void> gesichtSetzen(
  WidgetTester tester,
  String assetId, {
  required double schaerfe,
  required double augen,
}) => mitDb(tester, () async {
  final id = const Uuid().v4();
  final rel = 'faces/$id.jpg';
  final bild = img.Image(width: 160, height: 160);
  img.fill(bild, color: img.ColorRgb8(200, 160, 140));
  bibliothek.paths.absolute(rel)
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(img.encodeJpg(bild));
  await bibliothek.db
      .into(bibliothek.db.faces)
      .insert(
        FacesCompanion.insert(
          id: id,
          assetId: assetId,
          boxX: 0.3,
          boxY: 0.2,
          boxW: 0.3,
          boxH: 0.4,
          cropRelativePath: Value(rel),
          schaerfe: Value(schaerfe),
          eyeOpenScore: Value(augen),
        ),
      );
});

/// Drei fast gleiche Aufnahmen im Abstand von drei Sekunden.
List<File> serie(String name, DateTime start) {
  final basis = testfoto('${name}_1.jpg', datum: start);
  return [
    basis,
    variante(
      basis,
      '${name}_2.jpg',
      breite: 780,
      hoehe: 585,
      datum: start.add(const Duration(seconds: 3)),
    ),
    variante(
      basis,
      '${name}_3.jpg',
      breite: 760,
      hoehe: 570,
      datum: start.add(const Duration(seconds: 6)),
    ),
  ];
}

String _exifText(DateTime d) {
  String z(int v, int s) => v.toString().padLeft(s, '0');
  return '${z(d.year, 4)}:${z(d.month, 2)}:${z(d.day, 2)} '
      '${z(d.hour, 2)}:${z(d.minute, 2)}:${z(d.second, 2)}';
}

/// Eine verkleinerte (und auf Wunsch bemalte) Kopie von [basis] – ein
/// fast gleiches Foto mit anderer Prüfsumme.
File variante(
  File basis,
  String name, {
  required int breite,
  required int hoehe,
  DateTime? datum,
  void Function(img.Image bild)? zeichne,
}) {
  final bild = img.decodeJpg(basis.readAsBytesSync())!;
  final neu = img.copyResize(bild, width: breite, height: hoehe);
  zeichne?.call(neu);
  if (datum != null) {
    neu.exif.exifIfd['DateTimeOriginal'] = _exifText(datum);
    neu.exif.imageIfd['DateTime'] = _exifText(datum);
  }
  return File(p.join(eingang.path, name))
    ..writeAsBytesSync(img.encodeJpg(neu, quality: 90));
}

/// Ein Foto mit vollständigen Kameradaten in den EXIF-Angaben.
File kamerafoto(String name) {
  final vorlage = testfoto(
    'vorlage_$name',
    datum: DateTime(2023, 9, 9, 9, 9, 9),
  );
  final bild = img.decodeJpg(vorlage.readAsBytesSync())!;
  bild.exif.imageIfd['Make'] = 'Testkamera';
  bild.exif.imageIfd['Model'] = 'T1';
  bild.exif.exifIfd[0x829D] = img.IfdValueRational(28, 10); // FNumber
  bild.exif.exifIfd[0x829A] = img.IfdValueRational(1, 250); // ExposureTime
  bild.exif.exifIfd[0x8827] = img.IfdValueShort(200); // ISO
  bild.exif.exifIfd[0x920A] = img.IfdValueRational(35, 1); // FocalLength
  bild.exif.exifIfd[0xA434] = img.IfdValueAscii('Testobjektiv 35mm'); // Lens
  bild.exif.exifIfd['DateTimeOriginal'] = _exifText(
    DateTime(2023, 9, 9, 9, 9, 9),
  );
  vorlage.deleteSync();
  return File(p.join(eingang.path, name))
    ..writeAsBytesSync(img.encodeJpg(bild, quality: 90));
}

File _umbenannt(File f, String name) =>
    f.renameSync(p.join(f.parent.path, name));

/// Trägt [zeit] als Aufnahmezeit in den `mvhd`-Kasten eines MP4/MOV ein.
File mitVideozeit(File video, DateTime zeit) {
  final bytes = video.readAsBytesSync();
  final kennung = 'mvhd'.codeUnits;
  var stelle = -1;
  for (var i = 0; i + 4 <= bytes.length; i++) {
    if (bytes[i] == kennung[0] &&
        bytes[i + 1] == kennung[1] &&
        bytes[i + 2] == kennung[2] &&
        bytes[i + 3] == kennung[3]) {
      stelle = i;
      break;
    }
  }
  if (stelle < 0) throw StateError('kein mvhd in ${video.path}');
  final sekunden = DateTime.utc(
    zeit.year,
    zeit.month,
    zeit.day,
    zeit.hour,
    zeit.minute,
    zeit.second,
  ).difference(DateTime.utc(1904)).inSeconds;
  final daten = ByteData.sublistView(bytes);
  final fassung = bytes[stelle + 4];
  if (fassung == 1) {
    daten.setUint64(stelle + 8, sekunden);
    daten.setUint64(stelle + 16, sekunden);
  } else {
    daten.setUint32(stelle + 8, sekunden);
    daten.setUint32(stelle + 12, sekunden);
  }
  video.writeAsBytesSync(bytes);
  return video;
}

List<String> _dateienUnter(Directory d) => [
  for (final e in d.listSync(recursive: true))
    if (e is File && !e.path.endsWith('.part')) e.path,
]..sort();

// ---------------------------------------------------------------------------
// Nachgestelltes CLIP
// ---------------------------------------------------------------------------

const _dim = 512;
const _bildraster = 12;
const _textAnfang = _bildraster * _bildraster * 3;

/// Bildmerkmal: 12×12 gemittelt, je Farbkanal zentriert, normiert.
Float32List bildmerkmal(img.Image bild) {
  final klein = img.copyResize(
    bild,
    width: _bildraster,
    height: _bildraster,
    interpolation: img.Interpolation.average,
  );
  final kanaele = [<double>[], <double>[], <double>[]];
  for (final px in klein) {
    kanaele[0].add(px.r.toDouble());
    kanaele[1].add(px.g.toDouble());
    kanaele[2].add(px.b.toDouble());
  }
  final v = Float32List(_dim);
  var i = 0;
  for (final k in kanaele) {
    final mittel = k.reduce((a, b) => a + b) / k.length;
    for (final x in k) {
      v[i++] = x - mittel;
    }
  }
  return _normiert(v);
}

/// Ein Satz über ein Jahrzehnt („a photo taken in the 1960s.") zeigt auf
/// eine eigene Achse; jeder andere Text auf eine feste Zufallsrichtung.
Float32List textmerkmal(String satz) {
  final treffer = RegExp(r'(18\d\d|19\d\d|20\d\d)').firstMatch(satz);
  if (treffer != null) {
    return jahrzehntVektor(int.parse(treffer.group(1)!) ~/ 10 * 10);
  }
  final zufall = math.Random(satz.hashCode);
  final v = Float32List(_dim);
  for (var i = 0; i < _dim; i++) {
    v[i] = zufall.nextDouble() - 0.5;
  }
  return _normiert(v);
}

Float32List jahrzehntVektor(int jahrzehnt) {
  final v = Float32List(_dim);
  v[_textAnfang + ((jahrzehnt - 1880) ~/ 10).clamp(0, 60)] = 1;
  return v;
}

Float32List _normiert(Float32List v) {
  var laenge = 0.0;
  for (final x in v) {
    laenge += x * x;
  }
  laenge = math.sqrt(laenge);
  if (laenge == 0) return v;
  for (var i = 0; i < v.length; i++) {
    v[i] /= laenge;
  }
  return v;
}

class _NachgestelltesClip implements ClipService {
  @override
  Future<Float32List> embedImage(img.Image decoded) async =>
      bildmerkmal(decoded);

  @override
  Future<Float32List> embedText(String text) async => textmerkmal(text);

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Setzt Halter ein, die „installiert" melden. Der Bildteil lädt nichts
/// (die Einbettungen kommen über [einbettungenSetzen]); der Textteil
/// liefert [textmerkmal] für die Datierung.
void clipNachstellen() {
  bibliothek.clipBildHalter = ModellHalter<ClipService>(
    name: 'CLIP-Bild',
    installiert: true,
    laden: () async => throw StateError('Im Prüfstand wird nichts geladen'),
    entsorgen: (_) async {},
  );
  bibliothek.clipTextHalter = ModellHalter<ClipService>(
    name: 'CLIP-Text',
    installiert: true,
    laden: () async => _NachgestelltesClip(),
    entsorgen: (_) async {},
  );
}

/// Schreibt für jedes (nicht gesperrte) Foto die Einbettung aus seinen
/// Bildpunkten in die Datenbank; [fest] gibt einzelne vor, [ohne] lässt
/// welche aus.
Future<void> einbettungenSetzen(
  WidgetTester tester, {
  Map<String, Float32List> fest = const {},
  Set<String> ohne = const {},
}) => mitDb(tester, () async {
  final db = bibliothek.db;
  for (final a in await db.select(db.assets).get()) {
    if (a.type != 'IMAGE' || a.isLocked || ohne.contains(a.id)) continue;
    final v =
        fest[a.id] ??
        bildmerkmal(img.decodeImage(await datei(a).readAsBytes())!);
    await db.saveEmbedding(a.id, v);
  }
});
