import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'package:uuid/uuid.dart';

import '../db/database.dart';
import '../db/rasterzeile.dart';
import '../services/suchfehler.dart';
import '../services/serienvorschlag.dart';
import 'serienvergleich_screen.dart';
import '../state/library_state.dart';
import '../theme/app_spacing.dart';
import '../widgets/asset_thumbnail_tile.dart';
import '../widgets/selection_action_bar.dart';

/// Gruppiert Fotos, die sich sowohl visuell ähneln ALS AUCH zeitlich nah
/// beieinander aufgenommen wurden ([findBurstGroups]) – z.B. Serienbilder
/// vom Fotoapparat oder mehrere Smartphone-Aufnahmen derselben Szene kurz
/// hintereinander. Muster wie [DuplicatesScreen], aber statt "löschen"
/// fasst "Übernehmen" eine Gruppe zu einem Stapel zusammen (ein Titelbild
/// bleibt in Timeline & Co. sichtbar, siehe AppDatabase.createStack) statt
/// Fotos zu entfernen – nichts geht dabei verloren, "Serie auflösen" im
/// Info-Panel macht die Gruppierung jederzeit rückgängig.
class StackReviewScreen extends StatefulWidget {
  final LibraryState library;
  const StackReviewScreen({super.key, required this.library});

  @override
  State<StackReviewScreen> createState() => _StackReviewScreenState();
}

class _StackReviewScreenState extends State<StackReviewScreen> {
  bool _loading = true;
  Suchfehlerstand? _error;
  List<List<AssetData>> _groups = [];

  /// Gewählter Titelbild-Index je Gruppe (Index in [_groups]) – defaultmäßig
  /// das Foto mit dem höchsten Unschärfe-Score (siehe [_defaultCoverIndex]),
  /// vom Nutzer per Antippen änderbar.
  final Map<int, int> _coverIndexByGroup = {};

  /// Läuft gerade „alle übernehmen"?
  bool _uebernimmtAlle = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      if (!widget.library.clipAvailable) {
        setState(() {
          _error = const Suchfehlerstand(Suchfehler.clipFehlt);
          _groups = [];
        });
        return;
      }

      // Eine eigene Liste: Der Vorrat gehoert dem LibraryState, und die
      // Anzeige darf ihn nicht nebenbei umbauen. Was hier erledigt wird,
      // wird ihm ausdruecklich gesagt (siehe serieErledigt).
      final groups = [...await widget.library.serienvorschlaegeGecacht()];

      if (!mounted) return;
      setState(() {
        _groups = groups;
        _error = null;
        _coverIndexByGroup
          ..clear()
          ..addEntries(groups.indexed.map((e) => MapEntry(e.$1, _defaultCoverIndex(e.$2))));
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = Suchfehlerstand(Suchfehler.gescheitert, '$e'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Schärfstes Foto der Gruppe (siehe blur_detection.dart) als
  /// Titelbild-Vorschlag – Fotos ohne berechneten Score gelten als am
  /// unschärfsten, damit ein tatsächlich vermessenes Foto immer Vorrang hat.
  int _defaultCoverIndex(List<AssetData> group) {
    var bestIndex = 0;
    var bestScore = group.first.sharpnessScore ?? -1;
    for (var i = 1; i < group.length; i++) {
      final score = group[i].sharpnessScore ?? -1;
      if (score > bestScore) {
        bestScore = score;
        bestIndex = i;
      }
    }
    return bestIndex;
  }

  Future<void> _applyStack(int groupIndex) async {
    final group = _groups[groupIndex];
    final coverIndex = _coverIndexByGroup[groupIndex] ?? 0;
    await widget.library.db.createStack(
      const Uuid().v4(),
      group.map((a) => a.id).toList(),
      group[coverIndex].id,
    );
    widget.library.serieErledigt(group);
    if (!mounted) return;
    setState(() {
      _groups.removeAt(groupIndex);
      _reindexCovers(groupIndex);
    });
  }

  Future<void> _discardGroup(int groupIndex) async {
    // Gemerkt, nicht nur weggeblendet: Wer einmal „nein" gesagt hat, will
    // nicht bei jedem Öffnen erneut gefragt werden.
    final gruppe = _groups[groupIndex];
    await widget.library.db.verwirfSerienvorschlag(serienschluessel(gruppe));
    widget.library.serieErledigt(gruppe);
    if (!mounted) return;
    setState(() {
      _groups.removeAt(groupIndex);
      _reindexCovers(groupIndex);
    });
  }

  /// Übernimmt alle vorgeschlagenen Serien auf einmal.
  ///
  /// **Warum es den Knopf braucht.** In der Prüfbibliothek findet die
  /// Erkennung 286 brauchbare Gruppen. Einzeln bestätigt wären das 286
  /// Klicks – genau die Rechnung, an der bis 2.5.0 die Bewertungen
  /// scheiterten. Das Titelbild ist je Gruppe das schärfste Foto, und
  /// „Serie auflösen" im Info-Blatt nimmt jede Gruppierung wieder zurück;
  /// verloren geht dabei nichts.
  Future<void> _uebernimmAlle() async {
    setState(() => _uebernimmtAlle = true);
    try {
      // **In einem Zug und nicht 499 Mal einzeln.** Jede Buchung ist
      // sonst ein eigener Vorgang samt Hin- und Rueckweg zum
      // Datenbank-Isolate. An der gewachsenen Bibliothek gemessen:
      // 249 Gruppen einzeln 155 ms, dieselbe Zahl in einem Zug 40 ms.
      await widget.library.db.transaction(() async {
        for (var i = _groups.length - 1; i >= 0; i--) {
          final gruppe = _groups[i];
          await widget.library.db.createStack(
            const Uuid().v4(),
            [for (final a in gruppe) a.id],
            gruppe[_coverIndexByGroup[i] ?? 0].id,
          );
        }
      });
      widget.library.serienGeleert();
      if (!mounted) return;
      setState(() {
        _groups.clear();
        _coverIndexByGroup.clear();
      });
    } finally {
      if (mounted) setState(() => _uebernimmtAlle = false);
    }
  }

  void _reindexCovers(int entfernt) {
    final verschoben = verschobeneTitelwahl(_coverIndexByGroup, entfernt);
    _coverIndexByGroup
      ..clear()
      ..addAll(verschoben);
  }

  Future<void> _frageAlle() async {
    final t = AppTexte.of(context);
    final anzahl = _groups.length;
    final ja = await confirmDialog(
        context, t.stapelAlleFrageTitel, t.stapelAlleFrage(anzahl));
    if (ja) await _uebernimmAlle();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppTexte.of(context).werkzStapelTitel),
        actions: [
          // 286 Gruppen einzeln zu bestätigen wären 286 Klicks – genau die
          // Rechnung, an der bis 2.5.0 die Bewertungen scheiterten.
          if (_groups.length > 1)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.md),
              child: FilledButton.tonalIcon(
                onPressed: _uebernimmtAlle ? null : _frageAlle,
                icon: _uebernimmtAlle
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.done_all),
                label: Text(AppTexte.of(context)
                    .stapelAlleUebernehmen(_groups.length)),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0),
            child: Text(
              AppTexte.of(context).stapelErklaerung,
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          const Divider(height: 16),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Text(_error!.satz(AppTexte.of(context)),
              textAlign: TextAlign.center),
        ),
      );
    }
    if (_groups.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Text(AppTexte.of(context).stapelKeine, textAlign: TextAlign.center),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: _groups.length,
      itemBuilder: (context, groupIndex) {
        final group = _groups[groupIndex];
        final coverIndex = _coverIndexByGroup[groupIndex] ?? 0;
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(AppTexte.of(context).stapelSerie(groupIndex + 1, group.length),
                        style: Theme.of(context).textTheme.titleSmall),
                  ),
                  // Vor dem Verwerfen: erst ansehen, wer blinzelt.
                  TextButton.icon(
                    onPressed: () => Navigator.of(context, rootNavigator: true).push(
                      MaterialPageRoute(
                        builder: (_) => SerienvergleichScreen(
                            library: widget.library, serie: group),
                      ),
                    ),
                    icon: const Icon(Icons.face_retouching_natural, size: 18),
                    label:
                        Text(AppTexte.of(context).serienvergleichOeffnen),
                  ),
                  TextButton(
                    onPressed: () => _discardGroup(groupIndex),
                    child: Text(AppTexte.of(context).allgVerwerfen),
                  ),
                  FilledButton(
                    onPressed: () => _applyStack(groupIndex),
                    child: Text(AppTexte.of(context).allgUebernehmen),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 160,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: group.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final asset = group[index];
                    final isCover = index == coverIndex;
                    return SizedBox(
                      width: 140,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                border: isCover
                                    ? Border.all(color: Theme.of(context).colorScheme.primary, width: 3)
                                    : null,
                              ),
                              child: AssetThumbnailTile(
                                asset: Rasterzeile.aus(asset),
                                paths: widget.library.paths,
                                onTap: () => setState(() => _coverIndexByGroup[groupIndex] = index),
                              ),
                            ),
                          ),
                          Positioned(
                            left: 4,
                            top: 4,
                            child: Material(
                              color: Colors.black54,
                              shape: const CircleBorder(),
                              child: Padding(
                                padding: const EdgeInsets.all(AppSpacing.xs),
                                child: Icon(
                                  isCover ? Icons.star : Icons.star_border,
                                  color: isCover ? Colors.amber : Colors.white70,
                                  size: 16,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Zieht die Titelbild-Wahl mit, wenn die Gruppe auf Platz [entfernt]
/// aus der Liste faellt.
///
/// **Der Fehler, den das behebt.** Die Karte ist nach Listenplatz
/// geordnet, die Liste aber schrumpft mit jeder uebernommenen Gruppe. Wer
/// Gruppe 1 uebernahm, rueckte Gruppe 2 auf Platz 1 – und bekam dort die
/// Sternwahl der uebernommenen. Der vorherige Rumpf schrieb jeden Platz
/// auf sich selbst zurueck und verschob damit gar nichts.
///
/// Als eigene Funktion und nicht als Rumpf im Zustand: Sonst koennte ein
/// Pruefstand sie nur nachrechnen, und ein Test, der die Rechnung
/// nachbaut, faellt auch dann nicht, wenn die echte falsch ist.
Map<int, int> verschobeneTitelwahl(Map<int, int> wahl, int entfernt) {
  final verschoben = <int, int>{};
  for (final e in wahl.entries) {
    if (e.key == entfernt) continue;
    verschoben[e.key > entfernt ? e.key - 1 : e.key] = e.value;
  }
  return verschoben;
}
