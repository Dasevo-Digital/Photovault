import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'package:image/image.dart' as img;

import '../services/geometry_edits.dart';
import '../services/inpainting_service.dart';
import 'package:path/path.dart' as p;

import '../db/database.dart';
import '../services/bilddekodierung.dart';
import '../services/import_service.dart';
import '../services/storage_paths.dart';
import '../theme/app_spacing.dart';
import '../services/meldungsdienst.dart';

/// Ergebnis einer Bildbearbeitungs-Operation in einem Hintergrund-Isolate
/// (siehe [_ImageEditorScreenState]): die neu encodierten JPEG-Bytes plus
/// die resultierenden Abmessungen (werden für Anzeige-Skalierung und
/// Zuschnitt-Koordinaten gebraucht, ohne dafür das dekodierte [img.Image]
/// selbst über die Isolate-Grenze schicken zu müssen).
typedef _ImageEditResult = ({Uint8List bytes, int width, int height});

_ImageEditResult? _encodeResult(img.Image image) => (
      bytes: Uint8List.fromList(img.encodeJpg(image, quality: 90)),
      width: image.width,
      height: image.height,
    );

/// Läuft über `compute()` in einem Hintergrund-Isolate (siehe
/// [ImageEditorScreen]) – Dekodieren + Transformieren + JPEG-Encodieren
/// einer vollauflösenden Fotodatei kostet bei jedem Werkzeug-Klick leicht
/// hunderte Millisekunden bis niedrige Sekunden und würde sonst die UI bei
/// jedem einzelnen Dreh-/Spiegel-/Zuschneide-Tastendruck kurz einfrieren.
_ImageEditResult? _rotateImageLeftIsolate(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  return decoded == null ? null : _encodeResult(img.copyRotate(decoded, angle: -90));
}

_ImageEditResult? _rotateImageRightIsolate(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  return decoded == null ? null : _encodeResult(img.copyRotate(decoded, angle: 90));
}

_ImageEditResult? _flipImageHorizontalIsolate(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  return decoded == null ? null : _encodeResult(img.flipHorizontal(decoded));
}

_ImageEditResult? _flipImageVerticalIsolate(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  return decoded == null ? null : _encodeResult(img.flipVertical(decoded));
}

typedef _StraightenArgs = ({Uint8List bytes, double grad});

_ImageEditResult? _straightenImageIsolate(_StraightenArgs args) {
  final decoded = img.decodeImage(args.bytes);
  return decoded == null ? null : _encodeResult(geradeziehen(decoded, args.grad));
}

typedef _PerspectiveArgs = ({Uint8List bytes, List<Offset> ecken});

_ImageEditResult? _perspectiveImageIsolate(_PerspectiveArgs args) {
  final decoded = img.decodeImage(args.bytes);
  if (decoded == null) return null;
  // Die Zielgrösse aus dem Viereck ableiten: die längere der beiden
  // gegenüberliegenden Seiten. Fest auf die Bildgrösse zu gehen streckte
  // ein hochkant stehendes Motiv in die Breite.
  double laenge(Offset a, Offset b) => (a - b).distance;
  final breite = math.max(laenge(args.ecken[0], args.ecken[1]),
      laenge(args.ecken[3], args.ecken[2]));
  final hoehe = math.max(laenge(args.ecken[0], args.ecken[3]),
      laenge(args.ecken[1], args.ecken[2]));
  final entzerrt = perspektivischEntzerren(
      decoded, args.ecken, breite.round().clamp(1, 20000), hoehe.round().clamp(1, 20000));
  return entzerrt == null ? null : _encodeResult(entzerrt);
}

typedef _CropArgs = ({Uint8List bytes, int x, int y, int width, int height});

_ImageEditResult? _cropImageIsolate(_CropArgs args) {
  final decoded = img.decodeImage(args.bytes);
  if (decoded == null) return null;
  final cropped = img.copyCrop(decoded, x: args.x, y: args.y, width: args.width, height: args.height);
  return _encodeResult(cropped);
}

/// Finale, etwas höherwertige JPEG-Encodierung beim Speichern (siehe
/// [_ImageEditorScreenState._save]) – separat von den Zwischenschritten,
/// die für eine flüssige Vorschau bewusst mit niedrigerer Qualität
/// encodieren.
Uint8List? _finalizeImageIsolate(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  return Uint8List.fromList(img.encodeJpg(decoded, quality: 92));
}

/// Grundlegende Bildbearbeitung (Zuschneiden, Spiegeln, Drehen) direkt auf
/// der Originaldatei. Bewusst destruktiv – ersetzt die Originaldatei ohne
/// Bearbeitungs-Historie oder "Zurücksetzen auf Original": eine
/// nicht-destruktive Bearbeitung (mit dauerhaft aufbewahrten Ausgangsdaten)
/// wäre ein eigenständiges, deutlich größeres Feature. Nur für Fotos, nicht
/// für gesperrte (verschlüsselte) Assets, um die Wiederverschlüsselung nach
/// dem Speichern nicht mit abdecken zu müssen.
class ImageEditorScreen extends StatefulWidget {
  final AssetData asset;
  final AppDatabase db;
  final StoragePaths paths;

  /// Wo die KI-Modelle liegen – nur für die Objektentfernung. `null`
  /// heisst „nicht verfügbar"; das Werkzeug steht dann abgeschaltet da
  /// und sagt im Hinweistext, was fehlt (siehe `_retuscheMoeglich`).
  final String? modelsDir;

  const ImageEditorScreen({
    super.key,
    required this.asset,
    required this.db,
    required this.paths,
    this.modelsDir,
  });

  @override
  State<ImageEditorScreen> createState() => _ImageEditorScreenState();
}

class _ImageEditorScreenState extends State<ImageEditorScreen> {
  // _currentBytes ist bereits das, was angezeigt wird (Image.memory erkennt
  // das Format selbst – vor der ersten Bearbeitung können das auch die
  // unveränderten Original-Bytes in einem anderen Format als JPEG sein).
  Uint8List? _currentBytes;
  int? _currentWidth;
  int? _currentHeight;
  bool _loading = true;
  bool _processing = false; // Dreh-/Spiegel-/Zuschneide-Operation läuft im Hintergrund-Isolate.
  bool _saving = false;
  String? _error;

  bool _cropping = false;

  /// Geradeziehen: der Winkel, solange der Regler gezogen wird. `null`
  /// heisst „Werkzeug nicht offen".
  double? _straightenGrad;

  /// Perspektive: die vier Ecken in Anzeigekoordinaten, im Uhrzeigersinn ab
  /// oben links. `null` heisst „Werkzeug nicht offen".
  List<Offset>? _perspektiveEcken;
  int? _gezogeneEcke;

  /// Objektentfernung: die gemalten Striche in Anzeigekoordinaten. `null`
  /// heisst „Werkzeug nicht offen".
  List<List<Offset>>? _retuscheStriche;
  double _pinselbreite = 24;
  Rect? _cropRect; // In lokalen Koordinaten des angezeigten (skalierten) Bilds.
  double? _displayScale; // Bild-Pixel * _displayScale = angezeigte Koordinaten.

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final relativePath = widget.asset.previewRelativePath ?? widget.asset.relativePath;
      final bytes = await widget.paths.absolute(relativePath).readAsBytes();
      // Nur zum Ermitteln der Abmessungen – läuft einmalig beim Öffnen des
      // Editors (nicht pro Werkzeug-Klick), ein einmaliger kurzer Ruckler
      // ist hier anders als bei den Bearbeitungs-Operationen unten
      // akzeptabel.
      final decoded = img.decodeImage(bytes);
      if (!mounted) return;
      if (decoded == null) {
        setState(() {
          _loading = false;
          _error = AppTexte.of(context).bearbBildNichtLesbar;
        });
        return;
      }
      setState(() {
        _currentBytes = bytes;
        _currentWidth = decoded.width;
        _currentHeight = decoded.height;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = AppTexte.of(context).bearbBildNichtLesbarFehler('$e');
        });
      }
    }
  }

  Future<void> _runEdit(Future<_ImageEditResult?> Function() operation) async {
    if (_processing) return;
    setState(() => _processing = true);
    final result = await operation();
    if (!mounted) return;
    setState(() {
      if (result != null) {
        _currentBytes = result.bytes;
        _currentWidth = result.width;
        _currentHeight = result.height;
      }
      _cropping = false;
      _cropRect = null;
      _straightenGrad = null;
      _perspektiveEcken = null;
      _gezogeneEcke = null;
      _retuscheStriche = null;
      _processing = false;
    });
  }

  void _rotateLeft() => _runEdit(() => compute(_rotateImageLeftIsolate, _currentBytes!));
  void _rotateRight() => _runEdit(() => compute(_rotateImageRightIsolate, _currentBytes!));
  void _flipHorizontal() => _runEdit(() => compute(_flipImageHorizontalIsolate, _currentBytes!));
  void _flipVertical() => _runEdit(() => compute(_flipImageVerticalIsolate, _currentBytes!));

  void _startCrop() => setState(() => _cropping = true);

  void _startStraighten() => setState(() => _straightenGrad = 0);

  void _applyStraighten() {
    final grad = _straightenGrad;
    final bytes = _currentBytes;
    if (grad == null || bytes == null) return;
    if (grad == 0) {
      setState(() => _straightenGrad = null);
      return;
    }
    _runEdit(() => compute(_straightenImageIsolate, (bytes: bytes, grad: grad)));
  }

  /// Öffnet die Perspektivkorrektur mit vier Ecken leicht innerhalb des
  /// Bildrands.
  ///
  /// Nicht genau in den Ecken: Dort liessen sie sich mit dem Zeiger kaum
  /// fassen, und der erste Griff ginge daneben.
  void _startPerspektive() {
    final scale = _displayScale;
    final w = _currentWidth, h = _currentHeight;
    if (scale == null || w == null || h == null) return;
    final bw = w * scale, bh = h * scale;
    const rand = 0.12;
    setState(() => _perspektiveEcken = [
          Offset(bw * rand, bh * rand),
          Offset(bw * (1 - rand), bh * rand),
          Offset(bw * (1 - rand), bh * (1 - rand)),
          Offset(bw * rand, bh * (1 - rand)),
        ]);
  }

  void _startRetusche() => setState(() => _retuscheStriche = []);

  /// Führt die Objektentfernung aus.
  ///
  /// Läuft NICHT über `compute()`: Die ONNX-Anbindung geht über einen
  /// Plattformkanal und ist in einem Hintergrund-Isolat nicht erreichbar –
  /// dasselbe gilt für alle Modelle dieser App. Der Durchgang dauert
  /// gemessen rund 1,3 Sekunden; solange zeigt die Fläche ihren
  /// Warte-Schleier.
  Future<void> _applyRetusche() async {
    final striche = _retuscheStriche;
    final scale = _displayScale;
    final bytes = _currentBytes;
    final w = _currentWidth, h = _currentHeight;
    final modelle = widget.modelsDir;
    if (striche == null || striche.isEmpty || scale == null || bytes == null ||
        w == null || h == null || modelle == null) {
      return;
    }

    setState(() => _processing = true);
    InpaintingService? dienst;
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) throw StateError('nicht dekodierbar');

      // Die Striche als Graustufenmaske in Bildauflösung.
      final maske = img.Image(width: w, height: h);
      final radius = (_pinselbreite / 2 / scale).clamp(1.0, 400.0);
      for (final strich in striche) {
        for (final punkt in strich) {
          img.fillCircle(maske,
              x: (punkt.dx / scale).round(),
              y: (punkt.dy / scale).round(),
              radius: radius.round(),
              color: img.ColorRgb8(255, 255, 255));
        }
      }

      dienst = await InpaintingService.load(modelle);
      final ergebnis = await dienst.entferne(decoded, maske);
      if (ergebnis == null) {
        // Leere Maske. Frueher endete der Weg hier wortlos - und wortlos
        // nichts tun ist die Auskunft, die am teuersten zu deuten ist.
        if (mounted) {
          setState(() => _processing = false);
          melde.hinweis(AppTexte.of(context).bearbRetuscheNichtsMarkiert);
        }
        return;
      }
      final kodiert = _encodeResult(ergebnis)!;
      if (!mounted) return;
      setState(() {
        _currentBytes = kodiert.bytes;
        _currentWidth = kodiert.width;
        _currentHeight = kodiert.height;
        _retuscheStriche = null;
        _processing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _processing = false);
      melde.fehler(AppTexte.of(context).bearbRetuscheFehler('$e'));
    } finally {
      await dienst?.dispose();
    }
  }

  void _applyPerspektive() {
    final ecken = _perspektiveEcken;
    final scale = _displayScale;
    final bytes = _currentBytes;
    if (ecken == null || scale == null || bytes == null) return;
    // Von Anzeige- in Bildkoordinaten.
    final inBild = [for (final e in ecken) Offset(e.dx / scale, e.dy / scale)];
    _runEdit(() => compute(_perspectiveImageIsolate, (bytes: bytes, ecken: inBild)));
  }
  void _cancelCrop() => setState(() {
        _cropping = false;
        _cropRect = null;
      });

  void _applyCrop() {
    final rect = _cropRect;
    final scale = _displayScale;
    final bytes = _currentBytes;
    final width = _currentWidth;
    final height = _currentHeight;
    if (rect == null || scale == null || bytes == null || width == null || height == null) return;
    final x = (rect.left / scale).round().clamp(0, width - 1);
    final y = (rect.top / scale).round().clamp(0, height - 1);
    final w = (rect.width / scale).round().clamp(1, width - x);
    final h = (rect.height / scale).round().clamp(1, height - y);
    _runEdit(() => compute(_cropImageIsolate, (bytes: bytes, x: x, y: y, width: w, height: h)));
  }

  Future<void> _save() async {
    final currentBytes = _currentBytes;
    if (currentBytes == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppTexte.of(context).bearbSpeichernTitel),
        content: Text(
          AppTexte.of(context).bearbSpeichernText,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(AppTexte.of(context).allgAbbrechen)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(AppTexte.of(context).allgSpeichern)),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // Vor dem await auflösen – danach ist der Kontext nicht mehr sicher.
    final nichtFinalisiert = AppTexte.of(context).bearbNichtFinalisiert;
    setState(() => _saving = true);
    try {
      final jpegBytes = await compute(_finalizeImageIsolate, currentBytes);
      if (jpegBytes == null) throw Exception(nichtFinalisiert);
      final checksum = sha256.convert(jpegBytes).toString();

      // Original bereits ein JPEG -> an Ort und Stelle ersetzen. Andere
      // Formate (HEIC/PNG/RAW & Co.) -> neue .jpg-Datei anlegen und die alte
      // Originaldatei danach entfernen, damit Dateiendung und tatsächlicher
      // Inhalt nicht auseinanderlaufen.
      final ext = p.extension(widget.asset.relativePath).toLowerCase();
      final keepsSamePath = ext == '.jpg' || ext == '.jpeg';
      final newRelativePath = keepsSamePath
          ? widget.asset.relativePath
          : widget.paths.originalRelativePath(widget.asset.fileCreatedAt, widget.asset.id, '.jpg');

      final targetFile = widget.paths.absolute(newRelativePath);
      await targetFile.parent.create(recursive: true);
      await targetFile.writeAsBytes(jpegBytes);
      if (!keepsSamePath) {
        await widget.paths.deletePermanently(widget.asset.relativePath);
      }

      await widget.db.setEditedAssetFile(widget.asset.id, relativePath: newRelativePath, checksum: checksum);

      final importService = ImportService(widget.db, widget.paths);
      final thumbResult = await importService.generateThumbnailAndPreview(
        targetFile,
        widget.asset.id,
        '.jpg',
        alreadyReadBytes: jpegBytes,
      );
      await widget.db.updateThumbnailInfo(
        widget.asset.id,
        thumbnailRelativePath: thumbResult.thumbnailRelativePath,
        widthPx: thumbResult.width,
        heightPx: thumbResult.height,
      );

      // Die Datei ist neu, ihr Pfad ist derselbe – und Flutter merkt
      // sich dekodierte Bilder nach dem Pfad. Ohne dieses Vergessen zeigt
      // die Vollbildansicht danach weiter das ungedrehte Bild.
      vergissAlleBilder();

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        melde.fehler(AppTexte.of(context).bearbSpeichernFehler('$e'));
      }
    }
  }

  Widget _buildEditorArea() {
    final bytes = _currentBytes;
    final width = _currentWidth;
    final height = _currentHeight;
    if (bytes == null || width == null || height == null) return const SizedBox.shrink();

    return LayoutBuilder(builder: (context, constraints) {
      final imgW = width.toDouble();
      final imgH = height.toDouble();
      final scale = (constraints.maxWidth / imgW < constraints.maxHeight / imgH)
          ? constraints.maxWidth / imgW
          : constraints.maxHeight / imgH;
      final displayW = imgW * scale;
      final displayH = imgH * scale;
      _displayScale = scale;

      if (_cropping) {
        _cropRect ??= Rect.fromLTWH(displayW * 0.1, displayH * 0.1, displayW * 0.8, displayH * 0.8);
      }

      return Center(
        child: SizedBox(
          width: displayW,
          height: displayH,
          child: Stack(
            children: [
              Image.memory(bytes, width: displayW, height: displayH, fit: BoxFit.fill, gaplessPlayback: true),
              if (_cropping && _cropRect != null)
                _CropOverlay(
                  imageSize: Size(displayW, displayH),
                  rect: _cropRect!,
                  onChanged: (r) => setState(() => _cropRect = r),
                ),
              // Beim Geradeziehen ein Gitter: Ein schiefer Horizont lässt
              // sich nur gegen eine Bezugslinie ausrichten, nach Gefühl
              // trifft man ihn nicht.
              if (_straightenGrad != null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                        painter: _AusrichtGitter(winkelGrad: _straightenGrad!)),
                  ),
                ),
              if (_retuscheStriche != null)
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (d) => setState(
                        () => _retuscheStriche = [..._retuscheStriche!, [d.localPosition]]),
                    onPanUpdate: (d) => setState(() {
                      final alle = [..._retuscheStriche!];
                      alle[alle.length - 1] = [...alle.last, d.localPosition];
                      _retuscheStriche = alle;
                    }),
                    child: CustomPaint(
                      painter: _RetuscheMaler(_retuscheStriche!, _pinselbreite),
                    ),
                  ),
                ),
              if (_perspektiveEcken != null)
                _EckenUeberlagerung(
                  ecken: _perspektiveEcken!,
                  groesse: Size(displayW, displayH),
                  gezogen: _gezogeneEcke,
                  onGriff: (i) => setState(() => _gezogeneEcke = i),
                  onZieht: (i, punkt) => setState(() {
                    final neu = [..._perspektiveEcken!];
                    neu[i] = Offset(
                      punkt.dx.clamp(0.0, displayW),
                      punkt.dy.clamp(0.0, displayH),
                    );
                    _perspektiveEcken = neu;
                  }),
                  onLoslassen: () => setState(() => _gezogeneEcke = null),
                ),
              if (_processing)
                const Positioned.fill(
                  child: ColoredBox(
                    color: Colors.black45,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
            ],
          ),
        ),
      );
    });
  }

  Widget _buildToolbar() {
    final tt = AppTexte.of(context);
    if (_straightenGrad != null) {
      return Row(
        children: [
          TextButton(
            onPressed: _processing ? null : () => setState(() => _straightenGrad = null),
            child: Text(tt.allgAbbrechen, style: const TextStyle(color: Colors.white70)),
          ),
          Expanded(
            child: Slider(
              value: _straightenGrad!,
              min: -15,
              max: 15,
              divisions: 300,
              label: '${_straightenGrad!.toStringAsFixed(1)}°',
              onChanged: _processing
                  ? null
                  : (v) => setState(() => _straightenGrad = v),
            ),
          ),
          SizedBox(
            width: 52,
            child: Text('${_straightenGrad!.toStringAsFixed(1)}°',
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ),
          FilledButton(
            onPressed: _processing ? null : _applyStraighten,
            child: Text(tt.allgUebernehmen),
          ),
        ],
      );
    }
    if (_retuscheStriche != null) {
      return Row(
        children: [
          TextButton(
            onPressed: _processing ? null : () => setState(() => _retuscheStriche = null),
            child: Text(tt.allgAbbrechen, style: const TextStyle(color: Colors.white70)),
          ),
          IconButton(
            tooltip: tt.bearbRetuscheZurueck,
            color: Colors.white70,
            icon: const Icon(Icons.undo),
            onPressed: _processing || _retuscheStriche!.isEmpty
                ? null
                : () => setState(() =>
                    _retuscheStriche = _retuscheStriche!.sublist(0, _retuscheStriche!.length - 1)),
          ),
          Expanded(
            child: Slider(
              value: _pinselbreite,
              min: 6,
              max: 120,
              label: tt.bearbPinselbreite,
              onChanged: _processing ? null : (v) => setState(() => _pinselbreite = v),
            ),
          ),
          FilledButton.icon(
            onPressed:
                _processing || _retuscheStriche!.isEmpty ? null : _applyRetusche,
            icon: const Icon(Icons.auto_fix_high),
            label: Text(tt.bearbRetuscheAnwenden),
          ),
        ],
      );
    }
    if (_perspektiveEcken != null) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TextButton.icon(
            onPressed: _processing ? null : () => setState(() => _perspektiveEcken = null),
            icon: const Icon(Icons.close, color: Colors.white70),
            label: Text(tt.allgAbbrechen, style: const TextStyle(color: Colors.white70)),
          ),
          const SizedBox(width: 24),
          FilledButton.icon(
            onPressed: _processing ? null : _applyPerspektive,
            icon: const Icon(Icons.check),
            label: Text(tt.bearbPerspektiveAnwenden),
          ),
        ],
      );
    }
    if (_cropping) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TextButton.icon(
            onPressed: _processing ? null : _cancelCrop,
            icon: const Icon(Icons.close, color: Colors.white70),
            label: Text(AppTexte.of(context).allgAbbrechen, style: const TextStyle(color: Colors.white70)),
          ),
          const SizedBox(width: 24),
          FilledButton.icon(
            onPressed: _processing ? null : _applyCrop,
            icon: const Icon(Icons.check),
            label: Text(AppTexte.of(context).bearbZuschneidenAnwenden),
          ),
        ],
      );
    }
    final t = AppTexte.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _toolButton(Icons.crop_outlined, t.bearbZuschneiden, _startCrop),
        _toolButton(Icons.straighten, t.bearbGeradeziehen, _startStraighten),
        _toolButton(Icons.transform, t.bearbPerspektive, _startPerspektive),
        // **Sichtbar, auch ohne Modell – aber abgeschaltet und mit
        // Begründung.** Vorher fiel der Knopf ganz weg, mit dem Argument,
        // ein Werkzeug, das beim Antippen nur „geht nicht" meldet, sei
        // schlechter als keines. Das Ergebnis war schlechter als beides:
        // In den Einstellungen steht ein Modell namens
        // „Objektentfernung (LaMa)", in der Bearbeitung gab es dazu
        // nichts zu sehen, und nirgends stand ein Zusammenhang. Wer das
        // Werkzeug suchte, fand eine leere Stelle. Dieselbe Regel wie
        // beim leeren Gesichter-Tab und bei der KI-Maske im Entwickeln:
        // sagen, was fehlt und wo es herkommt.
        _toolButton(
          Icons.auto_fix_high,
          _retuscheMoeglich
              ? t.bearbRetusche
              : '${t.bearbRetusche} – '
                  '${t.aufgModellNoetig(t.aufgLamaModell, t.aufgWoModelle)}',
          _startRetusche,
          aus: !_retuscheMoeglich,
        ),
        _toolButton(Icons.rotate_left, t.bearbLinksDrehen, _rotateLeft),
        _toolButton(Icons.rotate_right, t.bearbRechtsDrehen, _rotateRight),
        _toolButton(Icons.flip, t.bearbHorizontalSpiegeln, _flipHorizontal),
        _toolButton(Icons.flip, t.bearbVertikalSpiegeln, _flipVertical, quarterTurns: 1),
      ],
    );
  }

  /// Ob die Objektentfernung ueberhaupt rechnen kann.
  bool get _retuscheMoeglich =>
      widget.modelsDir != null &&
      InpaintingService.isAvailable(widget.modelsDir!);

  Widget _toolButton(IconData icon, String tooltip, VoidCallback onPressed,
      {int quarterTurns = 0, bool aus = false}) {
    return IconButton(
      tooltip: tooltip,
      color: Colors.white,
      // Ein abgeschalteter Knopf behaelt seinen Hinweistext: Genau dort
      // steht, warum er abgeschaltet ist.
      disabledColor: Colors.white24,
      icon: RotatedBox(quarterTurns: quarterTurns, child: Icon(icon)),
      onPressed: _processing || aus ? null : onPressed,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(AppTexte.of(context).bearbTitel),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.check),
              tooltip: AppTexte.of(context).allgSpeichern,
              onPressed: _currentBytes == null || _processing ? null : _save,
            ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!, style: const TextStyle(color: Colors.white70)))
                : Column(
                    children: [
                      Expanded(child: Padding(padding: const EdgeInsets.all(AppSpacing.lg), child: _buildEditorArea())),
                      Padding(padding: const EdgeInsets.symmetric(vertical: AppSpacing.md), child: _buildToolbar()),
                    ],
                  ),
      ),
    );
  }
}

/// Interaktives Zuschneide-Rechteck über einem Bild: vier Eck-Anfasser zum
/// Ändern der Größe, Ziehen innerhalb des Rechtecks zum Verschieben. Alle
/// Koordinaten sind lokal zum angezeigten (bereits skalierten) Bild.
class _CropOverlay extends StatelessWidget {
  final Size imageSize;
  final Rect rect;
  final ValueChanged<Rect> onChanged;
  const _CropOverlay({required this.imageSize, required this.rect, required this.onChanged});

  static const _handleSize = 24.0;
  static const _minSize = 40.0;

  Rect _clamp(Rect r) {
    final left = r.left.clamp(0.0, imageSize.width - _minSize);
    final top = r.top.clamp(0.0, imageSize.height - _minSize);
    final right = r.right.clamp(left + _minSize, imageSize.width);
    final bottom = r.bottom.clamp(top + _minSize, imageSize.height);
    return Rect.fromLTRB(left, top, right, bottom);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(child: CustomPaint(painter: _CropMaskPainter(rect))),
        ),
        Positioned.fromRect(
          rect: rect,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanUpdate: (details) {
              var moved = rect.shift(details.delta);
              if (moved.left < 0) moved = moved.shift(Offset(-moved.left, 0));
              if (moved.top < 0) moved = moved.shift(Offset(0, -moved.top));
              if (moved.right > imageSize.width) moved = moved.shift(Offset(imageSize.width - moved.right, 0));
              if (moved.bottom > imageSize.height) {
                moved = moved.shift(Offset(0, imageSize.height - moved.bottom));
              }
              onChanged(moved);
            },
            child: Container(decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 2))),
          ),
        ),
        _cornerHandle(
          Offset(rect.left, rect.top),
          (delta) => _clamp(Rect.fromLTRB(rect.left + delta.dx, rect.top + delta.dy, rect.right, rect.bottom)),
        ),
        _cornerHandle(
          Offset(rect.right, rect.top),
          (delta) => _clamp(Rect.fromLTRB(rect.left, rect.top + delta.dy, rect.right + delta.dx, rect.bottom)),
        ),
        _cornerHandle(
          Offset(rect.left, rect.bottom),
          (delta) => _clamp(Rect.fromLTRB(rect.left + delta.dx, rect.top, rect.right, rect.bottom + delta.dy)),
        ),
        _cornerHandle(
          Offset(rect.right, rect.bottom),
          (delta) => _clamp(Rect.fromLTRB(rect.left, rect.top, rect.right + delta.dx, rect.bottom + delta.dy)),
        ),
      ],
    );
  }

  Widget _cornerHandle(Offset at, Rect Function(Offset delta) resize) {
    return Positioned(
      left: at.dx - _handleSize / 2,
      top: at.dy - _handleSize / 2,
      width: _handleSize,
      height: _handleSize,
      child: GestureDetector(
        onPanUpdate: (details) => onChanged(resize(details.delta)),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.black26),
          ),
        ),
      ),
    );
  }
}

class _CropMaskPainter extends CustomPainter {
  final Rect hole;
  _CropMaskPainter(this.hole);

  @override
  void paint(Canvas canvas, Size size) {
    final outer = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final inner = Path()..addRect(hole);
    final mask = Path.combine(PathOperation.difference, outer, inner);
    canvas.drawPath(mask, Paint()..color = Colors.black54);
    canvas.drawRect(hole, Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(covariant _CropMaskPainter oldDelegate) => oldDelegate.hole != hole;
}

/// Ein mitgedrehtes Gitter über dem Bild.
///
/// Ohne Bezugslinie trifft man einen schiefen Horizont nicht: Das Auge
/// gleicht die Neigung des ganzen Bildes aus. Erst gegen ein Gitter sieht
/// man, wann eine Kante wirklich waagerecht steht.
class _AusrichtGitter extends CustomPainter {
  final double winkelGrad;
  const _AusrichtGitter({required this.winkelGrad});

  @override
  void paint(Canvas canvas, Size size) {
    final stift = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = 1;

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(winkelGrad * math.pi / 180);
    // Über die Diagonale hinaus zeichnen, damit die Linien beim Drehen
    // nicht vor dem Bildrand enden.
    final reichweite = math.sqrt(size.width * size.width + size.height * size.height);
    const linien = 9;
    for (var i = 1; i < linien; i++) {
      final anteil = i / linien - 0.5;
      canvas.drawLine(Offset(-reichweite / 2, anteil * reichweite),
          Offset(reichweite / 2, anteil * reichweite), stift);
      canvas.drawLine(Offset(anteil * reichweite, -reichweite / 2),
          Offset(anteil * reichweite, reichweite / 2), stift);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _AusrichtGitter old) => old.winkelGrad != winkelGrad;
}

/// Die vier ziehbaren Ecken der Perspektivkorrektur.
class _EckenUeberlagerung extends StatelessWidget {
  final List<Offset> ecken;
  final Size groesse;
  final int? gezogen;
  final void Function(int index) onGriff;
  final void Function(int index, Offset punkt) onZieht;
  final VoidCallback onLoslassen;

  const _EckenUeberlagerung({
    required this.ecken,
    required this.groesse,
    required this.gezogen,
    required this.onGriff,
    required this.onZieht,
    required this.onLoslassen,
  });

  /// Wie nah man an eine Ecke muss, um sie zu fassen.
  static const _fangradius = 28.0;

  int? _naechsteEcke(Offset punkt) {
    var beste = -1;
    var abstand = _fangradius;
    for (var i = 0; i < ecken.length; i++) {
      final d = (ecken[i] - punkt).distance;
      if (d < abstand) {
        abstand = d;
        beste = i;
      }
    }
    return beste < 0 ? null : beste;
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (d) {
          final i = _naechsteEcke(d.localPosition);
          if (i != null) onGriff(i);
        },
        onPanUpdate: (d) {
          final i = gezogen;
          if (i != null) onZieht(i, d.localPosition);
        },
        onPanEnd: (_) => onLoslassen(),
        child: CustomPaint(painter: _EckenMaler(ecken)),
      ),
    );
  }
}

class _EckenMaler extends CustomPainter {
  final List<Offset> ecken;
  const _EckenMaler(this.ecken);

  @override
  void paint(Canvas canvas, Size size) {
    final pfad = Path()..addPolygon(ecken, true);
    canvas.drawPath(
        pfad,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
    // Der Bereich ausserhalb des Vierecks wird abgedunkelt – so sieht man,
    // was nach dem Entzerren übrig bleibt.
    final aussen = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      pfad,
    );
    canvas.drawPath(aussen, Paint()..color = Colors.black54);

    for (final ecke in ecken) {
      canvas.drawCircle(ecke, 8, Paint()..color = Colors.white);
      canvas.drawCircle(ecke, 8,
          Paint()
            ..color = Colors.black54
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);
    }
  }

  @override
  bool shouldRepaint(covariant _EckenMaler old) => old.ecken != ecken;
}

/// Zeichnet die gemalten Retusche-Striche über dem Bild.
class _RetuscheMaler extends CustomPainter {
  final List<List<Offset>> striche;
  final double breite;
  const _RetuscheMaler(this.striche, this.breite);

  @override
  void paint(Canvas canvas, Size size) {
    final stift = Paint()
      // Halbdurchsichtig, damit man sieht, was darunter liegt – man muss
      // beim Malen erkennen können, ob man das Objekt schon ganz erwischt
      // hat.
      ..color = const Color(0x99FF5252)
      ..style = PaintingStyle.stroke
      ..strokeWidth = breite
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final strich in striche) {
      if (strich.isEmpty) continue;
      if (strich.length == 1) {
        canvas.drawCircle(strich.first, breite / 2, Paint()..color = const Color(0x99FF5252));
        continue;
      }
      final pfad = Path()..moveTo(strich.first.dx, strich.first.dy);
      for (final p in strich.skip(1)) {
        pfad.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(pfad, stift);
    }
  }

  @override
  bool shouldRepaint(covariant _RetuscheMaler old) =>
      old.striche != striche || old.breite != breite;
}
