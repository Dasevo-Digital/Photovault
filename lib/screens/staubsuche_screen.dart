import 'dart:io';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../db/database.dart';
import '../l10n/app_localizations.dart';
import '../services/bilddekodierung.dart';
import '../services/staubflecken.dart';
import '../state/library_state.dart';
import '../theme/app_spacing.dart';
import 'image_editor_screen.dart';

/// Sucht Sensorstaub in den Aufnahmen einer Kamera.
///
/// **Warum je Kamera und nicht über die ganze Bibliothek.** Staub sitzt auf
/// dem Sensor, nicht im Motiv. Aufnahmen verschiedener Gehäuse
/// zusammenzuwerfen hiesse, die eine Eigenschaft wegzumitteln, an der man
/// Staub überhaupt erkennt – dass er an derselben Stelle bleibt.
///
/// Der Lauf dauert: rund eine halbe bis eine Sekunde je Aufnahme (an der
/// echten Bibliothek gemessen). Deshalb ein eigener Bildschirm mit
/// Fortschritt statt eines Knopfes, der eine Minute lang nichts tut.
class StaubsucheScreen extends StatefulWidget {
  final LibraryState library;
  const StaubsucheScreen({super.key, required this.library});

  @override
  State<StaubsucheScreen> createState() => _StaubsucheScreenState();
}

/// Wie viele Aufnahmen je Lauf untersucht werden.
///
/// Vierzig. Weniger, und die Bestätigung über die Serie wird zum Zufall –
/// bei zehn Aufnahmen genügen sechs zufällige Übereinstimmungen. Mehr, und
/// der Lauf dauert länger als eine Minute, ohne mehr zu finden.
const int _stichprobe = 40;

class _StaubsucheScreenState extends State<StaubsucheScreen> {
  List<String>? _kameras;
  String? _kamera;

  bool _laeuft = false;
  int _erledigt = 0;
  int _gesamt = 0;

  List<Staubstelle>? _ergebnis;
  List<AssetData> _untersucht = const [];

  /// Wie viele Aufnahmen gezogen wurden. Unterscheidet sich von
  /// [_untersucht], sobald eine Datei fehlt oder sich nicht lesen lässt –
  /// und dann muss es dastehen: „kein Staub gefunden" nach fünf von vierzig
  /// Aufnahmen ist keine Entwarnung.
  int _gezogen = 0;

  @override
  void initState() {
    super.initState();
    _ladeKameras();
  }

  Future<void> _ladeKameras() async {
    final kameras = await widget.library.db.distinctCameraModels();
    if (mounted) setState(() => _kameras = kameras);
  }

  Future<void> _suche() async {
    final kamera = _kamera;
    if (kamera == null) return;
    setState(() {
      _laeuft = true;
      _ergebnis = null;
      _erledigt = 0;
      _gesamt = 0;
    });

    final aufnahmen = await widget.library.db.aufnahmenDerKamera(kamera, _stichprobe);
    if (!mounted) return;
    setState(() => _gesamt = aufnahmen.length);

    final proAufnahme = <List<Staubverdacht>>[];
    final genommen = <AssetData>[];
    for (final asset in aufnahmen) {
      // Die Vorschau, wenn es eine gibt – genau wie überall sonst, wo aus
      // dem Bildinhalt etwas gerechnet wird (siehe
      // `LibraryState._decodeAsset`). Ohne das fiel die Suche bei jeder
      // RAW-Aufnahme still aus: Das `image`-Paket dekodiert weder CR3 noch
      // DNG und gibt nach neun Millisekunden `null` zurück. Bei einer
      // Canon EOS R10 mit 939 Aufnahmen blieben von vierzig gezogenen fünf
      // übrig – und gemeldet wurde „kein Staub gefunden".
      //
      // Die Vorschau misst 2048 Punkte an der langen Kante und liegt damit
      // über den [staubSuchkante] 1024, auf die ohnehin verkleinert wird.
      // Es geht also keine Genauigkeit verloren, nur Speicher: Das grösste
      // Original der Prüfbibliothek treibt den Arbeitssatz beim Dekodieren
      // von 328 auf 1226 MB, seine Vorschau nicht messbar.
      final datei = widget.library.paths
          .absolute(asset.previewRelativePath ?? asset.relativePath);
      try {
        if (await datei.exists()) {
          // In einem eigenen Isolat: Die Weichzeichnung braucht knapp eine
          // Sekunde, und die Oberfläche soll dabei nicht stehen.
          final verdachte = await compute(_sucheInDatei, datei.path);
          if (verdachte != null) {
            proAufnahme.add(verdachte);
            genommen.add(asset);
          }
        }
      } catch (_) {
        // Eine nicht lesbare Datei überspringen – ein Formatfehler darf den
        // Lauf nicht beenden.
      }
      if (!mounted) return;
      setState(() => _erledigt++);
    }

    final stellen = bestaetigeUeberSerie(proAufnahme);
    if (!mounted) return;
    setState(() {
      _laeuft = false;
      _ergebnis = stellen;
      _untersucht = genommen;
      _gezogen = aufnahmen.length;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.staubTitel)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Text(t.staubErklaerung),
          const SizedBox(height: AppSpacing.lg),
          if (_kameras == null)
            const Center(child: CircularProgressIndicator())
          else if (_kameras!.isEmpty)
            Text(t.staubKeineKameras)
          else
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _kamera,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: t.allgKamera,
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      for (final k in _kameras!)
                        DropdownMenuItem(value: k, child: Text(k, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: _laeuft ? null : (w) => setState(() => _kamera = w),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                FilledButton(
                  onPressed: _laeuft || _kamera == null ? null : _suche,
                  child: Text(t.staubSuchen),
                ),
              ],
            ),
          if (_laeuft) ...[
            const SizedBox(height: AppSpacing.lg),
            LinearProgressIndicator(value: _gesamt == 0 ? null : _erledigt / _gesamt),
            const SizedBox(height: AppSpacing.sm),
            Text(t.staubFortschritt(_erledigt, _gesamt)),
          ],
          if (_ergebnis != null) ...[
            const SizedBox(height: AppSpacing.xl),
            // Vor dem Ergebnis und unabhängig davon, wie es ausfällt: Auch
            // ein Fund ruht nur auf dem, was gelesen werden konnte.
            if (_untersucht.length < _gezogen) ...[
              _Uebersprungen(
                  uebersprungen: _gezogen - _untersucht.length,
                  gezogen: _gezogen),
              const SizedBox(height: AppSpacing.lg),
            ],
            if (_ergebnis!.isEmpty)
              _Sauber(untersucht: _untersucht.length)
            else
              _Fundliste(
                stellen: _ergebnis!,
                beispiel: _untersucht.first,
                library: widget.library,
              ),
          ],
        ],
      ),
    );
  }
}

/// Läuft in einem eigenen Isolat. `null` heisst: Datei nicht deutbar.
List<Staubverdacht>? _sucheInDatei(String pfad) {
  final bild = img.decodeImage(File(pfad).readAsBytesSync());
  return bild == null ? null : findeStaubverdacht(bild);
}

/// Der Hinweis, dass die Stichprobe kleiner war als gezogen.
///
/// Ein „kein Sensorstaub gefunden" nach fünf von vierzig Aufnahmen ist
/// keine Entwarnung – und ein Fund auf fünf von vierzig ist auch keine
/// belastbare Aussage. Deshalb steht der Hinweis über beiden Ergebnissen
/// und nicht nur über dem freundlichen.
class _Uebersprungen extends StatelessWidget {
  final int uebersprungen;
  final int gezogen;
  const _Uebersprungen({required this.uebersprungen, required this.gezogen});

  @override
  Widget build(BuildContext context) {
    final farben = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline, size: 20, color: farben.tertiary),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            AppTexte.of(context).staubUebersprungen(uebersprungen, gezogen),
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: farben.tertiary),
          ),
        ),
      ],
    );
  }
}

class _Sauber extends StatelessWidget {
  final int untersucht;
  const _Sauber({required this.untersucht});

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    return Column(
      children: [
        Icon(Icons.check_circle_outline,
            size: 56, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: AppSpacing.md),
        Text(t.staubNichtsGefunden(untersucht), textAlign: TextAlign.center),
      ],
    );
  }
}

/// Die bestätigten Stellen, eingezeichnet auf eine der untersuchten
/// Aufnahmen.
///
/// Auf einem echten Bild und nicht auf einem leeren Rechteck: Wo der Fleck
/// sitzt, sagt einem erst das Motiv daneben.
class _Fundliste extends StatelessWidget {
  final List<Staubstelle> stellen;
  final AssetData beispiel;
  final LibraryState library;

  const _Fundliste({
    required this.stellen,
    required this.beispiel,
    required this.library,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final vorschau = beispiel.thumbnailRelativePath ?? beispiel.relativePath;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t.staubGefunden(stellen.length),
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.md),
        Stack(
          children: [
            // Gedeckelt: Ein Original der Bibliothek misst bis zu 20383
            // Punkte und belegt ungedeckelt 317 MB.
            Image(
              image: begrenztesBild(library.paths.absolute(vorschau), kante: 1600),
              fit: BoxFit.contain,
            ),
            Positioned.fill(
              child: CustomPaint(painter: _Stellenmaler(stellen)),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        for (final s in stellen)
          ListTile(
            dense: true,
            leading: const Icon(Icons.blur_circular_outlined),
            title: Text('${(s.x * 100).toStringAsFixed(1)} % / '
                '${(s.y * 100).toStringAsFixed(1)} %'),
            subtitle: Text(t.staubAufWievielen(s.treffer, s.untersucht)),
          ),
        const SizedBox(height: AppSpacing.md),
        // Entfernt wird von Hand, mit dem Reparaturpinsel, der längst da
        // ist. Alle Fotos in einem Zug zu überschreiben wäre eine
        // Massenänderung an Originalen ohne Rückweg.
        OutlinedButton.icon(
          icon: const Icon(Icons.healing_outlined),
          label: Text(t.staubImEditorOeffnen),
          onPressed: () => Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
            builder: (_) => ImageEditorScreen(
              asset: beispiel,
              db: library.db,
              paths: library.paths,
              modelsDir: library.modelsDir,
            ),
          )),
        ),
      ],
    );
  }
}

class _Stellenmaler extends CustomPainter {
  final List<Staubstelle> stellen;
  const _Stellenmaler(this.stellen);

  @override
  void paint(Canvas canvas, Size size) {
    final stift = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xFFFF5252);
    for (final s in stellen) {
      final r = (s.radius * size.height).clamp(8.0, 60.0) + 6;
      canvas.drawCircle(Offset(s.x * size.width, s.y * size.height), r, stift);
    }
  }

  @override
  bool shouldRepaint(_Stellenmaler alt) => alt.stellen != stellen;
}
