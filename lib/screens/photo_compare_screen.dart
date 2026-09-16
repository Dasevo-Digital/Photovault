import 'package:flutter/material.dart';

import '../db/database.dart';
import '../l10n/app_localizations.dart';
import '../services/bilddekodierung.dart';
import '../services/storage_paths.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';

/// Stellt zwei frei gewählte Fotos nebeneinander, mit gekoppeltem Zoom.
///
/// Vergleiche gab es bisher nur dort, wo die App selbst zwei Bilder
/// zusammenstellt: bei Duplikaten, in Stapeln, in der Sichtung und als
/// Vorher/Nachher beim Entwickeln. „Diese zwei, frei gewählt" fehlte – und
/// das ist der Vergleich, den man beim Aussuchen aus einer Serie braucht.
///
/// Die Kopplung ist der Kern: Beide Bilder teilen sich einen
/// [TransformationController]. Zoomt oder schiebt man das eine, folgt das
/// andere pixelgenau. Ohne das müsste man zwei Ausschnitte von Hand
/// gleichziehen, und genau daran scheitert der Vergleich zweier fast
/// gleicher Aufnahmen.
class PhotoCompareScreen extends StatefulWidget {
  final AssetData links;
  final AssetData rechts;
  final StoragePaths paths;

  const PhotoCompareScreen({
    super.key,
    required this.links,
    required this.rechts,
    required this.paths,
  });

  @override
  State<PhotoCompareScreen> createState() => _PhotoCompareScreenState();
}

class _PhotoCompareScreenState extends State<PhotoCompareScreen> {
  /// EIN Controller für beide Seiten – das ist die Kopplung. Zwei
  /// Controller mit einem Abgleich dazwischen wären fehleranfälliger und
  /// hätten immer einen Frame Verzug.
  final _sicht = TransformationController();

  /// Ob die beiden Ansichten aneinander hängen. Zum Abschalten, wenn man
  /// zwei unterschiedliche Ausschnitte vergleichen will – etwa bei zwei
  /// Aufnahmen aus verschiedenen Blickwinkeln.
  bool _gekoppelt = true;
  final _sichtRechts = TransformationController();

  /// Übereinander statt nebeneinander. Bei Hochformaten ist das die
  /// bessere Aufteilung; nebeneinander blieben zwei schmale Streifen.
  bool _uebereinander = false;

  @override
  void dispose() {
    _sicht.dispose();
    _sichtRechts.dispose();
    super.dispose();
  }

  void _zuruecksetzen() {
    _sicht.value = Matrix4.identity();
    _sichtRechts.value = Matrix4.identity();
  }

  Widget _seite(AssetData asset, TransformationController regler) {
    final datei =
        widget.paths.absolute(asset.previewRelativePath ?? asset.relativePath);
    return Column(
      children: [
        Expanded(
          child: InteractiveViewer(
            transformationController: regler,
            minScale: 1,
            maxScale: 12,
            // Ohne das verschiebt eine Wischgeste nur, statt zu zoomen –
            // und eine Magic Mouse hat kein Rad, sondern eine Tastfläche.
            // macOS meldet ein Wischen darauf wie ein Trackpad, und
            // Flutters Vorgabe für solche Eingaben ist „verschieben".
            trackpadScrollCausesScale: true,
            // Begrenzt dekodieren, und hier besonders: Dieser
            // Bildschirm zeigt ZWEI Originale gleichzeitig. An der
            // Prüfbibliothek waren das im schlimmsten Fall 317 MB und
            // 236 MB nebeneinander – eine halbe Milliarde Byte für zwei
            // Fotos, die auf je eine halbe Fensterbreite gezeichnet
            // werden.
            child: Center(
              child: Image(image: begrenztesBild(datei), fit: BoxFit.contain),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs, horizontal: AppSpacing.sm),
          child: Text(
            asset.originalFileName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: DunkleFlaeche.zweitText, fontSize: 12),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    // Gekoppelt teilen sich beide Seiten denselben Regler.
    final rechterRegler = _gekoppelt ? _sicht : _sichtRechts;
    final seiten = [
      Expanded(child: _seite(widget.links, _sicht)),
      const VerticalDivider(width: 1, color: DunkleFlaeche.linie),
      Expanded(child: _seite(widget.rechts, rechterRegler)),
    ];

    return Scaffold(
      backgroundColor: DunkleFlaeche.grund,
      appBar: AppBar(
        backgroundColor: DunkleFlaeche.grund,
        foregroundColor: DunkleFlaeche.text,
        title: Text(t.vergleichTitel),
        actions: [
          IconButton(
            tooltip: _uebereinander ? t.vergleichNebeneinander : t.vergleichUebereinander,
            icon: Icon(_uebereinander ? Icons.view_column_outlined : Icons.view_agenda_outlined),
            onPressed: () => setState(() => _uebereinander = !_uebereinander),
          ),
          IconButton(
            tooltip: _gekoppelt ? t.vergleichEntkoppeln : t.vergleichKoppeln,
            icon: Icon(_gekoppelt ? Icons.link : Icons.link_off),
            onPressed: () => setState(() {
              _gekoppelt = !_gekoppelt;
              // Beim Koppeln übernimmt die linke Sicht – sonst spränge die
              // rechte Seite auf einen alten Ausschnitt zurück.
              if (_gekoppelt) _sichtRechts.value = _sicht.value;
            }),
          ),
          IconButton(
            tooltip: t.vergleichZuruecksetzen,
            icon: const Icon(Icons.zoom_out_map),
            onPressed: _zuruecksetzen,
          ),
        ],
      ),
      body: _uebereinander
          ? Column(children: [
              Expanded(child: _seite(widget.links, _sicht)),
              const Divider(height: 1, color: DunkleFlaeche.linie),
              Expanded(child: _seite(widget.rechts, rechterRegler)),
            ])
          : Row(children: seiten),
    );
  }
}
