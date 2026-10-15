import 'package:flutter/material.dart';

/// Das Kontextmenü jedes Eingabefelds (Rechtsklick, langes Drücken) – mit
/// „Einfügen“ in jedem Fall.
///
/// Flutters eigenes Menü bietet „Einfügen“ nur an, wenn es die
/// Zwischenablage vorher als einfügbar erkannt hat. Unter macOS schlägt
/// diese Abfrage nicht verlässlich an; dann fehlte der Eintrag, und ein
/// Passwort aus dem Passwortmanager liess sich nur per Tastenkürzel
/// einsetzen. Kopieren und Ausschneiden bleiben, wie Flutter sie anbietet –
/// in Passwortfeldern also aus.
///
/// Jedes `TextField` und jede `SearchBar` bekommt es als
/// `contextMenuBuilder`; `einfuegen_ueberall_test.dart` achtet darauf.
Widget einfuegbaresMenue(BuildContext context, EditableTextState feld) {
  final eintraege = [...feld.contextMenuButtonItems];
  if (!feld.widget.readOnly &&
      !eintraege.any((e) => e.type == ContextMenuButtonType.paste)) {
    // Wo es auch sonst steht: nach Ausschneiden und Kopieren, vor „Alles
    // auswählen“.
    final vor = eintraege.indexWhere(
      (e) => e.type == ContextMenuButtonType.selectAll,
    );
    eintraege.insert(
      vor < 0 ? eintraege.length : vor,
      ContextMenuButtonItem(
        type: ContextMenuButtonType.paste,
        onPressed: () => feld.pasteText(SelectionChangedCause.toolbar),
      ),
    );
  }
  return AdaptiveTextSelectionToolbar.buttonItems(
    anchors: feld.contextMenuAnchors,
    buttonItems: eintraege,
  );
}
