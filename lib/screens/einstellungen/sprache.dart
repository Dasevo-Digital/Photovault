import 'dart:async';

import 'package:flutter/material.dart';

import 'package:kern/db/database.dart';
import '../../l10n/app_localizations.dart';
import 'package:kern/services/ai_tagging_service.dart';
import '../../services/meldungsdienst.dart';
import 'einstellungsstand.dart';

/// Sprache der Oberfläche – beim Wechsel mit dem Angebot, das Vokabular mitzuübersetzen.
class SpracheGruppe extends StatelessWidget {
  const SpracheGruppe(this.stand, {super.key});

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
            final t = AppTexte.of(context);
            final aktuell = snapshot.data?.sprache ?? 'system';
            return ListTile(
              leading: const Icon(Icons.translate_outlined),
              title: Text(t.spracheTitel),
              isThreeLine: true,
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 6),
                  SegmentedButton<String>(
                    segments: [
                      ButtonSegment(
                        value: 'system',
                        label: Text(t.spracheSystem),
                      ),
                      // Sprachnamen stehen bewusst in ihrer eigenen Sprache
                      // da – wer die Oberfläche nicht versteht, findet
                      // "English" trotzdem, "Englisch" womöglich nicht.
                      ButtonSegment(value: 'de', label: Text(t.spracheDeutsch)),
                      ButtonSegment(
                        value: 'en',
                        label: Text(t.spracheEnglisch),
                      ),
                    ],
                    selected: {aktuell},
                    showSelectedIcon: false,
                    onSelectionChanged: (auswahl) =>
                        _wechsleSprache(stand, auswahl.first),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    t.spracheHinweis,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    ],
  );
}

/// Wechselt die Oberflächensprache und bietet dabei einmalig an, das
/// Schlagwort-Vokabular mitzuziehen.
///
/// Die Reihenfolge ist Absicht: erst umstellen, dann fragen. So sieht der
/// Nutzer den Dialog bereits in der neuen Sprache und kann beurteilen,
/// worauf er sich einlässt. Lehnt er ab, bleibt es dabei – es gibt keine
/// zweite Nachfrage bei jedem Start.
Future<void> _wechsleSprache(Einstellungsstand stand, String sprachcode) async {
  final context = stand.kontext;
  // Vor dem ersten await lesen: Danach kann der Kontext veraltet sein,
  // und die Sprache VOR der Umstellung ist genau das, was gebraucht wird.
  //
  // Massgeblich ist dabei, welche Sprache tatsächlich WIRKT, nicht welche
  // eingestellt ist: Wer von „System" (auf einem englischen Rechner) auf
  // „Deutsch" stellt, wechselt real von Englisch nach Deutsch – die
  // gespeicherten Werte allein ('system' -> 'de') verrieten das nicht.
  final vorher = Localizations.localeOf(context).languageCode;

  if (await stand.library.db.spracheWert() == sprachcode) return;
  await stand.library.db.setSprache(sprachcode);
  final nachher = sprachcode == 'system' ? _systemsprache() : sprachcode;

  final richtung = switch ((vorher, nachher)) {
    ('de', 'en') => aiTagVocabularyEnglisch,
    ('en', 'de') => {
      for (final e in aiTagVocabularyEnglisch.entries) e.value: e.key,
    },
    _ => null,
  };
  if (richtung == null || !context.mounted) return;

  // Nur Begriffe anbieten, die auch wirklich im Vokabular stehen.
  final vorhandene = await stand.library.db.aiTagVocabularyTerms();
  final betroffen = {
    for (final e in richtung.entries)
      if (vorhandene.contains(e.key)) e.key: e.value,
  };
  if (betroffen.isEmpty || !context.mounted) return;
  final eigene = vorhandene.length - betroffen.length;

  // Die Texte erst im Aufbau des Dialogs holen, nicht hier: In diesem
  // Augenblick hat die App ihre neue Sprache noch nicht gezeichnet, und
  // der Dialog stand – entgegen der Absicht oben – in der alten da.
  final uebersetzen = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(AppTexte.of(context).spracheVokabularTitel),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppTexte.of(
              context,
            ).spracheVokabularText(betroffen.length, vorhandene.length),
          ),
          if (eigene > 0) ...[
            const SizedBox(height: 10),
            Text(
              AppTexte.of(context).spracheVokabularSelbstAngelegt(eigene),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(AppTexte.of(context).spracheVokabularBehalten),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(AppTexte.of(context).spracheVokabularUebersetzen),
        ),
      ],
    ),
  );
  if (uebersetzen != true) return;

  final anzahl = await stand.library.db.fuehreAus(
    VokabularUebersetzen(betroffen),
  );
  // Die zwischengespeicherten Begriffs-Vektoren gehören zu den alten
  // Wörtern und wären danach nie wieder erreichbar.
  stand.library.aiTaggingService.leereBegriffsCache();
  if (!context.mounted) return;
  melde.erfolg(AppTexte.of(context).spracheVokabularFertig(anzahl));
}

/// Welche der unterstützten Sprachen bei "System" greift.
///
/// Flutter würde bei einer nicht unterstützten Systemsprache auf den
/// ersten Eintrag aus `supportedLocales` zurückfallen; genau das bildet
/// diese Zeile nach, statt es zu raten.
String _systemsprache() {
  final system = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
  return AppTexte.supportedLocales.any((l) => l.languageCode == system)
      ? system
      : AppTexte.supportedLocales.first.languageCode;
}
