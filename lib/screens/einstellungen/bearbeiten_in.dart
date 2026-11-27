import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/bearbeitungsprogramme.dart';
import '../../services/fremdprogramme.dart';
import '../../services/meldungsdienst.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';

/// Welche Programme im Vollbild unter „Bearbeiten in“ stehen (#499):
/// die gefundenen, die ausgeschalteten und die selbst gewählten.
///
/// Anders als die übrigen Gruppen hält sie ihren Stand nicht im
/// `Einstellungsstand`: Die Liste gehört [Bearbeitungsprogramme], und das
/// Vollbild liest dieselbe. Beim Aufklappen wird neu gesucht – wer hier
/// nachsieht, hat vielleicht gerade ein Programm installiert.
class BearbeitenInGruppe extends StatefulWidget {
  const BearbeitenInGruppe({super.key, this.programme});

  /// Ohne Angabe die Liste der App; ein Test gibt eine eigene.
  final Bearbeitungsprogramme? programme;

  @override
  State<BearbeitenInGruppe> createState() => _BearbeitenInGruppeState();
}

class _BearbeitenInGruppeState extends State<BearbeitenInGruppe> {
  late final Bearbeitungsprogramme _programme =
      widget.programme ?? Bearbeitungsprogramme.standard;

  @override
  void initState() {
    super.initState();
    unawaited(_programme.laden(neu: true));
  }

  Future<void> _tue(Future<void> Function() aenderung) async {
    try {
      await aenderung();
    } on Object catch (e) {
      melde.fehler('$e');
    }
  }

  Future<void> _hinzufuegen() async {
    final t = AppTexte.of(context);
    await _tue(() async {
      final pfad = await _programme.waehle(t.fremdProgrammWaehlen);
      if (pfad != null) await _programme.fuegeHinzu(pfad);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final klein = TextStyle(
      fontSize: 12,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return ListenableBuilder(
      listenable: _programme,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Text(t.einstBearbeitenInText, style: klein),
          ),
          if (_programme.imFlatpak)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Text(t.einstBearbeitenInFlatpak, style: klein),
            ),
          Card(
            child: Column(
              children: [
                for (final programm in _programme.alle)
                  _Programmzeile(
                    programm: programm,
                    gesucht: _programme.geladen,
                    schalte: (an) =>
                        _tue(() => _programme.schalte(programm.kennung, an)),
                    entferne: programm.eigenes
                        ? () =>
                              _tue(() => _programme.entferne(programm.kennung))
                        : null,
                  ),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: OutlinedButton.icon(
                    onPressed: _hinzufuegen,
                    icon: const Icon(Icons.add),
                    label: Text(t.einstBearbeitenInHinzufuegen),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              t.einstBearbeitenInOrdner(_programme.basis.path),
              style: klein,
            ),
          ),
        ],
      ),
    );
  }
}

/// Ein Programm mit Schalter; ein selbst gewähltes dazu mit „Entfernen“.
class _Programmzeile extends StatelessWidget {
  const _Programmzeile({
    required this.programm,
    required this.gesucht,
    required this.schalte,
    this.entferne,
  });

  final Fremdprogramm programm;

  /// Ob die Erkennung durch ist. Vorher steht kein „nicht gefunden“ da –
  /// und bewusst auch kein Ladebalken: Die Suche dauert einen Augenblick,
  /// ein Balken flackerte nur.
  final bool gesucht;
  final ValueChanged<bool> schalte;
  final VoidCallback? entferne;

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final pfad = programm.pfad;
    return ListTile(
      leading: Icon(
        pfad != null ? Icons.check_circle : Icons.help_outline,
        color: pfad != null ? context.semantik.erfolg : null,
      ),
      title: Text(programm.name),
      subtitle: pfad != null
          ? Text(pfad)
          : gesucht
          ? Text(t.einstBearbeitenInNichtGefunden)
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (entferne != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: t.einstBearbeitenInEntfernen,
              onPressed: entferne,
            ),
          Switch(value: programm.aktiv, onChanged: schalte),
        ],
      ),
    );
  }
}
