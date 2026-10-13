import 'package:flutter/material.dart';
import 'package:kern/db/database.dart';
import 'package:kern/db/rasterzeile.dart';
import 'package:kern/services/bildsuche.dart';
import 'package:kern/services/search_filters.dart';

import '../l10n/app_localizations.dart';
import '../sitzung.dart';
import 'raster.dart';

enum _Art { inhalt, text }

/// Suchen – nach Bildinhalt („Strand bei Sonnenuntergang“) oder nach Text
/// (Dateiname, Beschreibung, erkannter Text, Bildbeschreibung, Transkript;
/// siehe `textfundstellen` im Kern).
///
/// Nach Inhalt bettet der Server den Suchtext ein (das Modell dafür gehört
/// nicht aufs Telefon); die Rangfolge rechnet das Telefon mit den
/// abgeglichenen Einbettungen – wie die Desktop-App.
class Suche extends StatefulWidget {
  const Suche({super.key, required this.sitzung});

  final Sitzung sitzung;

  @override
  State<Suche> createState() => _SucheState();
}

class _SucheState extends State<Suche> {
  final _feld = TextEditingController();
  var _art = _Art.inhalt;
  var _laeuft = false;
  List<Rasterzeile>? _treffer;
  String? _hinweis;

  AppDatabase get _db => widget.sitzung.db;

  @override
  void dispose() {
    _feld.dispose();
    super.dispose();
  }

  Future<void> _suche() async {
    final t = AppTexte.of(context);
    final text = _feld.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _laeuft = true;
      _hinweis = null;
    });
    try {
      final vektor = _art == _Art.inhalt
          ? await widget.sitzung.textvektor(text)
          : null;
      if (_art == _Art.inhalt && vektor == null) _hinweis = t.sucheKeinModell;
      final List<AssetData> funde;
      if (vektor != null) {
        // Wie am Desktop: erst die sichtbaren Aufnahmen, dann innerhalb
        // davon nach Ähnlichkeit – Videos mit all ihren Standbildern.
        final erlaubt = (await _db.searchAssetIds(
          const SearchFilters(),
        )).toSet();
        final rangfolge = rangfolgeDerBildsuche(
          vektor,
          suchkandidatenAus(
            await _db.allEmbeddings(),
            await _db.alleVideoeinbettungen(),
          ),
          erlaubt,
        );
        // `assetsByIds` behält die Reihenfolge – die nach Ähnlichkeit.
        funde = await _db.assetsByIds(rangfolge);
      } else {
        final ids = await _db.textfundstellen(text);
        funde = ids.isEmpty
            ? const []
            : await _db.searchAssets(const SearchFilters(), restrictToIds: ids);
      }
      _treffer = [for (final a in funde) Rasterzeile.aus(a)];
    } catch (_) {
      _hinweis = t.sucheFehler;
    } finally {
      if (mounted) setState(() => _laeuft = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final kopf = Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _feld,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _suche(),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: _art == _Art.inhalt
                  ? t.sucheHinweisInhalt
                  : t.sucheHinweisText,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<_Art>(
            segments: [
              ButtonSegment(
                value: _Art.inhalt,
                icon: const Icon(Icons.auto_awesome_outlined),
                label: Text(t.sucheInhalt),
              ),
              ButtonSegment(
                value: _Art.text,
                icon: const Icon(Icons.text_fields),
                label: Text(t.sucheText),
              ),
            ],
            selected: {_art},
            onSelectionChanged: (s) {
              setState(() => _art = s.first);
              if (_feld.text.trim().isNotEmpty) _suche();
            },
          ),
          if (_laeuft) const LinearProgressIndicator(),
          if (_hinweis != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_hinweis!),
            ),
          if (_treffer != null && _treffer!.isEmpty && !_laeuft)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(t.sucheNichts, textAlign: TextAlign.center),
            ),
        ],
      ),
    );
    return AufnahmenRaster(
      sitzung: widget.sitzung,
      zeilen: _treffer ?? const [],
      kopf: kopf,
    );
  }
}
