import 'package:flutter/material.dart';
import 'package:kern/db/database.dart';
import 'package:kern/db/rasterzeile.dart';
import 'package:kern/services/asset_display_path.dart';

import '../bilder.dart';
import '../l10n/app_localizations.dart';
import '../sitzung.dart';

/// Zwei frei gewählte Fotos nebeneinander oder übereinander (Issue #197),
/// wie am Rechner (photo_compare_screen.dart) und im Browser.
///
/// Die Kopplung ist der Kern: Beide Seiten teilen sich einen
/// [TransformationController]. Zoomt oder schiebt man das eine, folgt das
/// andere genau – sonst müsste man zwei Ausschnitte von Hand gleichziehen,
/// und genau daran scheitert der Vergleich zweier fast gleicher Aufnahmen.
class Vergleich extends StatefulWidget {
  const Vergleich({
    super.key,
    required this.sitzung,
    required this.links,
    required this.rechts,
  });

  final Sitzung sitzung;
  final Rasterzeile links;
  final Rasterzeile rechts;

  @override
  State<Vergleich> createState() => _VergleichState();
}

class _VergleichState extends State<Vergleich> {
  final _sicht = TransformationController();
  final _sichtRechts = TransformationController();
  var _gekoppelt = true;

  /// `null`, solange niemand umgeschaltet hat: dann hochkant übereinander,
  /// sonst blieben zwei schmale Streifen.
  bool? _uebereinander;

  static const _grund = Color(0xFF111111);
  static const _linie = Color(0xFF333333);

  @override
  void dispose() {
    _sicht.dispose();
    _sichtRechts.dispose();
    super.dispose();
  }

  void _zurueck() {
    _sicht.value = Matrix4.identity();
    _sichtRechts.value = Matrix4.identity();
  }

  Widget _seite(Rasterzeile z, TransformationController regler) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(
        child: ClipRect(
          child: InteractiveViewer(
            transformationController: regler,
            minScale: 1,
            maxScale: 8,
            child: Center(
              child: _Bild(sitzung: widget.sitzung, zeile: z),
            ),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          z.originalFileName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final ueber =
        _uebereinander ??
        MediaQuery.orientationOf(context) == Orientation.portrait;
    return Scaffold(
      backgroundColor: _grund,
      appBar: AppBar(
        backgroundColor: _grund,
        foregroundColor: Colors.white,
        title: Text(t.vergleichTitel),
        actions: [
          IconButton(
            tooltip: ueber
                ? t.vergleichNebeneinander
                : t.vergleichUebereinander,
            icon: Icon(
              ueber ? Icons.view_column_outlined : Icons.view_agenda_outlined,
            ),
            onPressed: () => setState(() {
              _uebereinander = !ueber;
              _zurueck();
            }),
          ),
          IconButton(
            tooltip: _gekoppelt ? t.vergleichEntkoppeln : t.vergleichKoppeln,
            icon: Icon(_gekoppelt ? Icons.link_off : Icons.link),
            onPressed: () => setState(() {
              // Entkoppelt beginnt die zweite Seite dort, wo beide stehen.
              if (_gekoppelt) _sichtRechts.value = _sicht.value.clone();
              _gekoppelt = !_gekoppelt;
            }),
          ),
          IconButton(
            tooltip: t.vergleichZuruecksetzen,
            icon: const Icon(Icons.zoom_out_map),
            onPressed: _zurueck,
          ),
        ],
      ),
      body: Flex(
        direction: ueber ? Axis.vertical : Axis.horizontal,
        children: [
          Expanded(child: _seite(widget.links, _sicht)),
          if (ueber)
            const Divider(height: 1, color: _linie)
          else
            const VerticalDivider(width: 1, color: _linie),
          Expanded(
            child: _seite(widget.rechts, _gekoppelt ? _sicht : _sichtRechts),
          ),
        ],
      ),
    );
  }
}

/// Das Foto selbst, auf höchstens 2000 Punkte dekodiert – hier stehen zwei
/// zugleich. Bis es da ist, die Miniatur.
class _Bild extends StatelessWidget {
  const _Bild({required this.sitzung, required this.zeile});

  final Sitzung sitzung;
  final Rasterzeile zeile;

  @override
  Widget build(BuildContext context) {
    final t = zeile.thumbnailRelativePath;
    final miniatur = t == null
        ? const SizedBox.shrink()
        : Image(image: BibliotheksBild(sitzung.paths, t), fit: BoxFit.contain);
    return FutureBuilder<AssetData?>(
      future: sitzung.db.assetById(zeile.id),
      builder: (context, snap) {
        final a = snap.data;
        if (a == null) return miniatur;
        return Image(
          image: ResizeImage(
            BibliotheksBild(sitzung.paths, displayRelativePath(a)),
            width: 2000,
            height: 2000,
            policy: ResizeImagePolicy.fit,
            allowUpscaling: false,
          ),
          fit: BoxFit.contain,
          gaplessPlayback: true,
          frameBuilder: (context, kind, frame, sofort) =>
              frame == null && !sofort ? miniatur : kind,
          errorBuilder: (_, _, _) => miniatur,
        );
      },
    );
  }
}
