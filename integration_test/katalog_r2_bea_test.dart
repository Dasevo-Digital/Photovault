// ignore_for_file: avoid_print, implementation_imports
// Zweite Prüfrunde, Bereiche BEA und PER (Prüfer r2-bea): Einträge, die in
// der ersten Runde `teilweise` oder `ungeprueft` blieben, hier mit den
// neuen Mitteln nachgeholt – echte Porträts für die Gesichtssuche,
// Bildauswertung der ausgegebenen Videos (Standbilder über den nativen
// Wandler, Texterkennung über Vision), Text aus den PDF-Dateien (über die
// ToUnicode-Tabellen der Schriften) und ein eigener Wegwerf-Server, den die
// Prüfung mitten im Lauf anhalten kann.
//
// Die Hilfen der ersten Runde kommen aus katalog_bea_test.dart (`bea.`)
// und katalog_per_test.dart (`per.`).
//
// Laufen lassen nur über die Warteschlange des Prüfkatalogs. Die
// Prüfungen „Mitserver“ brauchen den Wegwerf-Server r2bea (Port 18875)
// und seine Steuerung (127.0.0.1:18879, siehe
// pruefkatalog/arbeit/r2-bea/serversteuer_r2bea.py); die Adresse kommt
// über `--dart-define=PV_KATALOG_SERVER=http://127.0.0.1:18875`.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:kern/db/database.dart';
import 'package:kern/services/asset_display_path.dart' show lesbarerPfad;
import 'package:kern/services/exif_camera.dart' show CameraInfo;
import 'package:kern/services/stammbaum.dart' show Verwandtschaft;
import 'package:kern/services/textstellen.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/screens/asset_viewer_screen.dart';
import 'package:photo_vault/screens/develop_screen.dart';
import 'package:photo_vault/screens/erinnerungen_screen.dart';
import 'package:photo_vault/screens/face_review_screen.dart';
import 'package:photo_vault/screens/home_shell.dart' show HomeShell;
import 'package:photo_vault/screens/image_editor_screen.dart';
import 'package:photo_vault/screens/person_detail_screen.dart';
import 'package:photo_vault/screens/person_suggestions_screen.dart';
import 'package:photo_vault/screens/video_trim_screen.dart';
import 'package:photo_vault/services/export_service.dart';
import 'package:photo_vault/services/fotobuch.dart' show Fotobuchformat;
import 'package:photo_vault/services/inpainting_service.dart';
import 'package:photo_vault/services/meldungsdienst.dart';
import 'package:photo_vault/services/native_image_converter.dart';
import 'package:photo_vault/services/secure_share_service.dart';
import 'package:photo_vault/services/tonspur.dart' show tonEndungen;
import 'package:photo_vault/widgets/asset_thumbnail_tile.dart';
import 'package:photo_vault/widgets/familientage_abschnitt.dart';
import 'package:photo_vault/widgets/gesichtsrahmen.dart';
import 'package:photo_vault/widgets/sanduhr_ansicht.dart';
import 'package:photo_vault/widgets/zierbaum_ansicht.dart';
import 'package:teilen_ui/collage.dart' show Collageseite;
import 'package:teilen_ui/geteilte_alben.dart' show teilenTexte;

import 'katalog_bea_test.dart' as bea;
import 'katalog_kit.dart';
import 'katalog_per_test.dart' as per;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    binding.platformDispatcher.semanticsEnabledTestValue = false;
    bea.meldungenAus();
  });
  // Bei angehaltenem Wegwerf-Server wirft die App an einer Stelle „keine
  // Verbindung“ als unbehandelten Fehler in einer Zone, die das
  // Prüfgerüst der ersten Prüfung des Laufs zuordnet – diese gälte dann
  // „nach ihrem Ende“ als gescheitert. Solche Fehler werden nur
  // festgehalten (siehe [mitServer]); alle anderen wie gewohnt gemeldet.
  final standard = reportTestException;
  reportTestException = (details, beschreibung) {
    if (_istVerbindungsfehler(details.exception) &&
        (_serverGestoppt || '${details.exception}'.contains(':18875'))) {
      print(
        'GEDULDET (Server angehalten, gemeldet bei „$beschreibung“): '
        '${'${details.exception}'.split('\n').first} '
        '${details.stack.toString().split('\n').take(6).join(' / ')}',
      );
      return;
    }
    standard(details, beschreibung);
  };
  _fotobuchTests();
  _bearbeitenTests();
  _diashowTests();
  _exportTests();
  _personenTests();
  _serverTests();
}

// ===========================================================================
// Hilfen
// ===========================================================================

const _lang = Duration(seconds: 60);
const _sehrLang = Duration(seconds: 240);

/// Die Testbilder mit echtem Inhalt und die freien Porträts.
String get _mlOrdner => p.join(p.dirname(fixturesOrdner), 'fixtures-ml');

/// Kopiert eine Datei aus fixtures-ml in den Eingang der Prüfung.
File mlFixture(String relativ, {String? name}) {
  final quelle = File(p.join(_mlOrdner, relativ));
  if (!quelle.existsSync()) throw StateError('fixtures-ml fehlt: $relativ');
  return quelle.copySync(p.join(eingang.path, name ?? p.basename(relativ)));
}

/// Hier bleiben Ausgaben liegen, die nach dem Lauf noch einmal von aussen
/// angesehen werden sollen (im Temp-Ordner des Testplatzes, nicht in der
/// Wegwerf-Bibliothek, die am Ende gelöscht wird).
Directory get artefakte =>
    Directory(p.join(Directory.systemTemp.path, 'r2bea_artefakte'))
      ..createSync(recursive: true);

void sichere(String name, List<int> bytes) {
  File(p.join(artefakte.path, name)).writeAsBytesSync(bytes);
  print('ARTEFAKT ${p.join(artefakte.path, name)}');
}

/// Ein einfarbiges JPEG (mit kleiner Markierung gegen Dubletten).
File farbFoto(
  String name,
  int r,
  int g,
  int b, {
  int breite = 640,
  int hoehe = 480,
  DateTime? datum,
}) => bea.jpegAus(
  name,
  bea.flaeche(breite, hoehe, r, g, b),
  datum: datum ?? DateTime(2024, 5, 1, 10, 7),
);

/// Mittelwert von R, G, B im Ausschnitt (Anteile 0..1).
(double, double, double) farbe(
  img.Image b, {
  double x0 = 0.4,
  double y0 = 0.4,
  double x1 = 0.6,
  double y1 = 0.6,
}) => (
  bea.mittel(b, x0: x0, y0: y0, x1: x1, y1: y1, kanal: 'r'),
  bea.mittel(b, x0: x0, y0: y0, x1: x1, y1: y1, kanal: 'g'),
  bea.mittel(b, x0: x0, y0: y0, x1: x1, y1: y1, kanal: 'b'),
);

/// Grobe Einordnung einer Farbe: rot, gruen, blau, gelb, hell, dunkel,
/// grau.
String farbname((double, double, double) f) {
  final (r, g, b) = f;
  final hi = math.max(r, math.max(g, b));
  final lo = math.min(r, math.min(g, b));
  if (hi - lo < 35) {
    if (hi > 170) return 'hell';
    if (hi < 50) return 'dunkel';
    return 'grau';
  }
  if (r > 140 && g > 140 && b < 90) return 'gelb';
  if (r == hi && r > 120) return 'rot';
  if (g == hi && g > 120) return 'gruen';
  if (b == hi && b > 120) return 'blau';
  return 'grau';
}

/// Ein Standbild aus einem Video an der Stelle [anteil] (0..1) über den
/// nativen Wandler der App.
Future<img.Image> videobild(
  WidgetTester tester,
  File video,
  double anteil,
) async {
  final r = await bea.lauf(
    tester,
    () => NativeImageConverter.generateVideoThumbnail(
      video,
      maxDimension: 960,
      anteil: anteil,
      hoheQualitaet: true,
    ),
  );
  expect(r, isNotNull, reason: 'Standbild bei $anteil');
  return img.decodeJpg(r!.jpegBytes)!;
}

/// Liest Text in einem Bild über Apples Vision (wie die Texterkennung der
/// App).
Future<String> texterkennung(WidgetTester tester, img.Image bild) async {
  final datei = File(
    p.join(
      Directory.systemTemp.path,
      'r2bea_ocr_${DateTime.now().microsecondsSinceEpoch}.jpg',
    ),
  )..writeAsBytesSync(img.encodeJpg(bild, quality: 95));
  try {
    final stellen = await bea.lauf(
      tester,
      () => NativeImageConverter.recognizeText(datei),
    );
    return [for (final s in stellen ?? const []) s.text].join('\n');
  } finally {
    datei.deleteSync();
  }
}

String _kompakt(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'\s+'), '').replaceAll('·', '');

/// Eine WAV-Datei mit einem Sinuston (16 Bit, mono).
File wavDatei(String name, {double sekunden = 5, double hz = 440}) {
  const rate = 44100;
  final n = (sekunden * rate).round();
  final d = ByteData(44 + n * 2);
  void kennung(int o, String t) {
    for (var i = 0; i < 4; i++) {
      d.setUint8(o + i, t.codeUnitAt(i));
    }
  }

  kennung(0, 'RIFF');
  d.setUint32(4, 36 + n * 2, Endian.little);
  kennung(8, 'WAVE');
  kennung(12, 'fmt ');
  d.setUint32(16, 16, Endian.little);
  d.setUint16(20, 1, Endian.little);
  d.setUint16(22, 1, Endian.little);
  d.setUint32(24, rate, Endian.little);
  d.setUint32(28, rate * 2, Endian.little);
  d.setUint16(32, 2, Endian.little);
  d.setUint16(34, 16, Endian.little);
  kennung(36, 'data');
  d.setUint32(40, n * 2, Endian.little);
  for (var i = 0; i < n; i++) {
    d.setInt16(
      44 + i * 2,
      (math.sin(2 * math.pi * hz * i / rate) * 12000).round(),
      Endian.little,
    );
  }
  final f = File(p.join(eingang.path, name));
  f.writeAsBytesSync(d.buffer.asUint8List());
  return f;
}

/// Lautstärke (RMS) je 100 ms aus 16-kHz-PCM.
List<double> huelle(Int16List pcm) {
  const fenster = 1600;
  return [
    for (var i = 0; i + fenster <= pcm.length; i += fenster)
      math.sqrt(
        [
              for (var j = i; j < i + fenster; j++) pcm[j] * pcm[j].toDouble(),
            ].reduce((a, b) => a + b) /
            fenster,
      ),
  ];
}

double _median(List<double> w) {
  final s = [...w]..sort();
  return s.isEmpty ? 0 : s[s.length ~/ 2];
}

// --- Dateidialog mit Mitschnitt --------------------------------------------

/// Wie der nachgestellte Dialog des Kits (dieselben Rückgaben über
/// `dialog`), schreibt aber mit, welche Dateiarten der Dialog anbietet.
class MitschnittDialog extends KatalogDateidialog {
  final aufrufe = <({String weg, FileType typ, List<String>? endungen})>[];

  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) {
    aufrufe.add((weg: 'pickFiles', typ: type, endungen: allowedExtensions));
    return dialog.pickFiles(
      dialogTitle: dialogTitle,
      type: type,
      allowedExtensions: allowedExtensions,
    );
  }

  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) {
    aufrufe.add((weg: 'pickFile', typ: type, endungen: allowedExtensions));
    return dialog.pickFile(
      dialogTitle: dialogTitle,
      type: type,
      allowedExtensions: allowedExtensions,
    );
  }

  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    String? initialDirectory,
    AndroidOptions androidOptions = const AndroidOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) => dialog.getDirectoryPath(dialogTitle: dialogTitle);

  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? dialogTitle,
    String? initialDirectory,
    Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) => dialog.saveFile(
    fileName: fileName,
    bytes: bytes,
    mimeType: mimeType,
    dialogTitle: dialogTitle,
  );
}

MitschnittDialog mitschnitt() {
  final d = MitschnittDialog();
  FilePickerPlatform.instance = d;
  addTearDown(() => FilePickerPlatform.instance = dialog);
  return d;
}

/// Speicherdialog, der genau an den gewählten Pfad schreibt – wie der
/// echte, der eine leere Platzhalterdatei hinterlässt (wie in
/// katalog_per_test.dart).
class GenauerDialog extends KatalogDateidialog {
  String? ziel;
  final namen = <String>[];

  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? dialogTitle,
    String? initialDirectory,
    Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    namen.add(fileName);
    final z = ziel;
    if (z == null) return null;
    File(z).writeAsBytesSync(bytes);
    return File(z).uri;
  }
}

GenauerDialog genauerDialog() {
  final d = GenauerDialog();
  FilePickerPlatform.instance = d;
  addTearDown(() => FilePickerPlatform.instance = dialog);
  return d;
}

// --- PDF --------------------------------------------------------------------

/// Text eines PDF aus der Schrift-Tabelle (ToUnicode) – für jede Tabelle
/// einmal alle Textzeichen dekodiert, dazu die Klartext-Strings. Ohne
/// Leerzeichen zu vergleichen (siehe [pdfEnthaelt]).
List<String> pdfKlartexte(Uint8List pdf) {
  final teile = bea.pdfTexte(pdf);
  String utf16(String hex) {
    final einheiten = <int>[
      for (var i = 0; i + 4 <= hex.length; i += 4)
        int.parse(hex.substring(i, i + 4), radix: 16),
    ];
    return String.fromCharCodes(einheiten);
  }

  final tabellen = <Map<int, String>>[];
  for (final t in teile) {
    if (!t.contains('begincmap')) continue;
    final karte = <int, String>{};
    for (final block in RegExp(
      r'beginbfchar(.*?)endbfchar',
      dotAll: true,
    ).allMatches(t)) {
      for (final m in RegExp(
        r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>',
      ).allMatches(block.group(1)!)) {
        karte[int.parse(m.group(1)!, radix: 16)] = utf16(m.group(2)!);
      }
    }
    for (final block in RegExp(
      r'beginbfrange(.*?)endbfrange',
      dotAll: true,
    ).allMatches(t)) {
      for (final m in RegExp(
        r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>',
      ).allMatches(block.group(1)!)) {
        final a = int.parse(m.group(1)!, radix: 16);
        final b = int.parse(m.group(2)!, radix: 16);
        final start = utf16(m.group(3)!).codeUnits;
        for (var c = a; c <= b; c++) {
          karte[c] = String.fromCharCodes([
            ...start.sublist(0, start.length - 1),
            start.last + (c - a),
          ]);
        }
      }
    }
    tabellen.add(karte);
  }
  final ergebnis = <String>[];
  final inhalte = [
    for (final t in teile)
      if (!t.contains('begincmap') && (t.contains('Tj') || t.contains('TJ'))) t,
  ];
  for (final karte in tabellen) {
    final b = StringBuffer();
    for (final t in inhalte) {
      for (final m in RegExp(r'<([0-9A-Fa-f]{4,})>').allMatches(t)) {
        final hex = m.group(1)!;
        for (var i = 0; i + 4 <= hex.length; i += 4) {
          b.write(karte[int.parse(hex.substring(i, i + 4), radix: 16)] ?? '');
        }
        b.write(' ');
      }
    }
    ergebnis.add(b.toString());
  }
  final klar = StringBuffer();
  for (final t in inhalte) {
    for (final m in RegExp(r'\(((?:[^()\\]|\\.)*)\)\s*Tj').allMatches(t)) {
      klar.write('${m.group(1)} ');
    }
  }
  ergebnis.add(klar.toString());
  return ergebnis;
}

/// Die Rasterbilder (RGB) eines PDF, entpackt.
List<img.Image> pdfRaster(Uint8List pdf) {
  final text = latin1.decode(pdf, allowInvalid: true);
  final ergebnis = <img.Image>[];
  for (final m in RegExp(
    r'<<([^<>]*?/Subtype\s*/Image[^<>]*?)>>\s*stream\r?\n',
  ).allMatches(text)) {
    final kopf = m.group(1)!;
    int? zahl(String n) {
      final z = RegExp('/$n\\s+(\\d+)').firstMatch(kopf);
      return z == null ? null : int.parse(z.group(1)!);
    }

    final b = zahl('Width'), h = zahl('Height'), n = zahl('Length');
    if (b == null || h == null || n == null) continue;
    if (!kopf.contains('DeviceRGB')) continue;
    try {
      final roh = ZLibCodec().decode(pdf.sublist(m.end, m.end + n));
      if (roh.length != b * h * 3) continue;
      ergebnis.add(
        img.Image.fromBytes(
          width: b,
          height: h,
          bytes: Uint8List.fromList(roh).buffer,
          numChannels: 3,
        ),
      );
    } catch (_) {}
  }
  return ergebnis;
}

/// Wie viele Punkte kräftig magenta sind (die Farbe der Prüf-Porträts).
int magenta(img.Image b) {
  var n = 0;
  for (final px in b) {
    if (px.r > 200 && px.g < 90 && px.b > 200) n++;
  }
  return n;
}

bool pdfEnthaelt(List<String> texte, String gesucht) =>
    texte.any((t) => _kompakt(t).contains(_kompakt(gesucht)));

/// Alle Objekte (auch aus Objektströmen) als Text.
String pdfAlles(Uint8List pdf) => bea.pdfTexte(pdf).join('\n');

int pdfBilder(Uint8List pdf) =>
    RegExp(r'/Subtype\s*/Image').allMatches(pdfAlles(pdf)).length;

// --- Steuerung des eigenen Wegwerf-Servers ---------------------------------

const _steuerung = 'http://127.0.0.1:18879';

Future<String> steuere(WidgetTester tester, String pfad) async {
  final antwort = await tester.runAsync(() async {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final anfrage = await c.getUrl(Uri.parse('$_steuerung$pfad'));
      final r = await anfrage.close().timeout(const Duration(seconds: 280));
      final text = await utf8.decodeStream(r);
      if (r.statusCode != 200) {
        throw StateError('Steuerung $pfad: ${r.statusCode} $text');
      }
      return text;
    } finally {
      c.close(force: true);
    }
  });
  print('Steuerung $pfad → ${antwort?.split('\n').first}');
  if (pfad == '/stopp') _serverGestoppt = true;
  if (pfad == '/neu') _serverGestoppt = false;
  return antwort!;
}

/// Ob der Wegwerf-Server gerade angehalten ist (siehe [mitServer]).
var _serverGestoppt = false;

bool _istVerbindungsfehler(Object e) {
  final t = '$e';
  return e is SocketException ||
      t.contains('KeineVerbindung') ||
      t.contains('Connection refused');
}

/// Eine Prüfung mit dem eigenen Wegwerf-Server.
///
/// Ist der Server angehalten, wirft die App an einigen Stellen „keine
/// Verbindung“ als unbehandelten Fehler (aus dem Holen einer Datei,
/// packages/kern/lib/abgleich/verbindung.dart:164 über
/// storage_paths.dart:250). Die Prüfung hält diese Fehler fest (Protokoll
/// „GEDULDET“), statt an ihnen zu scheitern. Jeder andere Fehler lässt sie
/// scheitern wie gewohnt.
void mitServer(
  String name,
  Future<void> Function(WidgetTester tester) rumpf, {
  bool skip = false,
}) => testWidgets(
  name,
  (tester) {
    _serverGestoppt = false;
    var geduldet = 0;
    final vorher = FlutterError.onError;
    FlutterError.onError = (d) {
      if (_serverGestoppt && _istVerbindungsfehler(d.exception)) {
        if (geduldet++ < 5) {
          print(
            'GEDULDET (Server angehalten): ${'${d.exception}'.split('\n').first}',
          );
        }
        return;
      }
      vorher?.call(d);
    };
    addTearDown(() => FlutterError.onError = vorher);
    final fertig = Completer<void>();
    runZonedGuarded(
      () async {
        try {
          await rumpf(tester);
        } catch (fehler, stapel) {
          if (!fertig.isCompleted) fertig.completeError(fehler, stapel);
          return;
        }
        print('$name: $geduldet Verbindungsfehler bei angehaltenem Server');
        if (!fertig.isCompleted) fertig.complete();
      },
      (fehler, stapel) {
        if (_serverGestoppt && _istVerbindungsfehler(fehler)) {
          if (geduldet++ < 5) {
            print(
              'GEDULDET (Server angehalten): ${'$fehler'.split('\n').first} '
              '${stapel.toString().split('\n').take(8).join(' / ')}',
            );
          }
          return;
        }
        final t = '$fehler';
        if (t.contains('connection was closed') ||
            t.contains('after closing')) {
          return;
        }
        print('Fehler in der Prüfung: ${t.split('\n').first}');
        if (!fertig.isCompleted) fertig.completeError(fehler, stapel);
      },
    );
    return fertig.future;
  },
  skip: skip,
  semanticsEnabled: false,
);

/// Wartet, bis eine Aufnahme der Server-Bibliothek [passt], und gibt sie.
Future<Map<String, dynamic>> amServer(
  WidgetTester tester,
  bool Function(Map<String, dynamic>) passt,
  String was,
) async {
  final ende = DateTime.now().add(_sehrLang);
  List<Map<String, dynamic>> zuletzt = const [];
  while (DateTime.now().isBefore(ende)) {
    zuletzt = await serverAufnahmen(tester);
    for (final z in zuletzt) {
      if (passt(z)) return z;
    }
    await tester.pump(const Duration(seconds: 1));
  }
  throw TimeoutException('$was – am Server: $zuletzt');
}

Future<List<Map<String, dynamic>>> serverAufnahmen(WidgetTester tester) async =>
    [
      for (final z in jsonDecode(await steuere(tester, '/aufnahmen')) as List)
        (z as Map).cast<String, dynamic>(),
    ];

// ===========================================================================
// Fotobuch
// ===========================================================================

Future<void> fotobuchWahlPruefen(
  WidgetTester tester, {
  required Fotobuchformat format,
  required int jeSeite,
  required Set<String> angaben,
}) async {
  await waitFor(tester, find.text(de.fotobuchGestalten));
  expect(
    tester
        .widget<SegmentedButton<Fotobuchformat>>(
          find.byType(SegmentedButton<Fotobuchformat>),
        )
        .selected,
    {format},
  );
  expect(
    tester
        .widget<SegmentedButton<int>>(find.byType(SegmentedButton<int>))
        .selected,
    {jeSeite},
  );
  for (final a in [
    de.fotobuchMitDatum,
    de.fotobuchMitOrt,
    de.fotobuchMitPersonen,
    de.fotobuchMitBeschreibung,
  ]) {
    expect(
      tester.widget<FilterChip>(find.widgetWithText(FilterChip, a)).selected,
      angaben.contains(a),
      reason: a,
    );
  }
}

Future<void> dialogAbbrechen(WidgetTester tester) => bea.tap(
  tester,
  find.descendant(
    of: find.byType(AlertDialog),
    matching: find.text(de.allgAbbrechen),
  ),
);

void _fotobuchTests() {
  // Muss die erste Prüfung sein, die den Fotobuch-Dialog öffnet: Die
  // Wahl merkt sich die App in einer Variablen des Prozesses
  // (lib/widgets/fotobuch_export.dart:44 `_zuletzt`), nicht in den
  // Einstellungen. Die erste Öffnung in einem frischen Prozess ist deshalb
  // genau der Zustand nach einem Neustart.
  bea.testWidgets(
    'BEA-117 Fotobuch: nach dem Start, bearbeitete Fassung, Vorbelegung',
    (tester) async {
      await startApp(tester);
      final entw = await importiereDirekt(tester, [
        bea.grauFoto('entw.jpg', wert: 60, datum: DateTime(2023, 9, 1, 10)),
      ]);
      final zwei = await importiereDirekt(tester, [
        bea.grauFoto('z1.jpg', wert: 90, datum: DateTime(2023, 9, 2, 10)),
        bea.grauFoto('z2.jpg', wert: 110, datum: DateTime(2023, 9, 3, 10)),
      ]);
      await bea.befehl(
        tester,
        AlbumAnlegen('alb-entw', 'Entwickelt', DateTime(2024)),
      );
      await bea.befehl(tester, AlbumFuellen('alb-entw', entw));
      await bea.befehl(
        tester,
        AlbumAnlegen('alb-zwei', 'Zwei', DateTime(2024)),
      );
      await bea.befehl(tester, AlbumFuellen('alb-zwei', zwei));
      await bea.oeffneEntwickeln(tester, entw.single);
      await bea.setzeRegler(tester, de.entwBelichtung, 3);
      await bea.entwSpeichern(tester);

      // Erste Öffnung im Prozess = nach dem Neustart.
      await bea.oeffneAlbum(tester, 'Entwickelt');
      await bea.tap(tester, find.byTooltip(de.fotobuchAlsPdf));
      await fotobuchWahlPruefen(
        tester,
        format: Fotobuchformat.a4Hoch,
        jeSeite: 1,
        angaben: {
          de.fotobuchMitDatum,
          de.fotobuchMitOrt,
          de.fotobuchMitPersonen,
        },
      );
      await bea.fotobuchGestalten(
        tester,
        format: de.fotobuchQuadrat,
        jeSeite: 4,
        angaben: {de.fotobuchMitDatum, de.fotobuchMitBeschreibung},
      );
      final ziel = bea.zielOrdner('fotobuch117');
      dialog.speichernUnter = ziel.path;
      bea.merkeMeldungen();
      await bea.tap(tester, find.text(de.fotobuchErstellen));
      await bea.erwarteNeueMeldung(
        tester,
        de.fotobuchFertig('Entwickelt.pdf', 2),
        timeout: _sehrLang,
      );
      final pdf = File(p.join(ziel.path, 'Entwickelt.pdf')).readAsBytesSync();
      final bilder = bea.pdfJpegs(pdf);
      expect(bilder, isNotEmpty);
      final hell = bilder
          .map((b) => bea.mittel(bea.klein(b, breite: 64)))
          .reduce(math.max);
      print('BEA-117 hellstes Bild im PDF: $hell (Original 60)');
      expect(hell, greaterThan(120), reason: 'entwickelte Fassung im PDF');
      final format = bea.pdfFormat(pdf)!;
      expect(format.$1, closeTo(595.3, 2), reason: '21 cm');
      expect(format.$2, closeTo(595.3, 2), reason: '21 cm');

      // Zweites Buch in derselben Sitzung: vorbelegt.
      await bea.oeffneAlbum(tester, 'Zwei');
      await bea.tap(tester, find.byTooltip(de.fotobuchAlsPdf));
      await fotobuchWahlPruefen(
        tester,
        format: Fotobuchformat.quadrat,
        jeSeite: 4,
        angaben: {de.fotobuchMitDatum, de.fotobuchMitBeschreibung},
      );
      await dialogAbbrechen(tester);
      await bea.abschluss(tester);
    },
  );

  bea.testWidgets('BEA-112 Fotobuch aus einem Album mit Ort und Personen', (
    tester,
  ) async {
    await startApp(tester);
    final urlaub = await importiereDirekt(tester, [
      for (var i = 0; i < 6; i++)
        bea.grauFoto(
          'u$i.jpg',
          wert: 60 + i * 20,
          datum: DateTime(2023, 7, 1 + i, 10, 15),
        ),
    ]);
    // Ort (ausgedacht) und benannte Gesichter: auf u0 links Person A,
    // rechts Person B; auf u1 umgekehrt.
    for (final id in urlaub) {
      await bea.setzeAngaben(
        tester,
        id,
        const AssetsCompanion(
          locationCity: Value('Prüfstadt'),
          latitude: Value(47.42),
          longitude: Value(10.98),
        ),
      );
    }
    late String a, b;
    await tester.runAsync(() async {
      a = await per.person('Person A');
      b = await per.person('Person B');
      await per.gesicht(urlaub[0], person: a, x: 0.1);
      await per.gesicht(urlaub[0], person: b, x: 0.6);
      await per.gesicht(urlaub[1], person: b, x: 0.1);
      await per.gesicht(urlaub[1], person: a, x: 0.6);
    });
    await bea.befehl(
      tester,
      AlbumAnlegen('alb-urlaub', 'Urlaub', DateTime(2024)),
    );
    await bea.befehl(tester, AlbumFuellen('alb-urlaub', urlaub));

    final ziel = bea.zielOrdner('fotobuch112');
    await bea.oeffneAlbum(tester, 'Urlaub');
    await bea.tap(tester, find.byTooltip(de.fotobuchAlsPdf));
    await waitFor(tester, find.text(de.fotobuchGestalten));
    expect(find.text(de.fotobuchUmfang(6)), findsOneWidget);
    expect(
      tester.widget<TextField>(field(de.fotobuchTitelseite)).controller!.text,
      'Urlaub',
    );
    await bea.fotobuchGestalten(
      tester,
      format: de.fotobuchA4Quer,
      jeSeite: 2,
      angaben: {de.fotobuchMitDatum, de.fotobuchMitOrt, de.fotobuchMitPersonen},
    );
    dialog.speichernUnter = ziel.path;
    bea.merkeMeldungen();
    await tester.tap(find.text(de.fotobuchErstellen));
    var fenster = false, balken = false;
    final ende = DateTime.now().add(_sehrLang);
    while (DateTime.now().isBefore(ende)) {
      await tester.pump(const Duration(milliseconds: 30));
      if (find.text(de.fotobuchWirdErstellt).evaluate().isNotEmpty) {
        fenster = true;
        balken |= find
            .descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(LinearProgressIndicator),
            )
            .evaluate()
            .isNotEmpty;
      }
      if (bea.hatNeueMeldung(de.fotobuchFertig('Urlaub.pdf', 4))) break;
    }
    expect(dialog.gerufen.last, 'saveFile Urlaub.pdf');
    expect(fenster, isTrue, reason: 'Fenster „Fotobuch wird erstellt …“');
    expect(balken, isTrue, reason: 'mit Balken');
    expect(bea.hatNeueMeldung(de.fotobuchFertig('Urlaub.pdf', 4)), isTrue);
    final pdf = File(p.join(ziel.path, 'Urlaub.pdf')).readAsBytesSync();
    sichere('bea112_Urlaub.pdf', pdf);
    expect(bea.pdfSeiten(pdf), 4, reason: 'Titelseite + 3');
    final format = bea.pdfFormat(pdf)!;
    expect(format.$1, closeTo(842, 2), reason: 'A4 quer');
    expect(format.$2, closeTo(595, 2));
    expect(bea.pdfJpegs(pdf).length, greaterThanOrEqualTo(6));
    final texte = pdfKlartexte(pdf);
    print(
      'BEA-112 Text im PDF: ${texte.map((t) => t.length > 400 ? t.substring(0, 400) : t).toList()}',
    );
    final tag = DateFormat.yMMMMd('de').format(DateTime(2023, 7, 1));
    expect(pdfEnthaelt(texte, 'Urlaub'), isTrue, reason: 'Titelseite');
    expect(
      pdfEnthaelt(texte, '$tag · Prüfstadt · Person A, Person B'),
      isTrue,
      reason: 'Datum, Ort, Personen von links nach rechts (u0)',
    );
    expect(
      pdfEnthaelt(
        texte,
        '${DateFormat.yMMMMd('de').format(DateTime(2023, 7, 2))} · Prüfstadt · Person B, Person A',
      ),
      isTrue,
      reason: 'u1: B links, A rechts',
    );
    for (var i = 2; i < 6; i++) {
      expect(
        pdfEnthaelt(
          texte,
          '${DateFormat.yMMMMd('de').format(DateTime(2023, 7, 1 + i))} · Prüfstadt',
        ),
        isTrue,
        reason: 'u$i',
      );
    }
    await bea.abschluss(tester);
  });

  bea.testWidgets(
    'BEA-115 Fotobuch: Kürzung, Videos und gesperrtes Foto draussen, nur Videos',
    (tester) async {
      await startApp(tester);
      final fotos = await importiereDirekt(tester, [
        for (var i = 0; i < 260; i++)
          bea.grauFoto(
            'b$i.jpg',
            wert: 40 + i % 150,
            breite: 160,
            hoehe: 120,
            datum: DateTime(2021, 6, 5, 6 + i ~/ 60, i % 60, 7),
          ),
      ]);
      expect(fotos, hasLength(260));
      final gesperrt = (await importiereDirekt(tester, [
        bea.grauFoto(
          'gesperrt.jpg',
          wert: 200,
          breite: 160,
          hoehe: 120,
          datum: DateTime(2021, 6, 5, 7, 30, 30),
        ),
      ])).single;
      final videos = await importiereDirekt(tester, [
        fixture('video_5s.mp4'),
        fixture('video_hoch_3s.mov'),
      ]);
      for (var i = 0; i < 2; i++) {
        await bea.setzeAngaben(
          tester,
          videos[i],
          AssetsCompanion(fileCreatedAt: Value(DateTime(2021, 6, 5, 12, i, 3))),
        );
      }
      await bea.tresorEinrichten(tester);
      // 263 Aufnahmen wählen; danach landet eine davon im gesperrten Ordner
      // (wie durch ein anderes Gerät). Die Zeitleiste lässt gesperrte
      // Fotos nie wählen (packages/kern/lib/db/rasterzeile.dart:61); nur
      // eine schon bestehende Auswahl kann eines enthalten.
      await bea.waehleBereich(tester, fotos.first, videos.last, 263);
      await bea.sperre(tester, gesperrt);
      expect((await bea.aufnahme(tester, gesperrt)).isLocked, isTrue);
      expect(find.text(de.auswAnzahl(263)), findsOneWidget);
      await bea.tap(tester, find.byTooltip(de.auswExportieren));
      await bea.tap(tester, find.text(de.fotobuchTitel));
      await waitFor(tester, find.text(de.fotobuchGestalten));
      expect(find.text(de.fotobuchUmfang(250)), findsOneWidget);
      await bea.fotobuchGestalten(
        tester,
        format: de.fotobuchA4Hoch,
        jeSeite: 4,
      );
      dialog.speichernUnter = bea.zielOrdner('gross').path;
      bea.merkeMeldungen();
      await bea.tap(tester, find.text(de.fotobuchErstellen));
      final m = await bea.erwarteNeueMeldung(
        tester,
        de.fotobuchGekuerzt(250),
        timeout: _sehrLang,
      );
      print('BEA-115 Meldung: $m');
      expect(m, startsWith(de.fotobuchFertig('', 0).split(':').first));
      expect(m, contains(de.fotobuchGekuerzt(250)));
      expect(
        m,
        contains(de.fotobuchUebersprungen(3)),
        reason: '2 Videos + 1 gesperrtes Foto',
      );

      await bea.waehleAus(tester, videos);
      await bea.tap(tester, find.byTooltip(de.auswExportieren));
      bea.merkeMeldungen();
      await bea.tap(tester, find.text(de.fotobuchTitel));
      await bea.erwarteNeueMeldung(tester, de.fotobuchKeineFotos);
      expect(find.text(de.fotobuchGestalten), findsNothing);
      await bea.abschluss(tester);
    },
  );
}

// ===========================================================================
// Entwickeln, Vorgaben, Objekt entfernen
// ===========================================================================

void _bearbeitenTests() {
  bea.testWidgets(
    'BEA-010 Farbtabelle: Dateiwahl nur .cube, Stärke, Entfernen',
    (tester) async {
      await startApp(tester);
      final ids = await importiereDirekt(tester, [
        bea.grauFoto('a.jpg', wert: 60),
      ]);
      final aufz = mitschnitt();
      await bea.oeffneEntwickeln(tester, ids.first);
      final h0 = bea.mittel(bea.vorschau(tester));
      final cube = bea.cubeDatei('umkehr.cube', bea.umkehrCube());
      expect(bea.inEntwickeln(find.text(de.entwLutKeine)), findsOneWidget);
      await bea.lutWaehlen(tester, cube);
      await waitFor(tester, bea.inEntwickeln(find.text('umkehr')));
      final ruf = aufz.aufrufe.last;
      print('BEA-010 Dateiwahl: ${ruf.weg} ${ruf.typ} ${ruf.endungen}');
      expect(ruf.typ, FileType.custom);
      expect(ruf.endungen, ['cube'], reason: 'nur .cube angeboten');
      expect(bea.inEntwickeln(find.text(de.entwLutKeine)), findsNothing);
      expect(bea.reglerWert(tester, de.entwLutStaerke), 1.0);
      expect(
        find.text('1.00'),
        findsWidgets,
        reason: 'Stärke 1.00 steht daneben',
      );
      await bea.renderAbwarten(tester);
      final h1 = bea.mittel(bea.vorschau(tester));
      expect(h1, greaterThan(h0 + 40), reason: 'Look angenommen ($h0 → $h1)');
      final kopie = bea.datei(bibliothek.paths.lutRelativePath('umkehr.cube'));
      expect(kopie.existsSync(), isTrue, reason: 'in die Bibliothek kopiert');
      expect(kopie.readAsStringSync(), cube.readAsStringSync());
      await bea.setzeRegler(tester, de.entwLutStaerke, 0.5);
      final hHalb = bea.mittel(bea.vorschau(tester));
      print('BEA-010 Helligkeit 0 / 0.5 / 1: $h0 / $hHalb / $h1');
      expect(hHalb, greaterThan(h0 + 10));
      expect(hHalb, lessThan(h1 - 10));
      await bea.tap(
        tester,
        bea.inEntwickeln(find.byTooltip(de.entwLutEntfernen)),
      );
      await bea.renderAbwarten(tester);
      expect(bea.inEntwickeln(find.text(de.entwLutKeine)), findsOneWidget);
      expect((bea.mittel(bea.vorschau(tester)) - h0).abs(), lessThan(8));
      await bea.abschluss(tester);
    },
  );

  bea.testWidgets(
    'BEA-043 Vorgabe auf fünf Aufnahmen: Video und gesperrtes Foto zählen nicht',
    (tester) async {
      await startApp(tester);
      final ids = await importiereDirekt(tester, [
        for (var i = 0; i < 3; i++)
          bea.grauFoto(
            'v$i.jpg',
            wert: 90 + i * 5,
            breite: 3600,
            hoehe: 2400,
            datum: DateTime(2024, 5, 1, 10, 10 + i),
          ),
        bea.grauFoto(
          'gesperrt.jpg',
          wert: 105,
          datum: DateTime(2024, 5, 1, 10, 20),
        ),
        fixture('video_5s.mp4'),
      ]);
      final videoId = ids[4];
      await bea.setzeAngaben(
        tester,
        videoId,
        AssetsCompanion(fileCreatedAt: Value(DateTime(2024, 5, 1, 10, 30))),
      );
      // Vorgabe „Warm“ anlegen.
      await bea.oeffneEntwickeln(tester, ids[0]);
      await bea.setzeRegler(tester, de.entwBelichtung, 0.8);
      bea.merkeMeldungen();
      await bea.tap(
        tester,
        bea.inEntwickeln(find.byTooltip(de.entwVorgabeSichern)),
      );
      await enter(tester, field(de.entwVorgabeName), 'Warm');
      await bea.tap(
        tester,
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(de.allgSpeichern),
        ),
      );
      await bea.erwarteNeueMeldung(tester, de.entwVorgabeGesichert('Warm'));
      await bea.zurueck(tester);

      await bea.tresorEinrichten(tester);
      await bea.waehleAus(tester, ids);
      // Danach in den gesperrten Ordner (wie durch ein anderes Gerät): Die
      // Zeitleiste lässt gesperrte Fotos sonst nie wählen.
      await bea.sperre(tester, ids[3]);
      expect(find.text(de.auswAnzahl(5)), findsOneWidget);
      final shas = {
        for (final id in ids)
          id: bea.sha(bea.datei((await bea.aufnahme(tester, id)).relativePath)),
      };
      await bea.tap(tester, find.byTooltip(de.auswVorgabeAnwenden));
      expect(find.text(de.auswVorgabeAnwendenTitel(5)), findsOneWidget);
      await tester.tap(find.widgetWithText(SimpleDialogOption, 'Warm'));
      final staende = <String>[];
      final stand = RegExp(r'^\d+ / \d+');
      final ende = DateTime.now().add(_sehrLang);
      while (DateTime.now().isBefore(ende)) {
        await tester.pump();
        for (final e in find.byType(Text).evaluate()) {
          final s = (e.widget as Text).data ?? '';
          if (stand.hasMatch(s) && (staende.isEmpty || staende.last != s)) {
            staende.add(s);
          }
        }
        if (staende.isNotEmpty &&
            staende.last.startsWith('3 / 3') &&
            find.text(de.allgSchliessen).evaluate().isNotEmpty) {
          break;
        }
      }
      print('BEA-043 Stände: $staende');
      expect(find.text(de.auswUebertrageLaeuft), findsOneWidget);
      expect(
        staende.first,
        '0 / 3',
        reason: 'Video und gesperrtes zählen nicht',
      );
      expect(staende.last, startsWith('3 / 3 — '));
      expect(staende.last, matches(RegExp(r'^3 / 3 — v\d\.jpg$')));
      await bea.tap(tester, find.text(de.allgSchliessen));
      for (final id in ids.take(3)) {
        final s = await bea.lauf(
          tester,
          () => bibliothek.db.developSettingsForAsset(id),
        );
        expect(s?.exposure, closeTo(0.8, 0.001), reason: id);
        expect(
          (await bea.aufnahme(tester, id)).developedRelativePath,
          isNotNull,
        );
      }
      for (final id in [ids[3], videoId]) {
        expect(
          await bea.lauf(
            tester,
            () => bibliothek.db.developSettingsForAsset(id),
          ),
          isNull,
          reason: 'unverändert: $id',
        );
        expect((await bea.aufnahme(tester, id)).developedRelativePath, isNull);
      }
      for (final id in ids) {
        expect(
          bea.sha(bea.datei((await bea.aufnahme(tester, id)).relativePath)),
          shas[id],
          reason: 'Original byte-gleich: $id',
        );
      }
      await bea.abschluss(tester);
    },
  );

  bea.testWidgets(
    'BEA-079 Objekt entfernen: Dienst und Bildeditor am selben Bild',
    (tester) async {
      await startApp(tester, modelle: ['lama_fp32.onnx']);
      img.Image mitQuadrat() {
        final b = bea.flaeche(900, 600, 150, 150, 150);
        img.fillRect(
          b,
          x1: 430,
          y1: 280,
          x2: 470,
          y2: 320,
          color: img.ColorRgb8(10, 10, 10),
        );
        return b;
      }

      // 1. Der Dienst allein, mit einer Rechteckmaske über dem Quadrat und
      //    mit einer Maske, wie der Bildeditor sie aus einem Strich baut.
      final roh = mitQuadrat();
      final rechteck = img.Image(width: 900, height: 600);
      img.fillRect(
        rechteck,
        x1: 425,
        y1: 275,
        x2: 475,
        y2: 325,
        color: img.ColorRgb8(255, 255, 255),
      );
      final strichMaske = img.Image(width: 900, height: 600);
      for (var x = 423; x <= 477; x += 3) {
        img.fillCircle(
          strichMaske,
          x: x,
          y: 300,
          radius: 24,
          color: img.ColorRgb8(255, 255, 255),
        );
      }
      final dienstWerte = <String, double>{};
      await tester.runAsync(() async {
        final dienst = await InpaintingService.load(bibliothek.modelsDir);
        try {
          for (final (name, maske) in [
            ('Rechteck', rechteck),
            ('Strich', strichMaske),
          ]) {
            final e = (await dienst.entferne(roh, maske))!;
            dienstWerte[name] = bea.mittel(
              e,
              x0: 435 / 900,
              y0: 285 / 600,
              x1: 465 / 900,
              y1: 315 / 600,
            );
            sichere('bea079_dienst_$name.jpg', img.encodeJpg(e));
          }
        } finally {
          await dienst.dispose();
        }
      });
      print('BEA-079 Dienst allein, Quadratmitte danach: $dienstWerte');

      // 2. Derselbe Weg durch den Bildeditor.
      final ids = await importiereDirekt(tester, [
        bea.jpegAus('objekt.jpg', mitQuadrat()),
      ]);
      final shaA = bea.sha(
        bea.datei((await bea.aufnahme(tester, ids.first)).relativePath),
      );
      await bea.oeffneEditor(tester, ids.first);
      final retusche = bea.tooltipBeginnt(de.bearbRetusche);
      await bea.tap(tester, retusche);
      FilledButton entfernen() => tester.widget<FilledButton>(
        find.ancestor(
          of: find.text(de.bearbRetuscheAnwenden),
          matching: find.byWidgetPredicate((w) => w is FilledButton),
        ),
      );
      expect(entfernen().onPressed, isNull, reason: 'erst mit Strich');
      final pinsel = find.descendant(
        of: find.byType(ImageEditorScreen),
        matching: find.byType(Slider),
      );
      final s = tester.widget<Slider>(pinsel);
      print('BEA-079 Pinselbreite: ${s.min}–${s.max}');
      // Pinsel 80: bei Massstab 1,23 rund 32 Bildpunkte Radius – das
      // Quadrat ist samt Ecken bedeckt. Mit Pinsel 50 (erste Runde) blieben
      // die Ecken frei, und LaMa setzte das Quadrat aus ihnen fort.
      s.onChanged!(math.min(80, s.max));
      await bea.settle(tester);
      await bea.editorStrich(tester, [
        const Offset(0.47, 0.5),
        const Offset(0.53, 0.5),
      ]);
      expect(entfernen().onPressed, isNotNull);
      final maler = find.byWidgetPredicate(
        (w) =>
            w is CustomPaint &&
            w.painter.runtimeType.toString() == '_RetuscheMaler',
      );
      expect(
        ((tester.widget(maler) as CustomPaint).painter as dynamic).striche
            as List,
        hasLength(1),
      );
      await bea.tap(tester, bea.editorKnopf(de.bearbRetuscheZurueck));
      expect(entfernen().onPressed, isNull, reason: 'Strich zurückgenommen');
      await bea.editorStrich(tester, [
        const Offset(0.47, 0.5),
        const Offset(0.53, 0.5),
      ]);
      final striche =
          ((tester.widget(maler) as CustomPaint).painter as dynamic).striche
              as List;
      final rahmen = bea.editorRechteck(tester);
      print(
        'BEA-079 Striche ${striche.length}, Punkte ${(striche.first as List).length}, '
        'erster ${(striche.first as List).first}, letzter ${(striche.first as List).last}, '
        'Bildfläche $rahmen (Massstab ${rahmen.width / 900})',
      );
      final vorher = bea.editorBild(tester);
      await bea.tap(tester, find.text(de.bearbRetuscheAnwenden));
      await bea.editorFertig(tester);
      expect(
        bea.editorKnopf(de.bearbZuschneiden),
        findsOneWidget,
        reason: 'Werkzeug geschlossen',
      );
      final nachher = bea.editorBild(tester);
      sichere('bea079_editor.jpg', bea.editorBytes(tester));
      var veraendert = 0;
      for (final px in nachher) {
        final o = vorher.getPixel(px.x, px.y);
        if ((o.r - px.r).abs() + (o.g - px.g).abs() + (o.b - px.b).abs() > 40) {
          veraendert++;
        }
      }
      final fleck = bea.mittel(
        nachher,
        x0: 435 / 900,
        y0: 285 / 600,
        x1: 465 / 900,
        y1: 315 / 600,
      );
      print(
        'BEA-079 Editor: Quadratmitte $fleck, veränderte Punkte $veraendert, '
        'Dienst: $dienstWerte',
      );
      expect(
        dienstWerte['Rechteck'],
        greaterThan(110),
        reason: 'Dienst füllt das Quadrat',
      );
      expect(fleck, greaterThan(110), reason: 'Objekt im Editor ersetzt');
      await bea.editorSpeichern(tester);
      final alle = await bea.alleAufnahmen(tester);
      expect(alle, hasLength(2), reason: 'Original als Variante');
      expect(
        alle.map((x) => bea.sha(bea.datei(x.relativePath))),
        contains(shaA),
      );
      await bea.abschluss(tester);
    },
  );
}

// ===========================================================================
// Diashow
// ===========================================================================

Finder knopfFuerVorJahren(int jahre) => find.descendant(
  of: find
      .ancestor(
        of: find.text(de.erkundenVorJahren(jahre)),
        matching: find.byType(Row),
      )
      .first,
  matching: find.byTooltip(de.diashowAlsVideo),
);

void _diashowTests() {
  bea.testWidgets(
    'BEA-105 BEA-106 Diashow: Titelkarte, Bildfolge, Musik mit Ein- und Ausblenden',
    (tester) async {
      await startApp(tester);
      final heute = DateTime.now();
      final jahr = heute.month <= 2 ? heute.year - 1 : heute.year;
      final ids = await importiereDirekt(tester, [
        farbFoto('rot.jpg', 220, 30, 30, datum: DateTime(jahr, 1, 10, 10, 5)),
        farbFoto('gruen.jpg', 30, 200, 30, datum: DateTime(jahr, 1, 10, 11, 5)),
        farbFoto('blau.jpg', 30, 30, 220, datum: DateTime(jahr, 2, 1, 9, 5)),
      ]);
      await bea.alleSchliessen(tester);
      await openSection(tester, Hauptbereich.rueckblick);
      await bea.tap(tester, find.text(de.jahresrueckblickTitel(jahr)));
      await waitFor(
        tester,
        find.text(de.jahresrueckblickAuswahl),
        timeout: _lang,
      );

      // BEA-105
      final ziel = bea.zielOrdner('diashow');
      bea.merkeMeldungen();
      await bea.tap(tester, find.byTooltip(de.diashowAlsVideo));
      await bea.diashowOhneMusik(tester, ziel.path);
      await waitFor(tester, find.text(de.diashowWirdErstellt));
      expect(find.text(de.diashowUmfang(3)), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      await bea.erwarteNeueMeldung(
        tester,
        de.flugVideoFertig('jahresrueckblick-$jahr.mp4'),
        timeout: _sehrLang,
      );
      expect(dialog.gerufen.last, 'saveFile jahresrueckblick-$jahr.mp4');
      final mp4 = File(p.join(ziel.path, 'jahresrueckblick-$jahr.mp4'));
      final bytes = mp4.readAsBytesSync();
      sichere('bea105_ohne_musik.mp4', bytes);
      expect(bea.mp4Spuren(bytes), contains((1920, 1080)));
      final dauer = bea.mp4Dauer(bytes)!;
      print('BEA-105 Dauer $dauer s');
      expect(dauer, closeTo(13.0, 1.0), reason: 'Titelkarte 2,5 s + 3 × 3,5 s');
      final titel = await videobild(tester, mp4, 1.0 / dauer);
      sichere('bea105_titel.jpg', img.encodeJpg(titel));
      final gelesen = await texterkennung(tester, titel);
      print('BEA-105 Titelkarte gelesen: ${gelesen.replaceAll('\n', ' | ')}');
      expect(
        _kompakt(gelesen),
        contains(_kompakt(de.jahresrueckblickTitel(jahr))),
        reason: 'Titel',
      );
      expect(
        _kompakt(gelesen),
        contains(_kompakt(de.jahresrueckblickUmfang(3, 2))),
        reason: 'Untertitel',
      );
      expect(
        farbname(farbe(titel, x0: 0.02, y0: 0.02, x1: 0.1, y1: 0.1)),
        'dunkel',
      );
      final folge = <String>[];
      for (var i = 0; i < 3; i++) {
        final t = 2.5 + 3.5 * i + 1.75;
        final b = await videobild(tester, mp4, t / dauer);
        folge.add(farbname(farbe(b)));
      }
      print('BEA-105 Bildfolge: $folge');
      expect(folge.toSet(), {'rot', 'gruen', 'blau'}, reason: 'alle Fotos');
      expect(folge, hasLength(3), reason: 'jedes Foto einmal, nacheinander');
      bea.beobachtung(
        'BEA-105',
        'Reihenfolge im Video: $folge (nach Datum: rot, gruen, blau)',
      );

      // BEA-106
      final aufz = mitschnitt();
      final ziel2 = bea.zielOrdner('mitmusik');
      final musik = wavDatei('ton_5s.wav');
      final vorher = (await bea.alleAufnahmen(tester)).length;
      bea.merkeMeldungen();
      await bea.tap(tester, find.byTooltip(de.diashowAlsVideo));
      await waitFor(tester, find.text(de.diashowMusikTitel));
      dialog.dateien = [musik];
      dialog.speichernUnter = ziel2.path;
      await bea.tap(tester, find.text(de.diashowMusikWaehlen));
      await bea.erwarteNeueMeldung(
        tester,
        de.flugVideoFertig('jahresrueckblick-$jahr.mp4'),
        timeout: _sehrLang,
      );
      final wahl = aufz.aufrufe.firstWhere((a) => a.weg.startsWith('pick'));
      print('BEA-106 Dateiwahl: ${wahl.weg} ${wahl.typ} ${wahl.endungen}');
      expect(wahl.typ, FileType.custom);
      expect(wahl.endungen?.toSet(), {
        'mp3',
        'm4a',
        'aac',
        'wav',
        'aif',
        'aiff',
        'flac',
      });
      expect(wahl.endungen, tonEndungen);
      final mitTon = File(p.join(ziel2.path, 'jahresrueckblick-$jahr.mp4'));
      final tonBytes = mitTon.readAsBytesSync();
      sichere('bea106_mit_musik.mp4', tonBytes);
      expect(bea.mp4HatTon(tonBytes), isTrue, reason: 'Tonspur');
      final dauer2 = bea.mp4Dauer(tonBytes)!;
      expect(dauer2, closeTo(dauer, 0.6), reason: 'endet mit dem Video');
      final pcm = await bea.lauf(
        tester,
        () => NativeImageConverter.videoTon(mitTon),
      );
      expect(pcm, isNotNull, reason: 'Tonspur lesbar');
      final h = huelle(pcm!);
      final tonDauer = pcm.length / 16000;
      final mitte = _median(h.sublist(15, math.min(h.length, 95)));
      double bei(double s) => h[math.min(h.length - 1, (s * 10).floor())];
      double schnitt(double von, double bis) {
        final w = h.sublist(
          (von * 10).floor(),
          math.min(h.length, (bis * 10).ceil()),
        );
        return w.reduce((a, b) => a + b) / w.length;
      }

      print(
        'BEA-106 Ton: Dauer $tonDauer s, Mitte $mitte, '
        'Anfang ${[for (var i = 0; i < 12; i++) (h[i] / mitte).toStringAsFixed(2)]}, '
        '5–6,5 s ${(schnitt(5.0, 6.5) / mitte).toStringAsFixed(2)}, '
        'Ende ${[for (var i = h.length - 32; i < h.length; i += 2) (h[i] / mitte).toStringAsFixed(2)]}',
      );
      expect(
        tonDauer,
        closeTo(dauer, 0.6),
        reason: 'Ton so lang wie das Video',
      );
      expect(mitte, greaterThan(1000), reason: 'hörbar');
      expect(
        bei(0.0),
        lessThan(0.3 * mitte),
        reason: 'Einblenden: leise am Anfang',
      );
      expect(bei(0.5), inInclusiveRange(0.2 * mitte, 0.85 * mitte));
      expect(bei(1.3), greaterThan(0.8 * mitte), reason: 'nach 1 s voll');
      expect(
        schnitt(5.2, 6.8),
        greaterThan(0.7 * mitte),
        reason: 'nach 5 s wiederholt (Musik ist 5 s lang)',
      );
      expect(
        bei(dauer - 3.6),
        greaterThan(0.75 * mitte),
        reason: 'vor dem Ausblenden',
      );
      expect(
        bei(dauer - 1.5),
        inInclusiveRange(0.2 * mitte, 0.8 * mitte),
        reason: 'mitten im Ausblenden',
      );
      expect(
        h.last,
        lessThan(0.25 * mitte),
        reason: 'am Ende ausgeblendet (3 s)',
      );
      expect((await bea.alleAufnahmen(tester)).length, vorher);
      expect(
        bibliothek.paths.root
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.toLowerCase().endsWith('.wav')),
        isEmpty,
        reason: 'Tondatei nicht in der Bibliothek',
      );
      expect(ids, hasLength(3));
      await bea.abschluss(tester);
    },
  );

  bea.testWidgets(
    'BEA-108 BEA-110 Diashow: Erinnerung nur aus Videos, bearbeitet und gesperrt',
    (tester) async {
      await startApp(tester);
      final heute = DateTime.now();
      DateTime vor(int jahre, int min) =>
          DateTime(heute.year - jahre, heute.month, heute.day, 14, min, 17);
      final videos = await importiereDirekt(tester, [
        fixture('video_5s.mp4'),
        fixture('video_hoch_3s.mov'),
      ]);
      for (var i = 0; i < videos.length; i++) {
        await bea.setzeAngaben(
          tester,
          videos[i],
          AssetsCompanion(
            fileCreatedAt: Value(vor(2, 23 + i)),
            datumGeschaetzt: const Value(false),
          ),
        );
      }
      final gemischt = await importiereDirekt(tester, [
        bea.grauFoto(
          'entw.jpg',
          wert: 60,
          breite: 640,
          hoehe: 480,
          datum: vor(3, 11),
        ),
        farbFoto('gesperrt.jpg', 220, 30, 30, datum: vor(3, 12)),
        farbFoto('normal.jpg', 30, 30, 220, datum: vor(3, 13)),
      ]);
      await bea.oeffneEntwickeln(tester, gemischt[0]);
      await bea.setzeRegler(tester, de.entwBelichtung, 3);
      await bea.entwSpeichern(tester);
      await bea.tresorEinrichten(tester);
      await bea.sperre(tester, gemischt[1]);
      final entwBild = img.decodeJpg(
        bea
            .datei(
              (await bea.aufnahme(tester, gemischt[0])).developedRelativePath!,
            )
            .readAsBytesSync(),
      )!;
      print('BEA-110 entwickelte Fassung: ${farbe(entwBild)}');

      // BEA-110 über die Zeile „vor 3 Jahren“ im Rückblick.
      await bea.alleSchliessen(tester);
      await openSection(tester, Hauptbereich.rueckblick);
      await waitFor(tester, find.text(de.erkundenVorJahren(3)), timeout: _lang);
      final ziel = bea.zielOrdner('gemischt');
      bea.merkeMeldungen();
      await bea.tap(tester, knopfFuerVorJahren(3));
      await bea.diashowOhneMusik(tester, ziel.path);
      await waitFor(tester, find.text(de.diashowWirdErstellt));
      expect(
        find.text(de.diashowUmfang(2)),
        findsOneWidget,
        reason: 'ohne das gesperrte Foto',
      );
      final datei = 'rueckblick-${heute.year - 3}.mp4';
      await bea.erwarteNeueMeldung(
        tester,
        de.flugVideoFertig(datei),
        timeout: _sehrLang,
      );
      final mp4 = File(p.join(ziel.path, datei));
      sichere('bea110_$datei', mp4.readAsBytesSync());
      final dauer = bea.mp4Dauer(mp4.readAsBytesSync())!;
      expect(dauer, closeTo(9.5, 1.0), reason: 'Titel + 2 Fotos');
      final folge = <String>[];
      final werte = <(double, double, double)>[];
      for (var i = 0; i < 2; i++) {
        final b = await videobild(tester, mp4, (2.5 + 3.5 * i + 1.75) / dauer);
        sichere('bea110_bild$i.jpg', img.encodeJpg(b));
        werte.add(farbe(b));
        folge.add(farbname(farbe(b)));
      }
      print('BEA-110 Bildfolge: $folge $werte');
      expect(folge, isNot(contains('rot')), reason: 'gesperrtes Foto fehlt');
      expect(folge, contains('blau'), reason: 'normales Foto');
      final grau = werte.firstWhere((w) => farbname(w) != 'blau');
      final hell = (grau.$1 + grau.$2 + grau.$3) / 3;
      expect(
        hell,
        greaterThan(130),
        reason: 'entwickelte Fassung (Original 60), gemessen $hell',
      );
      expect(
        (hell - (entwBild.getPixel(320, 240).r)).abs(),
        lessThan(45),
        reason: 'wie die gespeicherte Entwicklung',
      );

      // BEA-108: erst die Zeile „vor 2 Jahren“ im Rückblick (nur Videos),
      // dann dieselbe Gruppe in „Erinnerungen“.
      await bea.alleSchliessen(tester);
      await openSection(tester, Hauptbereich.rueckblick);
      await waitFor(tester, find.text(de.erkundenVorJahren(2)), timeout: _lang);
      final rufeVorher = dialog.gerufen.length;
      bea.merkeMeldungen();
      await bea.tap(tester, knopfFuerVorJahren(2));
      await bea.erwarteNeueMeldung(tester, de.diashowKeineFotos);
      expect(
        find.text(de.diashowMusikTitel),
        findsNothing,
        reason: 'kein Dialog',
      );
      expect(dialog.gerufen.length, rufeVorher);
      await bea.tapSichtbar(tester, find.text(de.erinnerungenUntertitel));
      await waitFor(tester, find.byType(ErinnerungenScreen));
      final gruppen = find.descendant(
        of: find.byType(ErinnerungenScreen),
        matching: bea.privat('_Gruppe'),
      );
      await waitFor(tester, gruppen, timeout: _lang);
      Finder? nurVideos;
      for (var i = 0; i < gruppen.evaluate().length; i++) {
        final dinge = ((tester.widget(gruppen.at(i)) as dynamic).dinge as List)
            .cast<AssetData>();
        print(
          'BEA-108 Gruppe ${(tester.widget(gruppen.at(i)) as dynamic).ueberschrift}: '
          '${dinge.map((d) => d.type).toList()}',
        );
        if (dinge.isNotEmpty && dinge.every((d) => d.type == 'VIDEO')) {
          nurVideos = gruppen.at(i);
        }
      }
      expect(nurVideos, isNotNull, reason: 'Gruppe nur aus Videos');
      final vorherRufe = dialog.gerufen.length;
      bea.merkeMeldungen();
      await bea.tap(
        tester,
        find.descendant(
          of: nurVideos!,
          matching: find.byTooltip(de.diashowAlsVideo),
        ),
      );
      await bea.erwarteNeueMeldung(tester, de.diashowKeineFotos);
      expect(
        find.text(de.diashowMusikTitel),
        findsNothing,
        reason: 'kein Dialog',
      );
      expect(dialog.gerufen.length, vorherRufe);
      await bea.abschluss(tester);
    },
  );
}

// ===========================================================================
// Collage, Export, Datenschutzexport, Austauschpaket
// ===========================================================================

/// Protokolliert jeden HTTP-Client, der entsteht.
class Netzprotokoll extends HttpOverrides {
  final clients = <String>[];
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    clients.add(StackTrace.current.toString().split('\n').take(8).join(' / '));
    return super.createHttpClient(context);
  }
}

void _exportTests() {
  bea.testWidgets(
    'BEA-122 Collage: Vorlage, Format, Hintergrund, Reihenfolge',
    (tester) async {
      await startApp(tester);
      final fotos = await importiereDirekt(tester, [
        farbFoto(
          'c_rot.jpg',
          220,
          30,
          30,
          breite: 400,
          hoehe: 300,
          datum: DateTime(2024, 4, 1, 10, 3),
        ),
        farbFoto(
          'c_gruen.jpg',
          30,
          200,
          30,
          breite: 400,
          hoehe: 300,
          datum: DateTime(2024, 4, 2, 10, 3),
        ),
        farbFoto(
          'c_blau.jpg',
          30,
          30,
          220,
          breite: 400,
          hoehe: 300,
          datum: DateTime(2024, 4, 3, 10, 3),
        ),
        farbFoto(
          'c_gelb.jpg',
          230,
          220,
          30,
          breite: 400,
          hoehe: 300,
          datum: DateTime(2024, 4, 4, 10, 3),
        ),
      ]);
      final tt = teilenTexte(tester.element(find.byType(HomeShell)));
      final shas = {
        for (final id in fotos)
          id: bea.sha(bea.datei((await bea.aufnahme(tester, id)).relativePath)),
      };
      await bea.waehleAus(tester, fotos);
      await bea.tap(tester, find.byTooltip(tt.collage));
      await waitFor(tester, find.byType(Collageseite));
      Uint8List? vorschauBytes() {
        for (final e
            in find
                .descendant(
                  of: find.byType(Collageseite),
                  matching: find.byType(Image),
                )
                .evaluate()) {
          final w = e.widget as Image;
          if (w.image is MemoryImage) return (w.image as MemoryImage).bytes;
        }
        return null;
      }

      Future<img.Image> neueVorschau(String? alt, String was) async {
        await eventually(
          tester,
          () async {
            final b = vorschauBytes();
            return b != null && bea.shaBytes(b) != alt;
          },
          timeout: _lang,
          was: was,
        );
        await bea.warte(tester, const Duration(milliseconds: 600));
        return img.decodeImage(vorschauBytes()!)!;
      }

      await eventually(
        tester,
        () async => vorschauBytes() != null,
        timeout: _lang,
      );
      String stand() => bea.shaBytes(vorschauBytes()!);
      final v0 = stand();
      // Vorlage: erst eine andere, dann „Raster“.
      final andere = find.byWidgetPredicate(
        (w) =>
            w is Tooltip &&
            w.message != tt.collageRaster &&
            [
              tt.collageGrossLinks,
              tt.collageGrossOben,
              tt.collageReihe,
              tt.collageStapel,
            ].contains(w.message),
      );
      await bea.tap(tester, andere);
      await neueVorschau(v0, 'Vorschau folgt der Vorlage');
      final v1 = stand();
      await bea.tap(tester, find.byTooltip(tt.collageRaster));
      await neueVorschau(v1, 'zurück zum Raster');
      // Format: erst Quer, dann Quadrat.
      final vq = stand();
      await bea.tap(tester, find.text(tt.collageQuer));
      final quer = await neueVorschau(vq, 'Quer');
      print('BEA-122 Vorschau Quer ${quer.width}×${quer.height}');
      expect(quer.width, greaterThan(quer.height + 10));
      final vq2 = stand();
      await bea.tap(tester, find.text(tt.collageQuadrat));
      final quadrat = await neueVorschau(vq2, 'Quadrat');
      print('BEA-122 Vorschau Quadrat ${quadrat.width}×${quadrat.height}');
      expect((quadrat.width - quadrat.height).abs(), lessThanOrEqualTo(2));
      // Abstand, Ecken.
      final vorAbstand = stand();
      final regler = find.descendant(
        of: find.byType(Collageseite),
        matching: find.byType(Slider),
      );
      tester.widget<Slider>(regler.at(0)).onChanged!(0.05);
      await bea.settle(tester);
      tester.widget<Slider>(regler.at(1)).onChanged!(0.1);
      await bea.settle(tester);
      await neueVorschau(vorAbstand, 'Abstand und Ecken');
      // Hintergrund schwarz.
      final schwarz = find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).shape == BoxShape.circle &&
            (w.decoration as BoxDecoration).color == const Color(0xFF000000),
      );
      final vorFarbe = stand();
      await bea.tap(tester, schwarz);
      final mitGrund = await neueVorschau(vorFarbe, 'Hintergrund');
      final luecke = farbe(mitGrund, x0: 0.495, y0: 0.2, x1: 0.505, y1: 0.3);
      print('BEA-122 Lücke zwischen den Feldern: $luecke');
      expect(farbname(luecke), 'dunkel', reason: 'Hintergrund in der Lücke');
      final obenLinks0 = farbname(
        farbe(mitGrund, x0: 0.2, y0: 0.2, x1: 0.3, y1: 0.3),
      );
      // Reihenfolge: das dritte Foto (blau) nach vorn.
      final vorReihe = stand();
      await bea.tap(tester, find.byKey(ValueKey('collage-${fotos[2]}')));
      final umsortiert = await neueVorschau(vorReihe, 'Reihenfolge');
      final obenLinks = farbname(
        farbe(umsortiert, x0: 0.2, y0: 0.2, x1: 0.3, y1: 0.3),
      );
      print('BEA-122 oben links vorher $obenLinks0, nachher $obenLinks');
      expect(obenLinks, 'blau', reason: 'angetipptes Foto steht vorn');
      // Speichern.
      await bea.tap(tester, find.widgetWithText(FilledButton, tt.speichern));
      await waitFor(
        tester,
        find.text(tt.collageGespeichert),
        timeout: _sehrLang,
      );
      final alle = await bea.alleAufnahmen(tester);
      final neu = alle.where((a) => !fotos.contains(a.id)).toList();
      expect(neu, hasLength(1), reason: 'ein neues Foto');
      expect(
        neu.single.fileCreatedAt,
        (await bea.aufnahme(tester, fotos.last)).fileCreatedAt,
        reason: 'Datum des jüngsten Quellfotos',
      );
      final collage = img.decodeImage(
        bea.datei(neu.single.relativePath).readAsBytesSync(),
      )!;
      sichere('bea122_collage.jpg', img.encodeJpg(collage));
      print('BEA-122 Collage ${collage.width}×${collage.height}');
      expect((collage.width - collage.height).abs(), lessThanOrEqualTo(2));
      expect(
        farbname(farbe(collage, x0: 0.2, y0: 0.2, x1: 0.3, y1: 0.3)),
        'blau',
      );
      expect(
        farbname(farbe(collage, x0: 0.495, y0: 0.2, x1: 0.505, y1: 0.3)),
        'dunkel',
      );
      for (final id in fotos) {
        expect(
          bea.sha(bea.datei((await bea.aufnahme(tester, id)).relativePath)),
          shas[id],
        );
      }
      await bea.abschluss(tester);
    },
  );

  bea.testWidgets(
    'BEA-130 Export: 500 Fotos, Zählung, Oberfläche bleibt flüssig',
    (tester) async {
      await startApp(tester);
      final ids = await importiereDirekt(tester, [
        for (var i = 0; i < 500; i++)
          bea.grauFoto(
            'e$i.jpg',
            wert: 30 + i % 200,
            breite: 1200,
            hoehe: 800,
            datum: DateTime(2020, 2, 2, 6 + i ~/ 60, i % 60, 9),
          ),
      ]);
      expect(ids, hasLength(500));
      await bea.waehleBereich(tester, ids.first, ids.last, 500);
      dialog.ordner = null;
      bea.merkeMeldungen();
      await bea.exportWaehlen(tester, de.exportUnveraendert);
      await bea.settle(tester);
      expect(bea.neueMeldungen(), isEmpty, reason: 'Abbruch: nichts passiert');
      expect(find.byType(AlertDialog), findsNothing);

      final ziel = bea.zielOrdner('fuenfhundert');
      await bea.waehleBereich(tester, ids.first, ids.last, 500);
      dialog.ordner = ziel.path;
      bea.merkeMeldungen();
      // Ohne das settle von `tap`: Darin liefe der ganze Export durch,
      // bevor die Zählung beobachtet wird (so in der ersten Runde).
      await bea.tap(tester, find.byTooltip(de.auswExportieren));
      await waitFor(tester, find.text(de.exportUnveraendert));
      await tester.tap(find.text(de.exportUnveraendert));
      final laeuft = bea.vorlage(de.auswExportiereLaeuft(111, 999), [111, 999]);
      final staende = <int>[];
      var gesamt = 0;
      var laengstes = Duration.zero;
      final uhr = Stopwatch()..start();
      final ende = DateTime.now().add(_sehrLang);
      while (DateTime.now().isBefore(ende)) {
        final vor = uhr.elapsed;
        await tester.pump();
        final dauer = uhr.elapsed - vor;
        if (dauer > laengstes) laengstes = dauer;
        for (final e in find.byType(Text).evaluate()) {
          final m = laeuft.firstMatch((e.widget as Text).data ?? '');
          if (m != null) {
            final n = int.parse(m.group(1)!);
            gesamt = int.parse(m.group(2)!);
            if (staende.isEmpty || staende.last != n) staende.add(n);
          }
        }
        if (bea.hatNeueMeldung(de.auswExportFertig(500, 500, ziel.path))) break;
      }
      print(
        'BEA-130 Zählerstände (${staende.length}): ${staende.take(40).toList()} … ${staende.isEmpty ? '' : staende.last}, '
        'gesamt $gesamt, längstes Bild ${laengstes.inMilliseconds} ms',
      );
      expect(
        bea.hatNeueMeldung(de.auswExportFertig(500, 500, ziel.path)),
        isTrue,
      );
      expect(gesamt, 500);
      expect(staende.length, greaterThanOrEqualTo(5), reason: 'zählt hoch');
      for (var i = 1; i < staende.length; i++) {
        expect(staende[i], greaterThan(staende[i - 1]), reason: 'steigend');
      }
      expect(staende.last, greaterThanOrEqualTo(450));
      expect(
        laengstes.inMilliseconds,
        lessThan(1500),
        reason: 'Oberfläche flüssig',
      );
      expect(bea.dateienIn(ziel), hasLength(1000), reason: 'Fotos + XMP');
      await bea.abschluss(tester);
    },
  );

  // Behoben in #420: Der Datenschutzexport entfernt den EXIF- und den
  // IPTC-Block, den ImageIO beim Kodieren anlegt; das JPEG trägt kein EXIF
  // mehr.
  bea.testWidgets('BEA-139 Datenschutzexport ohne EXIF, GPS und XMP', (
    tester,
  ) async {
    await startApp(tester);
    final ids = await importiereDirekt(tester, [
      bea.grauFoto(
        'privat.jpg',
        wert: 120,
        breite: 6000,
        hoehe: 4000,
        datum: DateTime(2022, 5, 5, 10, 4),
        kamera: 'Testkamera',
        modell: 'T1',
        breitengrad: 47.42,
        laengengrad: 10.98,
      ),
    ]);
    await bea.befehl(tester, SchlagwortAnheften([ids[0]], 'Zuhause'));
    await bea.befehl(tester, BeschreibungSetzen([ids[0]], 'Privat'));
    final ziel = bea.zielOrdner('datenschutz');
    await bea.waehleAus(tester, [ids[0]]);
    dialog.ordner = ziel.path;
    bea.merkeMeldungen();
    await bea.exportWaehlen(tester, de.datenschutzExportTitel);
    await bea.erwarteNeueMeldung(
      tester,
      de.auswExportFertig(1, 1, ziel.path),
      timeout: _sehrLang,
    );
    final aus = bea.dateienIn(ziel);
    expect(aus, hasLength(1), reason: 'nur ein JPEG, keine Beilage');
    expect(aus.single.path, endsWith('.jpg'));
    final bytes = aus.single.readAsBytesSync();
    sichere('bea139_datenschutz.jpg', bytes);
    final b = img.decodeJpg(bytes)!;
    expect(math.max(b.width, b.height), lessThanOrEqualTo(2048));
    expect(b.exif.gpsIfd.isEmpty, isTrue, reason: 'kein GPS');
    expect(b.exif.imageIfd['Make'], isNull);
    expect(b.exif.imageIfd['ImageDescription'], isNull);
    expect(b.exif.exifIfd['DateTimeOriginal'], isNull);
    expect(
      bea.enthaelt(bytes, ascii.encode('http://ns.adobe.com/xap')),
      isFalse,
    );
    expect(bea.enthaelt(bytes, ascii.encode('Testkamera')), isFalse);
    expect(bea.enthaelt(bytes, ascii.encode('Zuhause')), isFalse);
    expect(bea.enthaelt(bytes, ascii.encode('Privat')), isFalse);
    final tags = <String>[
      for (final ifd in b.exif.directories.entries)
        for (final t in ifd.value.data.keys)
          '${ifd.key}:0x${t.toRadixString(16)}',
    ];
    print(
      'BEA-139 EXIF-Segment: ${bea.hatExifSegment(bytes)}, Einträge: $tags, '
      'Exif-Verzeichnis: ${[for (final e in b.exif.exifIfd.data.entries) '0x${e.key.toRadixString(16)}=${e.value}']}',
    );
    expect(bea.hatExifSegment(bytes), isFalse, reason: 'ohne EXIF');
    await bea.abschluss(tester);
  });

  bea.testWidgets(
    'BEA-140 Datenschutzexport: Gesicht und Kennzeichen, kein Netz',
    (tester) async {
      await startApp(tester);
      final ids = await importiereDirekt(tester, [
        bea.jpegAus(
          'gesicht.jpg',
          bea.schachbrett(1200, 900),
          datum: DateTime(2022, 5, 6, 10, 4),
        ),
      ]);
      await bea.gesichtFuer(tester, ids[0], 'Person A', (0.1, 0.1, 0.25, 0.3));
      await bea.setzeAngaben(
        tester,
        ids[0],
        AssetsCompanion(
          ocrBoxen: Value(
            textstellenNachJson([
              const Textstelle(
                text: 'M AB 1234',
                links: 0.6,
                oben: 0.7,
                breite: 0.3,
                hoehe: 0.1,
              ),
            ]),
          ),
        ),
      );
      expect(bibliothek.verbunden, isFalse);
      final ziel = bea.zielOrdner('gesicht');
      await bea.waehleAus(tester, [ids[0]]);
      dialog.ordner = ziel.path;
      final netz = Netzprotokoll();
      final vorher = HttpOverrides.current;
      HttpOverrides.global = netz;
      try {
        bea.merkeMeldungen();
        await bea.exportWaehlen(tester, de.datenschutzExportTitel);
        await bea.erwarteNeueMeldung(
          tester,
          de.auswExportFertig(1, 1, ziel.path),
          timeout: _sehrLang,
        );
      } finally {
        HttpOverrides.global = vorher;
      }
      print('BEA-140 HTTP-Clients während des Exports: ${netz.clients}');
      expect(netz.clients, isEmpty, reason: 'kein Netzzugriff');
      final bytes = bea.dateienIn(ziel).single.readAsBytesSync();
      sichere('bea140_gesicht.jpg', bytes);
      final g = img.decodeJpg(bytes)!;
      double streuungIn(double x0, double y0, double x1, double y1) =>
          bea.streuung(
            img.copyCrop(
              g,
              x: (x0 * g.width).round(),
              y: (y0 * g.height).round(),
              width: ((x1 - x0) * g.width).round(),
              height: ((y1 - y0) * g.height).round(),
            ),
          );
      final gesicht = streuungIn(0.15, 0.15, 0.3, 0.35);
      final rand = streuungIn(0.07, 0.07, 0.09, 0.09);
      final kennzeichen = streuungIn(0.65, 0.72, 0.85, 0.78);
      final rest = streuungIn(0.45, 0.3, 0.55, 0.5);
      print(
        'BEA-140 Streuung Gesicht $gesicht, Rand $rand, Kennzeichen $kennzeichen, Rest $rest',
      );
      expect(gesicht, lessThan(rest * 0.5), reason: 'Gesicht weichgezeichnet');
      expect(rand, lessThan(rest * 0.5), reason: 'mit Rand um das Gesicht');
      expect(kennzeichen, lessThan(rest * 0.5), reason: 'Kennzeichen weich');
      expect(rest, greaterThan(60), reason: 'Rest scharf');
      await bea.abschluss(tester);
    },
  );

  bea.testWidgets(
    'BEA-145 Austauschpaket mit Ablaufdatum, nach dem Ablauf geöffnet',
    (tester) async {
      final draussen = Directory.systemTemp.createTempSync('pv_r2_paket_');
      addTearDown(() {
        try {
          draussen.deleteSync(recursive: true);
        } catch (_) {}
      });
      await startApp(tester);
      final ids = await importiereDirekt(tester, [
        testfoto('p1.jpg'),
        testfoto('p2.jpg'),
      ]);
      await bea.waehleAus(tester, ids);
      await bea.exportWaehlen(tester, de.sicherTeilenTitel);
      await bea.passphraseEingeben(tester, 'richtig-geheim', 'richtig-geheim');
      await bea.tap(tester, find.text(de.sicherTeilenAblaufSetzen));
      await waitFor(tester, find.byType(DatePickerDialog));
      final jetzt = DateTime.now();
      final morgen = DateTime(jetzt.year, jetzt.month, jetzt.day + 1);
      final erstes = tester
          .widget<DatePickerDialog>(find.byType(DatePickerDialog))
          .firstDate;
      expect(DateTime(erstes.year, erstes.month, erstes.day), morgen);
      expect(find.text(de.sicherTeilenAblaufDatum), findsOneWidget);
      dialog.speichernUnter = draussen.path;
      bea.merkeMeldungen();
      await per.datumEingeben(tester, morgen);
      await bea.erwarteNeueMeldung(
        tester,
        de.sicherTeilenFertig(p.join(draussen.path, de.sicherTeilenDateiname)),
        timeout: _sehrLang,
      );
      final paket = File(p.join(draussen.path, de.sicherTeilenDateiname));
      expect(paket.existsSync(), isTrue);
      // Ein zweites, schon abgelaufenes Paket für den Weg über die
      // Oberfläche (deren Uhr ist die echte).
      final abgelaufen = File(p.join(draussen.path, 'abgelaufen.pvshare'));
      final assets = [for (final id in ids) await bea.aufnahme(tester, id)];
      await bea.lauf(
        tester,
        () =>
            SecureShareService(
              ExportService(bibliothek.paths, library: bibliothek),
              now: () => DateTime.now().subtract(const Duration(days: 3)),
            ).createPackage(
              assets,
              abgelaufen,
              'richtig-geheim',
              expiresAt: DateTime.now().subtract(const Duration(days: 1)),
            ),
      );
      await bea.abschluss(tester);

      // Zweite Wegwerf-Bibliothek.
      await startApp(tester);
      final vorher = bea.shareTempOrdner();
      // Das per Oberfläche erstellte Paket mit vorgestellter Uhr: einen Tag
      // nach dem gewählten Tag. Die Frist gilt bis Mitternacht UTC nach dem
      // gewählten Tag (lib/widgets/selection_action_bar.dart:1205).
      final ablauf = DateTime.utc(morgen.year, morgen.month, morgen.day + 1);
      Object? fehler;
      await tester.runAsync(() async {
        try {
          await SecureShareService(
            ExportService(bibliothek.paths, library: bibliothek),
            now: () => ablauf.add(const Duration(hours: 1)),
          ).importPackage(paket, 'richtig-geheim', bibliothek.importService);
        } catch (e) {
          fehler = e;
        }
      });
      print('BEA-145 Paket nach dem Ablauf: $fehler');
      expect(fehler, isA<SharePackageExpired>());
      expect((fehler! as SharePackageExpired).expiresAt, ablauf);
      expect(await bea.alleAufnahmen(tester), isEmpty);
      // Über die Oberfläche: „Austauschpaket öffnen“ mit einem Paket, dessen
      // Frist schon um ist (die Oberfläche nimmt die echte Uhr).
      bea.merkeMeldungen();
      await bea.alleSchliessen(tester);
      await openSection(tester, Hauptbereich.werkzeuge);
      dialog.dateien = [abgelaufen];
      await bea.tapSichtbar(tester, find.text(de.sicherTeilenImportTitel));
      await waitFor(tester, find.text(de.sicherTeilenImportPassphrase));
      await enter(tester, field(de.passphraseFeld), 'richtig-geheim');
      await bea.tap(tester, bea.inDialog(find.text('OK')));
      await bea.erwarteNeueMeldung(
        tester,
        de.sicherTeilenImportAbgelaufen,
        timeout: _sehrLang,
      );
      expect(await bea.alleAufnahmen(tester), isEmpty);
      expect(
        bea.shareTempOrdner().difference(vorher),
        isEmpty,
        reason: 'keine Klartextdateien',
      );
      // Gegenprobe: dasselbe per Oberfläche erstellte Paket eine Stunde vor
      // dem Ablauf wird eingelesen.
      final eingelesen = await bea.lauf(
        tester,
        () => SecureShareService(
          ExportService(bibliothek.paths, library: bibliothek),
          now: () => ablauf.subtract(const Duration(hours: 1)),
        ).importPackage(paket, 'richtig-geheim', bibliothek.importService),
      );
      print('BEA-145 Gegenprobe vor dem Ablauf: ${eingelesen.imported}');
      expect(eingelesen.imported, 2);
      await bea.abschluss(tester);
    },
  );
}

// ===========================================================================
// Personen
// ===========================================================================

const _gesichtsmodelle = [
  'face_detection_yunet.onnx',
  'face_recognition_sface.onnx',
];

Finder imSanduhr(String n) =>
    find.descendant(of: find.byType(SanduhrAnsicht), matching: find.text(n));

Finder segment(String text) => find.descendant(
  of: find.byWidgetPredicate((w) => w is SegmentedButton),
  matching: find.text(text),
);

void _personenTests() {
  per.pruefung(
    'PER-034 Echte Gesichter: gelöschte kommen wieder, ignorierte nicht',
    (tester) async {
      await per.start(tester, modelle: _gesichtsmodelle);
      final f = await per.fotos(tester, [
        mlFixture('gesichter/person_a_1.jpg', name: 'pa1.jpg'),
        mlFixture('gesichter/person_b_1.jpg', name: 'pb1.jpg'),
      ]);
      final fa = f['pa1.jpg']!.id, fb = f['pb1.jpg']!.id;
      String zeige(List<FaceData> l) => [
        for (final g in l)
          '${g.assetId == fa ? 'A' : 'B'}:${g.isIgnored ? 'ign' : (g.personId == null ? 'offen' : 'benannt')}:'
              '${g.boxX.toStringAsFixed(2)},${g.boxY.toStringAsFixed(2)}',
      ].join(' ');
      Future<void> scanAlle() async {
        await per.aufgabeStarten(
          tester,
          de.werkzGesichterScannenTitel,
          de.aufgModusAlle,
        );
        await per.warteAufLauf(tester, 'gesichter');
      }

      await scanAlle();
      var alle = await per.alleGesichter(tester);
      print('PER-034 erster Scan: ${zeige(alle)}');
      final ersteA = alle.where((g) => g.assetId == fa).toList();
      final ersteB = alle.where((g) => g.assetId == fb).toList();
      expect(ersteA, isNotEmpty, reason: 'YuNet findet das Gesicht auf A');
      expect(ersteB, isNotEmpty, reason: 'YuNet findet das Gesicht auf B');

      // Löschen: „Alle unbenannten Erkennungen löschen“.
      await per.personenOeffnen(tester, reiterName: de.personenUnbenannteTab);
      await per.rechtsklick(tester, per.kacheln);
      await per.klick(tester, find.text(de.personenAlleErkennungenLoeschen));
      expect(
        find.text(de.personenErkennungenLoeschenText),
        findsOneWidget,
        reason: 'die Rückfrage sagt: auch die ignorierten, nicht dauerhaft',
      );
      await per.klick(tester, per.imDialog(find.text(de.allgLoeschen)));
      await per.erwarteText(
        tester,
        de.personenErkennungenGeloeschtMeldung(alle.length),
      );
      expect(await per.alleGesichter(tester), isEmpty);
      // Erneut scannen: Die gelöschten kommen wieder.
      await scanAlle();
      alle = await per.alleGesichter(tester);
      print('PER-034 nach dem Löschen gescannt: ${zeige(alle)}');
      final wiederA = alle.where((g) => g.assetId == fa).toList();
      final wiederB = alle.where((g) => g.assetId == fb).toList();
      expect(wiederB, hasLength(ersteB.length), reason: 'kommt wieder');
      expect(wiederA, hasLength(ersteA.length), reason: 'kommt wieder');
      expect(
        (wiederB.first.boxX - ersteB.first.boxX).abs() +
            (wiederB.first.boxY - ersteB.first.boxY).abs(),
        lessThan(0.02),
        reason: 'an derselben Stelle',
      );
      expect(wiederB.every((g) => !g.isIgnored && g.personId == null), isTrue);
      await per.personenOeffnen(tester, reiterName: de.personenUnbenannteTab);
      await waitFor(tester, per.kachel(wiederB.first.id));
      // Ignorieren (über die Oberfläche) und noch einmal scannen.
      await per.waehle(tester, [for (final g in wiederA) g.id]);
      await per.klick(tester, find.byTooltip(de.personenIgnorierenTooltip));
      await per.erwarteText(
        tester,
        de.personenIgnoriertMeldung(wiederA.length),
      );
      await scanAlle();
      alle = await per.alleGesichter(tester);
      print('PER-034 nach Ignorieren gescannt: ${zeige(alle)}');
      for (final g in wiederA) {
        final jetzt = alle.where((x) => x.id == g.id).toList();
        expect(jetzt, hasLength(1), reason: 'ignoriertes bleibt erhalten');
        expect(jetzt.single.isIgnored, isTrue, reason: 'bleibt ignoriert');
      }
      expect(
        alle.where((g) => g.assetId == fa && !g.isIgnored),
        isEmpty,
        reason: 'kommt nicht als unbenanntes wieder',
      );
      final offenB = alle
          .where((g) => g.assetId == fb && !g.isIgnored && g.personId == null)
          .toList();
      expect(offenB, hasLength(ersteB.length));
      // In der Oberfläche.
      await per.personenOeffnen(tester, reiterName: de.personenUnbenannteTab);
      await waitFor(tester, per.kachel(offenB.first.id));
      expect(per.kachel(wiederA.first.id), findsNothing);
      await per.klick(tester, per.reiter(de.personenIgnoriertTab));
      await waitFor(tester, per.kachel(wiederA.first.id));
      expect(per.kachel(offenB.first.id), findsNothing);
      await finish(tester);
    },
  );

  per.pruefung('PER-062 Weitere Fotos suchen: gesperrter Knopf mit Kreisel', (
    tester,
  ) async {
    await per.start(tester);
    final f = await per.fotos(tester, per.bilder('pv', 9));
    String id(int i) => f['pv$i.jpg']!.id;
    final vorschlaege = <String>[];
    await tester.runAsync(() async {
      final a = await per.person('Person A');
      for (var i = 1; i <= 3; i++) {
        await per.gesicht(id(i), person: a, vektor: per.richtung(1));
      }
      vorschlaege.add(
        await per.gesicht(id(4), vektor: per.vek({1: 1, 2: 0.1})),
      );
      vorschlaege.add(
        await per.gesicht(id(5), vektor: per.vek({1: 1, 3: 0.15})),
      );
      vorschlaege.add(
        await per.gesicht(id(6), vektor: per.vek({1: 1, 4: 0.2})),
      );
      vorschlaege.add(
        await per.gesicht(id(7), vektor: per.vek({1: 0.6, 5: 0.8})),
      );
      await per.gesicht(id(8), vektor: per.richtung(30));
      // Viele fremde Gesichter, damit die Suche messbar dauert.
      final aus = per.gemeinsamerAusschnitt('viele');
      final zeilen = [
        for (var i = 0; i < 20000; i++)
          per.gesichtszeile(
            id(9),
            aus,
            vektor: per.vek({40 + i % 80: 1, 121 + i % 7: 0.3}),
          ),
      ];
      for (var i = 0; i < zeilen.length; i += 2000) {
        await per.vieleGesichter(zeilen.sublist(i, i + 2000));
      }
    });
    await per.personenOeffnen(tester);
    await per.klick(tester, find.text('Person A'));
    await waitFor(tester, find.byType(PersonDetailScreen));
    await per.warte(tester, 500);
    Finder suchen() => find.ancestor(
      of: find.text(de.personWeitereFotosSuchen),
      matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
    );
    expect(tester.widget<ButtonStyleButton>(suchen().first).enabled, isTrue);
    await tester.tap(suchen().first);
    var gesperrt = false, kreisel = false, bilder = 0;
    final uhr = Stopwatch()..start();
    while (uhr.elapsed < const Duration(seconds: 30)) {
      await tester.pump();
      bilder++;
      if (find.byType(PersonSuggestionsScreen).evaluate().isNotEmpty) break;
      final k = suchen();
      if (k.evaluate().isEmpty) continue;
      if (!tester.widget<ButtonStyleButton>(k.first).enabled) {
        gesperrt = true;
        kreisel |= find
            .descendant(
              of: k.first,
              matching: find.byType(CircularProgressIndicator),
            )
            .evaluate()
            .isNotEmpty;
      }
    }
    print(
      'PER-062 gesperrt $gesperrt, Kreisel $kreisel, nach $bilder Bildern, ${uhr.elapsedMilliseconds} ms',
    );
    expect(gesperrt, isTrue, reason: 'Knopf während der Suche gesperrt');
    expect(kreisel, isTrue, reason: 'mit Kreisel');
    await waitFor(tester, find.byType(PersonSuggestionsScreen), timeout: _lang);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text(de.vorschlagTitel('Person A')),
      ),
      findsOneWidget,
    );
    expect(per.kacheln, findsNWidgets(4));
    for (final v in vorschlaege) {
      expect(per.ausgewaehlt(tester, v), isTrue);
    }
    expect(find.textContaining(RegExp(r'^[01]\.\d\d$')), findsNWidgets(4));
    expect(find.text(de.vorschlagUebernehmen(4)), findsOneWidget);
    await finish(tester);
  });

  per.pruefung(
    'PER-075 Ähnlichkeitsschwelle: 0.50 nach Neustart, weniger mit ausgewählt',
    (tester) async {
      await per.start(tester);
      final f = await per.fotos(tester, per.bilder('ws', 5));
      String id(int i) => f['ws$i.jpg']!.id;
      late String ref, h1, h2;
      await tester.runAsync(() async {
        final a = await per.person('Person A');
        await per.gesicht(id(1), person: a, vektor: per.richtung(1));
        ref = await per.gesicht(id(3), vektor: per.richtung(40));
        h1 = await per.gesicht(id(4), vektor: per.vek({40: 0.9, 41: 0.436}));
        h2 = await per.gesicht(id(5), vektor: per.vek({40: 0.42, 42: 0.907}));
      });
      Future<int> mitAusgewaehlt() async {
        await per.personenOeffnen(tester, reiterName: de.personenUnbenannteTab);
        await per.waehle(tester, [ref]);
        await per.klick(tester, find.text(de.personenAehnlicheAuswaehlen));
        await per.warte(tester, 400);
        return [h1, h2].where((x) => per.ausgewaehlt(tester, x)).length;
      }

      expect(await mitAusgewaehlt(), 2);
      Future<Finder> reglerOeffnen() async {
        await openSection(tester, Hauptbereich.alben);
        await openSection(tester, Hauptbereich.werkzeuge);
        await scrollTo(
          tester,
          find.text(de.werkzAbschnittGesichtserkennung),
          in_: per.werkzeugListe(),
        );
        return find.byWidgetPredicate(
          (w) => w is Slider && w.min == 0.15 && w.max == 0.6,
        );
      }

      final reglerFinder = await reglerOeffnen();
      expect(find.text('0.36'), findsOneWidget);
      final rect = tester.getRect(reglerFinder);
      Future<double> tippeBei(double anteil) async {
        await tester.tapAt(
          Offset(rect.left + rect.width * anteil, rect.center.dy),
        );
        await per.warte(tester, 300);
        return bibliothek.faceSimilarityThreshold;
      }

      final w1 = await tippeBei(0.25);
      final w2 = await tippeBei(0.85);
      final anteil = 0.25 + (0.5 - w1) / (w2 - w1) * 0.6;
      await tippeBei(anteil);
      for (
        var i = 0;
        i < 3 && (bibliothek.faceSimilarityThreshold - 0.5).abs() > 0.001;
        i++
      ) {
        final schritt = bibliothek.faceSimilarityThreshold < 0.5
            ? 0.012
            : -0.012;
        await tippeBei(anteil + schritt * (i + 1));
      }
      expect(bibliothek.faceSimilarityThreshold, closeTo(0.5, 0.001));
      expect(find.text('0.50'), findsOneWidget);
      // Neustart: neuer Widgetbaum, neue Bibliothek aus derselben Datenbank.
      final alteBibliothek = bibliothek;
      await bea.neustart(tester);
      expect(
        identical(bibliothek, alteBibliothek),
        isFalse,
        reason: 'neu gestartet',
      );
      expect(bibliothek.faceSimilarityThreshold, closeTo(0.5, 0.001));
      final nachNeustart = await reglerOeffnen();
      expect(tester.widget<Slider>(nachNeustart).value, closeTo(0.5, 0.001));
      expect(find.text('0.50'), findsOneWidget, reason: 'Wert steht daneben');
      expect(await mitAusgewaehlt(), 1, reason: 'höhere Schwelle, weniger');
      await finish(tester);
    },
  );

  per.pruefung('PER-097 Gesperrtes Foto in der Reihe der Gesichter-Ansicht', (
    tester,
  ) async {
    await per.start(tester);
    final f = await per.fotos(tester, per.bilder('gs', 2));
    final offen = f['gs1.jpg']!, zu = f['gs2.jpg']!;
    await tester.runAsync(() async {
      final a = await per.person('Person A');
      await per.gesicht(offen.id, person: a);
      await per.gesicht(zu.id, person: a);
      await bibliothek.setupVaultPin('4711');
      await bibliothek.lockAsset(zu);
    });
    // Die Personenansicht lässt das gesperrte Foto weg – die Oberfläche
    // baut keine Reihe mit Gesperrtem. Die Ansicht wird darum direkt mit
    // einer solchen Reihe geöffnet.
    await per.personenOeffnen(tester);
    await per.klick(tester, find.text('Person A'));
    final detail = find.descendant(
      of: find.byType(PersonDetailScreen),
      matching: find.byType(AssetThumbnailTile),
    );
    await waitFor(tester, detail);
    expect(detail, findsOneWidget, reason: 'Personenansicht ohne Gesperrtes');
    final gesperrt = await per.assetZeile(tester, zu.id);
    final offeneZeile = await per.assetZeile(tester, offen.id);
    expect(gesperrt.isLocked, isTrue);
    unawaited(
      Navigator.of(tester.element(find.byType(HomeShell))).push(
        MaterialPageRoute<void>(
          builder: (_) => FaceReviewScreen(
            library: bibliothek,
            assets: [offeneZeile, gesperrt],
          ),
        ),
      ),
    );
    await waitFor(tester, find.text(de.gesichtPosition(1, 2)));
    await per.taste(tester, LogicalKeyboardKey.arrowRight);
    await waitFor(tester, find.text(de.gesichtGesperrt));
    expect(find.byType(Gesichtsrahmen), findsNothing);
    for (final t in [
      de.gesichtRahmenAusblenden,
      de.gesichtManuellHinzufuegen,
      de.viewerFavoritSetzen,
      de.viewerInGesperrtenOrdner,
      de.viewerInfo,
      de.gesichtFotoLoeschen,
    ]) {
      expect(find.byTooltip(t), findsNothing, reason: t);
    }
    expect(per.symbolknopf(tester, de.gesichtVoriges).onPressed, isNotNull);
    await per.klick(tester, find.byTooltip(de.gesichtVoriges));
    await waitFor(tester, find.text(de.gesichtPosition(1, 2)));
    expect(find.text(de.gesichtGesperrt), findsNothing);
    expect(find.byType(Gesichtsrahmen), findsWidgets);
    await finish(tester);
  });

  per.pruefung(
    'PER-098 Gesichter bearbeiten aus der Vollbildansicht: Foto, Video, gesperrt',
    (tester) async {
      await per.start(tester);
      final f = await per.fotos(tester, [
        ...per.bilder('vb', 3),
        fixture('video_5s.mp4'),
      ]);
      final video = f['video_5s.mp4']!;
      await tester.runAsync(() async {
        final a = await per.person('Person A');
        await per.gesicht(f['vb1.jpg']!.id, person: a);
        await per.gesicht(f['vb2.jpg']!.id, person: a);
        await per.gesicht(video.id, person: a);
      });
      await per.personenOeffnen(tester);
      await per.klick(tester, find.text('Person A'));
      Finder kachelVon(String assetId) => find.byWidgetPredicate(
        (w) => w is AssetThumbnailTile && w.asset.id == assetId,
      );
      await waitFor(tester, kachelVon(f['vb1.jpg']!.id));
      final reihe = [
        for (final k in tester.widgetList<AssetThumbnailTile>(
          find.descendant(
            of: find.byType(PersonDetailScreen),
            matching: find.byType(AssetThumbnailTile),
          ),
        ))
          k.asset.id,
      ];
      final stelle = reihe.indexOf(f['vb1.jpg']!.id);
      await per.tippe(tester, kachelVon(f['vb1.jpg']!.id));
      await waitFor(tester, find.byType(AssetViewerScreen));
      await per.warte(tester, 800);
      await per.rechtsklick(tester, find.byType(PageView));
      await per.klick(tester, find.text(de.viewerGesichterBearbeiten));
      await waitFor(tester, find.byType(FaceReviewScreen));
      await waitFor(
        tester,
        find.text(de.gesichtPosition(stelle + 1, reihe.length)),
      );
      expect(
        find.descendant(
          of: find.byType(FaceReviewScreen),
          matching: find.text('vb1.jpg'),
        ),
        findsOneWidget,
      );
      await per.taste(tester, LogicalKeyboardKey.escape);
      await waitGone(tester, find.byType(FaceReviewScreen));
      await per.zurueck(tester);
      await waitGone(tester, find.byType(AssetViewerScreen));
      // Video.
      await per.tippe(tester, kachelVon(video.id));
      await waitFor(tester, find.byType(AssetViewerScreen));
      await per.warte(tester, 1500);
      await per.rechtsklick(tester, find.byType(PageView));
      await waitFor(tester, find.text(de.viewerAehnlicheZeigen));
      expect(
        find.text(de.viewerGesichterBearbeiten),
        findsNothing,
        reason: 'Video',
      );
      await per.taste(tester, LogicalKeyboardKey.escape);
      await per.zurueck(tester);
      // Gesperrtes Foto in der Vollbildansicht des gesperrten Ordners.
      await bea.tresorEinrichten(tester);
      await bea.sperre(tester, f['vb3.jpg']!.id);
      await bea.oeffneGesperrtenOrdner(tester);
      await bea.tap(tester, bea.gesperrteKacheln.first);
      await waitFor(tester, find.byType(AssetViewerScreen));
      await per.warte(tester, 1200);
      await per.rechtsklick(tester, find.byType(PageView));
      await waitFor(tester, find.text(de.viewerMetadatenBearbeiten));
      expect(
        find.text(de.viewerGesichterBearbeiten),
        findsNothing,
        reason: 'gesperrtes Foto',
      );
      await per.taste(tester, LogicalKeyboardKey.escape);
      await finish(tester);
    },
  );

  per.pruefung(
    'PER-100 Zusammenführen: Fotos und Stammbaum gehen an Person A',
    (tester) async {
      await per.start(tester);
      final f = await per.fotos(tester, per.bilder('zf', 4));
      String id(int i) => f['zf$i.jpg']!.id;
      late String a, b, kind, gb1, gb2;
      await tester.runAsync(() async {
        a = await per.person('Person A');
        b = await per.person('Person B');
        kind = await per.person('Kind');
        await per.gesicht(id(1), person: a);
        gb1 = await per.gesicht(id(2), person: b);
        gb2 = await per.gesicht(id(3), person: b);
        await per.gesicht(id(4), person: a);
        await per.verwandt(kind, b);
        await per.partner(a, b);
      });
      await per.personenOeffnen(tester);
      await waitFor(tester, per.reiterText(de.tabMitZahl(de.personenTab, 3)));
      await per.langDruecken(tester, find.text('Person B'));
      await waitFor(
        tester,
        find.text(de.personenZusammenfuehrenMit('Person B')),
      );
      await per.klick(
        tester,
        find.descendant(
          of: find.byType(SimpleDialog),
          matching: find.text('Person A'),
        ),
      );
      await waitFor(tester, find.text(de.personenZusammenfuehrenTitel));
      expect(
        find.text(de.personenZusammenfuehrenText('Person B', 'Person A')),
        findsOneWidget,
      );
      await per.klick(
        tester,
        per.imDialog(
          find.widgetWithText(FilledButton, de.personenZusammenfuehren),
        ),
      );
      await waitGone(tester, find.text('Person B'));
      await waitFor(tester, per.reiterText(de.tabMitZahl(de.personenTab, 2)));
      expect(await per.personZeile(tester, b), isNull, reason: 'Person B weg');
      expect((await per.gesichtZeile(tester, gb1)).personId, a);
      expect((await per.gesichtZeile(tester, gb2)).personId, a);
      final kanten = await per.dbx(
        tester,
        () => bibliothek.db.select(bibliothek.db.personBeziehungen).get(),
      );
      expect(
        kanten.where((k) => k.personId == kind && k.andereId == a),
        hasLength(1),
      );
      expect(kanten.where((k) => k.personId == k.andereId), isEmpty);
      expect(kanten.where((k) => k.personId == b || k.andereId == b), isEmpty);
      // Person A zeigt alle vier Fotos.
      await per.klick(tester, find.text('Person A'));
      final detail = find.descendant(
        of: find.byType(PersonDetailScreen),
        matching: find.byType(AssetThumbnailTile),
      );
      await waitFor(tester, detail);
      expect(detail, findsNWidgets(4), reason: 'alle Fotos von B jetzt bei A');
      await per.zurueck(tester);
      // Im Stammbaum: Kind hat Person A als Elternteil.
      await per.stammbaumOeffnen(tester);
      await per.mitte(tester, 'Kind');
      await waitFor(tester, per.schild('Person A'));
      expect(per.schild('Person B'), findsNothing);
      await finish(tester);
    },
  );

  per.pruefung('PER-118 Adoptivelternteil: Bezeichnung und gestrichelte Linie', (
    tester,
  ) async {
    await per.start(tester);
    late String a, b;
    await tester.runAsync(() async {
      a = await per.person('Person A');
      b = await per.person('Person B');
      await per.person('Person C');
    });
    await per.stammbaumOeffnen(tester);
    await per.mitte(tester, 'Person A');
    // Ein leiblicher Elternteil zum Vergleich.
    await per.klick(tester, find.byTooltip(de.stammbaumElternteilHinzufuegen));
    await per.klick(tester, find.text(de.stammbaumLeiblich));
    await per.bestehendePersonImDialog(tester, 'Person C');
    await waitFor(tester, per.schild('Person C'));
    // PER-118
    await per.klick(tester, find.byTooltip(de.stammbaumElternteilHinzufuegen));
    await per.klick(tester, find.text(de.stammbaumAdoptiv));
    await per.bestehendePersonImDialog(tester, 'Person B');
    await waitFor(tester, per.schild('Person B'));
    expect(
      find.descendant(
        of: find.byType(ZierbaumAnsicht),
        matching: find.text('Adoptivelternteil'),
      ),
      findsOneWidget,
    );
    final kanten = await per.dbx(
      tester,
      () => bibliothek.db.select(bibliothek.db.personBeziehungen).get(),
    );
    print(
      'PER-118 Beziehungen: ${[for (final k in kanten) '${k.personId}->${k.andereId}:${k.art}']}',
    );
    expect(
      kanten.where(
        (k) =>
            {k.personId, k.andereId}.containsAll({a, b}) &&
            k.art.toLowerCase().contains('adoptiv'),
      ),
      hasLength(1),
      reason: 'Person B als Adoptivelternteil',
    );
    // Die Sanduhr ist die Ansicht mit Linien.
    await per.klick(tester, segment(de.stammbaumAnsichtSanduhr));
    await waitFor(tester, imSanduhr('Person B'));
    await per.warte(tester, 600);
    final maler = find.descendant(
      of: find.byType(SanduhrAnsicht),
      matching: find.byWidgetPredicate(
        (w) =>
            w is CustomPaint &&
            w.painter.runtimeType.toString() == '_KantenMaler',
      ),
    );
    final painter = (tester.widget(maler) as CustomPaint).painter as dynamic;
    final arten = {
      for (final k in painter.kanten as List)
        '${(k as dynamic).vonId}-${k.zuId}': (k.art as Verwandtschaft),
    };
    print('PER-118 Kanten der Sanduhr: $arten');
    expect(arten.values, contains(Verwandtschaft.adoptivelternteil));
    expect(arten.values, contains(Verwandtschaft.elternteil));
    // Gemalt: entlang des senkrechten Stücks über jedem Elternkasten
    // zählen, wie oft Strich und Lücke wechseln.
    final lagen = (painter.lagen as Map).cast<String, Offset>();
    final grenze = find
        .ancestor(of: maler, matching: find.byType(RepaintBoundary))
        .first;
    final boundary = tester.renderObject<RenderRepaintBoundary>(grenze);
    final malerBox = tester.renderObject<RenderBox>(maler);
    final ursprung =
        malerBox.localToGlobal(Offset.zero) -
        boundary.localToGlobal(Offset.zero);
    final bild = await tester.runAsync(() async {
      final i = await boundary.toImage(pixelRatio: 2);
      final d = await i.toByteData(format: ui.ImageByteFormat.rawRgba);
      return (i.width, i.height, d!);
    });
    final (bw, bh, daten) = bild!;
    int hell(int px, int py) {
      if (px < 0 || py < 0 || px >= bw || py >= bh) return -1;
      final o = (py * bw + px) * 4;
      return daten.getUint8(o) + daten.getUint8(o + 1) + daten.getUint8(o + 2);
    }

    /// Wie oft Strich und Lücke wechseln – entlang des senkrechten Stücks
    /// über dem Kasten des Elternteils. Je Zeile zählt der Punkt, der am
    /// weitesten vom Grund (12 px daneben) abweicht.
    int wechsel(String eltern, String kind) {
      final e = lagen[eltern]!, k = lagen[kind]!;
      final x = ursprung.dx + e.dx + 116 / 2;
      final oben = e.dy + 56;
      final mitte = (oben + k.dy) / 2;
      final abstand = <double>[];
      for (var y = oben + 1.5; y < mitte - 1.5; y += 0.5) {
        final py = ((ursprung.dy + y) * 2).round();
        final grund = hell(((x + 12) * 2).round(), py);
        var weit = 0;
        for (var dx = -3; dx <= 3; dx++) {
          final l = hell((x * 2).round() + dx, py);
          if (l >= 0 && grund >= 0) weit = math.max(weit, (l - grund).abs());
        }
        abstand.add(weit.toDouble());
      }
      if (abstand.isEmpty) return -1;
      final hoch = abstand.reduce(math.max);
      if (hoch < 30) {
        print(
          'PER-118 $eltern: keine Linie gefunden (${abstand.length} Zeilen)',
        );
        return -1;
      }
      var n = 0;
      bool? vorher;
      for (final w in abstand) {
        final strich = w > hoch / 2;
        if (vorher != null && strich != vorher) n++;
        vorher = strich;
      }
      print(
        'PER-118 $eltern: ${abstand.map((w) => w > hoch / 2 ? '#' : '.').join()} '
        '(Wechsel $n)',
      );
      return n;
    }

    final personC = (await per.personNamens(tester, 'Person C')).id;
    final adoptiv = wechsel(b, a);
    final leiblich = wechsel(personC, a);
    print('PER-118 Wechsel adoptiv $adoptiv, leiblich $leiblich');
    expect(adoptiv, greaterThanOrEqualTo(2), reason: 'gestrichelt');
    expect(leiblich, inInclusiveRange(0, 1), reason: 'durchgezogen');
    await finish(tester);
  });

  per.pruefung('PER-156 PER-158 Tafel und Lebensbaum als PDF: Inhalt und Porträts', (
    tester,
  ) async {
    await per.start(tester);
    final f = await per.fotos(tester, per.bilder('pt', 3));
    await tester.runAsync(() async {
      final a = await per.person('Person A', geburt: DateTime(1960, 2, 3));
      final b = await per.person('Person B', geburt: DateTime(1930, 4, 5));
      final c = await per.person('Person C', geburt: DateTime(1932, 6, 7));
      final k = await per.person('Kind', geburt: DateTime(1990, 8, 9));
      await per.verwandt(a, b);
      await per.verwandt(a, c);
      await per.partner(b, c);
      await per.verwandt(k, a);
      // Porträts (Profilbilder) für A, B, C.
      await per.gesicht(f['pt1.jpg']!.id, person: a);
      await per.gesicht(f['pt2.jpg']!.id, person: b);
      await per.gesicht(f['pt3.jpg']!.id, person: c);
      // Die Porträts kräftig magenta, damit sie im Bild zu finden sind.
      final m = img.Image(width: 96, height: 96);
      img.fill(m, color: img.ColorRgb8(255, 0, 255));
      for (final id in [a, b, c]) {
        final pfad = (await (bibliothek.db.select(
          bibliothek.db.people,
        )..where((t) => t.id.equals(id))).getSingle()).coverFaceCropPath!;
        bibliothek.paths.absolute(pfad).writeAsBytesSync(img.encodeJpg(m));
      }
    });
    await per.stammbaumOeffnen(tester);
    await per.mitte(tester, 'Person A');
    final d = genauerDialog();
    final ordner = Directory(p.join(anker.path, 'ausgabe'))..createSync();
    // PER-156
    d.ziel = p.join(ordner.path, 'tafel');
    melde.verlaufLeeren();
    await per.stammbaumMehr(tester, de.stammbaumTafelDrucken);
    await per.erwarteText(tester, de.stammbaumTafelFertig, timeout: _lang);
    expect(d.namen.last, 'stammbaum-tafel.pdf');
    final tafel = File(p.join(ordner.path, 'tafel.pdf'));
    expect(tafel.existsSync(), isTrue);
    expect(File(p.join(ordner.path, 'tafel')).existsSync(), isFalse);
    final tafelPdf = tafel.readAsBytesSync();
    sichere('per156_tafel.pdf', tafelPdf);
    final alles = pdfAlles(tafelPdf);
    final seiten = RegExp(r'/Type\s*/Page(?![s\w])').allMatches(alles).length;
    final box = RegExp(
      r'/MediaBox\s*\[\s*0\s+0\s+([\d.]+)\s+([\d.]+)',
    ).firstMatch(alles);
    final raster = pdfRaster(tafelPdf);
    print(
      'PER-156 Seiten $seiten, MediaBox ${box?.group(0)}, '
      'Raster ${[for (final r in raster) '${r.width}×${r.height}']}',
    );
    expect(seiten, 1);
    expect(
      double.parse(box!.group(1)!),
      closeTo(1190.55, 2),
      reason: 'A3 quer',
    );
    expect(double.parse(box.group(2)!), closeTo(841.89, 2));
    // Die Tafel ist ein gemaltes Bild des Fächers (lib/services/tafel_pdf.dart:46ff).
    expect(raster, hasLength(1), reason: 'ein Bild: der Fächer');
    final fach = raster.single;
    expect(fach.width, greaterThan(fach.height), reason: 'quer');
    final gelesen = await texterkennung(
      tester,
      img.copyResize(fach, width: 1600),
    );
    print('PER-156 gelesen: ${gelesen.replaceAll('\n', ' | ')}');
    expect(_kompakt(gelesen), contains(_kompakt('Person A')), reason: 'Mitte');
    expect(_kompakt(gelesen), contains('1960'), reason: 'Lebensdaten');
    final farbig = [
      for (final px in fach)
        if ((px.r - px.g).abs() + (px.g - px.b).abs() > 40) 1,
    ].length;
    print('PER-156 farbige Punkte $farbig, magenta ${magenta(fach)}');
    expect(
      farbig,
      greaterThan(fach.width * fach.height ~/ 50),
      reason: 'Ringe des Fächers',
    );
    expect(magenta(fach), lessThan(20), reason: 'ohne Porträts');
    // PER-158
    await per.klick(tester, segment(de.stammbaumAnsichtLebensbaum));
    await waitFor(
      tester,
      find.byTooltip(de.lebensbaumPortraitsAus),
      timeout: _lang,
    );
    Future<Uint8List> drucke(String name) async {
      d.ziel = p.join(ordner.path, name);
      melde.verlaufLeeren();
      await per.klick(tester, find.byTooltip(de.lebensbaumDrucken));
      await per.erwarteText(
        tester,
        de.stammbaumTafelFertig,
        timeout: _sehrLang,
      );
      expect(d.namen.last, 'stammbaum-lebensbaum.pdf');
      return File(d.ziel!).readAsBytesSync();
    }

    final mit = await drucke('lebensbaum_mit.pdf');
    sichere('per158_mit_portraets.pdf', mit);
    // Die Meldung „Die Tafel wurde geschrieben.“ liegt oben rechts über dem
    // Schalter; erst schliessen.
    bea.meldungenAus();
    await per.warte(tester, 600);
    per.symbolknopf(tester, de.lebensbaumPortraitsAus).onPressed!();
    await per.warte(tester, 600);
    await waitFor(tester, find.byTooltip(de.lebensbaumPortraitsAn));
    final ohne = await drucke('lebensbaum_ohne.pdf');
    sichere('per158_ohne_portraets.pdf', ohne);
    final rMit = pdfRaster(mit), rOhne = pdfRaster(ohne);
    final mMit = rMit.fold<int>(0, (n, r) => n + magenta(r));
    final mOhne = rOhne.fold<int>(0, (n, r) => n + magenta(r));
    print(
      'PER-158 Raster mit ${[for (final r in rMit) '${r.width}×${r.height}']} magenta $mMit, '
      'ohne ${[for (final r in rOhne) '${r.width}×${r.height}']} magenta $mOhne, '
      'Bildobjekte ${pdfBilder(mit)}/${pdfBilder(ohne)}',
    );
    expect(mMit, greaterThan(200), reason: 'Porträts enthalten');
    expect(mOhne, lessThan(20), reason: 'ausgeschaltet keine Porträts');
    // Ohne Äste ausgegraut.
    await per.mitte(tester, 'Person B');
    await per.klick(
      tester,
      find
          .descendant(
            of: find.byWidgetPredicate((w) => w is SegmentedButton),
            matching: find.text(de.lebensbaumVorfahren),
          )
          .last,
    );
    await per.warte(tester, 500);
    expect(per.symbolknopf(tester, de.lebensbaumDrucken).onPressed, isNull);
    await finish(tester);
  });

  per.pruefung('PER-202 Familientage: Geburtstagsfotos zuerst, 29. Februar', (
    tester,
  ) async {
    await per.start(tester);
    final f = await per.fotos(tester, [
      for (var i = 0; i < 4; i++)
        testfoto('gb23_$i.jpg', datum: DateTime(2023, 2, 28, 10 + i, 5)),
      testfoto('gb22.jpg', datum: DateTime(2022, 2, 28, 12, 5)),
      testfoto('gb24_29.jpg', datum: DateTime(2024, 2, 29, 12, 5)),
      testfoto('gb24_28.jpg', datum: DateTime(2024, 2, 28, 12, 5)),
      testfoto('gb21.jpg', datum: DateTime(2021, 2, 28, 12, 5)),
      testfoto('neu.jpg', datum: DateTime(2026, 6, 5, 12, 5)),
    ]);
    await tester.runAsync(() async {
      final a = await per.person('Person A', geburt: DateTime(1992, 2, 29));
      for (final x in f.values) {
        await per.gesicht(x.id, person: a);
      }
      await bibliothek.setupVaultPin('4711');
      await bibliothek.lockAsset(f['gb21.jpg']!);
    });
    // Der Abschnitt nimmt sonst das echte Datum; sein Testschalter `heute`
    // stellt den 28. Februar 2027 ein (Gemeinjahr).
    unawaited(
      Navigator.of(tester.element(find.byType(HomeShell))).push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            body: SingleChildScrollView(
              child: FamilientageAbschnitt(
                library: bibliothek,
                heute: DateTime(2027, 2, 28),
              ),
            ),
          ),
        ),
      ),
    );
    final abschnitt = find.byType(FamilientageAbschnitt);
    await waitFor(tester, abschnitt);
    final kacheln = find.descendant(
      of: abschnitt,
      matching: find.byType(AssetThumbnailTile),
    );
    await waitFor(tester, kacheln, timeout: _lang);
    expect(
      find.text(
        '${de.familientagHeute} · ${de.familientagGeburtstag('Person A', 35)}',
      ),
      findsOneWidget,
      reason: 'am 28. Februar gefeiert',
    );
    final namen = {for (final x in f.values) x.id: x.originalFileName};
    final reihe = [
      for (final t in tester.widgetList<AssetThumbnailTile>(kacheln))
        namen[t.asset.id] ?? t.asset.id,
    ];
    print('PER-202 Reihe am 28.02.2027: $reihe');
    expect(reihe.first, 'gb24_29.jpg', reason: 'jüngstes Jahr zuerst');
    expect(
      reihe.sublist(1, 4).every((n) => n.startsWith('gb23_')),
      isTrue,
      reason: 'höchstens drei je Jahr',
    );
    expect(reihe[4], 'gb22.jpg');
    expect(
      reihe,
      isNot(contains('gb24_28.jpg')),
      reason: 'im Schaltjahr zählt der 29.',
    );
    expect(reihe, isNot(contains('gb21.jpg')), reason: 'gesperrt');
    expect(reihe, hasLength(5));
    await finish(tester);
  });
}

// ===========================================================================
// Mit Server (eigener Wegwerf-Server r2bea, über die Steuerung anhaltbar)
// ===========================================================================

void _serverTests() {
  const ohneServer = serverAdresse == '';

  mitServer(
    'BEA-169 Mitserver Fotokammer: zwei hinein, gesperrtes bleibt, zurück mit allem',
    (tester) async {
      await steuere(tester, '/neu');
      await startApp(tester);
      await bea.verbinde(tester);
      await bea.importiereVerbunden(tester, [
        testfoto('zurueck1.jpg', datum: DateTime(2024, 5, 5, 10, 3)),
        testfoto('zurueck2.jpg', datum: DateTime(2024, 5, 6, 10, 3)),
        testfoto('gesperrt3.jpg', datum: DateTime(2024, 5, 7, 10, 3)),
        testfoto('bleibt.jpg', datum: DateTime(2024, 5, 8, 10, 3)),
      ]);
      await bea.abgleichen(tester, (x) => x.length >= 4);
      final alle = await bea.alleAufnahmen(tester);
      String idVon(String n) =>
          alle.firstWhere((x) => x.originalFileName == n).id;
      final z1 = idVon('zurueck1.jpg'), z2 = idVon('zurueck2.jpg');
      final z3 = idVon('gesperrt3.jpg');
      await bea.befehl(
        tester,
        AlbumAnlegen('alb-kammer', 'Kammeralbum', DateTime(2024)),
      );
      await bea.befehl(tester, AlbumFuellen('alb-kammer', [z1]));
      await bea.befehl(tester, BewertungSetzen([z1], 3));
      await bea.oeffneEntwickeln(tester, z1);
      await bea.setzeRegler(tester, de.entwBelichtung, 1);
      await bea.entwSpeichern(tester);
      await bea.abgleichen(
        tester,
        (x) => x.any((y) => y.id == z1 && y.developedRelativePath != null),
      );
      // Am Server liegt gesperrt3 im gesperrten Ordner (wie nach einem
      // Import aus Immich). Die Desktop-App kann verbunden nicht sperren
      // (lib/state/library_state.dart:3890 _nurOhneServer); darum in der
      // Datenbank des Wegwerf-Servers gesetzt.
      // Der Abgleich bringt die Sperre mit, die Aufnahme verschwindet dann
      // aus der Zeitleiste; gewählt wird darum vorher.
      await bea.waehleAus(tester, [z1, z2, z3]);
      expect(await steuere(tester, '/sperre?name=gesperrt3.jpg'), '1');
      await bea.warte(tester, const Duration(seconds: 4));
      print(
        'BEA-169 gesperrt3 hier gesperrt: ${(await bea.aufnahme(tester, z3)).isLocked}, '
        'in der Zeitleiste: ${bea.kachel(z3).evaluate().isNotEmpty}',
      );
      expect(find.text(de.auswAnzahl(3)), findsOneWidget);
      await bea.tap(tester, find.byTooltip(de.auswInDieKammer));
      expect(find.text(de.kammerAufnehmenTitel(3)), findsOneWidget);
      expect(find.text(de.kammerAufnehmenText), findsOneWidget);
      final erwartet = [
        de.kammerAufgenommen(2),
        de.kammerNichtAufgenommen(1, de.kammerGesperrt),
      ].join(' · ');
      await bea.tap(tester, bea.inDialog(find.text(de.auswInDieKammer)));
      await waitFor(tester, find.text(erwartet), timeout: _sehrLang);
      expect(find.text(de.importZurKammer), findsOneWidget);
      await bea.abgleichen(
        tester,
        (x) => !x.any((y) => (y.id == z1 || y.id == z2) && !y.isTrashed),
      );
      await openSection(tester, Hauptbereich.zeitleiste);
      await bea.warte(tester, const Duration(seconds: 1));
      expect(bea.kachel(z1), findsNothing);
      expect(bea.kachel(z2), findsNothing);
      expect(bea.kachel(idVon('bleibt.jpg')), findsWidgets);

      await bea.alleSchliessen(tester);
      await openSection(tester, Hauptbereich.fotokammer);
      final kacheln = bea.privat('_Kachel');
      await eventually(tester, () async {
        if (kacheln.evaluate().length >= 2) return true;
        final neu = find.byTooltip(de.kammerNeuLaden);
        if (neu.evaluate().isNotEmpty) await tester.tap(neu.first);
        return false;
      }, timeout: _sehrLang);
      expect(kacheln, findsNWidgets(2));
      await bea.tap(tester, find.byTooltip(de.kammerAlle));
      bea.meldungenAus();
      await tester.tap(find.text(de.kammerFreigeben));
      await bea.abgleichen(
        tester,
        (x) =>
            x
                .where(
                  (y) =>
                      (y.originalFileName == 'zurueck1.jpg' ||
                          y.originalFileName == 'zurueck2.jpg') &&
                      !y.isTrashed,
                )
                .length >=
            2,
      );
      final zurueck = (await bea.alleAufnahmen(tester)).firstWhere(
        (x) => x.originalFileName == 'zurueck1.jpg' && !x.isTrashed,
      );
      expect(zurueck.rating, 3, reason: 'Bewertung zurück');
      expect(
        zurueck.developedRelativePath,
        isNotNull,
        reason: 'Entwicklung zurück',
      );
      expect(
        (await bea.lauf(
          tester,
          () => bibliothek.db.assetsInAlbumOnce('alb-kammer'),
        )).map((x) => x.originalFileName),
        contains('zurueck1.jpg'),
        reason: 'Album zurück',
      );
      await bea.abschluss(tester);
    },
    skip: ohneServer,
  );

  // Befund: Bei angehaltenem Server und fehlendem Original kommt in
  // „Entwickeln“ zwar die Meldung „Das Original liegt nicht hier …“, die
  // Bildfläche dreht aber weiter endlos: _originalOderMeldung
  // (lib/screens/entwickeln/masken.dart:86–100) setzt kein `_error`, und
  // ohne Vorschau und ohne `_error` zeigt die Fläche einen Ladekreis
  // (lib/screens/develop_screen.dart:562–575). Zweimal nachgestellt
  // (Läufe r2-bea-b und r2-bea-d). Video öffnen und Zuschneiden speichern
  // verhalten sich wie erwartet.
  mitServer(
    'BEA-177 Mitserver Server gestoppt: Entwickeln, Video öffnen, Zuschneiden speichern',
    (tester) async {
      await steuere(tester, '/neu');
      await startApp(tester);
      await bea.verbinde(tester);
      await bea.importiereVerbunden(tester, [
        testfoto('weg_q.jpg', datum: DateTime(2024, 4, 2, 10, 3)),
        fixture('video_hoch_3s.mov'),
        fixture('video_5s.mp4'),
      ]);
      await bea.abgleichen(tester, (x) => x.length >= 3);
      await bea.abschluss(tester);

      // Neues Gerät: Originale liegen erst nach dem Holen hier.
      await startApp(tester);
      await bea.verbinde(tester, geraet: 'Rechner 3');
      await bea.abgleichen(tester, (x) => x.length >= 3);
      final alle = await bea.alleAufnahmen(tester);
      final q = alle.firstWhere((x) => x.originalFileName == 'weg_q.jpg').id;
      final geholt = alle
          .firstWhere((x) => x.originalFileName == 'video_hoch_3s.mov')
          .id;
      final fern = alle
          .firstWhere((x) => x.originalFileName == 'video_5s.mp4')
          .id;
      // Das eine Video einmal zum Zuschneiden öffnen, solange der Server
      // läuft: Sein Original liegt danach hier.
      await bea.oeffneFoto(tester, geholt);
      await bea.oeffneSchnitt(tester);
      await bea.schnittBereit(tester);
      await bea.alleSchliessen(tester);
      final qDatei = bibliothek.paths.absolute(
        (await bea.aufnahme(tester, q)).relativePath,
      );
      expect(qDatei.existsSync(), isFalse, reason: 'Original von q nicht hier');

      await steuere(tester, '/stopp');

      // Entwickeln.
      bea.merkeMeldungen();
      await bea.oeffneFoto(tester, q);
      await bea.tap(tester, find.byTooltip(de.viewerEntwickeln));
      await bea.erwarteNeueMeldung(
        tester,
        de.entwOriginalNichtDa,
        timeout: _sehrLang,
      );
      await bea.warte(tester, const Duration(seconds: 3));
      for (final e in find.byType(CircularProgressIndicator).evaluate()) {
        final kette = <String>[];
        e.visitAncestorElements((x) {
          kette.add(x.widget.runtimeType.toString());
          return kette.length < 10;
        });
        print('BEA-177 Kreisel nach der Meldung in: $kette');
      }
      print('BEA-177 nach der Meldung: ${onScreen(tester)}');
      expect(
        find.descendant(
          of: find.byType(DevelopScreen),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsNothing,
        reason: 'kein endloser Ladekreis nach der Meldung',
      );
      await bea.alleSchliessen(tester);

      // Video ohne Original: öffnen geht nicht.
      await bea.oeffneFoto(tester, fern);
      await bea.oeffneSchnitt(tester);
      await waitFor(
        tester,
        find.text(de.videoNichtGeoeffnet),
        timeout: _sehrLang,
      );
      await bea.alleSchliessen(tester);

      // Video mit Original: öffnen geht, speichern scheitert.
      await bea.oeffneFoto(tester, geholt);
      await bea.oeffneSchnitt(tester);
      await bea.schnittBereit(tester);
      await bea.setzeSchnitt(tester, 0.5, 2.0);
      bea.merkeMeldungen();
      await tester.tap(
        find.descendant(
          of: find.byType(VideoTrimScreen),
          matching: find.byTooltip(de.allgSpeichern),
        ),
      );
      await bea.erwarteNeueMeldung(
        tester,
        de.videoZuschneidenFehler,
        timeout: _sehrLang,
      );
      expect(
        find.byType(VideoTrimScreen),
        findsOneWidget,
        reason: 'bleibt offen',
      );
      expect(
        await bea.lauf(tester, () => bibliothek.db.videoTrimForAsset(geholt)),
        isNull,
        reason: 'kein Schnitt gespeichert',
      );
      await bea.abschluss(tester);
    },
    skip: true,
  );

  mitServer(
    'BEA-180 Mitserver Videobild: Zeit, Ort und Kamera am Server, dann in der Zeitleiste',
    (tester) async {
      await steuere(tester, '/neu');
      await startApp(tester);
      await bea.verbinde(tester);
      await bea.importiereVerbunden(tester, [fixture('video_5s.mp4')]);
      await bea.abgleichen(tester, (x) => x.isNotEmpty);
      final idV = (await bea.alleAufnahmen(tester)).single.id;
      await bea.befehl(tester, OrtSetzen([idV], 47.5, 11.0));
      await bea.befehl(
        tester,
        KameraangabenSetzen(
          idV,
          const CameraInfo(make: 'Pruefkamera', model: 'PK-1'),
        ),
      );
      final videoAmServer = await amServer(
        tester,
        (z) =>
            z['id'] == idV &&
            z['camera_make'] == 'Pruefkamera' &&
            (z['latitude'] as num?) != null,
        'Kamera und Ort am Server',
      );
      print('BEA-180 Video am Server: $videoAmServer');

      await bea.oeffneFoto(tester, idV);
      await bea.videoAbspielen(tester, const Duration(milliseconds: 1800));
      bea.merkeMeldungen();
      await bea.tap(tester, find.byTooltip(de.viewerVideobildSichern));
      final m = await bea.erwarteNeueMeldung(
        tester,
        de.viewerVideobildGesichert('§').split('§').first,
        timeout: _lang,
      );
      print('BEA-180 Meldung: $m');
      expect(
        m,
        matches(
          RegExp(
            r'^Bild bei \d+:\d\d als Foto gesichert – mit Datum und Ort des Videos$',
          ),
        ),
      );
      final bild = await amServer(
        tester,
        (z) => z['type'] == 'IMAGE',
        'Foto am Server',
      );
      print('BEA-180 Foto am Server: $bild');
      expect(bild['latitude'] as num, closeTo(47.5, 0.001));
      expect(bild['longitude'] as num, closeTo(11.0, 0.001));
      expect(bild['camera_make'], 'Pruefkamera');
      expect(bild['camera_model'], 'PK-1');
      final tVideo = (videoAmServer['file_created_at'] as num).toInt();
      final tBild = (bild['file_created_at'] as num).toInt();
      expect(
        tBild - tVideo,
        inInclusiveRange(0, 5),
        reason: 'Zeit des Videos + Stelle',
      );
      // Nach dem Abgleich in der Zeitleiste.
      await bea.abgleichen(tester, (x) => x.any((y) => y.id == bild['id']));
      final lokal = await bea.aufnahme(tester, bild['id'] as String);
      expect(lokal.latitude, closeTo(47.5, 0.001));
      expect(lokal.cameraMake, 'Pruefkamera');
      await bea.alleSchliessen(tester);
      await openSection(tester, Hauptbereich.zeitleiste);
      await bea.sichtbarMachen(tester, bea.kachel(lokal.id));
      expect(bea.kachel(lokal.id), findsWidgets);
      await bea.abschluss(tester);
    },
    skip: ohneServer,
  );

  // Befund: Auf dem Weg des Katalogs (Foto bei laufendem Server geöffnet,
  // Server angehalten, Gesicht aufgezogen, „Person B“ angelegt) entsteht
  // eine leere Person B ohne Gesicht, und es kommt keine Meldung.
  // _finishManualBox legt die Person an, bevor das Gesicht entsteht
  // (lib/screens/face_review_screen.dart:649–657); die Anzeigedatei liegt
  // nach dem Öffnen hier, darum greift die Prüfung davor (638–646) nicht.
  // Verbunden schickt gesichtVonHandAnlegen das Gesicht an den Server
  // (lib/services/gesicht_von_hand.dart:48–58); bei angehaltenem Server
  // wirft das „KeineVerbindung“ unbehandelt, ohne Meldung. Zweimal
  // nachgestellt (Läufe r2-bea-d und r2-bea-f).
  mitServer('PER-090 Mitserver Manuelles Gesicht bei gestopptem Server', (
    tester,
  ) async {
    await steuere(tester, '/neu');
    await startApp(tester);
    await bea.verbinde(tester);
    await bea.importiereVerbunden(tester, [
      testfoto('gesehen.jpg', datum: DateTime(2024, 6, 1, 10, 3)),
      testfoto('nie.jpg', datum: DateTime(2024, 6, 2, 10, 3)),
    ]);
    await bea.abgleichen(tester, (x) => x.length >= 2);
    await bea.abschluss(tester);

    await startApp(tester);
    await bea.verbinde(tester, geraet: 'Rechner 2');
    await bea.abgleichen(tester, (x) => x.length >= 2);
    final alle = await bea.alleAufnahmen(tester);
    final gesehen = alle.firstWhere((x) => x.originalFileName == 'gesehen.jpg');
    final nie = alle.firstWhere((x) => x.originalFileName == 'nie.jpg');
    print(
      'PER-090 Masse aus dem Abgleich: ${gesehen.widthPx}×${gesehen.heightPx}, '
      'Anzeigedatei ${lesbarerPfad(gesehen)}',
    );
    for (final a in [gesehen, nie]) {
      expect(
        bibliothek.paths.absolute(lesbarerPfad(a)).existsSync(),
        isFalse,
        reason: 'Anzeigedatei von ${a.originalFileName} noch nicht hier',
      );
    }

    Future<void> gesichterAnsicht(String id) async {
      await bea.oeffneFoto(tester, id);
      await per.rechtsklick(tester, find.byType(PageView));
      await per.klick(tester, find.text(de.viewerGesichterBearbeiten));
      await waitFor(tester, find.byType(FaceReviewScreen));
      await per.warte(tester, 1500);
    }

    Future<bool> aufziehen(String name) async {
      await per.klick(tester, find.byTooltip(de.gesichtManuellHinzufuegen));
      final flaeche = find.descendant(
        of: find.byType(FaceReviewScreen),
        matching: find.byType(AspectRatio),
      );
      if (flaeche.evaluate().isEmpty) {
        print('PER-090 keine Bildfläche zum Aufziehen');
        return false;
      }
      final r = tester.getRect(flaeche.first);
      final zug = await tester.startGesture(
        Offset(r.left + r.width * 0.4, r.top + r.height * 0.4),
        kind: PointerDeviceKind.mouse,
      );
      for (var i = 0; i < 8; i++) {
        await zug.moveBy(const Offset(12, 10));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await zug.up();
      await zug.removePointer();
      await per.warte(tester, 800);
      if (find.byType(AlertDialog).evaluate().isEmpty) {
        print('PER-090 Aufziehen ohne Dialog: ${onScreen(tester)}');
        return false;
      }
      await per.neuePersonImDialog(tester, name);
      return true;
    }

    // „gesehen“ einmal in der Gesichter-Ansicht zeigen, solange der Server
    // läuft: Ihre Anzeigedatei (beim JPEG das Original) liegt danach hier.
    await gesichterAnsicht(gesehen.id);
    await bea.alleSchliessen(tester);
    expect(
      bibliothek.paths.absolute(lesbarerPfad(gesehen)).existsSync(),
      isTrue,
      reason: 'nach dem Zeigen hier',
    );
    await steuere(tester, '/stopp');
    final vorherGesichter = (await per.alleGesichter(tester)).length;

    // 1. Das nie gezeigte Foto: Es lässt sich nicht zeigen.
    melde.verlaufLeeren();
    await gesichterAnsicht(nie.id);
    final dialog1 = await aufziehen('Person C');
    await per.warte(tester, 1500);
    print(
      'PER-090 nie gezeigt: Dialog $dialog1, '
      'Meldungen ${[for (final m in melde.verlauf) m.text]}',
    );
    expect((await per.alleGesichter(tester)).length, vorherGesichter);
    expect(
      (await per.allePersonen(tester)).where((x) => x.name == 'Person C'),
      isEmpty,
    );
    await bea.alleSchliessen(tester);

    // 2. Der Weg des Katalogs: Foto geöffnet (bei laufendem Server),
    //    Server gestoppt, Gesicht aufziehen, „Person B“ anlegen.
    melde.verlaufLeeren();
    await gesichterAnsicht(gesehen.id);
    final dialog2 = await aufziehen('Person B');
    await per.warte(tester, 3000);
    final meldungen2 = [for (final m in melde.verlauf) m.text];
    final gesichter2 = await per.alleGesichter(tester);
    final personB = (await per.allePersonen(
      tester,
    )).where((x) => x.name == 'Person B').toList();
    print(
      'PER-090 vorher gezeigt: Dialog $dialog2, Meldungen $meldungen2, '
      'neue Gesichter ${gesichter2.length - vorherGesichter}, Person B ${personB.length}',
    );
    expect(dialog2, isTrue);
    expect(gesichter2.length, vorherGesichter, reason: 'kein Gesicht');
    expect(personB, isEmpty, reason: 'keine leere Person B');
    expect(
      meldungen2,
      contains(de.entwOriginalNichtDa),
      reason: 'Fehlermeldung',
    );
    await bea.abschluss(tester);
  }, skip: true);
}
