/// **Was der Bildspeicher beim Scrollen wirklich tut.**
///
/// Kein Teil der Prüfsuite; liegt deshalb unter `tool/`. Flutters Vorgabe
/// – 1000 Bilder und 100 MB – ist nie angefasst worden. Ob sie reicht,
/// entscheidet nicht die Zahl, sondern die Frage: **Wird beim Zurück-
/// scrollen neu dekodiert?**
///
/// Genau das wird hier gemessen, und zwar ohne Buchführung über einzelne
/// Schlüssel: Ein Bild, das noch im Speicher liegt, legt beim Wiedersehen
/// **keinen neuen Eintrag** an. Die Zahl der Einträge, die beim Sprung
/// zurück an den Anfang hinzukommen, ist deshalb genau die Zahl der
/// verdrängten und neu dekodierten Bilder.
///
/// ```sh
/// PV_DB=…/lese.sqlite PV_LIB=…/lib flutter test tool/messe_bildspeicher_test.dart
/// ```
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/db/rasterzeile.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/services/bilddekodierung.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/theme/app_theme.dart';
import 'package:photo_vault/widgets/asset_thumbnail_tile.dart';
import 'package:photo_vault/widgets/month_grouped_asset_grid.dart';
import 'package:photo_vault/widgets/timeline_grid_layout.dart';

ImageCache get _speicher => PaintingBinding.instance.imageCache;

/// Sammelt waehrend des ersten Einpendelns je Runde
/// „Eintraege im Speicher / Schluessel im Baum gesehen".
List<String>? _spur;

String _mb(int bytes) => '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';

void main() {
  testWidgets('Bildspeicher beim Scrollen', (tester) async {
    final dbPfad = Platform.environment['PV_DB'];
    final libPfad = Platform.environment['PV_LIB'];
    if (dbPfad == null || libPfad == null) {
      markTestSkipped('PV_DB / PV_LIB nicht gesetzt');
      return;
    }
    final db = AppDatabase(NativeDatabase(File(dbPfad)));
    addTearDown(db.close);

    late final StoragePaths paths;
    late final List<Rasterzeile> zeilen;
    await tester.runAsync(() async {
      // ignore: invalid_use_of_visible_for_testing_member
      paths = await StoragePaths.forTesting(Directory(libPfad));
      zeilen = await db.watchRasterzeilen().first;
    });
    // ignore: avoid_print
    print('${zeilen.length} Aufnahmen im Raster\n');

    final grenzeMb = int.tryParse(Platform.environment['PV_CACHE_MB'] ?? '');
    if (grenzeMb != null) _speicher.maximumSizeBytes = grenzeMb * 1024 * 1024;
    final grenzeN = int.tryParse(Platform.environment['PV_CACHE_N'] ?? '');
    if (grenzeN != null) _speicher.maximumSize = grenzeN;
    // ignore: avoid_print
    print('Grenze: ${_speicher.maximumSize} Bilder, '
        '${_mb(_speicher.maximumSizeBytes)}\n');

    const fensterBreite = 1600.0;
    const fensterHoehe = 1000.0;
    const schritte = 12;

    for (final dpr in [1.0, 2.0]) {
      for (final form in Zeitleistenform.values) {
        _speicher
          ..clear()
          ..clearLiveImages();
        tester.view.physicalSize =
            const Size(fensterBreite, fensterHoehe) * dpr;
        tester.view.devicePixelRatio = dpr;
        addTearDown(tester.view.reset);

        // Was ueber die Runden hinweg ueberhaupt an Bildern gebaut wird -
        // nicht nur, was am Ende dasteht. Zwischenstaende zaehlen, weil
        // jeder von ihnen einen eigenen Schluessel im Speicher hinterlaesst.
        final gesehenDateien = <String>{};
        final gesehenSchluessel = <String>{};
        void mitschreiben() {
          for (final bild in tester.widgetList<Image>(find.byType(Image))) {
            final p = bild.image;
            if (p is ResizeImage) {
              final f = p.imageProvider;
              if (f is FileImage) {
                gesehenDateien.add(f.file.path);
                gesehenSchluessel.add('${f.file.path}|${p.width}x${p.height}');
              }
            } else if (p is FileImage) {
              gesehenDateien.add(p.file.path);
              gesehenSchluessel.add('${p.file.path}|voll');
            }
          }
        }

        Future<void> ruhen([int runden = 24]) async {
          await tester.runAsync(() async {
            for (var i = 0; i < runden; i++) {
              await Future<void>.delayed(const Duration(milliseconds: 25));
              await tester.pump();
              mitschreiben();
              if (_spur != null) {
                _spur!.add('${_speicher.currentSize}/'
                    '${gesehenSchluessel.length}');
              }
            }
          });
        }

        /// Pumpt, bis sich am Speicher nichts mehr aendert - und sagt, wie
        /// lange das gedauert hat. Eine feste Rundenzahl misst nur sich
        /// selbst; genau das tat der erste Anlauf.
        Future<int> einpendeln() async {
          final uhr = Stopwatch()..start();
          var letzte = -1;
          var ruhig = 0;
          await tester.runAsync(() async {
            for (var i = 0; i < 200 && ruhig < 6; i++) {
              await Future<void>.delayed(const Duration(milliseconds: 16));
              await tester.pump();
              mitschreiben();
              final jetzt = _speicher.currentSizeBytes;
              ruhig = jetzt == letzte ? ruhig + 1 : 0;
              letzte = jetzt;
            }
          });
          uhr.stop();
          return uhr.elapsedMilliseconds - 6 * 16;
        }

        await tester.runAsync(() async {
          await tester.pumpWidget(MaterialApp(
            locale: const Locale('de'),
            localizationsDelegates: AppTexte.localizationsDelegates,
            supportedLocales: AppTexte.supportedLocales,
            theme: buildDarkTheme(),
            home: Scaffold(
              body: MonthGroupedAssetGrid(
                // Ein eigener Schlüssel je Durchgang: Sonst behält das
                // Raster seinen Zustand samt Scrollstelle.
                key: ValueKey('$dpr-${form.name}'),
                assets: zeilen,
                paths: paths,
                onTap: (_) {},
                form: form,
              ),
            ),
          ));
        });
        _spur = <String>[];
        final aufbau = await einpendeln();
        // ignore: avoid_print
        print('  Verlauf (Eintraege/gesehene Schluessel): '
            '${_spur!.take(14).join(' ')} ...');
        _spur = null;
        // ignore: avoid_print
        print('  bis der erste Bildschirm steht: $aufbau ms');
        // Wie hoch ist die Ueberschrift wirklich? Die Rechnung des
        // Zeitstrahls setzt timelineHeaderHeight = 64 an.
        final ersteKachel = find.byType(AssetThumbnailTile).first;
        // ignore: avoid_print
        print('  Ueberschrift misst: '
            '${tester.getTopLeft(ersteKachel).dy.toStringAsFixed(1)} Punkte '
            '(die Rechnung setzt $timelineHeaderHeight an)');

        final ersteBytes = _speicher.currentSizeBytes;
        // Die Schluessel des ersten Bildschirms, aus den gezeichneten
        // Bildern selbst geholt - nicht nachgerechnet. Ein nachgerechneter
        // Schluessel prueft die eigene Rechnung, nicht den Speicher.
        final schluessel = <Object>[];
        await tester.runAsync(() async {
          for (final bild in tester.widgetList<Image>(find.byType(Image))) {
            schluessel.add(
                await bild.image.obtainKey(ImageConfiguration.empty));
          }
        });
        final ersteEintraege = schluessel.length;
        // ignore: avoid_print
        print('== dpr $dpr, ${form.name} ==');
        // ignore: avoid_print
        print('  erster Bildschirm: $ersteEintraege Bilder im Baum, '
            '${_mb(ersteBytes)}, ${_speicher.currentSize} Eintraege');
        // ignore: avoid_print
        print('  dafuer gebaut: ${gesehenDateien.length} Dateien unter '
            '${gesehenSchluessel.length} Schluesseln');

        // Woher kommen die Eintraege, die niemand sieht? Wenn jeder Monat
        // seine erste Reihe baut, muesste das ERSTE FOTO JEDER Gruppe im
        // Speicher liegen - auch das des aeltesten Monats, tausende
        // Punkte unterhalb des Fensters. Der Schluessel dafuer laesst
        // sich ausrechnen: dieselbe Geometrie, die die Kachel benutzt.
        await tester.runAsync(() async {
          final g = monatsgruppen(zeilen);
          const gitter = fensterBreite - 64;
          var drin = 0;
          for (final k in g.schluessel) {
            final gr = g.gruppen[k]!;
            final a = gr.first;
            if (a.thumbnailRelativePath == null) continue;
            double kb, kh;
            if (form == Zeitleistenform.reihen) {
              final r = zeitleisteReihen(gr, gitter).first;
              kb = r.plaetze.first.breite;
              kh = r.hoehe;
            } else {
              kb = kh = timelineRowHeightForWidth(gitter) - 4;
            }
            final m = deckendeDekodiermasse(
                kachelBreite: kb,
                kachelHoehe: kh,
                bildBreite: a.widthPx,
                bildHoehe: a.heightPx,
                pixelverhaeltnis: dpr);
            final prov = ResizeImage.resizeIfNeeded(m.breite, m.hoehe,
                FileImage(paths.absolute(a.thumbnailRelativePath!)));
            if (_speicher
                .containsKey(await prov.obtainKey(ImageConfiguration.empty))) {
              drin++;
            }
          }
          // ignore: avoid_print
          print('  Erstfoto der Monatsgruppen im Speicher: '
              '$drin von ${g.schluessel.length}');
        });

        final lage = tester.state<ScrollableState>(
            find.byType(Scrollable).first).position;

        // Trifft der gerechnete Sprung? Geprueft in der Mitte der
        // Bibliothek - dort haette sich ein Fehler je Monatsgruppe schon
        // aufsummiert, und anders als am Ende klemmt nichts an der
        // Gesamthoehe.
        final gruppen = monatsgruppen(zeilen);
        final mitte = gruppen.schluessel[gruppen.schluessel.length ~/ 2];
        final ziel = gruppen.gruppen[mitte]!.first;
        final gerechnet = timelineOffsetForAsset(
            gruppen.schluessel, gruppen.gruppen, fensterBreite - 64, ziel.id,
            kachelbreite: timelineGridMaxCrossAxisExtent, form: form);
        if (gerechnet != null) {
          // Die Stelle suchen, an der das Foto wirklich steht: erst am
          // gerechneten Punkt nachsehen, dann in Schritten davor. Der
          // Vorlauf muss kleiner als das Fenster bleiben, sonst steht das
          // Foto unterhalb des Randes und ist gar nicht gebaut - daran
          // sind die ersten beiden Anlaeufe gescheitert.
          final treffer = find.byWidgetPredicate((w) =>
              w is AssetThumbnailTile && w.asset.id == ziel.id);
          var gefunden = false;
          for (var vor = 0.0; vor <= 6000 && !gefunden; vor += 300) {
            lage.jumpTo((gerechnet - vor).clamp(0.0, lage.maxScrollExtent));
            await ruhen(6);
            if (treffer.evaluate().isEmpty) continue;
            gefunden = true;
            final dy = tester.getTopLeft(treffer.first).dy;
            // ignore: avoid_print
            print('  Sprung in die Mitte (Gruppe '
                '${gruppen.schluessel.length ~/ 2} von '
                '${gruppen.schluessel.length}): Rechnung liegt '
                '${(vor - dy).round()} Punkte daneben');
          }
          if (!gefunden) {
            // ignore: avoid_print
            print('  Sprung: Foto in 6000 Punkten nicht gefunden');
          }
          lage.jumpTo(0);
          await ruhen(8);
        }

        var voll = -1;
        var verloren = -1;
        final weiten = <int>{};
        for (var s = 1; s <= schritte; s++) {
          lage.jumpTo(
              (s * fensterHoehe).clamp(0.0, lage.maxScrollExtent));
          await ruhen(20);
          weiten.add(lage.maxScrollExtent.round());
          if (voll < 0 &&
              (_speicher.currentSize >= _speicher.maximumSize ||
                  _speicher.currentSizeBytes >=
                      _speicher.maximumSizeBytes * 0.98)) {
            voll = s;
          }
          final leben = schluessel.where(_speicher.containsKey).length;
          if (leben < ersteEintraege && verloren < 0) verloren = s;
          if (s <= 6 || s == schritte) {
            // ignore: avoid_print
            print('  nach $s Bildschirmen: vom ersten noch '
                '$leben von $ersteEintraege');
          }
          if (s % 4 == 0 || s == schritte) {
            // ignore: avoid_print
            print('  nach $s Bildschirmen: ${_speicher.currentSize} Bilder, '
                '${_mb(_speicher.currentSizeBytes)}');
          }
        }
        // ignore: avoid_print
        print('  Speicher voll ab Bildschirm: '
            '${voll < 0 ? 'nie' : voll}');
        // ignore: avoid_print
        print('  Gesamthoehe waehrend des Scrollens: '
            '${weiten.length} verschiedene Werte '
            '(${weiten.reduce((a, b) => a < b ? a : b)}'
            '..${weiten.reduce((a, b) => a > b ? a : b)})');

        // Der eigentliche Befund. Die Zahl der EINTRAEGE zu vergleichen
        // waere die Falle: Ist der Speicher voll, verdraengt jeder neue
        // Eintrag einen alten, und die Summe bleibt gleich - auch wenn
        // jedes Bild neu dekodiert wurde. Gezaehlt wird deshalb, wie
        // viele Schluessel des ersten Bildschirms noch da sind.
        final ueberlebt = schluessel.where(_speicher.containsKey).length;
        // ignore: avoid_print
        print('  belegter Arbeitsspeicher: '
            '${_mb(ProcessInfo.currentRss)}');
        // ignore: avoid_print
        print('  erstes Bild verdraengt ab Bildschirm: '
            '${verloren < 0 ? 'nie' : verloren}'
            ' - am Ende $ueberlebt von $ersteEintraege');
        lage.jumpTo(0);
        final zurueck = await einpendeln();
        // ignore: avoid_print
        print('  zurueck an den Anfang: $zurueck ms bis zur Ruhe\n');
      }
    }
  }, timeout: const Timeout(Duration(minutes: 15)));
}
