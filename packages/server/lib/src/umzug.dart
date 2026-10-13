import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:sqlite3/sqlite3.dart';

import 'anmeldung_api.dart';
import 'bibliotheken.dart';
import 'hochladen.dart';

Response _json(Object? daten, {int status = 200}) => Response(
  status,
  body: jsonEncode(daten),
  headers: {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store',
  },
);

/// Zieht eine Bibliothek, die bisher nur auf einem Rechner lag, auf den
/// Server – samt allem: Aufnahmen, Personen, Bearbeitungen, Tresor.
///
/// **Nur in eine leere Bibliothek.** Zwei Bibliotheken zusammenzuführen
/// ist etwas anderes; der Umzug ersetzt die leere Bibliothek des Kontos.
/// Sie wird dabei nicht gelöscht, sondern beiseitegelegt
/// (`bibliotheken/<Konto>.vor-umzug-<Zeit>`).
///
/// **Der Ablauf.** `beginnen` legt einen Zwischenordner an. Die Dateien
/// kommen per tus mit ihrem Pfad in der Bibliothek und ihrer Prüfsumme;
/// was schon dort liegt, nennt `stand`, sodass ein unterbrochener Umzug
/// weitergeht, statt von vorn zu beginnen. Die Datenbank kommt zuletzt
/// (`art=datenbank`). `abschliessen` tauscht den Zwischenordner gegen die
/// leere Bibliothek und öffnet sie – mit der Migration auf das Schema
/// dieses Servers und dem Protokoll für den Abgleich.
class Umzugsdienst {
  Umzugsdienst(this.bibliotheken);

  final Bibliotheken bibliotheken;
  final _hochladen = <String, Hochladen>{};

  Directory _zwischen(String kontoId) =>
      Directory(p.join(bibliotheken.wurzel.path, '$kontoId.umzug'));

  Future<int> _aufnahmen(String kontoId) async {
    final db = (await bibliotheken.fuer(kontoId)).bibliothek.db;
    return (await db
            .customSelect('SELECT count(*) AS n FROM assets')
            .getSingle())
        .read<int>('n');
  }

  /// Hochladen in den Zwischenordner des Kontos.
  Hochladen hochladen(Request anfrage) {
    final id = kontoVon(anfrage).id;
    return _hochladen.putIfAbsent(
      id,
      () => Hochladen(
        Directory(p.join(bibliotheken.eingang.path, '$id.umzug')),
        null,
        pfad: '/api/v1/umzug/hochladen',
        abschluss: (teil, a) => _lege(id, teil, a),
      ),
    );
  }

  Future<Map<String, Object?>> _lege(
    String kontoId,
    File teil,
    Map<String, Object?> a,
  ) async {
    final soll = a['sha256'] as String?;
    if (soll != null) {
      final ist = (await sha256.bind(teil.openRead()).first).toString();
      if (ist != soll) {
        await teil.delete();
        return {'ausgang': 'failed', 'fehler': 'Prüfsumme stimmt nicht'};
      }
    }
    final zwischen = _zwischen(kontoId);
    final ziel = a['art'] == 'datenbank'
        ? File(p.join(zwischen.path, 'library.sqlite'))
        : File(p.join(zwischen.path, 'library', a['pfad']! as String));
    if (!p.isWithin(zwischen.path, ziel.path)) {
      await teil.delete();
      return {'ausgang': 'failed', 'fehler': 'Pfad ausserhalb'};
    }
    await ziel.parent.create(recursive: true);
    await teil.rename(ziel.path);
    return {'ausgang': 'imported'};
  }

  Future<Response> beginnen(Request anfrage) async {
    final id = kontoVon(anfrage).id;
    if (await _aufnahmen(id) > 0) {
      return _json({
        'fehler':
            'Die Bibliothek dieses Kontos ist nicht leer – ein Umzug geht nur '
            'in eine leere.',
      }, status: 409);
    }
    await Directory(
      p.join(_zwischen(id).path, 'library'),
    ).create(recursive: true);
    return _json({'bereit': true});
  }

  /// Was schon im Zwischenordner liegt: Pfad → Grösse.
  Future<Response> stand(Request anfrage) async {
    final zwischen = _zwischen(kontoVon(anfrage).id);
    final bib = Directory(p.join(zwischen.path, 'library'));
    final dateien = <String, int>{};
    if (await bib.exists()) {
      await for (final e in bib.list(recursive: true)) {
        if (e is File) {
          dateien[p.posix.joinAll(
            p.split(p.relative(e.path, from: bib.path)),
          )] = await e
              .length();
        }
      }
    }
    return _json({
      'dateien': dateien,
      'datenbank': await File(p.join(zwischen.path, 'library.sqlite')).exists(),
    });
  }

  Future<Response> abschliessen(Request anfrage) async {
    final id = kontoVon(anfrage).id;
    final zwischen = _zwischen(id);
    final datenbank = File(p.join(zwischen.path, 'library.sqlite'));
    if (!await datenbank.exists()) {
      return _json({'fehler': 'Die Datenbank fehlt noch.'}, status: 409);
    }
    // Eine Bibliothek von Photo Vault, lesbar und ganz?
    try {
      final db = sqlite3.open(datenbank.path, mode: OpenMode.readOnly);
      try {
        final ok = db.select('PRAGMA quick_check').first.columnAt(0);
        if (ok != 'ok') throw StateError('quick_check: $ok');
        db.select('SELECT count(*) FROM assets');
      } finally {
        db.close();
      }
    } on Object catch (e) {
      return _json({'fehler': 'Die Datenbank taugt nicht: $e'}, status: 400);
    }
    if (await _aufnahmen(id) > 0) {
      return _json({
        'fehler': 'Die Bibliothek ist nicht mehr leer.',
      }, status: 409);
    }
    await bibliotheken.schliesse(id);
    final jetzt = Directory(p.join(bibliotheken.wurzel.path, id));
    if (await jetzt.exists()) {
      final stempel = DateTime.now()
          .toUtc()
          .toIso8601String()
          .replaceAll(RegExp(r'[^0-9]'), '')
          .substring(0, 14);
      await jetzt.rename(
        p.join(bibliotheken.wurzel.path, '$id.vor-umzug-$stempel'),
      );
    }
    await zwischen.rename(jetzt.path);
    final b = await bibliotheken.fuer(id);
    return _json({
      'stand': await b.bibliothek.protokoll.stand(),
      'aufnahmen': await _aufnahmen(id),
    });
  }
}
