import 'dart:async';

import 'package:kern/auswertung/auswertungen.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/bildnachlauf.dart';
import 'package:kern/protokoll.dart';
import 'package:kern/services/speicher_rueckgabe.dart';

import 'bibliothek.dart';
import 'rechnen.dart';

/// Wo die Auswertung gerade steht.
class Auswertungsstand {
  const Auswertungsstand({
    required this.stufe,
    required this.stufeNummer,
    required this.stufenGesamt,
    required this.erledigt,
    required this.gesamt,
  });

  final Analysestufe stufe;
  final int stufeNummer;
  final int stufenGesamt;
  final int erledigt;
  final int gesamt;

  Map<String, Object> alsJson() => {
    'stufe': stufe.name,
    'stufeNummer': stufeNummer,
    'stufenGesamt': stufenGesamt,
    'erledigt': erledigt,
    'gesamt': gesamt,
  };
}

/// Wertet die Bibliothek nach dem Hochladen aus – dieselben Stufen in
/// derselben Reihenfolge wie die Hintergrundanalyse der App (siehe
/// [Analysestufe]).
///
/// **Gesammelt, nicht je Datei.** Ein Handy lädt hundert Fotos hoch; nach
/// jedem einzelnen eine Analyse über die ganze Bibliothek zu beginnen, hiesse
/// hundertmal die Modelle laden. [anstossen] wartet deshalb [ruhe] ab, bis
/// nichts mehr hereinkommt. Kommt während eines Laufs etwas dazu, folgt ein
/// zweiter: Jede Stufe sucht ihre offenen Aufnahmen beim Beginn.
///
/// **Modelle bleiben nicht liegen.** Nach jeder Stufe und alle
/// [freigabeTakt] gibt der Dienst frei, was gerade niemand benutzt. Ein Server mit der
/// Bildbeschreibung im Speicher hielte sonst Tag und Nacht ein Gigabyte.
class Auswertungsdienst {
  Auswertungsdienst(
    this.bibliothek, {
    this.ruhe = const Duration(seconds: 10),
    Duration freigabeTakt = const Duration(minutes: 1),
    Rechenreihe? reihe,
    this.vergabe,
    this.selbst = const {...Analysestufe.values},
  }) : reihe = reihe ?? Rechenreihe() {
    _freigabe = Timer.periodic(freigabeTakt, (_) => _gibFrei());
  }

  final Bibliothek bibliothek;

  /// Teilen sich alle Bibliotheken eines Servers: Es rechnet immer nur
  /// eine, sonst lägen die Modelle doppelt im Speicher und die Kerne wären
  /// doppelt belegt, ohne dass irgendetwas früher fertig würde.
  final Rechenreihe reihe;

  /// Wie lange nach dem letzten Anstoss gewartet wird.
  final Duration ruhe;

  /// Wer an welcher Aufnahme rechnet (siehe Rechenvergabe).
  final Rechenvergabe? vergabe;

  /// Welche Stufen der Server selbst rechnet. Die übrigen rechnen
  /// verbundene Rechner – oder niemand, wenn keiner hilft.
  final Set<Analysestufe> selbst;

  Timer? _warte;
  late final Timer _freigabe;
  Future<void>? _lauf;
  bool _nochmal = false;
  bool _beendet = false;

  /// Der aktuelle Stand, `null`, solange nichts läuft.
  Auswertungsstand? get stand => _stand;
  Auswertungsstand? _stand;

  bool get laeuft => _lauf != null;

  /// Ein Lauf ist fällig. Beginnt nach [ruhe], wenn bis dahin nichts
  /// weiteres kommt; läuft gerade einer, folgt danach ein weiterer.
  void anstossen() {
    if (_beendet) return;
    if (_lauf != null) {
      _nochmal = true;
      return;
    }
    _warte?.cancel();
    _warte = Timer(ruhe, _beginne);
  }

  /// Sofort und ohne Wartezeit – für den Start des Servers und einen
  /// Anstoss von Hand. Gibt den Lauf zurück.
  Future<void> jetzt() {
    _warte?.cancel();
    _beginne();
    return _lauf ?? Future.value();
  }

  void _beginne() {
    if (_beendet || _lauf != null) return;
    _lauf = () async {
      try {
        await reihe.nacheinander(_laufe);
      } catch (e) {
        protokoll('Auswertung gescheitert: $e');
      } finally {
        _lauf = null;
        _stand = null;
      }
      if (_nochmal && !_beendet) {
        _nochmal = false;
        _beginne();
      }
    }();
  }

  Future<void> _laufe() async {
    // Kann in der Reihe gewartet haben, während der Server beendet wurde.
    if (_beendet) return;
    await _nachlaeufe();
    if (!await bibliothek.db.autoAnalyzeAfterImportEnabled()) return;
    bibliothek.auswertungAbbrechen = false;
    vergabe?.neuerDurchgang();
    final stufen = [
      for (final s in Analysestufe.values)
        if (selbst.contains(s)) s,
    ];
    final uhr = Stopwatch()..start();
    for (var i = 0; i < stufen.length; i++) {
      if (bibliothek.auswertungAbbrechen) break;
      final stufe = stufen[i];
      var zuletzt = 0;
      // Jede Stufe für sich abgesichert: Scheitert eine, laufen die
      // folgenden trotzdem.
      try {
        await for (final f in bibliothek.auswertungen.stufe(stufe)) {
          zuletzt = f.total;
          _stand = Auswertungsstand(
            stufe: stufe,
            stufeNummer: i + 1,
            stufenGesamt: stufen.length,
            erledigt: f.done,
            gesamt: f.total,
          );
          if (bibliothek.auswertungAbbrechen) break;
        }
        if (zuletzt > 0) {
          protokoll('Auswertung ${stufe.name}: $zuletzt Aufnahmen');
        }
      } catch (e) {
        protokoll('Auswertung ${stufe.name} gescheitert: $e');
      }
      // Die Modelle dieser Stufe gleich abgeben, nicht erst nach dem Takt:
      // Sonst lägen CLIP, Gesichter und Texterkennung noch im Speicher,
      // während die Bildbeschreibung lädt – mit der Grafik lagerte ein
      // Container mit 4 GiB dabei fast ein Gigabyte aus.
      await _gibFrei();
    }
    protokoll('Auswertung fertig nach ${uhr.elapsed.inSeconds} s');
  }

  /// Einmal je Bibliothek: was ein früherer Fehler an den Bilddateien
  /// hinterlassen hat (siehe bildnachlauf.dart). Unabhängig davon, ob
  /// ausgewertet wird – es sind keine Auswertungen, sondern Reparaturen.
  Future<void> _nachlaeufe() async {
    final db = bibliothek.db;
    final laeufe = <(String, Future<int> Function())>[
      (
        nachlaufRohvorschau,
        () => erneuereRohvorschauen(
          db,
          bibliothek.pfade,
          bibliothek.importe,
          abbrechen: () => _beendet,
        ),
      ),
      (
        nachlaufOriginalmasse,
        () => berichtigeOriginalmasse(
          db,
          bibliothek.pfade,
          abbrechen: () => _beendet,
        ),
      ),
    ];
    for (final (schluessel, lauf) in laeufe) {
      if (_beendet) return;
      if (await db.aufgabeFertigAm(schluessel) != null) continue;
      try {
        final n = await lauf();
        if (_beendet) return;
        await db.merkeAufgabenlauf(schluessel);
        protokoll('Nachlauf $schluessel: $n Aufnahmen');
      } catch (e) {
        protokoll('Nachlauf $schluessel gescheitert: $e');
      }
    }
  }

  Future<void> _gibFrei() async {
    var etwas = false;
    for (final h in bibliothek.modelle.alle) {
      if (await h.freigebenWennUnbenutzt()) etwas = true;
    }
    // Die geschlossenen Sitzungen geben ihren Speicher an die
    // C-Bibliothek zurück, nicht ans System (siehe SpeicherRueckgabe).
    if (etwas) SpeicherRueckgabe.jetzt();
  }

  /// Hält einen laufenden Durchgang nach der aktuellen Aufnahme an und
  /// wartet auf ihn.
  Future<void> beende() async {
    _beendet = true;
    _warte?.cancel();
    _freigabe.cancel();
    bibliothek.auswertungAbbrechen = true;
    await _lauf;
    await _gibFrei();
  }
}

/// Lässt Arbeiten nacheinander laufen, in der Reihenfolge ihres Eintreffens.
class Rechenreihe {
  Future<void> _ende = Future.value();

  Future<T> nacheinander<T>(Future<T> Function() arbeit) {
    final vorher = _ende;
    final fertig = Completer<void>();
    _ende = fertig.future;
    return vorher.then((_) => arbeit()).whenComplete(fertig.complete);
  }
}
