import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../background_tasks_screen.dart';
import 'einstellungsstand.dart';

/// Der Weg zu den Hintergrundaufgaben.
class HintergrundGruppe extends StatelessWidget {
  const HintergrundGruppe(this.stand, {super.key});

  final Einstellungsstand stand;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      Card(
        child: ListTile(
          leading: const Icon(Icons.pending_actions_outlined),
          title: Text(AppTexte.of(context).einstAufgabenTitel),
          subtitle: Text(AppTexte.of(context).einstAufgabenText),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => BackgroundTasksScreen(library: stand.library),
            ),
          ),
        ),
      ),
    ],
  );
}
