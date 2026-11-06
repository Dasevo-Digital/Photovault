import 'dart:async';

import 'package:kern/db/database.dart';
import 'package:kern/protokoll.dart';
import 'package:kern/services/papierkorb_leeren.dart';

import 'albumteilungen.dart';
import 'bibliotheken.dart';
import 'fassungen_aufraeumen.dart';
import 'konten/kontodienst.dart';

/// Löscht im Papierkorb von [kontoId] endgültig (#296) – ausgewählte
/// [ids], alles vor [vor] (der Ablauf) oder ohne beides den ganzen
/// Papierkorb. Gibt die Kennungen zurück, die gingen.
///
/// Danach gehen auch die gewandelten Fassungen dieser Aufnahmen
/// (`vollbild/`, `abspielbar/`) und die Hinweise auf neue Beiträge, die
/// auf sie zeigen – sonst stünde am Album „3 neu“ für Fotos, die es nicht
/// mehr gibt.
Future<List<String>> leereImBereich(
  Kontobereich bereich,
  String kontoId, {
  Albumteilungen? teilungen,
  Iterable<String>? ids,
  DateTime? vor,
}) async {
  final b = bereich.bibliothek;
  final weg = await leerePapierkorb(b.db, b.pfade, ids: ids, vor: vor);
  if (weg.isEmpty) return weg;
  teilungen?.vergissBeitraege(kontoId, weg);
  try {
    await raeumeFassungenAuf(b);
  } catch (e) {
    protokoll('Gewandelte Fassungen nicht aufgeräumt: $e');
  }
  return weg;
}

/// Wendet die Frist des Papierkorbs an, die jede Bibliothek in ihren
/// Einstellungen trägt (#296).
///
/// In der App läuft derselbe Ablauf, solange sie offen ist – aber nur
/// ohne Server. Eine Bibliothek auf dem Server erreichte er nie: Ein
/// verbundenes Gerät darf seine Kopie nicht selbst ändern. Hier läuft er
/// alle [takt] für jede Bibliothek, und zwar nur, wenn ihr Besitzer ihn
/// eingeschaltet hat (aus ist die Vorgabe, wie in der App).
class Papierkorbablauf {
  Papierkorbablauf({
    required this.konten,
    required this.bibliotheken,
    this.takt = const Duration(hours: 6),
    DateTime Function()? uhr,
  }) : _uhr = uhr ?? DateTime.now;

  final Kontodienst konten;
  final Bibliotheken bibliotheken;
  final Duration takt;
  final DateTime Function() _uhr;
  Timer? _wecker;
  Future<void>? _lauf;

  /// Ein Durchgang über alle Bibliotheken; läuft schon einer, derselbe.
  Future<void> pruefe() => _lauf ??= _pruefe().whenComplete(() => _lauf = null);

  Future<void> _pruefe() async {
    final List<Konto> alle;
    try {
      alle = konten.alle();
    } catch (e) {
      // Im Takt liefe ein Fehler in keine Anfrage, sondern beendete den
      // ganzen Server.
      protokoll('Konten für den Papierkorb nicht gelesen: $e');
      return;
    }
    for (final k in alle) {
      try {
        final bereich = await bibliotheken.fuer(k.id);
        final db = bereich.bibliothek.db;
        final frist = await db.trashSettingsRow();
        if (frist == null || !frist.autoDeleteEnabled) continue;
        final jetzt = _uhr();
        final weg = await leereImBereich(
          bereich,
          k.id,
          teilungen: konten.albumteilungen,
          vor: jetzt.subtract(Duration(days: frist.autoDeleteAfterDays)),
        );
        await db.setLastTrashPurgeAt(jetzt);
        if (weg.isNotEmpty) {
          protokoll(
            'Papierkorb von ${k.name}: '
            '${weg.length == 1 ? 'eine Aufnahme' : '${weg.length} Aufnahmen'} '
            'nach '
            '${frist.autoDeleteAfterDays} Tagen endgültig gelöscht',
          );
        }
      } catch (e) {
        protokoll('Papierkorb von ${k.name} nicht geleert: $e');
      }
    }
  }

  /// Der erste Durchgang wartet [verzug] – erst lauscht der Server, und
  /// die Bibliotheken öffnen sich.
  void starte({Duration verzug = const Duration(minutes: 2)}) {
    _wecker = Timer(verzug, () {
      unawaited(pruefe());
      _wecker = Timer.periodic(takt, (_) => unawaited(pruefe()));
    });
  }

  void beende() => _wecker?.cancel();
}
