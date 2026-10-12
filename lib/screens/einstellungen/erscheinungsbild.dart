import 'package:flutter/material.dart';

import 'package:kern/db/database.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import 'einstellungsstand.dart';

/// Erscheinungsbild: helles oder dunkles Design, Schwebe-Vorschau.
class ErscheinungsbildGruppe extends StatelessWidget {
  const ErscheinungsbildGruppe(this.stand, {super.key});

  final Einstellungsstand stand;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      Card(
        child: StreamBuilder<AppSettingsData?>(
          stream: stand.library.db.watchAppSettings(),
          builder: (context, snapshot) {
            final mode = themeModeFromString(snapshot.data?.themeMode);
            return ListTile(
              leading: const Icon(Icons.contrast_outlined),
              title: Text(AppTexte.of(context).einstDesign),
              subtitle: SegmentedButton<ThemeMode>(
                segments: [
                  ButtonSegment(
                    value: ThemeMode.light,
                    label: Text(AppTexte.of(context).einstDesignHell),
                    icon: const Icon(Icons.light_mode_outlined),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    label: Text(AppTexte.of(context).einstDesignDunkel),
                    icon: const Icon(Icons.dark_mode_outlined),
                  ),
                  ButtonSegment(
                    value: ThemeMode.system,
                    label: Text(AppTexte.of(context).einstDesignSystem),
                    icon: const Icon(Icons.brightness_auto_outlined),
                  ),
                ],
                selected: {mode},
                onSelectionChanged: (selection) => stand.library.db
                    .setThemeMode(themeModeToString(selection.first)),
              ),
            );
          },
        ),
      ),
      // Die Schwebe-Vorschau steht beim Erscheinungsbild und nicht bei
      // den Videos: Sie aendert nicht, wie ein Video abgespielt wird,
      // sondern wie sich die Kachelwand anfuehlt.
      Card(
        child: StreamBuilder<AppSettingsData?>(
          stream: stand.library.db.watchAppSettings(),
          builder: (context, snapshot) {
            final t = AppTexte.of(context);
            return SwitchListTile(
              secondary: const Icon(Icons.slow_motion_video_outlined),
              title: Text(t.einstSchwebeVorschauTitel),
              subtitle: Text(t.einstSchwebeVorschauText),
              value: snapshot.data?.schwebeVorschau ?? true,
              onChanged: (an) => stand.library.db.setzeSchwebeVorschau(an),
            );
          },
        ),
      ),
    ],
  );
}
