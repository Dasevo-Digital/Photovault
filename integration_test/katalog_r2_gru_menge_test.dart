// ignore_for_file: avoid_print
// Zweite Prüfrunde, Prüfer r2-gru: grosse Mengen (3000 Fotos).
//
// Eigene Datei, weil jede Prüfung hier viele Minuten dauert und der
// Wächter der Warteschlange je Datei 40 Minuten zulässt.
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show FrameTiming;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kern/db/database.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/screens/albums_screen.dart';
import 'package:photo_vault/screens/home_shell.dart' show HomeShell;
import 'package:photo_vault/screens/import_plan_screen.dart';
import 'package:photo_vault/screens/search_screen.dart';
import 'package:photo_vault/screens/timeline_screen.dart';

import 'katalog_kit.dart';
import 'katalog_r2_gru_test.dart' hide main;

/// Sammelt die Bildzeiten (Aufbau + Zeichnen) über eine Phase.
class Bildzeiten {
  Bildzeiten() {
    SchedulerBinding.instance.addTimingsCallback(_sammle);
  }

  final ms = <double>[];

  void _sammle(List<FrameTiming> t) {
    for (final f in t) {
      ms.add(
        (f.buildDuration.inMicroseconds + f.rasterDuration.inMicroseconds) /
            1000,
      );
    }
  }

  var _aktiv = true;

  void stopp() {
    if (!_aktiv) return;
    _aktiv = false;
    SchedulerBinding.instance.removeTimingsCallback(_sammle);
  }

  double anteil(double p) {
    if (ms.isEmpty) return 0;
    final s = [...ms]..sort();
    return s[((s.length - 1) * p).round()];
  }

  @override
  String toString() =>
      '${ms.length} Bilder, Median ${anteil(0.5).toStringAsFixed(1)} ms, '
      '95 % ${anteil(0.95).toStringAsFixed(1)} ms, '
      'max ${ms.isEmpty ? 0 : ms.reduce(math.max).toStringAsFixed(1)} ms, '
      'über 100 ms: ${ms.where((m) => m > 100).length}';
}

/// Der senkrechte Scrollbereich der Zeitleiste.
Finder get zeitleistenScroller => find
    .descendant(
      of: find.byType(TimelineScreen),
      matching: find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      ),
    )
    .first;

/// Ein JPEG aus Rauschen – etwa 2 MB, wie ein Foto, das sich nicht
/// zusammendrücken lässt.
List<int> rauschJpeg(int breite, int hoehe) {
  final zufall = math.Random(42);
  final bild = img.Image(width: breite, height: hoehe);
  for (final px in bild) {
    px
      ..r = zufall.nextInt(256)
      ..g = zufall.nextInt(256)
      ..b = zufall.nextInt(256);
  }
  bild.exif.exifIfd['DateTimeOriginal'] = '2016:01:01 10:00:00';
  return img.encodeJpg(bild, quality: 90);
}

final _pruefFortschritt = RegExp(r'^\d+ von \d+ Dateien geprüft$');

/// Der Knopf „Importieren“ unten in der Seitenleiste.
Finder get leistenImport => find.descendant(
  of: find.ancestor(
    of: find.text(de.navImportieren),
    matching: find.byType(InkWell),
  ),
  matching: find.byIcon(Icons.add_photo_alternate_outlined),
);

/// Ordner-Import bis zum Startknopf von „Import prüfen“; liefert die
/// gesehenen Zählerstände der Prüfung.
Future<Set<String>> planFuerOrdner(
  WidgetTester tester,
  Directory ordner, {
  Duration timeout = const Duration(minutes: 3),
}) async {
  dialog.ordner = ordner.path;
  await tippe(tester, leistenImport.first);
  await waitFor(tester, find.text(de.importWasTitel));
  await tester.tap(find.text(de.importGanzerOrdner));
  final zeilen = find.descendant(
    of: find.byType(ImportPlanScreen),
    matching: find.byType(CheckboxListTile),
  );
  final zaehler = <String>{};
  final ende = DateTime.now().add(timeout);
  while (zeilen.evaluate().isEmpty ||
      find.textContaining(_pruefFortschritt).evaluate().isNotEmpty) {
    if (DateTime.now().isAfter(ende)) fail('Prüfung endet nicht');
    await tester.pump(const Duration(milliseconds: 100));
    for (final e in find.textContaining(_pruefFortschritt).evaluate()) {
      zaehler.add((e.widget as Text).data!);
    }
  }
  return zaehler;
}

/// Tippt auf den Startknopf von „Import prüfen“, sobald er frei ist.
Future<void> starteImport(WidgetTester tester, int n) async {
  final knopf = find.ancestor(
    of: find.text(de.importPlanStarten(n)),
    matching: find.byType(FilledButton),
  );
  await waitFor(tester, knopf, timeout: const Duration(seconds: 60));
  final ende = DateTime.now().add(const Duration(seconds: 60));
  while (tester.widget<FilledButton>(knopf).onPressed == null) {
    if (DateTime.now().isAfter(ende)) fail('Startknopf bleibt gesperrt');
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.tap(knopf);
  await tester.pump();
}

void main() {
  lebenszeichen();

  testWidgets('GRU-175 3000 Fotos: Orte einlesen, App bleibt bedienbar', (
    tester,
  ) async {
    filtereSemantik();
    await starte(tester);
    await bibliothek.db.setAutoAnalyzeAfterImport(false);
    const n = 3000;
    await importiere(
      tester,
      grosseFotos(n, stamm: 'ort', breite: 120, hoehe: 90, mitOrt: true),
    );
    expect(await aufnahmen(tester), hasLength(n));
    await bibliothek.db.customStatement(
      'UPDATE assets SET latitude = NULL, longitude = NULL, gps_geprueft = 0',
    );
    await aufgabenOeffnen(tester);
    final orte = await aufgabe(tester, de.aufgOrteTitel);
    final huelle = tester.state(find.byType(HomeShell));
    final zeiten = Bildzeiten();
    addTearDown(zeiten.stopp);
    final beginn = DateTime.now();
    await aktion(tester, orte, de.aufgModusAlle);
    await leisteSchnell(tester, de.navFotos);
    await waitFor(tester, find.byType(TimelineScreen));
    final zahlen = <int>[];
    final antwort = <int>[];
    var gerollt = 0.0;
    var i = 0;
    final band = RegExp('  (\\d+)/$n');
    while (!(bibliothek.lauf('orte')?.beendet ?? false) &&
        DateTime.now().difference(beginn) < const Duration(minutes: 8)) {
      i++;
      await tester.pump(const Duration(milliseconds: 16));
      for (final t in tester.widgetList<Text>(
        find.textContaining(de.werkzLeseOrte),
      )) {
        final m = band.firstMatch(t.data ?? '');
        if (m != null) {
          final z = int.parse(m.group(1)!);
          if (zahlen.isEmpty || zahlen.last != z) zahlen.add(z);
        }
      }
      if (i % 8 == 0 && find.byType(TimelineScreen).evaluate().isNotEmpty) {
        final pos = tester.state<ScrollableState>(zeitleistenScroller).position;
        final vor = pos.pixels;
        await tester.drag(
          zeitleistenScroller,
          Offset(0, pos.pixels > pos.maxScrollExtent - 600 ? 2000 : -400),
          warnIfMissed: false,
        );
        await tester.pump(const Duration(milliseconds: 16));
        gerollt += (pos.pixels - vor).abs();
      }
      if (i % 50 == 25) {
        final uhr = Stopwatch()..start();
        await leisteSchnell(tester, de.navAlben);
        await waitFor(tester, find.byType(AlbumsScreen));
        antwort.add(uhr.elapsedMilliseconds);
        final uhr2 = Stopwatch()..start();
        await leisteSchnell(tester, de.navSuche);
        await waitFor(tester, find.byType(SearchScreen));
        antwort.add(uhr2.elapsedMilliseconds);
        final uhr3 = Stopwatch()..start();
        await leisteSchnell(tester, de.navFotos);
        await waitFor(tester, find.byType(TimelineScreen));
        antwort.add(uhr3.elapsedMilliseconds);
      }
    }
    final dauer = DateTime.now().difference(beginn);
    zeiten.stopp();
    final lauf = bibliothek.lauf('orte');
    print(
      'GRU-175: Orte ${lauf?.erledigt}/${lauf?.gesamt} in '
      '${dauer.inSeconds} s, Band ${zahlen.length} Stände '
      '(${zahlen.take(5)} … ${zahlen.reversed.take(3)}), gerollt '
      '${gerollt.round()} px, Bereichswechsel $antwort ms, Bildzeiten $zeiten',
    );
    expect(lauf?.beendet, isTrue);
    expect(lauf!.erfolgreich, isTrue);
    expect(zahlen.length, greaterThan(3), reason: 'Band zählt sichtbar');
    for (var k = 1; k < zahlen.length; k++) {
      expect(zahlen[k], greaterThan(zahlen[k - 1]), reason: 'zählt weiter');
    }
    expect(gerollt, greaterThan(500), reason: 'Zeitleiste rollt');
    expect(antwort, isNotEmpty);
    expect(antwort.reduce(math.max), lessThan(2000), reason: 'Wechsel');
    expect(zeiten.anteil(0.95), lessThan(250), reason: 'flüssig');
    expect(
      identical(tester.state(find.byType(HomeShell)), huelle),
      isTrue,
      reason: 'die Hülle wird nicht neu aufgebaut (kein Flackern)',
    );
    expect(tester.takeException(), isNull);
    final mitOrt = (await aufnahmen(
      tester,
    )).where((a) => a.latitude != null).length;
    expect(mitOrt, n);
    await ende(tester);
  }, timeout: const Timeout(Duration(minutes: 25)));

  testWidgets('IMP-039 3000 Fotos zu je etwa 2 MB über den Ordner-Import', (
    tester,
  ) async {
    filtereSemantik();
    await starte(tester);
    await bibliothek.db.setAutoAnalyzeAfterImport(false);
    const n = 3000;
    final o = Directory(p.join(anker.path, 'quellen', 'menge'))
      ..createSync(recursive: true);
    final basis = rauschJpeg(1200, 900);
    print('IMP-039: Grundbild ${(basis.length / 1e6).toStringAsFixed(2)} MB');
    expect(basis.length, greaterThan(1500000), reason: 'etwa 2 MB');
    schritt = 'IMP-039 Dateien anlegen';
    await tester.runAsync(() async {
      grosseFotos(
        n,
        stamm: 'm',
        ordner: o,
        basisBytes: Uint8List.fromList(basis),
      );
    });
    final zaehler = await planFuerOrdner(
      tester,
      o,
      timeout: const Duration(minutes: 12),
    );
    print('IMP-039: Prüfung zählte ${zaehler.length} Stände');
    expect(zaehler.length, greaterThan(3), reason: 'Prüfung zählt sichtbar');
    final zeiten = Bildzeiten();
    addTearDown(zeiten.stopp);
    await starteImport(tester, n);
    schritt = 'IMP-039 Import';
    final stand = <String>{};
    var blaetternVersucht = false;
    var blaetternGing = false;
    final ende0 = DateTime.now().add(const Duration(minutes: 30));
    while (find.text(de.importAbgeschlossen).evaluate().isEmpty) {
      if (DateTime.now().isAfter(ende0)) fail('Import endet nicht');
      await tester.pump(const Duration(milliseconds: 100));
      for (final e in find.textContaining(RegExp('^\\d+ / $n')).evaluate()) {
        stand.add(((e.widget as Text).data!).split(' — ').first);
      }
      // Während des Imports in der App blättern: das Blatt wegschieben,
      // einen anderen Bereich öffnen und das Blatt aus der Aufgabenleiste
      // zurückholen (#464).
      if (!blaetternVersucht && stand.length > 20) {
        blaetternVersucht = true;
        await tester.tapAt(const Offset(700, 40));
        await tester.pump(const Duration(milliseconds: 500));
        final vorher = gewaehlt(tester);
        // Links auf das Symbol: Die Mitte der eingeklappten Zeile läge
        // über der Zeitleiste und öffnete womöglich ein Foto.
        await leisteSchnell(tester, de.navAlben);
        await tester.pump(const Duration(milliseconds: 300));
        blaetternGing = gewaehlt(tester) != vorher;
        print('IMP-039: Klick auf „Alben“ während des Imports: $blaetternGing');
        await tester.tap(find.text(de.importAnzeigen).first);
        await tester.pump(const Duration(milliseconds: 500));
      }
    }
    zeiten.stopp();
    print(
      'IMP-039: Import zählte ${stand.length} Stände, Bildzeiten $zeiten, '
      'blättern ging: $blaetternGing',
    );
    expect(stand.length, greaterThan(20), reason: 'Import zählt sichtbar');
    expect(blaetternGing, isTrue, reason: 'blättern während des Imports');
    expect(zeiten.anteil(0.95), lessThan(250), reason: 'Blatt bleibt flüssig');
    await tippe(tester, find.widgetWithText(OutlinedButton, de.allgFertig));
    await waitGone(tester, find.text(de.importAbgeschlossen));
    final alle = await aufnahmen(tester);
    expect(alle, hasLength(n));
    expect(
      alle.map((a) => a.checksum).toSet(),
      hasLength(n),
      reason: 'keine doppelt',
    );
    await ende(tester);
  }, timeout: const Timeout(Duration(minutes: 38)));

  // Behoben in #464 (IMP-039): Das Fortschrittsblatt lässt sich
  // wegschieben; der Import läuft in der Aufgabenleiste weiter, und ein
  // Klick auf die Seitenleiste öffnet einen anderen Bereich. Das Ergebnis
  // holt die Aufgabenleiste oder die Schlussmeldung zurück.
  testWidgets(
    'IMP-039 Befund: während des Imports einen anderen Bereich öffnen',
    (tester) async {
      filtereSemantik();
      final befunde = <String>[];
      for (var durchgang = 1; durchgang <= 2; durchgang++) {
        await starte(tester);
        await bibliothek.db.setAutoAnalyzeAfterImport(false);
        final o = Directory(p.join(anker.path, 'quellen', 'b$durchgang'))
          ..createSync(recursive: true);
        final basis = rauschJpeg(1200, 900);
        grosseFotos(
          400,
          stamm: 'b$durchgang',
          ordner: o,
          basisBytes: Uint8List.fromList(basis),
        );
        await planFuerOrdner(tester, o);
        await starteImport(tester, 400);
        await waitFor(
          tester,
          find.textContaining(RegExp(r'^\d+ / 400')),
          timeout: const Duration(seconds: 60),
        );
        // Das Blatt wegschieben: daneben klicken.
        await tester.tapAt(const Offset(700, 40));
        await tester.pump(const Duration(milliseconds: 500));
        final blattWeg = find.text(de.importLaeuft).evaluate().isEmpty;
        final inDerLeiste = find.text(de.importAnzeigen).evaluate().isNotEmpty;
        final vorher = gewaehlt(tester);
        // Links auf das Symbol: Die Mitte der eingeklappten Zeile läge
        // über der Zeitleiste und öffnete womöglich ein Foto.
        await leisteSchnell(tester, de.navAlben);
        await tester.pump(const Duration(milliseconds: 500));
        final ging =
            gewaehlt(tester) != vorher &&
            find.byType(AlbumsScreen).hitTestable().evaluate().isNotEmpty;
        final nochImport = bibliothek.importlauf?.laeuft ?? false;
        print(
          'IMP-039 Befund Durchgang $durchgang: Blatt weg $blattWeg, '
          'in der Leiste $inDerLeiste, Bereich gewechselt $ging, '
          'Import lief noch $nochImport',
        );
        if (nochImport && (!blattWeg || !inDerLeiste || !ging)) {
          befunde.add('Durchgang $durchgang');
        }
        await eventually(
          tester,
          () async => bibliothek.importlauf?.fertig ?? false,
          timeout: const Duration(minutes: 5),
          was: 'Import fertig',
        );
        // Das Ergebnis bleibt erreichbar: „Anzeigen“ an der Schlussmeldung.
        await tester.tap(find.text(de.importAnzeigen).first);
        await waitFor(tester, find.text(de.importAbgeschlossen));
        await tippe(tester, find.widgetWithText(OutlinedButton, de.allgFertig));
        expect(await aufnahmen(tester), hasLength(400));
        await ende(tester);
      }
      expect(befunde, isEmpty, reason: 'blättern während des Imports');
    },
    timeout: const Timeout(Duration(minutes: 20)),
  );
}
