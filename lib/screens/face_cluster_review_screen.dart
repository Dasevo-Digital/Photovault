import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'package:uuid/uuid.dart';

import '../db/database.dart';
import '../state/library_state.dart';
import '../theme/app_spacing.dart';
import '../widgets/person_picker_dialog.dart';

/// Eine per Union-Find-Clustering (siehe face_clustering_service.dart)
/// vorgeschlagene Gruppe unzugeordneter Gesichter, die vermutlich zur
/// selben Person gehören – optional mit einem Vorschlag, welche bereits
/// benannte Person das sein könnte (Centroid-Vergleich).
class FaceClusterSuggestion {
  final List<FaceData> faces;
  final PersonData? suggestedPerson;

  /// Ähnlichkeit zwischen diesem Cluster und [suggestedPerson] – nur
  /// gesetzt, wenn es einen Vorschlag gibt.
  ///
  /// Wird beim Zuordnen als Rückmeldung festgehalten: Ohne den Wert zum
  /// Zeitpunkt der Entscheidung liesse sich später keine Schwelle daraus
  /// ableiten (siehe face_threshold.dart).
  final double? similarity;

  const FaceClusterSuggestion({
    required this.faces,
    this.suggestedPerson,
    this.similarity,
  });
}

/// Review-Ansicht für die Vorschläge aus "Automatisch gruppieren": jede
/// Karte zeigt eine vermutete Personengruppe zur Bestätigung durch den
/// Nutzer. Es wird nie automatisch/still zugeordnet – passend zur sonst in
/// der App durchgängigen Konvention, dass KI-gestützte Operationen manuell
/// ausgelöst UND bestätigt werden (siehe z.B. Gesichts-Scan, KI-Tagging).
/// Jede Zuordnung wird sofort committet, kein Sammel-Commit am Ende; nicht
/// durchgesehene Cluster bleiben unzugeordnet und tauchen beim nächsten
/// "Automatisch gruppieren"-Lauf wieder auf.
class FaceClusterReviewScreen extends StatefulWidget {
  final LibraryState library;
  final List<FaceClusterSuggestion> suggestions;
  const FaceClusterReviewScreen({super.key, required this.library, required this.suggestions});

  @override
  State<FaceClusterReviewScreen> createState() => _FaceClusterReviewScreenState();
}

class _FaceClusterReviewScreenState extends State<FaceClusterReviewScreen> {
  late final List<FaceClusterSuggestion> _pending = List.of(widget.suggestions);

  Future<void> _assign(FaceClusterSuggestion cluster) async {
    final people = await widget.library.db.select(widget.library.db.people).get();
    if (!mounted) return;
    final choice = await showPersonPickerDialog(
      context,
      people,
      paths: widget.library.paths,
      title: AppTexte.of(context).clusterGesichterZuordnen(cluster.faces.length),
      suggestedPerson: cluster.suggestedPerson,
    );
    if (choice == null) return;

    String personId;
    if (choice.newName != null) {
      personId = const Uuid().v4();
      await widget.library.db.createPerson(
        PeopleCompanion.insert(id: personId, name: choice.newName!),
      );
    } else {
      personId = choice.existingPersonId!;
    }
    await widget.library.db.assignFacesToPerson(cluster.faces.map((f) => f.id).toList(), personId);

    // Gab es einen Vorschlag, ist die Wahl des Nutzers ein Urteil darüber:
    // dieselbe Person = bestätigt, eine andere = abgelehnt.
    //
    // Ein Eintrag je Cluster, nicht je Gesicht: Die Ähnlichkeit wurde
    // zwischen dem Cluster-Schwerpunkt und der Person gemessen, nicht für
    // jedes einzelne Gesicht. Sie acht Mal einzutragen behauptete acht
    // Beobachtungen, wo nur eine vorliegt – und liesse die Schwelle nach
    // einem einzigen Klick als "belegt" gelten.
    final vorschlag = cluster.suggestedPerson;
    final aehnlichkeit = cluster.similarity;
    if (vorschlag != null && aehnlichkeit != null) {
      await widget.library.db.merkeGesichtsEntscheidungen(
        vorschlag.id,
        [
          (
            faceId: cluster.faces.first.id,
            accepted: personId == vorschlag.id,
            similarity: aehnlichkeit,
          ),
        ],
        allgemeineSchwelle: widget.library.faceSimilarityThreshold,
      );
    }

    if (mounted) setState(() => _pending.remove(cluster));
  }

  /// "Überspringen" heisst "nicht jetzt", nicht "falsch" – deshalb wird
  /// hier bewusst nichts festgehalten. Als Ablehnung gewertet würde jeder
  /// übersprungene Vorschlag die Schwelle der vorgeschlagenen Person
  /// hochziehen, obwohl der Nutzer gar keine Aussage gemacht hat.
  void _skip(FaceClusterSuggestion cluster) => setState(() => _pending.remove(cluster));

  /// Die ganze Gruppe beiseitelegen.
  ///
  /// Der lohnendste Ort dafür: Was die Gruppierung findet, sind nicht nur
  /// Personen, sondern auch immer wieder dasselbe Nicht-Gesicht in Serie –
  /// ein Plakat im Hintergrund, eine Schaufensterpuppe, ein wiederkehrendes
  /// Logo. Hier liegen sie bereits fertig beisammen und sind mit einem
  /// Klick erledigt statt einzeln im Raster.
  ///
  /// Auch das ist keine Aussage über die *Erkennungs*schwelle: Der Nutzer
  /// sagt „das ist keine Person", nicht „diese Gesichter gehören nicht
  /// zusammen". Deshalb wird, wie beim Überspringen, nichts gelernt.
  Future<void> _ignorieren(FaceClusterSuggestion cluster) async {
    await widget.library.db
        .setFacesIgnored(cluster.faces.map((f) => f.id).toList(), true);
    if (mounted) setState(() => _pending.remove(cluster));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppTexte.of(context).clusterTitel)),
      body: _pending.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xxl),
                child: Text(AppTexte.of(context).clusterFertig, textAlign: TextAlign.center),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(AppSpacing.lg),
              itemCount: _pending.length,
              itemBuilder: (context, index) {
                final cluster = _pending[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            for (final face in cluster.faces.take(6))
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: face.cropRelativePath != null
                                      ? Image.file(
                                          widget.library.paths.absolute(face.cropRelativePath!),
                                          width: 56,
                                          height: 56,
                                          fit: BoxFit.cover,
                                          // 160 px auf der Platte, 56 auf
                                          // dem Schirm – das Achtfache an
                                          // Bildspeicher für nichts
                                          // (Prüfrunde 8).
                                          cacheWidth: (56 *
                                                  MediaQuery.devicePixelRatioOf(
                                                      context))
                                              .round(),
                                        )
                                      : const SizedBox(width: 56, height: 56),
                                ),
                              ),
                            if (cluster.faces.length > 6)
                              Text('+${cluster.faces.length - 6}',
                                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(AppTexte.of(context).clusterGesichterAnzahl(cluster.faces.length)),
                        if (cluster.suggestedPerson != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Chip(
                              label: Text(AppTexte.of(context).clusterAehnlichZu(cluster.suggestedPerson!.name)),
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            IconButton(
                              tooltip: AppTexte.of(context).clusterIgnorierenTooltip,
                              icon: const Icon(Icons.visibility_off_outlined),
                              onPressed: () => _ignorieren(cluster),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => _skip(cluster),
                                child: Text(AppTexte.of(context).clusterUeberspringen),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton(
                                onPressed: () => _assign(cluster),
                                child: Text(AppTexte.of(context).personZuordnenAktion),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
