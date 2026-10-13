import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import '../auswertung/rechenhilfe.dart';
import '../protokoll.dart';
import '../services/storage_paths.dart';
import 'dateibeschaffung.dart';
import 'verbindung.dart';

/// Wie es um die [Rechenhilfe] steht.
enum Rechenhilfelage {
  /// Noch nicht gestartet oder beendet.
  aus,
  rechnet,

  /// Der Server hat gerade nichts, oder hier fehlt jedes Modell.
  wartet,
  offline,

  /// Der Server kennt `api/v1/rechnen` noch nicht.
  serverZuAlt,
  abgemeldet,
}

class Rechenhilfestand {
  const Rechenhilfestand(this.lage, {this.geliefert = 0, this.ausgelassen = 0});

  final Rechenhilfelage lage;

  /// Seit dem Start geliefert bzw. zurückgegeben, weil es hier nicht ging.
  final int geliefert;
  final int ausgelassen;
}

/// Rechnet für den Server, solange diese App offen ist (Issue #104): holt
/// Aufträge, rechnet sie mit den Modellen hier und schickt die Ergebnisse
/// zurück. Eingetragen wird auf dem Server.
///
/// **Die Kopie bleibt, wie sie ist:** Eine Datei, die hier noch nicht
/// liegt, kommt in eine Zwischenablage und ist nach dem Rechnen wieder
/// weg – sonst wüchse die Kopie über die Rechenhilfe zur ganzen
/// Bibliothek an.
///
/// **Ein Auftrag, der hier nicht geht** (Datei nicht lesbar, Modell fehlt),
/// geht mit `auslassen` zurück: Den rechnet dann der Server selbst, und
/// kein Rechner bekommt ihn wieder.
class Rechenhilfe {
  Rechenhilfe(
    this.verbindung,
    this.paths, {
    required this.arten,
    required this.teile,
    required this.rechne,
    this.darf,
    this.anzahl = 5,
    this.ruhe = const Duration(minutes: 1),
    Directory? zwischenablage,
  }) : _ablage =
           zwischenablage ??
           Directory(p.join(Directory.systemTemp.path, 'pv_rechenhilfe'));

  final Serververbindung verbindung;
  final StoragePaths paths;

  /// Was die Modelle hier gerade können – je Runde neu gefragt, denn ein
  /// Modell kann inzwischen heruntergeladen worden sein.
  final Set<Rechenart> Function() arten;
  final Set<String> Function() teile;
  final Future<Rechenergebnis?> Function(Rechenauftrag auftrag, File datei)
  rechne;

  /// Ob gerade gerechnet werden darf (z. B. nicht bei anderem Schema).
  final bool Function()? darf;
  final int anzahl;

  /// So lange wartet sie, wenn es nichts zu tun gibt.
  final Duration ruhe;
  final Directory _ablage;

  final _stand = StreamController<Rechenhilfestand>.broadcast();
  Rechenhilfestand _letzter = const Rechenhilfestand(Rechenhilfelage.aus);
  Stream<Rechenhilfestand> get stand => _stand.stream;
  Rechenhilfestand get standJetzt => _letzter;

  bool _laeuft = false;
  Future<void>? _schleife;
  Completer<void>? _wecker;
  var _geliefert = 0;
  var _ausgelassen = 0;

  void starte() {
    if (_laeuft) return;
    _laeuft = true;
    _schleife = _laufe();
  }

  /// Hält an; ein Auftrag, der gerade rechnet, wird noch fertig.
  Future<void> beende() async {
    _laeuft = false;
    wecke();
    await _schleife;
    _schleife = null;
    _melde(Rechenhilfelage.aus);
  }

  /// Fragt gleich wieder, statt die Ruhe abzuwarten.
  void wecke() {
    final w = _wecker;
    if (w != null && !w.isCompleted) w.complete();
  }

  Future<void> schliesse() async {
    await beende();
    await _stand.close();
  }

  Future<void> _laufe() async {
    var pause = const Duration(seconds: 2);
    while (_laeuft) {
      try {
        final a = arten();
        if (a.isEmpty || !(darf?.call() ?? true)) {
          _melde(Rechenhilfelage.wartet);
          await _schlafe(ruhe);
          continue;
        }
        final antwort = await verbindung.schicke('api/v1/rechnen/auftraege', {
          'arten': [for (final x in a) x.name],
          'teile': teile().toList(),
          'anzahl': anzahl,
        });
        final auftraege = [
          for (final j in (antwort['auftraege'] as List?) ?? const [])
            Rechenauftrag.ausJson((j as Map).cast<String, Object?>()),
        ];
        pause = const Duration(seconds: 2);
        if (auftraege.isEmpty) {
          _melde(Rechenhilfelage.wartet);
          await _schlafe(ruhe);
          continue;
        }
        _melde(Rechenhilfelage.rechnet);
        for (final auftrag in auftraege) {
          if (!_laeuft) {
            await _zurueck(auftrag);
            continue;
          }
          await _erledige(auftrag);
        }
      } on KeineVerbindung {
        if (!_laeuft) break;
        _melde(Rechenhilfelage.offline);
        await _schlafe(pause);
        pause = Duration(seconds: min(pause.inSeconds * 2, 120));
      } on Serverfehler catch (f) {
        if (f.abgemeldet) {
          _melde(Rechenhilfelage.abgemeldet);
          _laeuft = false;
          break;
        }
        if (f.status == 404) {
          _melde(Rechenhilfelage.serverZuAlt);
          await _schlafe(ruhe * 30);
          continue;
        }
        protokoll('Rechenhilfe: $f');
        _melde(Rechenhilfelage.wartet);
        await _schlafe(pause);
        pause = Duration(seconds: min(pause.inSeconds * 2, 120));
      }
    }
  }

  Future<void> _erledige(Rechenauftrag auftrag) async {
    File? zwischen;
    Rechenergebnis? ergebnis;
    try {
      final hier = paths.absolute(auftrag.datei);
      File datei;
      if (await hier.exists()) {
        datei = hier;
      } else {
        datei = zwischen = File(
          p.join(_ablage.path, '${auftrag.id}${p.extension(auftrag.datei)}'),
        );
        await verbindung.ladeHerunter(
          Dateibeschaffung.adresse(auftrag.datei),
          datei,
        );
      }
      ergebnis = await rechne(auftrag, datei);
    } on Serverfehler catch (f) {
      if (f.abgemeldet) rethrow;
      // Die Datei gibt es auf dem Server nicht (mehr) – dort weiss man,
      // was damit ist.
      protokoll('Rechenhilfe: ${auftrag.datei} – $f');
    } on ArgumentError catch (f) {
      protokoll('Rechenhilfe: ${auftrag.datei} – $f');
    } catch (f) {
      if (f is KeineVerbindung) rethrow;
      protokoll('Rechenhilfe: ${auftrag.art.name} ${auftrag.aufnahme} – $f');
    } finally {
      if (zwischen != null && await zwischen.exists()) await zwischen.delete();
    }
    if (ergebnis == null) {
      _ausgelassen++;
      await _zurueck(auftrag, auslassen: true);
      return;
    }
    try {
      await verbindung.schicke('api/v1/rechnen/ergebnis', {
        'auftrag': auftrag.id,
        'ergebnis': ergebnis.alsJson(),
      });
      _geliefert++;
    } on Serverfehler catch (f) {
      if (f.abgemeldet) rethrow;
      // 409: abgelaufen, oder der Server hat es inzwischen selbst. 400:
      // er nimmt es nicht – beides ist für diesen Auftrag das Ende.
      protokoll('Rechenhilfe: Ergebnis für ${auftrag.aufnahme} – $f');
    }
    _melde(Rechenhilfelage.rechnet);
  }

  Future<void> _zurueck(Rechenauftrag a, {bool auslassen = false}) async {
    try {
      await verbindung.schicke('api/v1/rechnen/zurueck', {
        'auftrag': a.id,
        if (auslassen) 'auslassen': true,
      });
    } on KeineVerbindung {
      // Dann läuft die Vergabe eben ab.
    } on Serverfehler catch (f) {
      if (f.abgemeldet) rethrow;
    }
  }

  /// Mit einer Uhr, die [beende] mit abstellt – ein liegengebliebenes
  /// `Future.delayed` hielte die App (und jeden Test) noch so lange fest.
  Future<void> _schlafe(Duration d) async {
    if (!_laeuft) return;
    final w = _wecker = Completer<void>();
    final uhr = Timer(d, wecke);
    await w.future;
    uhr.cancel();
    _wecker = null;
  }

  void _melde(Rechenhilfelage lage) {
    if (_stand.isClosed) return;
    final neu = Rechenhilfestand(
      lage,
      geliefert: _geliefert,
      ausgelassen: _ausgelassen,
    );
    if (neu.lage == _letzter.lage &&
        neu.geliefert == _letzter.geliefert &&
        neu.ausgelassen == _letzter.ausgelassen) {
      return;
    }
    _letzter = neu;
    _stand.add(neu);
  }
}
