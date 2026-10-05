import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../state/library_state.dart';
import '../theme/app_spacing.dart';
import 'calendar_screen.dart';

/// Kompakte Einstiegslandkarte der Timeline. Anders als der frühere
/// Monats-Scrubber lädt sie keine Medienliste, sondern nur eine SQL-Aggregation
/// pro Jahr. So bleiben auch alte Jahre sichtbar, bevor jemand scrollt.
class TimelineYearOverview extends StatelessWidget {
  const TimelineYearOverview({super.key, required this.library});

  final LibraryState library;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<int, int>>(
      stream: library.db.watchAssetCountsByYear(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final counts = snapshot.data!;
        final years = counts.keys.toList()..sort((a, b) => b.compareTo(a));
        return GridView.builder(
          padding: const EdgeInsets.all(AppSpacing.md),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 150,
            mainAxisExtent: 58,
            mainAxisSpacing: AppSpacing.sm,
            crossAxisSpacing: AppSpacing.sm,
          ),
          itemCount: years.length,
          itemBuilder: (context, index) {
            final year = years[index];
            return Material(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.md),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        MonatsuebersichtScreen(library: library, jahr: year),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '$year',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      Semantics(
                        label: AppTexte.of(
                          context,
                        ).kalenderAnzahlFotos(counts[year]!),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.photo_outlined, size: 15),
                            const SizedBox(width: 3),
                            Text(
                              '${counts[year]}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
