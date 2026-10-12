import 'dart:async';

import 'package:kern/auswertung/auswertungen.dart';
import 'package:kern/protokoll.dart';
import 'package:kern/services/speicher_rueckgabe.dart';

import 'bibliothek.dart';

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
/// **Modelle bleiben nicht liegen.** Alle [freigabeTakt] gibt der Dienst
/// frei, was gerade niemand benutzt – wie die App. Ein Server mit der
/// Bildbeschreibung im Speicher hielte sonst Tag und Nacht ein Gigabyte.
class Auswertungsdienst {
  Auswertungsdienst(
    this.bibliothek, {
    this.ruhe = const Duration(seconds: 10),
    Duration freigabeTakt = const Duration(minutes: 1),
  }) {
    _freigabe = Timer.periodic(freigabeTakt, (_) => _gibFrei());
  }

  final Bibliothek bibliothek;

  /// Wie lange nach dem letzten Anstoss gewartet wird.
  final Duration ruhe;

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
        await _laufe();
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
    if (!await bibliothek.db.autoAnalyzeAfterImportEnabled()) return;
    bibliothek.auswertungAbbrechen = false;
    const stufen = Analysestufe.values;
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
    }
    protokoll('Auswertung fertig nach ${uhr.elapsed.inSeconds} s');
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
