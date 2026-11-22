import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kern/services/import_plan.dart';

import '../l10n/app_localizations.dart';
import '../services/importfehler.dart';
import '../services/importquittungen.dart';
import '../services/meldungsdienst.dart';
import 'hintergrundlauf.dart';
import 'library_state.dart';

/// Ein Import, der nicht am Fortschrittsblatt hängt (IMP-039).
///
/// **Warum es das gibt.** Der Import lief im Zustand des Blattes, und das
/// Blatt war deshalb modal: nicht wegzuschieben, kein Klick daneben, kein
/// Abbrechen. Bei 3000 Fotos war die App eine halbe Stunde gesperrt. Jetzt
/// gehört der Lauf hierher und steht als Zeile in der Aufgabenleiste (ein
/// [Hintergrundlauf] unter [schluessel]) – mit Fortschritt, „Anzeigen“ und
/// „Abbrechen“. Das Blatt ist nur noch eine Ansicht darauf und lässt sich
/// wegschieben.
///
/// **Was erreichbar bleibt, wenn das Blatt weg ist.** Ein Abbruch des
/// ganzen Laufs meldet sich sofort ([melde]), gleich ob jemand hinsieht.
/// Am Ende steht die Bilanz als Meldung mit „Anzeigen“ da – auch im
/// Verlauf hinter der Glocke –, und „Anzeigen“ öffnet das Blatt mit
/// „Warum?“, dem erneuten Versuch und der Quittung.
class Importlauf extends ChangeNotifier {
  Importlauf({
    required this.library,
    required this.plan,
    required this.texte,
    this.zeigen,
    this.aufraeumen,
  });

  /// Räumt weg, was nur dieser Lauf braucht – die entpackten Archive
  /// eines Umzugs. Einmal, sobald nichts mehr erneut zu versuchen ist oder
  /// der Lauf abgelöst wird (siehe [verwerfe]).
  Future<void> Function()? aufraeumen;

  Future<void> _raeumeAuf() async {
    final f = aufraeumen;
    aufraeumen = null;
    try {
      await f?.call();
    } on Object catch (e) {
      debugPrint('Import: Aufräumen – $e');
    }
  }

  /// Der Lauf wird nicht mehr gebraucht – ein neuer Import löst ihn ab,
  /// oder die App endet. Ein noch laufender bricht ab.
  Future<void> verwerfe() async {
    abbrechen();
    // Erst wenn die letzte Datei durch ist – sie kann gerade aus dem
    // entpackten Archiv gelesen werden.
    await _ende;
    await _raeumeAuf();
  }

  /// Das Ende des gerade laufenden (oder letzten) Durchgangs.
  Future<void>? _ende;

  /// Unter dieser Kennung steht der Lauf in der Aufgabenleiste.
  static const schluessel = 'import';

  final LibraryState library;
  final ImportPlan plan;

  /// Die Texte in der Sprache der Oberfläche, beim Start aufgelöst: Die
  /// Meldungen am Ende entstehen, wenn das Blatt längst weg sein kann.
  final AppTexte texte;

  /// Öffnet das Blatt wieder – für „Anzeigen“ an der Schlussmeldung.
  void Function(Importlauf lauf)? zeigen;

  int erledigt = 0;
  int gesamt = 0;
  String? datei;
  bool fertig = false;
  bool abgebrochen = false;
  String? quittungId;

  /// Die in diesem Lauf neu hereingekommenen Aufnahmen – für „Jetzt
  /// sichten“.
  final List<String> importierteIds = [];
  int duplikate = 0;
  int fehler = 0;

  /// Wie viele in der Fotokammer liegen (#336).
  int inKammer = 0;

  /// Die gescheiterten Dateien mit ihrem Grund – für „Warum?“ und den
  /// erneuten Versuch.
  final gescheitert = <String, Object?>{};

  bool get laeuft => !fertig;

  /// Wie viele Blätter gerade auf diesen Lauf sehen. Sieht keines hin,
  /// meldet sich das Ende als Meldung.
  int _ansichten = 0;
  bool get sichtbar => _ansichten > 0;
  void angezeigt() => _ansichten++;
  void verborgen() => _ansichten = _ansichten > 0 ? _ansichten - 1 : 0;

  /// Startet den Import der Dateien in [plan].
  Future<void> starte() =>
      _ende = _laufe(plan.eintraege.map((e) => e.pfad).toList(), plan);

  /// Nur die gescheiterten Dateien noch einmal, mit demselben Plan.
  Future<void> wiederhole() async {
    final pfade = gescheitert.keys.toList();
    if (pfade.isEmpty || laeuft) return;
    gescheitert.clear();
    fehler = 0;
    erledigt = 0;
    gesamt = pfade.length;
    datei = null;
    abgebrochen = false;
    await (_ende = _laufe(pfade, plan.auswahl(pfade.toSet())));
  }

  /// Bricht nach der gerade laufenden Datei ab.
  void abbrechen() {
    if (laeuft) library.brichAufgabeAb(schluessel);
  }

  Future<void> _laufe(List<String> pfade, ImportPlan plan) async {
    fertig = false;
    quittungId = null;
    notifyListeners();
    final offen = pfade.toSet();
    library.verwerfeLauf(schluessel);
    final lauf = library.starteImport(
      titel: texte.importLaeuft,
      strom: () => _strom(pfade, plan, offen),
    );
    await lauf.abschluss;
    final e = lauf.fehler;
    abgebrochen = lauf.abgebrochen;
    if (e != null) {
      // Was der Lauf nicht mehr erreichte, kam auch nicht herein – und
      // lässt sich so noch einmal versuchen.
      for (final pfad in offen) {
        gescheitert[pfad] = e;
      }
      fehler += offen.isEmpty ? 1 : offen.length;
      // Der wirkliche Grund: Vorher stand hier für jeden Abbruch „…
      // haben sich geändert“, auch wenn der Server weg oder zu alt war
      // (IMP-087).
      melde.warnung(
        e is QuittungSchreibfehler
            ? texte.quittungSchreibfehler
            : importFehlertext(texte, e),
      );
    }
    fertig = true;
    library.verwerfeLauf(schluessel);
    notifyListeners();
    if (!sichtbar) _meldeEnde();
    if (gescheitert.isEmpty) await _raeumeAuf();
  }

  Stream<ImportProgress> _strom(
    List<String> pfade,
    ImportPlan plan,
    Set<String> offen,
  ) async* {
    final ablage = await Importquittungen.fuer(library.paths.root);
    await for (final p in ablage.protokolliere(
      plan,
      pfade.isEmpty
          ? const Stream.empty()
          : library.importFiles(pfade, plan: plan),
      begonnen: (id) => quittungId = id,
    )) {
      erledigt = p.done;
      gesamt = p.total;
      datei = p.currentFile;
      if (p.pfad case final pfad?) offen.remove(pfad);
      if (p.assetId case final id?) importierteIds.add(id);
      if (p.duplikat) duplikate++;
      if (p.kammer) inKammer++;
      if (p.gescheitert) {
        fehler++;
        if (p.pfad case final pfad?) gescheitert[pfad] = p.grund;
      }
      notifyListeners();
      yield p;
    }
  }

  /// Die Bilanz als eine Zeile, wie im Blatt.
  String bilanz(AppTexte t) => [
    if (inKammer == 0 || importierteIds.isNotEmpty)
      t.importBilanzNeu(importierteIds.length),
    if (inKammer > 0) t.importBilanzKammer(inKammer),
    if (duplikate > 0) t.importBilanzDuplikate(duplikate),
    if (fehler > 0) t.importBilanzFehler(fehler),
  ].join(' · ');

  void _meldeEnde() {
    final text =
        '${abgebrochen ? texte.importAbgebrochen : texte.importAbgeschlossen}'
        ' – ${bilanz(texte)}';
    final aktion = zeigen == null
        ? null
        : (beschriftung: texte.importAnzeigen, beiDruck: () => zeigen!(this));
    if (fehler > 0) {
      melde.warnung(text, aktion: aktion);
    } else {
      melde.erfolg(text, aktion: aktion);
    }
  }
}
