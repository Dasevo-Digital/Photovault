import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

import '../db/database.dart';
import '../services/storage_paths.dart';
import '../theme/app_spacing.dart';
import 'profilbild.dart';

/// Was der Nutzer im Zuordnungs-Dialog entschieden hat.
class PersonChoice {
  final String? newName;
  final String? existingPersonId;

  /// „Das ist kein Gesicht" bzw. „interessiert mich nicht" – nur möglich,
  /// wenn der Aufrufer es mit `erlaubtIgnorieren` angeboten hat.
  final bool ignorieren;

  PersonChoice.newPerson(this.newName)
      : existingPersonId = null,
        ignorieren = false;
  PersonChoice.existing(this.existingPersonId)
      : newName = null,
        ignorieren = false;
  const PersonChoice.ignorieren()
      : newName = null,
        existingPersonId = null,
        ignorieren = true;
}

/// Zeigt einen Dialog, um ein (oder mehrere) Gesicht(er) einer neuen oder
/// bestehenden Person zuzuordnen. Wird sowohl bei der Massenzuordnung in
/// "Unbenannte Gesichter" als auch in der Foto-Detailansicht (Gesichter
/// direkt am Foto benennen) verwendet.
///
/// **Ein Feld für beides: suchen und neu anlegen.** Vorher standen hier ein
/// Auswahlfeld mit allen Personen und darunter ein Textfeld für einen neuen
/// Namen. Das Auswahlfeld hatte keine Suche – in einer gewachsenen
/// Bibliothek sind das 39 Bilder zum Scrollen, und wer den Namen kennt,
/// tippt ihn schneller, als er ihn findet. Jetzt filtert die Eingabe die
/// Liste; steht der getippte Name in keiner Zeile, legt derselbe Knopf ihn
/// neu an. Die zwei Wege bleiben unterscheidbar, weil die Beschriftung des
/// Knopfes es sagt.
///
/// [paths] wird für die Profilbilder in der Liste gebraucht: Bei mehr als
/// einer Handvoll Personen sagt ein Name allein wenig – zwei Verwandte
/// gleichen Vornamens sind an der Schreibweise nicht zu unterscheiden, an
/// ihren Gesichtern sofort.
///
/// [suggestedPerson] ist der Vorschlag der Wiedererkennung. Er steht ganz
/// oben und ist vorausgewählt, aber nicht bestätigt – siehe
/// [LibraryState.personenvorschlag].
Future<PersonChoice?> showPersonPickerDialog(
  BuildContext context,
  List<PersonData> existingPeople, {
  required StoragePaths paths,
  String? title,
  String? currentName,
  PersonData? suggestedPerson,
  bool erlaubtIgnorieren = false,
}) {
  return showDialog<PersonChoice>(
    context: context,
    builder: (context) => _PersonPickerDialog(
      existingPeople: existingPeople,
      paths: paths,
      // Vorgabewert erst hier: im Kopf gibt es noch keinen Kontext.
      title: title ?? AppTexte.of(context).personZuordnenTitel,
      currentName: currentName,
      suggestedPerson: suggestedPerson,
      erlaubtIgnorieren: erlaubtIgnorieren,
    ),
  );
}

class _PersonPickerDialog extends StatefulWidget {
  final List<PersonData> existingPeople;
  final StoragePaths paths;
  final String title;
  final String? currentName;
  final PersonData? suggestedPerson;
  final bool erlaubtIgnorieren;
  const _PersonPickerDialog({
    required this.existingPeople,
    required this.paths,
    required this.title,
    this.currentName,
    this.suggestedPerson,
    this.erlaubtIgnorieren = false,
  });

  @override
  State<_PersonPickerDialog> createState() => _PersonPickerDialogState();
}

class _PersonPickerDialogState extends State<_PersonPickerDialog> {
  final _suchfeld = TextEditingController();
  final _fokus = FocusNode();
  late PersonData? _gewaehlt = widget.suggestedPerson;

  @override
  void initState() {
    super.initState();
    // Der Dialog öffnet sich für eine Eingabe, nicht zum Ansehen. Ohne
    // diesen Griff müsste man erst ins Feld klicken – bei einer Reihe von
    // Gesichtern hintereinander jedes Mal.
    _fokus.requestFocus();
  }

  @override
  void dispose() {
    _suchfeld.dispose();
    _fokus.dispose();
    super.dispose();
  }

  String get _suche => _suchfeld.text.trim();

  /// Die Personen, die zur Eingabe passen – der Vorschlag immer zuerst.
  List<PersonData> get _gezeigt {
    final suche = _suche.toLowerCase();
    final passend = [
      for (final p in widget.existingPeople)
        if (suche.isEmpty || p.name.toLowerCase().contains(suche)) p,
    ]..sort((a, b) {
        // Wer vorn ANFÄNGT, steht vor dem, bei dem es mittendrin steht:
        // Wer „Ma" tippt, meint eher Martin als Thomas.
        if (suche.isNotEmpty) {
          final a0 = a.name.toLowerCase().startsWith(suche);
          final b0 = b.name.toLowerCase().startsWith(suche);
          if (a0 != b0) return a0 ? -1 : 1;
        }
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    final vorschlag = widget.suggestedPerson;
    if (vorschlag == null) return passend;
    final rest = passend.where((p) => p.id != vorschlag.id).toList();
    // Der Vorschlag bleibt oben – aber nur, solange die Eingabe ihn nicht
    // ausschliesst. Sonst stünde beim Tippen eines anderen Namens immer
    // noch der Vorschlag darüber und wäre die erste Zeile, die man trifft.
    final passtNoch = _suche.isEmpty ||
        vorschlag.name.toLowerCase().contains(_suche.toLowerCase());
    return passtNoch ? [vorschlag, ...rest] : rest;
  }

  /// Ob die Eingabe genau eine bestehende Person nennt.
  ///
  /// Gross-/Kleinschreibung zählt hier nicht: Wer „martin" tippt, meint
  /// nicht, eine zweite Person neben „Martin" anzulegen.
  PersonData? get _namensgleich {
    if (_suche.isEmpty) return null;
    for (final p in widget.existingPeople) {
      if (p.name.toLowerCase() == _suche.toLowerCase()) return p;
    }
    return null;
  }

  /// Was der Knopf tut. `null` heisst: nichts, er ist abgeschaltet.
  PersonChoice? get _ergebnis {
    final gleich = _namensgleich;
    if (gleich != null) return PersonChoice.existing(gleich.id);
    if (_gewaehlt != null) return PersonChoice.existing(_gewaehlt!.id);
    if (_suche.isNotEmpty) return PersonChoice.newPerson(_suche);
    return null;
  }

  /// Ob der Knopf eine neue Person anlegen würde.
  bool get _legtAn => _namensgleich == null && _gewaehlt == null && _suche.isNotEmpty;

  Widget _zeile(PersonData person, {required bool istVorschlag}) {
    final bild = person.coverFaceCropPath;
    final farben = Theme.of(context).colorScheme;
    final gewaehlt = _gewaehlt?.id == person.id;
    return ListTile(
      dense: true,
      selected: gewaehlt,
      selectedTileColor: farben.primaryContainer,
      leading: Profilbild(
        datei: bild == null ? null : widget.paths.absolute(bild),
        radius: 16,
        hintergrund: farben.surfaceContainerHighest,
        symbolgroesse: 18,
      ),
      title: Text(person.name, overflow: TextOverflow.ellipsis),
      subtitle: istVorschlag
          ? Text(AppTexte.of(context).personVorschlag,
              style: TextStyle(color: farben.primary, fontSize: 12))
          : null,
      trailing: gewaehlt ? const Icon(Icons.check) : null,
      // Ein zweiter Tipp nimmt die Wahl zurück – sonst käme man aus einer
      // versehentlich getroffenen Zeile nur über Abbrechen wieder heraus.
      onTap: () => setState(() => _gewaehlt = gewaehlt ? null : person),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final gezeigt = _gezeigt;
    final vorschlag = widget.suggestedPerson;

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.currentName != null) ...[
              Text(t.personAktuell(widget.currentName!),
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(height: AppSpacing.md),
            ],
            TextField(
              controller: _suchfeld,
              focusNode: _fokus,
              autofocus: true,
              decoration: InputDecoration(
                labelText: t.personSuchenOderAnlegen,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _suche.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        tooltip: t.allgLeeren,
                        onPressed: () => setState(_suchfeld.clear),
                      ),
              ),
              onChanged: (_) => setState(() {
                // Eine Wahl aus der Liste gilt nur, solange sie noch in der
                // Liste steht. Wer weitertippt, meint jemand anderen.
                if (_gewaehlt != null &&
                    !_gewaehlt!.name.toLowerCase().contains(_suche.toLowerCase())) {
                  _gewaehlt = null;
                }
              }),
              onSubmitted: (_) {
                final e = _ergebnis;
                if (e != null) Navigator.pop(context, e);
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            if (widget.existingPeople.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Text(t.personNochKeine,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
              )
            else if (gezeigt.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Text(t.personKeinTreffer(_suche),
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
              )
            else
              // Fest begrenzt statt mitwachsend: Ein Dialog, der bei
              // vierzig Personen bis an den Bildschirmrand reicht, schiebt
              // seine eigenen Knöpfe hinaus.
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: Scrollbar(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: gezeigt.length,
                    itemBuilder: (_, i) => _zeile(gezeigt[i],
                        istVorschlag:
                            vorschlag != null && gezeigt[i].id == vorschlag.id),
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t.allgAbbrechen)),
        if (widget.erlaubtIgnorieren)
          TextButton(
            onPressed: () =>
                Navigator.pop(context, const PersonChoice.ignorieren()),
            child: Text(t.gesichtIgnorieren),
          ),
        FilledButton(
          onPressed: _ergebnis == null
              ? null
              : () => Navigator.pop(context, _ergebnis),
          // Die Beschriftung sagt, was passiert: zuordnen oder neu anlegen.
          // Ein Knopf, der beides tut und nur eines sagt, legt irgendwann
          // eine zweite „Martin" an, weil sich jemand vertippt hat.
          child: Text(_legtAn
              ? t.personAnlegenAktion(_suche)
              : t.personZuordnenAktion),
        ),
      ],
    );
  }
}
