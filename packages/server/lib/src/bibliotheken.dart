import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:kern/auswertung/auswertungen.dart' show Analysestufe;
import 'package:kern/auswertung/modelle.dart';
import 'package:kern/db/database.dart';
import 'package:kern/protokoll.dart';
import 'package:kern/services/bildwerkzeuge.dart';
import 'package:kern/services/reverse_geocoder.dart';
import 'package:path/path.dart' as p;

import 'auswertungsdienst.dart';
import 'bibliothek.dart';
import 'rechnen.dart';
import 'hochladen.dart';

/// Was zu einem Konto gehört: seine Bibliothek, sein Eingang für Uploads
/// und seine Auswertung.
class Kontobereich {
  Kontobereich(this.bibliothek, this.hochladen, this.auswertung, this.vergabe);

  final Bibliothek bibliothek;
  final Hochladen hochladen;
  final Auswertungsdienst auswertung;

  /// Wer an welcher Aufnahme rechnet – Rechner und Server (Issue #104).
  final Rechenvergabe vergabe;
}

/// Die Bibliotheken des Servers, eine je Konto, unter
/// `<PV_DATEN>/bibliotheken/<Kontokennung>`.
///
/// **Getrennt, nicht nur gefiltert.** Jede Bibliothek ist eine eigene
/// Datenbank mit eigenem Ordner – dasselbe Schema wie in der App. Eine
/// Anfrage kommt nur an die Bibliothek ihres Kontos heran, weil es keinen
/// Weg von einer zur anderen gibt, nicht weil eine Abfrage richtig
/// filtert. Teilen zwischen Konten folgt später (Stufe 6) als eigener,
/// ausdrücklicher Weg.
///
/// Geöffnet wird bei Bedarf und dann offen gehalten; die Modelle teilen
/// sich alle, und gerechnet wird immer nur in einer ([Rechenreihe]).
class Bibliotheken {
  Bibliotheken({
    required this.wurzel,
    required this.eingang,
    Modelle? modelle,
    this.ortsverzeichnis,
    this.bildwerkzeuge = const WerkzeugBildwerkzeuge(),
    this.ruhe = const Duration(seconds: 10),
    this.selbst = const {...Analysestufe.values},
  }) : modelle = modelle ?? Modelle() {
    // drift warnt, sobald es AppDatabase zweimal gibt – für den Fall, dass
    // zwei Instanzen auf dieselbe Datei schreiben. Hier hat jedes Konto
    // seine eigene Datei, und genau das ist gewollt.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  }

  final Directory wurzel;
  final Directory eingang;
  final Modelle modelle;
  final ReverseGeocoder? ortsverzeichnis;
  final Bildwerkzeuge bildwerkzeuge;

  /// Welche Stufen der Server selbst rechnet (`PV_SELBST_RECHNEN`); die
  /// übrigen bleiben verbundenen Rechnern (siehe Rechenapi).
  final Set<Analysestufe> selbst;

  final Duration ruhe;
  final reihe = Rechenreihe();

  final _offen = <String, Future<Kontobereich>>{};

  static final _kennung = RegExp(r'^[0-9a-f-]{36}$');

  /// Der Bereich von [kontoId]; beim ersten Mal wird er geöffnet und eine
  /// Auswertung angestossen, die nachholt, was offen ist.
  Future<Kontobereich> fuer(String kontoId) {
    if (!_kennung.hasMatch(kontoId)) {
      throw ArgumentError('keine Kontokennung: $kontoId');
    }
    return _offen.putIfAbsent(kontoId, () async {
      final vergabe = Rechenvergabe();
      final b = await Bibliothek.oeffne(
        Directory(p.join(wurzel.path, kontoId)),
        bildwerkzeuge: bildwerkzeuge,
        modelle: modelle,
        ortsverzeichnis: ortsverzeichnis,
        vergabe: vergabe,
      );
      final auswertung = Auswertungsdienst(
        b,
        ruhe: ruhe,
        reihe: reihe,
        vergabe: vergabe,
        selbst: selbst,
      );
      final hochladen = Hochladen(
        Directory(p.join(eingang.path, kontoId)),
        b,
        nachImport: auswertung.anstossen,
      );
      await hochladen.raeumeAuf();
      // Was bis 3.49.8 hinter einer Hauptversion im Papierkorb oder neben
      // einem gelöschten Live-Photo-Foto unsichtbar zurückblieb (#254).
      // Am Server, damit es auch verbundene Geräte erreicht.
      try {
        final n = await b.db.repariereVerdeckteZugehoerige();
        if (n > 0) protokoll('$n verdeckte Aufnahmen in Ordnung gebracht');
      } catch (e) {
        protokoll('Verdeckte Aufnahmen nicht geprüft: $e');
      }
      auswertung.anstossen();
      return Kontobereich(b, hochladen, auswertung, vergabe);
    });
  }

  /// Übernimmt die Bibliothek aus der Zeit vor den Konten
  /// (`bibliotheken/standard`) für [kontoId] – beim ersten Konto. Gibt
  /// zurück, ob es eine gab.
  static bool uebernimmStandard(Directory wurzel, String kontoId) {
    final alt = Directory(p.join(wurzel.path, 'standard'));
    final neu = Directory(p.join(wurzel.path, kontoId));
    if (!alt.existsSync() || neu.existsSync()) return false;
    alt.renameSync(neu.path);
    return true;
  }

  /// Schliesst die Bibliothek von [kontoId], falls sie offen ist – vor
  /// dem Umzug, der sie austauscht.
  Future<void> schliesse(String kontoId) async {
    final f = _offen.remove(kontoId);
    if (f == null) return;
    final b = await f;
    await b.auswertung.beende();
    await b.bibliothek.schliesse();
  }

  /// Legt die Bibliothek von [kontoId] beiseite, wenn das Konto entfernt
  /// wird: `bibliotheken/<Konto>.entfernt-<Zeit>`, nicht gelöscht – wie beim
  /// Umzug. Wer sie wirklich los sein will, löscht den Ordner von Hand.
  /// Halb hochgeladene Dateien im Eingang gehen weg.
  Future<Directory?> legeBeiseite(String kontoId) async {
    await schliesse(kontoId);
    final eingangKonto = Directory(p.join(eingang.path, kontoId));
    if (await eingangKonto.exists()) await eingangKonto.delete(recursive: true);
    final ordner = Directory(p.join(wurzel.path, kontoId));
    if (!await ordner.exists()) return null;
    final stempel = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(RegExp(r'[^0-9]'), '')
        .substring(0, 14);
    return ordner.rename(p.join(wurzel.path, '$kontoId.entfernt-$stempel'));
  }

  Future<void> schliesseAlle() async {
    for (final f in _offen.values) {
      final b = await f;
      await b.auswertung.beende();
      await b.bibliothek.schliesse();
    }
    _offen.clear();
  }
}
