import 'package:flutter/material.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/asset_display_path.dart';
import 'package:kern/services/gesichtsuebersicht.dart';

import '../bilder.dart';
import '../formate.dart';
import '../l10n/app_localizations.dart';
import '../sitzung.dart';

/// Ein Gesicht im ganzen Foto (Issue #189) – der kleine Ausschnitt sagt
/// oft nicht, wer das ist; das Foto drumherum schon. Wie im Browser
/// (web/app.js, zeigeImFoto): alle Gesichter des Fotos mit Rahmen, das
/// gewählte orange, benannte grün mit Namen.
Future<void> zeigeGesichtImFoto(
  BuildContext context,
  Sitzung sitzung,
  FaceData gesicht,
) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => GesichtImFoto(sitzung: sitzung, gesicht: gesicht),
  ),
);

/// Der kleine Knopf in der Ecke eines Gesichtsausschnitts, der
/// [zeigeGesichtImFoto] öffnet.
class ImFotoKnopf extends StatelessWidget {
  const ImFotoKnopf({super.key, required this.beiTipp});

  final VoidCallback beiTipp;

  @override
  Widget build(BuildContext context) {
    final farben = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: AppTexte.of(context).gesichtImFoto,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: beiTipp,
        // Grösser als das Zeichen: Mit dem Finger muss es zu treffen sein.
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: farben.onSurface,
              shape: BoxShape.circle,
              border: Border.all(color: farben.surface, width: 2),
            ),
            child: Icon(
              Icons.center_focus_strong_outlined,
              size: 15,
              color: farben.surface,
            ),
          ),
        ),
      ),
    );
  }
}

class GesichtImFoto extends StatefulWidget {
  const GesichtImFoto({
    super.key,
    required this.sitzung,
    required this.gesicht,
  });

  final Sitzung sitzung;
  final FaceData gesicht;

  @override
  State<GesichtImFoto> createState() => _GesichtImFotoState();
}

class _GesichtImFotoState extends State<GesichtImFoto> {
  AssetData? _aufnahme;
  List<GesichtAufAufnahme> _gesichter = const [];

  @override
  void initState() {
    super.initState();
    _lade();
  }

  Future<void> _lade() async {
    final db = widget.sitzung.db;
    final a = await db.assetById(widget.gesicht.assetId);
    final g = await gesichterDerAufnahme(db, widget.gesicht.assetId);
    if (!mounted || a == null) return;
    setState(() {
      _aufnahme = a;
      _gesichter = g;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final a = _aufnahme;
    final sprache = Localizations.localeOf(context).toLanguageTag();
    // Breite und Höhe so, wie das Bild gezeigt wird – dieselben Masse, nach
    // denen das Raster seine Kacheln legt. Die Rahmen sind Anteile davon.
    final w = a?.widthPx, h = a?.heightPx;
    final seitenverhaeltnis = w != null && h != null && w > 0 && h > 0
        ? w / h
        : 4 / 3;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: a == null
            ? null
            : Text(
                [
                  datumZeitMittel(sprache).format(a.fileCreatedAt),
                  ?a.locationCity,
                ].join(' · '),
                style: const TextStyle(fontSize: 16),
              ),
      ),
      body: SafeArea(
        child: a == null
            ? const Center(child: CircularProgressIndicator())
            : InteractiveViewer(
                maxScale: 6,
                child: Center(
                  child: AspectRatio(
                    aspectRatio: seitenverhaeltnis,
                    child: LayoutBuilder(
                      builder: (context, c) => Stack(
                        fit: StackFit.expand,
                        children: [
                          Image(
                            image: BibliotheksBild(
                              widget.sitzung.paths,
                              displayRelativePath(a),
                            ),
                            fit: BoxFit.fill,
                            errorBuilder: (context, _, _) => Center(
                              child: Text(
                                t.gesichtFotoFehlt,
                                style: const TextStyle(color: Colors.white70),
                              ),
                            ),
                          ),
                          for (final (:gesicht, :person) in _gesichter)
                            _Rahmen(
                              gesicht: gesicht,
                              name: person?.name,
                              gewaehlt: gesicht.id == widget.gesicht.id,
                              flaeche: c.biggest,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

class _Rahmen extends StatelessWidget {
  const _Rahmen({
    required this.gesicht,
    required this.name,
    required this.gewaehlt,
    required this.flaeche,
  });

  final FaceData gesicht;
  final String? name;
  final bool gewaehlt;
  final Size flaeche;

  @override
  Widget build(BuildContext context) {
    final farbe = gewaehlt
        ? const Color(0xFFF76B15)
        : name != null
        ? const Color(0xFF30A46C)
        : Colors.white70;
    return Positioned(
      left: gesicht.boxX * flaeche.width,
      top: gesicht.boxY * flaeche.height,
      width: gesicht.boxW * flaeche.width,
      height: gesicht.boxH * flaeche.height,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: farbe, width: gewaehlt ? 3 : 2),
          borderRadius: BorderRadius.circular(4),
        ),
        child: name == null || gewaehlt
            ? null
            : OverflowBox(
                alignment: Alignment.bottomLeft,
                maxWidth: 240,
                maxHeight: double.infinity,
                child: Transform.translate(
                  offset: const Offset(0, 22),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      name!,
                      maxLines: 1,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
