import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// Fragt nach einem Namen und gibt ihn beschnitten zurück – `null`, wenn
/// abgebrochen oder nur Leerraum eingegeben wurde.
///
/// **Warum ein eigenes Widget und nicht drei Zeilen am Aufrufort.** Der
/// naheliegende Weg legt eine `TextEditingController` an, ruft
/// `showDialog`, wartet und wirft sie danach weg. Das ist falsch, und
/// zwar auf eine Weise, die man der laufenden App nicht ansieht:
/// `showDialog` kommt zurück, sobald `Navigator.pop` gerufen wurde – die
/// Ausblendung des Fensters läuft dann noch, und das Textfeld greift
/// währenddessen weiter auf die Steuerung zu. In der Auslieferung sind
/// die Behauptungen abgeschaltet, es fällt niemandem auf; im Test fällt
/// es sofort auf („A TextEditingController was used after being
/// disposed").
///
/// Ein Widget, das seine Steuerung selbst hält und in `dispose`
/// aufräumt, hat das Problem nicht: Es wird erst abgebaut, wenn das
/// Fenster wirklich weg ist.
Future<String?> frageNamen(
  BuildContext context, {
  required String titel,
  required String feldbeschriftung,
  String vorgabe = '',
  String? uebernehmen,
  bool mehrzeilig = false,
  bool leerErlaubt = false,
}) async {
  final ergebnis = await showDialog<String>(
    context: context,
    builder: (dialog) => _NamensDialog(
      titel: titel,
      feldbeschriftung: feldbeschriftung,
      vorgabe: vorgabe,
      uebernehmen: uebernehmen ?? AppTexte.of(dialog).allgUebernehmen,
      mehrzeilig: mehrzeilig,
    ),
  );
  if (ergebnis == null) return null;
  final sauber = ergebnis.trim();
  // Bei einer Notiz ist der leere Text eine Eingabe – so löscht man sie.
  // Bei einem Namen ist er keine.
  return (sauber.isEmpty && !leerErlaubt) ? null : sauber;
}

class _NamensDialog extends StatefulWidget {
  final String titel;
  final String feldbeschriftung;
  final String vorgabe;
  final String uebernehmen;
  final bool mehrzeilig;

  const _NamensDialog({
    required this.titel,
    required this.feldbeschriftung,
    required this.vorgabe,
    required this.uebernehmen,
    this.mehrzeilig = false,
  });

  @override
  State<_NamensDialog> createState() => _NamensDialogState();
}

class _NamensDialogState extends State<_NamensDialog> {
  late final _steuerung = TextEditingController(text: widget.vorgabe)
    // Der Vorschlag steht vollständig ausgewählt da: Wer ihn übernehmen
    // will, drückt die Eingabetaste; wer ihn ersetzen will, tippt drauf
    // los, ohne erst löschen zu müssen.
    ..selection = widget.mehrzeilig
        // Eine Notiz will man fortsetzen, nicht ersetzen.
        ? TextSelection.collapsed(offset: widget.vorgabe.length)
        : TextSelection(baseOffset: 0, extentOffset: widget.vorgabe.length);

  @override
  void dispose() {
    _steuerung.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    return AlertDialog(
      title: Text(widget.titel),
      content: TextField(
        controller: _steuerung,
        autofocus: true,
        // Mehrzeilig gibt es keine Eingabetaste zum Abschliessen – dort
        // wäre sie ein Zeilenumbruch, und ein Notizfeld ohne Umbruch
        // wäre kein Notizfeld.
        minLines: widget.mehrzeilig ? 3 : 1,
        maxLines: widget.mehrzeilig ? 8 : 1,
        decoration: InputDecoration(labelText: widget.feldbeschriftung),
        onSubmitted: widget.mehrzeilig
            ? null
            : (w) => Navigator.pop(context, w),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t.allgAbbrechen)),
        FilledButton(
            onPressed: () => Navigator.pop(context, _steuerung.text),
            child: Text(widget.uebernehmen)),
      ],
    );
  }
}

/// Ein Dialoginhalt, der seine Textsteuerung selbst besitzt.
///
/// Für alle Fenster, die mehr wollen als [frageNamen] – eine PIN, eine
/// Bestätigung durch Abtippen, ein Feld neben anderen Bedienelementen.
///
/// **Der Fehler, den es verhindert,** ist derselbe wie oben und stand an
/// sieben Stellen dieser App: `showDialog` kommt zurück, sobald
/// `Navigator.pop` gerufen wurde. Die Ausblendung läuft dann noch, das
/// Textfeld baut sich dabei weiter auf – und greift auf eine Steuerung
/// zu, die der Aufrufer inzwischen weggeworfen hat. In der Auslieferung
/// sind die Behauptungen abgeschaltet und es fällt nicht auf; im Test
/// fällt es sofort auf.
///
/// ```dart
/// showDialog(
///   context: context,
///   builder: (dialog) => MitTextsteuerung(
///     builder: (context, steuerung) => AlertDialog(...),
///   ),
/// );
/// ```
class MitTextsteuerung extends StatefulWidget {
  final String vorgabe;

  /// Ob der Vorgabetext beim Öffnen ausgewählt ist – dann ersetzt das
  /// erste Zeichen ihn, statt sich anzuhängen.
  final bool vorgabeAuswaehlen;

  final Widget Function(BuildContext, TextEditingController) builder;

  const MitTextsteuerung({
    super.key,
    this.vorgabe = '',
    this.vorgabeAuswaehlen = true,
    required this.builder,
  });

  @override
  State<MitTextsteuerung> createState() => _MitTextsteuerungState();
}

class _MitTextsteuerungState extends State<MitTextsteuerung> {
  late final _steuerung = TextEditingController(text: widget.vorgabe)
    ..selection = widget.vorgabeAuswaehlen
        ? TextSelection(baseOffset: 0, extentOffset: widget.vorgabe.length)
        : TextSelection.collapsed(offset: widget.vorgabe.length);

  @override
  void dispose() {
    _steuerung.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _steuerung);
}

/// Wie [MitTextsteuerung], nur mit mehreren Feldern.
///
/// Für Fenster, die zweimal dasselbe abfragen – eine PIN und ihre
/// Bestätigung, eine Passphrase und ihre Bestätigung. Zwei geschachtelte
/// [MitTextsteuerung] täten es auch; eine Ebene je Feld macht den Aufbau
/// aber schwerer lesbar, als die Sache ist.
class MitTextsteuerungen extends StatefulWidget {
  final int anzahl;
  final Widget Function(BuildContext, List<TextEditingController>) builder;

  const MitTextsteuerungen({
    super.key,
    required this.anzahl,
    required this.builder,
  });

  @override
  State<MitTextsteuerungen> createState() => _MitTextsteuerungenState();
}

class _MitTextsteuerungenState extends State<MitTextsteuerungen> {
  late final _steuerungen =
      List.generate(widget.anzahl, (_) => TextEditingController());

  @override
  void dispose() {
    for (final s in _steuerungen) {
      s.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _steuerungen);
}
