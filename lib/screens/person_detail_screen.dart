import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

import '../db/database.dart';
import '../db/rasterzeile.dart';
import '../services/face_threshold.dart';
import '../state/library_state.dart';
import '../theme/app_spacing.dart';
import '../widgets/asset_thumbnail_tile.dart';
import '../widgets/pin_dialogs.dart';
import 'package:flutter/foundation.dart' show compute;

import '../services/embedding_codec.dart';
import '../services/face_suggestions.dart';
import 'asset_viewer_screen.dart';
import 'face_review_screen.dart';
import 'person_suggestions_screen.dart';
import 'lebenslauf_screen.dart';
import 'stammbaum_screen.dart';
import '../services/meldungsdienst.dart';
import '../widgets/profilbild.dart';
import '../widgets/stromhalter.dart';

class PersonDetailScreen extends StatefulWidget {
  final LibraryState library;
  final PersonData person;
  const PersonDetailScreen({super.key, required this.library, required this.person});

  @override
  State<PersonDetailScreen> createState() => _PersonDetailScreenState();
}

class _PersonDetailScreenState extends State<PersonDetailScreen> {
  LibraryState get library => widget.library;
  PersonData get person => widget.person;

  bool _sucheLaeuft = false;

  /// Siehe [Stromhalter]. Die Fotoliste einer Person kostete 3,8 ms je
  /// Neubau, und der Bildschirm baut auch neu, wenn nur die Person selbst
  /// sich ändert (der Strom darüber).
  final _personenstrom = Stromhalter<PersonData?>();
  final _fotostrom = Stromhalter<List<AssetData>>();

  /// Sucht unbenannte Gesichter, die dieser Person ähnlich genug sind, und
  /// legt sie zur Bestätigung vor.
  ///
  /// Der Weg gab es bisher nur andersherum: Gesichter auswählen und einer
  /// Person zuordnen. Wer wissen wollte, ob jemand noch auf weiteren Fotos
  /// ist, musste das ganze Raster selbst durchsehen.
  Future<void> _vorschlaegeSuchen() async {
    setState(() => _sucheLaeuft = true);
    try {
      final bekannt = [
        for (final f in await library.db.facesForPerson(person.id))
          if (f.embedding != null) floatsFromEmbeddingBlob(f.embedding!),
      ];
      final offen = await library.db.allUnassignedFaces();
      final kandidaten = {
        for (final f in offen)
          if (f.embedding != null) f.id: floatsFromEmbeddingBlob(f.embedding!),
      };

      if (bekannt.isEmpty || kandidaten.isEmpty) {
        if (!mounted) return;
        melde.hinweis(bekannt.isEmpty
            ? AppTexte.of(context).vorschlagKeineEmbeddings
            : AppTexte.of(context).vorschlagKeineKandidaten);
        return;
      }

      // In einem eigenen Isolat. Gemessen ist der Lauf schnell – 300
      // bekannte Gesichter gegen 17.836 Kandidaten brauchen 52 ms, weil der
      // Deckel in [vorschlaegeFuerPerson] die Referenzen auf 40 begrenzt.
      // Das allein rechtfertigte kein Isolat. Es steht hier für den Fall,
      // auf den diese App ausgelegt ist: Bei 100.000 Fotos sind es rund
      // zehnmal so viele Kandidaten, und dann wären es ein halbe Sekunde
      // stehendes Bild.
      final roh = await compute(
        vorschlaegeFuerPerson,
        VorschlagsEingabe(
          bekannt: bekannt,
          kandidaten: kandidaten,
          schwelle: library.schwelleFuerPerson(person),
        ),
      );

      if (!mounted) return;
      if (roh.isEmpty) {
        melde.hinweis(AppTexte.of(context).vorschlagNichtsGefunden(
            library.schwelleFuerPerson(person).toStringAsFixed(2)));
        return;
      }

      final nachId = {for (final f in offen) f.id: f};
      final vorschlaege = [
        for (final v in roh)
          if (nachId.containsKey(v.faceId))
            (gesicht: nachId[v.faceId]!, aehnlichkeit: v.aehnlichkeit),
      ];

      final uebernommen = await Navigator.of(context).push<int>(MaterialPageRoute(
        builder: (_) => PersonSuggestionsScreen(
          library: library,
          person: person,
          vorschlaege: vorschlaege,
        ),
      ));
      if (!mounted || uebernommen == null) return;
      melde.erfolg(AppTexte.of(context).vorschlagUebernommenMeldung(uebernommen));
    } finally {
      if (mounted) setState(() => _sucheLaeuft = false);
    }
  }

  /// Zeigt alle Gesichter dieser Person zur Auswahl an und setzt das
  /// angetippte als neues Profilbild (überschreibt ein evtl. vorhandenes).
  Future<void> _pickProfilePicture(BuildContext context) async {
    final faces = (await library.db.facesForPerson(person.id))
        .where((f) => f.cropRelativePath != null)
        .toList();
    if (faces.isEmpty) {
      if (context.mounted) {
        melde.hinweis(AppTexte.of(context).personKeineGesichter);
      }
      return;
    }
    if (!context.mounted) return;
    final chosen = await showDialog<FaceData>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppTexte.of(context).personProfilbildWaehlen),
        content: SizedBox(
          width: 360,
          height: 360,
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 100,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
            ),
            itemCount: faces.length,
            itemBuilder: (context, index) {
              final face = faces[index];
              return InkWell(
                onTap: () => Navigator.pop(context, face),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: Image.file(
                    library.paths.absolute(face.cropRelativePath!),
                    fit: BoxFit.cover,
                    // Ein Gesichtsausschnitt liegt mit 160 px auf der
                    // Platte, die Kachel ist höchstens 100 breit. Bei einer
                    // Person mit vielen hundert Erkennungen summiert sich
                    // der Unterschied (Prüfrunde 8).
                    cacheWidth: (100 * MediaQuery.devicePixelRatioOf(context))
                        .round(),
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(AppTexte.of(context).allgAbbrechen)),
        ],
      ),
    );
    if (chosen != null) {
      await library.db.setPersonCover(person.id, chosen.cropRelativePath!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(person.name),
        actions: [
          // **Die fehlende Tür.** Den Lebenslauf einer Person gab es nur
          // im Menü ihres Schildes im Stammbaum – wer eine Person
          // aufschlug, um etwas über sie zu erfahren, fand ihn nicht.
          // Derselbe Fehler wie beim Papierkorb ohne Eingang.
          IconButton(
            tooltip: AppTexte.of(context).lebenslaufVon(person.name),
            icon: const Icon(Icons.timeline_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) =>
                  LebenslaufScreen(library: library, person: person),
            )),
          ),
          IconButton(
            tooltip: AppTexte.of(context).stammbaumTitel,
            icon: const Icon(Icons.account_tree_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => StammbaumScreen(
                library: library,
                startPersonId: person.id,
              ),
            )),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm),
            child: Row(
              children: [
                StreamBuilder<PersonData?>(
                  stream: _personenstrom.hole(
                      person.id, () => library.db.watchPerson(person.id)),
                  initialData: person,
                  builder: (context, snapshot) {
                    final coverPath = snapshot.data?.coverFaceCropPath;
                    return Profilbild(
                      datei: coverPath == null
                          ? null
                          : library.paths.absolute(coverPath),
                      radius: 36,
                      hintergrund: Colors.grey.shade800,
                      symbolgroesse: 28,
                    );
                  },
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickProfilePicture(context),
                    icon: const Icon(Icons.image_outlined),
                    label: Text(AppTexte.of(context).personProfilbildAendern),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _sucheLaeuft ? null : _vorschlaegeSuchen,
                    icon: _sucheLaeuft
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.person_search_outlined),
                    label: Text(AppTexte.of(context).personWeitereFotosSuchen),
                  ),
                ),
              ],
            ),
          ),
          _ErkennungsStand(library: library, person: person),
          Expanded(
            child: StreamBuilder<List<AssetData>>(
              stream: _fotostrom.hole(person.id,
                  () => library.db.watchAssetsForPerson(person.id)),
              builder: (context, snapshot) {
                final assets = snapshot.data ?? [];
                if (assets.isEmpty) {
                  return Center(child: Text(AppTexte.of(context).personKeineFotos));
                }
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                      child: Text(
                        AppTexte.of(context).personDoppelklickHinweis,
                        style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ),
                    Expanded(
                      child: GridView.builder(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 160,
                          mainAxisSpacing: 4,
                          crossAxisSpacing: 4,
                        ),
                        itemCount: assets.length,
                        itemBuilder: (context, index) {
                          final asset = assets[index];
                          return AssetThumbnailTile(
                            asset: Rasterzeile.aus(asset),
                            paths: library.paths,
                            onTap: () => Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
                              builder: (_) => AssetViewerScreen(
                                assets: assets,
                                initialIndex: index,
                                paths: library.paths,
                                db: library.db,
                                library: library,
                                onToggleFavorite: (a) => library.db.setFavorite(a.id, !a.isFavorite),
                                onDelete: (a) => library.db.moveToTrash([a.id]),
                                onLock: (a) async {
                                  if (await ensureVaultUnlocked(context, library)) {
                                    await library.lockAsset(a);
                                  }
                                },
                              ),
                            )),
                            onDoubleTap: () => Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => FaceReviewScreen(
                                library: library,
                                assets: assets,
                                startIndex: index,
                              ),
                            )),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Zeigt im Klartext, nach welcher Schwelle diese Person wiedererkannt wird
/// und warum.
///
/// Eine Schwelle, die sich hinter dem Rücken des Nutzers verstellt, wäre in
/// einem Programm unangebracht, das KI-Schritte sonst durchgehend auslösen
/// UND bestätigen lässt. Deshalb steht hier nicht nur die Zahl, sondern
/// auch, woraus sie stammt – und ein Weg zurück.
class _ErkennungsStand extends StatefulWidget {
  final LibraryState library;
  final PersonData person;

  const _ErkennungsStand({required this.library, required this.person});

  @override
  State<_ErkennungsStand> createState() => _ErkennungsStandState();
}

class _ErkennungsStandState extends State<_ErkennungsStand> {
  List<GesichtsRueckmeldung>? _rueckmeldungen;

  @override
  void initState() {
    super.initState();
    _lade();
  }

  Future<void> _lade() async {
    final r = await widget.library.db.gesichtsRueckmeldungen(widget.person.id);
    if (mounted) setState(() => _rueckmeldungen = r);
  }

  Future<void> _vergessen() async {
    await widget.library.db.vergissGesichtsEntscheidungen(widget.person.id);
    await _lade();
    if (mounted) {
      melde.erfolg(AppTexte.of(context).personGelerntesVerworfen);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rueckmeldungen = _rueckmeldungen;
    if (rueckmeldungen == null || rueckmeldungen.isEmpty) return const SizedBox.shrink();

    final allgemein = widget.library.faceSimilarityThreshold;
    final schwelle = leiteSchwelleAb(rueckmeldungen, allgemein);
    final woher = herkunft(rueckmeldungen, allgemein);
    final bestaetigt = rueckmeldungen.where((r) => r.bestaetigt).length;
    final abgelehnt = rueckmeldungen.length - bestaetigt;

    final t = AppTexte.of(context);
    final erklaerung = switch (woher) {
      SchwellenHerkunft.angepasst => t.personSchwelleAngepasst(
          schwelle.toStringAsFixed(2), allgemein.toStringAsFixed(2)),
      SchwellenHerkunft.widerspruch =>
        t.personSchwelleWiderspruch(allgemein.toStringAsFixed(2)),
      SchwellenHerkunft.zuWenigDaten =>
        t.personSchwelleWirdAngepasst(mindestEntscheidungen),
      SchwellenHerkunft.wieAllgemein =>
        t.personSchwelleWieAllgemein(allgemein.toStringAsFixed(2)),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.sm),
      child: Row(
        children: [
          Icon(
            woher == SchwellenHerkunft.angepasst
                ? Icons.auto_awesome_outlined
                : Icons.info_outline,
            size: 16,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              t.personWiedererkennung(erklaerung, bestaetigt, abgelehnt),
              style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          TextButton(
            onPressed: _vergessen,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(AppTexte.of(context).personVerwerfen, style: const TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }
}
