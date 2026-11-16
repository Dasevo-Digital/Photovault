/// **Ein Flugstil über echtem Gelände – als Standbilder oder als Video.**
///
/// Kein Teil der Prüfsuite: Holt echte Höhen-, Karten- und Blockkacheln
/// aus dem Netz und geht den Weg, den auch die Videoausgabe der App
/// geht – dieselbe Kamera, dieselben Tafeln, dieselbe Wartezeit auf die
/// scharfen Kacheln vor jedem Bild. Gebaut, um den Stil „Nah dran" am
/// Bild einzustellen statt an Zahlen.
///
/// ```sh
/// PV_SPUR=spur.csv PV_BILDER=~/Desktop/pv_nah \
///   [PV_ORTE=orte.csv] [PV_STIL=nah|ueberblick] [PV_FORMAT=hoch|quer] \
///   [PV_KARTE=luftbild|wanderkarte] [PV_TITEL="Stoos Gratweg"] \
///   [PV_VIDEO=/opt/homebrew/bin/ffmpeg] [PV_BREITE=540] \
///   flutter test tool/flugstil_bilder_test.dart
/// ```
///
/// `spur.csv`: breite,laenge[,hoehe] je Zeile. `orte.csv`:
/// name,breite,laenge[,hoehe] – Gipfel und Hütten, aus denen die Tafeln
/// Start und Ziel nennen. Ohne `PV_VIDEO` entstehen Standbilder im
/// Sekundenabstand, mit `PV_VIDEO` (Pfad zu ffmpeg) ein ganzes Video.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_map/flutter_map.dart' show DisabledMapCachingProvider;
import 'package:flutter_test/flutter_test.dart';
import 'package:gelaende/flugstil.dart';
import 'package:gelaende/flugvideo.dart';
import 'package:gelaende/gelaende.dart';
import 'package:gelaende/gelaende_laden.dart';
import 'package:gelaende/gelaendeflug.dart';
import 'package:gelaende/gelaendekacheln.dart';
import 'package:gelaende/gelaendeschilder.dart';
import 'package:gelaende/gelaendesicht.dart';
import 'package:http/http.dart' as http;
import 'package:kern/services/gelaendeebenen.dart';
import 'package:kern/services/wanderobjekte.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/services/flugvideo.dart' show schreibeFlugvideo;

List<List<String>> _csv(String pfad) => [
  for (final z in File(pfad).readAsLinesSync())
    if (z.trim().isNotEmpty) z.split(','),
];

/// Schreibt Standbilder statt eines Videos – oder reicht an ffmpeg weiter.
class _Pruefschreiber implements Videoschreiber {
  _Pruefschreiber(this.ordner, {this.ffmpeg});

  final Directory ordner;
  final String? ffmpeg;
  final fertig = Completer<Videoergebnis>();

  @override
  Future<bool> moeglich() async => true;

  @override
  Future<Videoergebnis> schreibe({
    required File ziel,
    required int breite,
    required int hoehe,
    required Duration dauer,
    required void Function(ui.Canvas leinwand, ui.Size flaeche, double t)
    maleBild,
    Future<void> Function(double t)? vorBild,
    void Function(double anteil)? fortschritt,
    bool Function()? abbruch,
  }) async {
    final uhr = Stopwatch()..start();
    Videoergebnis ergebnis;
    if (ffmpeg != null) {
      var zuletzt = -1;
      ergebnis = await schreibeFlugvideo(
        ziel: ziel,
        breite: breite,
        hoehe: hoehe,
        dauer: dauer,
        maleBild: maleBild,
        vorBild: vorBild,
        ffmpeg: ffmpeg,
        nativ: false,
        fortschritt: (a) {
          final p = (a * 20).floor();
          if (p != zuletzt) {
            zuletzt = p;
            stdout.writeln(
              '  ${(a * 100).round()} % nach ${uhr.elapsed.inSeconds} s',
            );
          }
        },
      );
    } else {
      final sekunden = dauer.inMilliseconds / 1000;
      final n = sekunden.floor();
      for (var i = 0; i <= n; i++) {
        final t = (i / sekunden).clamp(0.0, 1.0);
        stdout.writeln(
          '  Bild $i/$n (t=${t.toStringAsFixed(3)}) nach ${uhr.elapsed.inSeconds} s',
        );
        await vorBild?.call(t);
        final sammler = ui.PictureRecorder();
        maleBild(
          ui.Canvas(sammler),
          ui.Size(breite.toDouble(), hoehe.toDouble()),
          t,
        );
        final bild = await sammler.endRecording().toImage(breite, hoehe);
        final png = await bild.toByteData(format: ui.ImageByteFormat.png);
        bild.dispose();
        File(
          '${ordner.path}/bild-${i.toString().padLeft(3, '0')}.png',
        ).writeAsBytesSync(png!.buffer.asUint8List());
      }
      ergebnis = (ausgang: Videoausgang.fertig, meldung: null);
    }
    stdout.writeln('fertig nach ${uhr.elapsed.inSeconds} s');
    if (!fertig.isCompleted) fertig.complete(ergebnis);
    return ergebnis;
  }
}

void main() {
  testWidgets('Flugstil über echtem Gelände', (tester) async {
    final env = Platform.environment;
    final spurPfad = env['PV_SPUR'];
    final aus = env['PV_BILDER'];
    if (spurPfad == null || aus == null) {
      markTestSkipped('PV_SPUR und PV_BILDER setzen');
      return;
    }
    final ordner = Directory(aus)..createSync(recursive: true);
    final stil = env['PV_STIL'] == 'ueberblick'
        ? Flugstil.ueberblick
        : Flugstil.nahDran;
    final hoch = (env['PV_FORMAT'] ?? 'hoch') == 'hoch';
    final kurz = int.tryParse(env['PV_BREITE'] ?? '') ?? 540;
    final lang = (kurz * 16 / 9).round() & ~1;
    final (breite, hoehe) = hoch ? (kurz, lang) : (lang, kurz);
    final auflage = Gelaendekarte(
      grund: env['PV_KARTE'] == 'wanderkarte'
          ? Gelaendegrund.wanderkarte
          : Gelaendegrund.luftbild,
    );

    final roh = [
      for (final z in _csv(spurPfad))
        (
          breite: double.parse(z[0]),
          laenge: double.parse(z[1]),
          hoehe: z.length > 2 ? double.tryParse(z[2]) : null,
        ),
    ];
    var sued = 90.0, nord = -90.0, west = 180.0, ost = -180.0;
    for (final p in roh) {
      sued = math.min(sued, p.breite);
      nord = math.max(nord, p.breite);
      west = math.min(west, p.laenge);
      ost = math.max(ost, p.laenge);
    }
    // Derselbe Ausschnitt wie am Bildschirm.
    final ausschnitt = gelaendeAusschnitt(
      sued: sued,
      west: west,
      nord: nord,
      ost: ost,
      stil: stil,
    );
    sued = ausschnitt.sued;
    west = ausschnitt.west;
    nord = ausschnitt.nord;
    ost = ausschnitt.ost;

    // Eine echte Schrift für Schilder und Tafeln – sonst malt
    // `flutter test` jedes Zeichen als Kasten (siehe
    // `gelaende_schaerfe_test.dart`). Und `load()` in `runAsync`.
    await tester.runAsync(() async {
      final schrift = FontLoader('Tafelschrift');
      for (final pfad in const [
        '/System/Library/Fonts/Supplemental/Arial.ttf',
        '/System/Library/Fonts/Supplemental/Arial Bold.ttf',
      ]) {
        final datei = File(pfad);
        if (!datei.existsSync()) continue;
        final bytes = await datei.readAsBytes();
        schrift.addFont(Future.value(ByteData.view(bytes.buffer)));
      }
      await schrift.load();
    });

    tester.view.physicalSize = Size(breite.toDouble(), hoehe.toDouble());
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final vorher = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = vorher);
    final netzKlient = http.Client();
    addTearDown(netzKlient.close);

    Hoehengitter? gitter;
    ui.Image? karte;
    stdout.writeln('lade Höhen und Karte …');
    await tester.runAsync(() async {
      gitter = await ladeHoehengitter(
        sued: sued,
        west: west,
        nord: nord,
        ost: ost,
        netz: netzKlient,
        speicher: const DisabledMapCachingProvider(),
      );
      karte = await ladeKartenbild(
        sued: sued,
        west: west,
        nord: nord,
        ost: ost,
        netz: netzKlient,
        karte: auflage,
        hoehen: gitter,
        speicher: const DisabledMapCachingProvider(),
      );
    });
    final g = gitter;
    if (g == null) {
      markTestSkipped('Keine Höhenkacheln erreichbar');
      return;
    }
    final netz = baueNetz(
      g,
      grundfarbe: karte == null ? gelaendeGrundfarbe : const Color(0xFFFFFFFF),
      ueberhoehung: stil.ueberhoehung,
      kante: stil.gitterkante,
      weich: stil.weicheSchattierung,
    );
    Raumpunkt imNetz(double b, double l, double h) => (
      x: ((l - g.west) / (g.ost - g.west) - 0.5) * netz.breiteMeter,
      y: (0.5 - (g.nord - b) / (g.nord - g.sued)) * netz.hoeheMeter,
      z: (h - netz.mittlereHoehe) * netz.ueberhoehung,
    );

    final start = DateTime.utc(2026, 8, 30, 9);
    final linie = <Raumpunkt>[];
    final werte = <Flugwert>[];
    for (final (i, p) in roh.indexed) {
      final boden = g.anOrt(p.breite, p.laenge);
      final gemessen = p.hoehe ?? boden;
      final gezeichnet = stil.spurAufDemGelaende ? boden : gemessen;
      if (gezeichnet == null) continue;
      linie.add(imNetz(p.breite, p.laenge, gezeichnet + 2));
      werte.add((hoehe: gemessen, zeit: start.add(Duration(seconds: i * 14))));
    }

    final schilder = <Gelaendeschild>[];
    final ortePfad = env['PV_ORTE'];
    if (ortePfad != null) {
      for (final z in _csv(ortePfad)) {
        final b = double.parse(z[1]), l = double.parse(z[2]);
        final h = g.anOrt(b, l);
        if (h == null) continue;
        final ele = z.length > 3 ? z[3] : null;
        schilder.add(
          Gelaendeschild(
            art: Wanderart.gipfel,
            name: z[0],
            beschriftung: ele == null ? z[0] : '${z[0]}  $ele m',
            ort: imNetz(b, l, h + schildHoeheMeter),
          ),
        );
      }
    }

    // Ein Foto zum Ansehen der Fototafel: PV_FOTO=bild.jpg, an der
    // Stelle PV_FOTO_BEI (Anteil der Strecke, Vorgabe 0,75).
    final fotos = <Flugfoto>[];
    final fotoPfad = env['PV_FOTO'];
    if (fotoPfad != null) {
      final anteil = double.tryParse(env['PV_FOTO_BEI'] ?? '') ?? 0.75;
      fotos.add((
        meter: Gelaendeflug(linie).laengeMeter * anteil,
        bild: FileImage(File(fotoPfad)),
        unterschrift: '11:42',
      ));
    }

    final schreiber = _Pruefschreiber(ordner, ffmpeg: env['PV_VIDEO']);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        locale: const Locale('de'),
        home: Scaffold(
          body: Gelaendeansicht(
            netz: netz,
            spur: linie,
            spurwerte: werte,
            karte: karte,
            auflage: auflage,
            hoehen: g,
            schilder: schilder,
            fotos: fotos,
            stil: stil,
            titel: env['PV_TITEL'] ?? 'Stoos Gratweg',
            schriftart: 'Tafelschrift',
            namensnennung: '3D-Ansicht · ${auflage.nennung}',
            netzKlient: netzKlient,
            videoschreiber: schreiber,
            beimVideoZiel: (vorgabe) async => (
              ziel: File('${ordner.path}/flug.mp4'),
              breite: breite,
              hoehe: hoehe,
              dauer: vorgabe,
            ),
            beiVideoFertig: (_) async {},
            melde: (text, {warnung = false}) => stdout.writeln(text),
          ),
        ),
      ),
    );
    await tester.pump();
    final leiste = tester.widget<Flugleiste>(find.byType(Flugleiste));
    stdout.writeln(
      '${stil.name}, ${breite}x$hoehe, '
      '${(Gelaendeflug(linie).laengeMeter / 1000).toStringAsFixed(1)} km, '
      '${schilder.length} Namen',
    );
    stdout.writeln('starte Ausgabe …');
    // **Alles in echter Zeit, und gefragt wird reihum.** Die Ausgabe
    // läuft in `runAsync` durch, aber ein `await` auf ihr Ende kehrte
    // dort nie zurück; also wird nachgesehen, ob sie fertig ist. Ausserhalb
    // von `runAsync` bliebe sie am ersten Bild hängen – sie wartet auf
    // Uhren, die in der gestellten Zeit nicht laufen.
    await tester.runAsync(() async {
      leiste.beimAusgeben!();
      while (!schreiber.fertig.isCompleted) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    });
    final e = await schreiber.fertig.future;
    stdout.writeln('${e.ausgang} ${e.meldung ?? ''}');
    await tester.pump();
    karte?.dispose();
    stdout.writeln('Ausgabe in ${ordner.path}');
  }, timeout: const Timeout(Duration(minutes: 40)));
}
