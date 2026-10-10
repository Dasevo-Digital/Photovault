// ignore_for_file: avoid_print
// **Abnahme im Zielprozess: was 3.25.0 und 3.26.0 neu mitbrachten.**
//
// Die Unittests dieser Funktionen laufen gegen Attrappen: kein Modell,
// kein Kodierer, keine Texterkennung. Genau dort lagen aber die Fehler,
// die erst bei Nutzern auffielen – ein fp16-Modell, das die mitgelieferte
// ONNX Runtime nicht öffnete, eine Videoausgabe, die im Sandkasten kein
// ffmpeg starten durfte. Hier läuft deshalb jede Funktion einmal durch
// die echten Teile, im eingesperrten Testbau:
//
//   * #66 Einfärben – DDColor, wie es der Katalog ausliefert.
//   * #64/#77 Diashow mit Musik – der echte Kodierer, und eine Musik, die
//     kürzer ist als das Video und deshalb wiederholt werden muss.
//   * #75 Videobild als Foto – das Bild an der richtigen Stelle, in der
//     vollen Grösse des Films.
//   * #74 Ausweise – die echte Texterkennung (macOS: Vision, sonst
//     PaddleOCR) auf gezeichneten Mustern, dazu eine Gegenprobe.
//   * #76 Datierung – CLIP der App auf Fotos und ihren gealterten
//     Fassungen; zu vergleichen mit der Python-Probe, aus der die Sätze
//     stammen (Mittel 2005).
//
// Fehlt ein Modell, wird der Teil übersprungen und das gesagt. Stimmt
// seine Grösse nicht mit dem Katalog, schlägt er fehl: Dann prüfte er ein
// anderes Modell als das ausgelieferte.
//
//   PV_MODELLE=<Modellordner> PV_ABNAHME=<Ordner mit Fotos> \
//   flutter test integration_test/abnahme_test.dart -d macos
//
// PV_MODELLE fehlt → der Modellordner des Testbaus. PV_ABNAHME fehlt →
// Einfärben nur am mitgelieferten Bild, Datierung entfällt. Die
// Ergebnisse (Bilder, Videos) landen in PV_ABNAHME_AUS oder im Ordner
// `abnahme` neben den Modellen des Testbaus.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:photo_vault/services/clip_service.dart';
import 'package:photo_vault/services/datierung.dart';
import 'package:photo_vault/services/diashow.dart';
import 'package:photo_vault/services/dokumenterkennung.dart';
import 'package:photo_vault/services/flugvideo.dart';
import 'package:photo_vault/services/kolorieren.dart';
import 'package:photo_vault/services/model_catalog.dart';
import 'package:photo_vault/services/native_image_converter.dart';
import 'package:photo_vault/services/ocr_service.dart';
import 'package:photo_vault/services/textstellen.dart';
import 'package:photo_vault/services/tonspur.dart';
import 'package:photo_vault/theme/zierbaum_farben.dart' show zierschrift;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late String modelle;
  late Directory aus;
  final eingang = Platform.environment['PV_ABNAHME'];
  late Directory arbeit;

  setUpAll(() async {
    final support = await getApplicationSupportDirectory();
    modelle =
        Platform.environment['PV_MODELLE'] ??
        p.join(support.path, 'PhotoVault', 'models');
    aus = Directory(
      Platform.environment['PV_ABNAHME_AUS'] ?? p.join(support.path, 'abnahme'),
    )..createSync(recursive: true);
    arbeit = Directory.systemTemp.createTempSync('pv_abnahme_');
    print(
      'Modelle: $modelle\nEingang: ${eingang ?? '-'}\nAusgang: ${aus.path}',
    );
  });
  tearDownAll(() {
    if (arbeit.existsSync()) arbeit.deleteSync(recursive: true);
  });

  /// Ob alle Dateien von [eintrag] da sind – und genau die ausgelieferten.
  bool vorhanden(ModelCatalogEntry eintrag) {
    for (final f in eintrag.files) {
      final datei = File(p.join(modelle, f.fileName));
      if (!datei.existsSync()) {
        markTestSkipped('${f.fileName} fehlt in $modelle');
        return false;
      }
      expect(
        datei.lengthSync(),
        f.bytes,
        reason: '${f.fileName} ist nicht die ausgelieferte Datei',
      );
    }
    return true;
  }

  /// Die Fotos aus PV_ABNAHME, sortiert wie in der Python-Probe.
  List<File> fotos() {
    if (eingang == null) return const [];
    final liste =
        Directory(eingang)
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.toLowerCase().endsWith('.jpg'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    return liste;
  }

  Future<img.Image> asset(String name) async {
    final daten = await rootBundle.load(name);
    return img.decodeImage(daten.buffer.asUint8List())!;
  }

  // ---------------------------------------------------------------- #66
  testWidgets('#66 Einfärben: DDColor gibt einem Graubild Farbe', (
    tester,
  ) async {
    if (!vorhanden(ModelCatalog.kolorieren)) return;
    final vorlagen = <String, img.Image>{
      'landschaft': await asset('assets/lebensbaum/landschaft_leer.jpg'),
      for (final f in fotos().take(3))
        p.basenameWithoutExtension(f.path): img.copyResize(
          img.decodeImage(f.readAsBytesSync())!,
          width: 1600,
        ),
    };
    final dienst = await KolorierService.load(modelle);
    try {
      for (final MapEntry(key: name, value: farbig) in vorlagen.entries) {
        final grau = img.grayscale(img.Image.from(farbig));
        final uhr = Stopwatch()..start();
        final ergebnis = await dienst.faerbe(grau);
        uhr.stop();

        expect(ergebnis.width, grau.width);
        expect(ergebnis.height, grau.height);
        final satt = _saettigung(ergebnis);
        final helligkeit = _helligkeitsabstand(grau, ergebnis);
        print(
          '#66 $name: ${grau.width}x${grau.height} in '
          '${uhr.elapsedMilliseconds} ms, Sättigung '
          'Original ${_saettigung(farbig).toStringAsFixed(3)} / '
          'grau ${_saettigung(grau).toStringAsFixed(3)} / '
          'eingefärbt ${satt.toStringAsFixed(3)}, '
          'Helligkeit weicht im Mittel um ${helligkeit.toStringAsFixed(1)} ab',
        );
        expect(satt, greaterThan(0.08), reason: 'kaum Farbe hinzugekommen');
        expect(
          helligkeit,
          lessThan(8),
          reason: 'die Helligkeit soll aus dem Original kommen',
        );
        final nebeneinander = img.Image(
          width: grau.width * 2,
          height: grau.height,
        );
        img.compositeImage(nebeneinander, grau);
        img.compositeImage(nebeneinander, ergebnis, dstX: grau.width);
        File(
          p.join(aus.path, 'einfaerben_$name.jpg'),
        ).writeAsBytesSync(img.encodeJpg(nebeneinander, quality: 85));
      }
    } finally {
      await dienst.dispose();
    }
  });

  // ------------------------------------------------------------ #64/#77
  testWidgets('#64/#77 Diashow mit Musik über den echten Kodierer', (
    tester,
  ) async {
    final dateien = <File>[];
    // Echte Fotos, wenn es welche gibt – hoch und quer gemischt.
    dateien.addAll(fotos().take(3));
    for (final name in ['landschaft', 'pergament', 'gold_leer']) {
      if (dateien.length >= 3) break;
      final daten = await rootBundle.load('assets/lebensbaum/$name.jpg');
      dateien.add(
        File(p.join(arbeit.path, '$name.jpg'))
          ..writeAsBytesSync(daten.buffer.asUint8List()),
      );
    }
    // Sechs Sekunden Ton unter dreizehn Sekunden Bild: Die Musik muss
    // zweimal neu anfangen.
    final musik = File(p.join(arbeit.path, 'ton.wav'))
      ..writeAsBytesSync(_wav(const Duration(seconds: 6)));
    final stumm = File(p.join(arbeit.path, 'stumm.mp4'));
    final ziel = File(p.join(aus.path, 'diashow_mit_musik.mp4'));
    if (ziel.existsSync()) ziel.deleteSync();

    late Videoergebnis bild, ton;
    final uhr = Stopwatch()..start();
    await tester.runAsync(() async {
      bild = await schreibeDiashow(
        ziel: stumm,
        dateien: dateien,
        titel: 'Venedig',
        untertitel: '14.–16. Mai 2026',
        schrift: zierschrift,
      );
    });
    final bildZeit = uhr.elapsedMilliseconds;
    expect(bild.ausgang, Videoausgang.fertig, reason: '${bild.meldung}');
    await tester.runAsync(() async {
      ton = await unterlegeMusik(
        video: stumm,
        musik: musik,
        ziel: ziel,
        dauer: diashowDauer(dateien.length),
      );
    });
    uhr.stop();
    expect(ton.ausgang, Videoausgang.fertig, reason: '${ton.meldung}');
    final gelesen = await tester.runAsync(
      () => NativeImageConverter.generateVideoThumbnail(ziel),
    );
    print(
      '#64/#77 Diashow ${(bildZeit / 1000).toStringAsFixed(1)} s, mit Ton '
      '${(uhr.elapsedMilliseconds / 1000).toStringAsFixed(1)} s, '
      '${(ziel.lengthSync() / 1024).round()} kB, '
      'Dauer laut System ${gelesen?.durationSeconds?.toStringAsFixed(2)} s '
      '(erwartet ${diashowDauer(dateien.length).inMilliseconds / 1000} s)',
    );
    expect(gelesen, isNotNull, reason: 'das System kann die Datei nicht lesen');
    expect(
      gelesen!.durationSeconds,
      closeTo(diashowDauer(dateien.length).inMilliseconds / 1000, 0.3),
    );
  });

  // ---------------------------------------------------------------- #75
  testWidgets('#75 Videobild: richtige Stelle, volle Grösse', (tester) async {
    final film = File(p.join(arbeit.path, 'drittel.mp4'));
    const farben = [Color(0xFFD02020), Color(0xFF20B020), Color(0xFF2040D0)];
    late Videoergebnis ergebnis;
    await tester.runAsync(() async {
      ergebnis = await schreibeFlugvideo(
        ziel: film,
        breite: 1920,
        hoehe: 1080,
        dauer: const Duration(seconds: 3),
        maleBild: (leinwand, flaeche, t) {
          final farbe = farben[math.min(2, (t * 3).floor())];
          leinwand.drawRect(Offset.zero & flaeche, Paint()..color = farbe);
          // Kanten, damit der Kodierer etwas zu tun hat und ein
          // verwaschenes Standbild auffiele.
          for (var x = 0.0; x < flaeche.width; x += 120) {
            leinwand.drawLine(
              Offset(x, 0),
              Offset(x, flaeche.height),
              Paint()
                ..color = Colors.white
                ..strokeWidth = 2,
            );
          }
        },
      );
    });
    expect(
      ergebnis.ausgang,
      Videoausgang.fertig,
      reason: '${ergebnis.meldung}',
    );

    for (final (anteil, erwartet) in [(0.17, 0), (0.5, 1), (0.83, 2)]) {
      final gut = await tester.runAsync(
        () => NativeImageConverter.generateVideoThumbnail(
          film,
          maxDimension: 8192,
          anteil: anteil,
          hoheQualitaet: true,
        ),
      );
      final schnell = await tester.runAsync(
        () => NativeImageConverter.generateVideoThumbnail(
          film,
          maxDimension: 8192,
          anteil: anteil,
        ),
      );
      expect(gut, isNotNull);
      final bild = img.decodeJpg(gut!.jpegBytes)!;
      final mitte = bild.getPixel(bild.width ~/ 2 + 60, bild.height ~/ 2);
      final kanaele = [mitte.r, mitte.g, mitte.b];
      final staerkster = kanaele.indexOf(kanaele.reduce(math.max));
      print(
        '#75 bei ${(anteil * 100).round()} %: ${bild.width}x${bild.height}, '
        'Mitte $kanaele, hohe Qualität ${(gut.jpegBytes.length / 1024).round()} kB '
        'gegen ${((schnell?.jpegBytes.length ?? 0) / 1024).round()} kB',
      );
      expect(bild.width, 1920, reason: 'nicht in voller Grösse');
      expect(bild.height, 1080);
      expect(staerkster, erwartet, reason: 'Bild von der falschen Stelle');
    }
  });

  // ---------------------------------------------------------------- #74
  //
  // Unter macOS liest die App mit Vision, sonst mit PaddleOCR. Auf dem Mac
  // läuft hier beides, sofern die Paddle-Modelle da sind – so prüft schon
  // der Mac den Weg von Linux und Windows mit. Die Karte liegt 2,5° schräg:
  // Achsenparallel ausgeschnitten, las PaddleOCR daraus nur Kauderwelsch.
  testWidgets('#74 Ausweise: echte Texterkennung, dann die Prüfung', (
    tester,
  ) async {
    final mitPaddle = !Platform.isMacOS || OcrService.isAvailable(modelle);
    if (!Platform.isMacOS && !vorhanden(ModelCatalog.ocrPaddle)) return;
    final paddle = mitPaddle ? await OcrService.load(modelle) : null;
    final leser = <String, Future<List<Textstelle>?> Function(File)>{
      if (Platform.isMacOS) 'Vision': NativeImageConverter.recognizeText,
      if (paddle != null)
        'PaddleOCR': (datei) =>
            paddle.erkenne(img.decodeJpg(datei.readAsBytesSync())!),
    };
    final faelle = <String, (Dokumentart?, Dokumentgrund?, _Szene)>{
      'ausweis_rueckseite': (
        Dokumentart.ausweis,
        Dokumentgrund.pruefzeile,
        _ausweisRueckseite,
      ),
      'ausweis_vorderseite': (
        Dokumentart.ausweis,
        Dokumentgrund.schluesselwort,
        _ausweisVorderseite,
      ),
      'reisepass': (
        Dokumentart.reisepass,
        Dokumentgrund.pruefzeile,
        _reisepass,
      ),
      'karte': (Dokumentart.karte, Dokumentgrund.kartennummer, _karte),
      'plakat_gegenprobe': (null, null, _plakat),
    };
    final fehler = <String>[];
    try {
      for (final MapEntry(key: name, value: (art, grund, szene))
          in faelle.entries) {
        late img.Image bild;
        await tester.runAsync(() async => bild = await _fotografiere(szene));
        // Als JPEG wie aus dem Telefon, und genau diese Datei wird gelesen.
        final datei = File(p.join(aus.path, 'dokument_$name.jpg'))
          ..writeAsBytesSync(img.encodeJpg(bild, quality: 82));
        for (final MapEntry(key: wer, value: lies) in leser.entries) {
          List<Textstelle>? stellen;
          await tester.runAsync(() async => stellen = await lies(datei));
          final text = textAusStellen(stellen ?? const []);
          final fund = dokumentImText(text);
          print(
            '#74 $wer $name: ${fund?.art.name ?? 'nichts'} '
            '(${fund?.grund.name ?? '-'}), erwartet ${art?.name ?? 'nichts'}\n'
            '    gelesen: ${text.replaceAll('\n', ' | ')}',
          );
          if (fund?.art != art || fund?.grund != grund) {
            fehler.add('$wer $name: ${fund?.art.name} statt ${art?.name}');
          }
        }
      }
    } finally {
      await paddle?.dispose();
    }
    expect(fehler, isEmpty);
  });

  // ---------------------------------------------------------------- #76
  testWidgets(
    '#76 Datierung: CLIP der App auf Fotos und gealterten Fassungen',
    (tester) async {
      final liste = fotos().take(24).toList();
      if (liste.isEmpty) {
        markTestSkipped('PV_ABNAHME fehlt – keine Fotos zum Datieren');
        return;
      }
      if (!vorhanden(ModelCatalog.clip)) return;
      final clip = await ClipService.load(modelle, bild: true, text: true);
      try {
        final saetze = <int, Float32List>{
          for (final j in datierungJahrzehnte)
            j: mittlererVektor([
              for (final satz in datierungsSaetze(j))
                await clip.embedText(satz),
            ]),
        };
        final farbig = <int>[], alt = <int>[];
        var belastbar = 0;
        for (final f in liste) {
          final bild = img.decodeImage(f.readAsBytesSync())!;
          final klein = img.copyResize(
            bild,
            width: bild.width >= bild.height ? 800 : null,
            height: bild.width < bild.height ? 800 : null,
          );
          final a = schaetzeDatierung(await clip.embedImage(klein), saetze);
          final b = schaetzeDatierung(
            await clip.embedImage(_altern(klein)),
            saetze,
          );
          // Verglichen wird das Mittel über die ganze Verteilung – das hat
          // die Python-Probe gemessen. Angezeigt wird das Mittel in der
          // Spanne, und das muss in ihr liegen.
          farbig.add(_vollesMittel(a));
          alt.add(_vollesMittel(b));
          expect(a.jahr, inInclusiveRange(a.von, a.bis));
          if (a.belastbar) belastbar++;
          print(
            '#76 ${p.basename(f.path).padRight(40).substring(0, 40)} '
            'farbig ${a.jahr} (${a.von}–${a.bis}) '
            'gealtert ${b.jahr} (${b.von}–${b.bis})',
          );
        }
        double mittel(List<int> l) => l.reduce((x, y) => x + y) / l.length;
        print(
          '#76 Mittel farbig ${mittel(farbig).round()}, gealtert '
          '${mittel(alt).round()}, belastbar $belastbar von ${liste.length}',
        );
        // Die Python-Probe mit denselben Sätzen ergab 2005. Weicht die App
        // deutlich ab, rechnet sie anders vor als die Probe.
        expect(mittel(farbig), inInclusiveRange(1998, 2012));
        expect(mittel(alt), lessThan(mittel(farbig) - 10));
      } finally {
        await clip.dispose();
      }
    },
  );
}

// ------------------------------------------------------------ Hilfsteile

int _vollesMittel(Datierung d) =>
    d.verteilung.entries.fold(0.0, (s, e) => s + e.value * (e.key + 5)).round();

double _saettigung(img.Image bild) {
  var summe = 0.0;
  var n = 0;
  for (var y = 0; y < bild.height; y += 4) {
    for (var x = 0; x < bild.width; x += 4) {
      final q = bild.getPixel(x, y);
      final hoch = math.max(q.r, math.max(q.g, q.b)).toDouble();
      final tief = math.min(q.r, math.min(q.g, q.b)).toDouble();
      summe += hoch == 0 ? 0 : (hoch - tief) / hoch;
      n++;
    }
  }
  return summe / n;
}

double _helligkeitsabstand(img.Image a, img.Image b) {
  var summe = 0.0;
  var n = 0;
  for (var y = 0; y < a.height; y += 4) {
    for (var x = 0; x < a.width; x += 4) {
      final p = a.getPixel(x, y), q = b.getPixel(x, y);
      final la = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
      final lb = 0.299 * q.r + 0.587 * q.g + 0.114 * q.b;
      summe += (la - lb).abs();
      n++;
    }
  }
  return summe / n;
}

/// Wie die Python-Probe: grau, flacher, weicher, sepia.
img.Image _altern(img.Image bild) {
  final grau = img.grayscale(img.Image.from(bild));
  img.adjustColor(grau, contrast: 0.75);
  final weich = img.gaussianBlur(grau, radius: 1);
  for (final q in weich) {
    final l = q.r / 255;
    q
      ..r = 40 + (240 - 40) * l
      ..g = 26 + (220 - 26) * l
      ..b = 13 + (180 - 13) * l;
  }
  return weich;
}

/// Ein Ton von 440 Hz als WAV, 44,1 kHz, 16 Bit, stereo.
Uint8List _wav(Duration dauer) {
  const rate = 44100;
  final n = rate * dauer.inMilliseconds ~/ 1000;
  final daten = ByteData(44 + n * 4);
  void kette(int at, String s) {
    for (var i = 0; i < 4; i++) {
      daten.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  kette(0, 'RIFF');
  daten.setUint32(4, 36 + n * 4, Endian.little);
  kette(8, 'WAVE');
  kette(12, 'fmt ');
  daten
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little)
    ..setUint16(22, 2, Endian.little)
    ..setUint32(24, rate, Endian.little)
    ..setUint32(28, rate * 4, Endian.little)
    ..setUint16(32, 4, Endian.little)
    ..setUint16(34, 16, Endian.little);
  kette(36, 'data');
  daten.setUint32(40, n * 4, Endian.little);
  for (var i = 0; i < n; i++) {
    final w = (math.sin(2 * math.pi * 440 * i / rate) * 9000).round();
    daten
      ..setInt16(44 + i * 4, w, Endian.little)
      ..setInt16(46 + i * 4, w, Endian.little);
  }
  return daten.buffer.asUint8List();
}

// ------------------------------------------------- Gezeichnete Dokumente
//
// Die Muster sind die öffentlichen Beispiele: Erika Mustermann aus den
// Unterlagen zum deutschen Personalausweis, Anna Maria Eriksson aus
// ICAO 9303, die Kartennummer ist die bekannte Testnummer. Die Gegenprobe
// trägt eine IBAN in Vierergruppen – solche Zahlen stehen auf jedem
// Spendenaufruf.

typedef _Szene = void Function(Canvas leinwand, Size karte);

/// Ein Foto von 3000 × 2000 auf einer Tischplatte, die Karte leicht
/// gedreht – so, wie man einen Ausweis mit dem Telefon aufnimmt.
Future<img.Image> _fotografiere(_Szene szene) async {
  const b = 3000, h = 2000;
  const karte = Size(2000, 1262);
  final rekorder = ui.PictureRecorder();
  final leinwand = Canvas(rekorder);
  leinwand.drawRect(
    const Rect.fromLTWH(0, 0, 3000, 2000),
    Paint()
      ..shader = ui.Gradient.linear(Offset.zero, const Offset(3000, 2000), [
        const Color(0xFF6B4A2E),
        const Color(0xFF8A6542),
      ]),
  );
  leinwand
    ..save()
    ..translate(b / 2, h / 2)
    ..rotate(-2.5 * math.pi / 180)
    ..translate(-karte.width / 2, -karte.height / 2);
  final rund = RRect.fromRectAndRadius(
    Offset.zero & karte,
    const Radius.circular(60),
  );
  leinwand
    ..drawRRect(
      rund.shift(const Offset(12, 16)),
      Paint()..color = const Color(0x55000000),
    )
    ..clipRRect(rund);
  szene(leinwand, karte);
  leinwand.restore();
  final bild = await rekorder.endRecording().toImage(b, h);
  final roh = (await bild.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  bild.dispose();
  return img.Image.fromBytes(
    width: b,
    height: h,
    bytes: roh.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
}

void _schreibe(
  Canvas leinwand,
  String text,
  Offset wo,
  double groesse, {
  bool mono = false,
  FontWeight gewicht = FontWeight.w500,
  Color farbe = const Color(0xFF1C1C24),
}) {
  final maler = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontSize: groesse,
        color: farbe,
        fontWeight: gewicht,
        fontFamily: mono ? 'Courier New' : 'Helvetica',
        fontFamilyFallback: mono
            ? const ['Courier', 'Menlo', 'DejaVu Sans Mono', 'Consolas']
            : const ['Arial', 'DejaVu Sans', 'Segoe UI'],
        letterSpacing: mono ? groesse * 0.08 : 0,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  maler.paint(leinwand, wo);
  maler.dispose();
}

void _grund(Canvas leinwand, Size karte, List<Color> farben) {
  leinwand.drawRect(
    Offset.zero & karte,
    Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        Offset(karte.width, karte.height),
        farben,
      ),
  );
  // Ein feines Guillochen-Muster, wie es auf Ausweisen liegt.
  final linie = Paint()
    ..color = const Color(0x22305070)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;
  for (var i = 0; i < 18; i++) {
    final pfad = Path()..moveTo(0, 80.0 + i * 70);
    for (var x = 0.0; x <= karte.width; x += 40) {
      pfad.lineTo(x, 80 + i * 70 + 25 * math.sin(x / 90 + i));
    }
    leinwand.drawPath(pfad, linie);
  }
}

void _ausweisVorderseite(Canvas l, Size k) {
  _grund(l, k, const [Color(0xFFE4EEF0), Color(0xFFD9E6DA)]);
  _schreibe(
    l,
    'BUNDESREPUBLIK DEUTSCHLAND',
    const Offset(560, 60),
    64,
    gewicht: FontWeight.w700,
  );
  _schreibe(l, 'FEDERAL REPUBLIC OF GERMANY', const Offset(560, 140), 42);
  _schreibe(
    l,
    'PERSONALAUSWEIS',
    const Offset(560, 220),
    70,
    gewicht: FontWeight.w700,
  );
  _schreibe(
    l,
    'IDENTITY CARD  ·  CARTE D\'IDENTITÉ',
    const Offset(560, 310),
    42,
  );
  l.drawRect(
    const Rect.fromLTWH(70, 300, 430, 560),
    Paint()..color = const Color(0xFFB8C0C4),
  );
  _schreibe(l, 'Name / Surname', const Offset(560, 440), 36);
  _schreibe(
    l,
    'MUSTERMANN',
    const Offset(560, 490),
    64,
    gewicht: FontWeight.w700,
  );
  _schreibe(l, 'Vornamen / Given names', const Offset(560, 600), 36);
  _schreibe(l, 'ERIKA', const Offset(560, 650), 64, gewicht: FontWeight.w700);
  _schreibe(l, 'Geburtstag / Date of birth', const Offset(560, 760), 36);
  _schreibe(l, '12.08.1964', const Offset(560, 810), 60);
  _schreibe(l, 'T22000129', const Offset(1500, 1120), 60, mono: true);
}

void _ausweisRueckseite(Canvas l, Size k) {
  _grund(l, k, const [Color(0xFFE6ECEF), Color(0xFFDDE5E0)]);
  _schreibe(l, 'Anschrift / Address', const Offset(80, 80), 36);
  _schreibe(l, '51147 KÖLN, HEIDESTRASSE 17', const Offset(80, 130), 54);
  _schreibe(l, 'Augenfarbe GRÜN   Größe 160 cm', const Offset(80, 230), 44);
  l.drawRect(
    const Rect.fromLTWH(0, 760, 2000, 502),
    Paint()..color = const Color(0xFFF4F4EE),
  );
  const zone = [
    'IDD<<T220001293<<<<<<<<<<<<<<<',
    '6408125<2010315D<<<<<<<<<<<<<4',
    'MUSTERMANN<<ERIKA<<<<<<<<<<<<<',
  ];
  for (var i = 0; i < zone.length; i++) {
    _schreibe(l, zone[i], Offset(70, 800 + i * 140.0), 92, mono: true);
  }
}

void _reisepass(Canvas l, Size k) {
  _grund(l, k, const [Color(0xFFF1E9DE), Color(0xFFE6DCCC)]);
  _schreibe(l, 'PASSPORT', const Offset(560, 60), 64, gewicht: FontWeight.w700);
  _schreibe(l, 'Utopia', const Offset(560, 150), 44);
  l.drawRect(
    const Rect.fromLTWH(70, 120, 430, 560),
    Paint()..color = const Color(0xFFC0B8A8),
  );
  _schreibe(
    l,
    'ERIKSSON',
    const Offset(560, 300),
    60,
    gewicht: FontWeight.w700,
  );
  _schreibe(l, 'ANNA MARIA', const Offset(560, 400), 60);
  _schreibe(l, '12 AUG 1974', const Offset(560, 520), 52);
  const zone = [
    'P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<',
    'L898902C36UTO7408122F1204159ZE184226B<<<<<10',
  ];
  for (var i = 0; i < zone.length; i++) {
    _schreibe(l, zone[i], Offset(40, 930 + i * 140.0), 64, mono: true);
  }
}

void _karte(Canvas l, Size k) {
  _grund(l, k, const [Color(0xFF15305A), Color(0xFF2B4F86)]);
  l.drawRRect(
    RRect.fromRectAndRadius(
      const Rect.fromLTWH(180, 380, 260, 200),
      const Radius.circular(24),
    ),
    Paint()..color = const Color(0xFFD8B860),
  );
  const weiss = Color(0xFFF2F2F2);
  _schreibe(
    l,
    '4111 1111 1111 1111',
    const Offset(180, 700),
    120,
    mono: true,
    farbe: weiss,
  );
  _schreibe(
    l,
    'GÜLTIG BIS 12/29',
    const Offset(900, 880),
    54,
    mono: true,
    farbe: weiss,
  );
  _schreibe(
    l,
    'ERIKA MUSTERMANN',
    const Offset(180, 1020),
    74,
    mono: true,
    farbe: weiss,
  );
}

void _plakat(Canvas l, Size k) {
  _grund(l, k, const [Color(0xFFFFF3C8), Color(0xFFFFE08A)]);
  _schreibe(
    l,
    'SOMMERFEST 2026',
    const Offset(160, 100),
    140,
    gewicht: FontWeight.w800,
  );
  _schreibe(l, 'Samstag, 12.07. ab 14 Uhr', const Offset(160, 330), 80);
  _schreibe(
    l,
    'Eintritt frei – Spenden willkommen',
    const Offset(160, 480),
    70,
  );
  _schreibe(l, 'Spendenkonto', const Offset(160, 700), 60);
  _schreibe(
    l,
    'DE89 3704 0044 0532 0130 00',
    const Offset(160, 790),
    92,
    mono: true,
  );
  _schreibe(l, 'Kartenvorverkauf 0511 2345 6789', const Offset(160, 1000), 64);
}
