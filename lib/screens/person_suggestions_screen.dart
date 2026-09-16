import 'package:flutter/material.dart';

import '../db/database.dart';
import '../l10n/app_localizations.dart';
import '../state/library_state.dart';
import '../theme/app_spacing.dart';
import '../widgets/asset_thumbnail_tile.dart';

/// Zeigt die Vorschläge für eine benannte Person zur Bestätigung.
///
/// Alles ist zunächst ausgewählt – die Erkennung hat ja bereits entschieden,
/// dass die Ähnlichkeit über der Schwelle liegt. Der Nutzer nimmt heraus,
/// was nicht stimmt, statt einzeln zu bestätigen. Bei einer Trefferquote
/// jenseits der Hälfte ist das die deutlich kürzere Arbeit.
///
/// Beim Übernehmen wird BEIDES festgehalten: das Bestätigte und das
/// Abgewählte. Nur so lernt die persönliche Schwelle (siehe
/// face_threshold.dart) – eine Ablehnung ist die aussagekräftigere der
/// beiden Rückmeldungen, weil sie die Grenze nach oben schiebt.
class PersonSuggestionsScreen extends StatefulWidget {
  final LibraryState library;
  final PersonData person;
  final List<({FaceData gesicht, double aehnlichkeit})> vorschlaege;

  const PersonSuggestionsScreen({
    super.key,
    required this.library,
    required this.person,
    required this.vorschlaege,
  });

  @override
  State<PersonSuggestionsScreen> createState() => _PersonSuggestionsScreenState();
}

class _PersonSuggestionsScreenState extends State<PersonSuggestionsScreen> {
  late final Set<String> _gewaehlt = {
    for (final v in widget.vorschlaege) v.gesicht.id,
  };
  bool _laeuft = false;

  Future<void> _uebernehmen() async {
    setState(() => _laeuft = true);
    final angenommen = [
      for (final v in widget.vorschlaege)
        if (_gewaehlt.contains(v.gesicht.id)) v.gesicht.id,
    ];
    if (angenommen.isNotEmpty) {
      await widget.library.db.assignFacesToPerson(angenommen, widget.person.id);
    }

    // Das Abgewaehlte verliert seinen gespeicherten Vorschlag. Ohne das
    // stuende dieselbe Frage nach jedem Oeffnen der Liste wieder da – die
    // Antwort ist aber gegeben, und sie steckt ab jetzt in der Schwelle
    // dieser Person.
    final abgelehnt = [
      for (final v in widget.vorschlaege)
        if (!_gewaehlt.contains(v.gesicht.id)) v.gesicht.id,
    ];
    if (abgelehnt.isNotEmpty) {
      await widget.library.db.verwirfVorschlaege(abgelehnt);
    }

    await widget.library.db.merkeGesichtsEntscheidungen(
      widget.person.id,
      [
        for (final v in widget.vorschlaege)
          (
            faceId: v.gesicht.id,
            accepted: _gewaehlt.contains(v.gesicht.id),
            similarity: v.aehnlichkeit,
          ),
      ],
      allgemeineSchwelle: widget.library.faceSimilarityThreshold,
    );

    if (!mounted) return;
    Navigator.of(context).pop(angenommen.length);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.vorschlagTitel(widget.person.name)),
        actions: [
          TextButton(
            onPressed: _laeuft
                ? null
                : () => setState(() => _gewaehlt.length == widget.vorschlaege.length
                    ? _gewaehlt.clear()
                    : _gewaehlt.addAll(
                        [for (final v in widget.vorschlaege) v.gesicht.id])),
            child: Text(_gewaehlt.length == widget.vorschlaege.length
                ? t.vorschlagKeineWaehlen
                : t.vorschlagAlleWaehlen),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.sm),
            child: Text(
              t.vorschlagHinweis,
              style: TextStyle(
                  fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(AppSpacing.md),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 110,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
              ),
              itemCount: widget.vorschlaege.length,
              itemBuilder: (context, index) {
                final v = widget.vorschlaege[index];
                final pfad = v.gesicht.cropRelativePath;
                if (pfad == null) return const SizedBox.shrink();
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    LocalImageTile(
                      file: widget.library.paths.absolute(pfad),
                      selected: _gewaehlt.contains(v.gesicht.id),
                      onTap: () => setState(() =>
                          _gewaehlt.contains(v.gesicht.id)
                              ? _gewaehlt.remove(v.gesicht.id)
                              : _gewaehlt.add(v.gesicht.id)),
                    ),
                    // Die Ähnlichkeit sichtbar zu machen ist kein Selbstzweck:
                    // Bei einem knappen Wert lohnt das genaue Hinsehen, bei
                    // einem hohen genügt der Blick.
                    Positioned(
                      left: 2,
                      bottom: 2,
                      // Ohne IgnorePointer schluckt der Text den Klick:
                      // Ein Textabsatz nimmt Zeigerereignisse selbst an,
                      // und wer auf die Zahl tippt, hätte nichts bewirkt.
                      child: IgnorePointer(
                          child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          child: Text(
                            v.aehnlichkeit.toStringAsFixed(2),
                            style: const TextStyle(fontSize: 10, color: Colors.white),
                          ),
                        ),
                      )),
                    ),
                  ],
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _laeuft ? null : _uebernehmen,
                icon: const Icon(Icons.person_add_alt_1),
                label: Text(t.vorschlagUebernehmen(_gewaehlt.length)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
