import 'dart:async';

import 'package:flutter/material.dart';

import 'package:kern/db/database.dart';
import '../../l10n/app_localizations.dart';
import '../../services/meldungsdienst.dart';
import '../../theme/app_spacing.dart';
import 'einstellungsstand.dart';
import '../../widgets/einfuegbares_menue.dart';

/// Das Schlagwort-Vokabular der Bilderkennung.
class VokabularGruppe extends StatelessWidget {
  const VokabularGruppe(this.stand, {super.key});

  final Einstellungsstand stand;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Text(
          AppTexte.of(context).einstVokabularText,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StreamBuilder<List<AiTagVocabularyData>>(
                stream: stand.library.db.watchAiTagVocabulary(),
                builder: (context, snapshot) {
                  final terms = snapshot.data ?? [];
                  if (terms.isEmpty) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final entry in terms)
                          InputChip(
                            label: Text(entry.term),
                            onDeleted: () => stand.library.db.fuehreAus(
                              KiBegriffEntfernen(entry.id),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      contextMenuBuilder: einfuegbaresMenue,
                      controller: stand.aiTagVocabularyController,
                      decoration: InputDecoration(
                        hintText: AppTexte.of(
                          context,
                        ).einstBegriffHinzufuegenFeld,
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _addAiTagVocabularyTerm(stand),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add),
                    tooltip: AppTexte.of(context).einstBegriffHinzufuegen,
                    onPressed: () => _addAiTagVocabularyTerm(stand),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      // Der Weg zurück. Er steht hier und nicht bei den Werkzeugen,
      // weil er zum Vokabular gehört: Wer die Begriffe ändert, will
      // meist auch die damit vergebenen Schlagwörter neu haben.
      FutureBuilder<int>(
        future: stand.einmal(
          EinstellungsAbfrage.kiTags,
          stand.library.db.kiTagAnzahl,
        ),
        builder: (context, schnappschuss) {
          final anzahl = schnappschuss.data;
          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.auto_delete_outlined),
            title: Text(AppTexte.of(context).einstKiTagsZurueck),
            subtitle: Text(
              anzahl == null
                  ? AppTexte.of(context).einstKiTagsZurueckText
                  : AppTexte.of(context).einstKiTagsZurueckAnzahl(anzahl),
            ),
            enabled: anzahl != null && anzahl > 0,
            onTap: anzahl == null || anzahl == 0
                ? null
                : () => _nimmKiTagsZurueck(stand, anzahl),
          );
        },
      ),
    ],
  );
}

Future<void> _addAiTagVocabularyTerm(Einstellungsstand stand) async {
  final term = stand.aiTagVocabularyController.text.trim();
  if (term.isEmpty) return;
  stand.aiTagVocabularyController.clear();
  await stand.library.db.fuehreAus(KiBegriffHinzufuegen(term));
}

/// Nimmt alle von der Bilderkennung vergebenen Schlagwörter zurück.
///
/// Mit Rückfrage und mit **Zahl** darin: „94.040 Schlagwörter werden
/// entfernt" wiegt anders als „alle KI-Schlagwörter entfernen".
Future<void> _nimmKiTagsZurueck(Einstellungsstand stand, int anzahl) async {
  final context = stand.kontext;
  final t = AppTexte.of(context);
  final ja = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text(t.einstKiTagsZurueck),
      content: Text(t.einstKiTagsZurueckFrage(anzahl)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog, false),
          child: Text(t.allgAbbrechen),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialog, true),
          child: Text(t.einstKiTagsZurueckJetzt),
        ),
      ],
    ),
  );
  if (ja != true) return;
  final entfernt = await stand.library.db.fuehreAus(
    const KiSchlagwoerterZuruecknehmen(),
  );
  if (!context.mounted) return;
  stand.neuFragen(EinstellungsAbfrage.kiTags);
  melde.erfolg(t.einstKiTagsZurueckFertig(entfernt));
}
