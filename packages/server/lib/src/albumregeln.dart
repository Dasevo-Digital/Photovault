import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart' show Variable;
import 'package:kern/db/database.dart';
import 'package:kern/db/rasterzeile.dart';
import 'package:kern/protokoll.dart';

import 'bibliotheken.dart';
import 'konten/kontodienst.dart';
import 'konten/serverdatenbank.dart';

/// Aufnahmen, auf denen [personen] zu sehen sind – als SQL-Bedingung über
/// `assets`, mit ihren Werten. [alle]: alle zusammen auf demselben Foto,
/// sonst mindestens eine davon. Beiseitegelegte Gesichter zählen nicht.
({String sql, List<Variable<Object>> werte}) personenBedingung(
  List<String> personen, {
  required bool alle,
}) {
  final platz = List.filled(personen.length, '?').join(', ');
  final werte = [for (final p in personen) Variable<String>(p)];
  if (!alle) {
    return (
      sql:
          'assets.id IN (SELECT asset_id FROM faces WHERE is_ignored = 0 '
          'AND person_id IN ($platz))',
      werte: werte,
    );
  }
  return (
    sql:
        '(SELECT count(DISTINCT person_id) FROM faces '
        'WHERE asset_id = assets.id AND is_ignored = 0 '
        'AND person_id IN ($platz)) = ?',
    werte: [...werte, Variable<int>(personen.length)],
  );
}

/// Was eine eingeschränkte Partnerfreigabe zeigt (#299): ab [ab] und mit
/// mindestens einer der [personen] – als SQL, das mit ` AND` beginnt, oder
/// leer, wenn nichts eingeschränkt ist.
({String sql, List<Variable<Object>> werte}) freigabeBedingung({
  DateTime? ab,
  List<String>? personen,
}) {
  final p = personen == null || personen.isEmpty
      ? null
      : personenBedingung(personen, alle: false);
  return (
    sql:
        '${ab == null ? '' : ' AND file_created_at >= ?'}'
        '${p == null ? '' : ' AND ${p.sql}'}',
    werte: [if (ab != null) Variable<DateTime>(ab), ...?p?.werte],
  );
}

/// Ein Album, das sich selbst füllt (#298): mit den Fotos von [personen],
/// wahlweise erst ab [ab].
class Albumregel {
  const Albumregel({
    required this.besitzer,
    required this.album,
    required this.personen,
    required this.alle,
    required this.ab,
    required this.angelegt,
  });

  final String besitzer;
  final String album;
  final List<String> personen;

  /// Alle [personen] zusammen auf einem Foto – sonst genügt eine.
  final bool alle;

  /// Nur, was an oder nach diesem Tag aufgenommen ist.
  final DateTime? ab;
  final DateTime angelegt;
}

/// Welche Alben sich selbst füllen, in server.sqlite – wie die Teilungen
/// neben den Konten (siehe [Serverdatenbank]).
///
/// **Die Regel legt nur hinein, sie nimmt nie heraus.** Erkennt die
/// Gesichtserkennung eine Person später nicht mehr, bleibt das Foto, wo
/// es ist: Ein Album, aus dem Fotos von allein verschwinden, wäre
/// unheimlicher als eines mit einem Foto zu viel. Und was der Besitzer
/// herausnimmt, bleibt draussen – dafür steht in
/// `albumregel_aufgenommen`, was die Regel schon einmal hineingelegt hat.
class Albumregeln {
  Albumregeln(this._sdb, {DateTime Function()? uhr})
    : _uhr = uhr ?? DateTime.now;

  final Serverdatenbank _sdb;
  final DateTime Function() _uhr;

  /// So viele Personen nimmt eine Regel höchstens.
  static const hoechstensPersonen = 20;

  Albumregel _aus(Map<String, Object?> z) => Albumregel(
    besitzer: z['besitzer']! as String,
    album: z['album']! as String,
    personen: [
      for (final p in jsonDecode(z['personen']! as String) as List) '$p',
    ],
    alle: z['alle'] == 1,
    ab: switch (z['ab']) {
      final int ms => DateTime.fromMillisecondsSinceEpoch(ms),
      _ => null,
    },
    angelegt: DateTime.fromMillisecondsSinceEpoch(z['angelegt']! as int),
  );

  Albumregel? regel(String besitzer, String album) {
    final z = _sdb.db.select(
      'SELECT * FROM albumregeln WHERE besitzer = ? AND album = ?',
      [besitzer, album],
    );
    return z.isEmpty ? null : _aus(z.first);
  }

  List<Albumregel> vonBesitzer(String besitzer) => [
    for (final z in _sdb.db.select(
      'SELECT * FROM albumregeln WHERE besitzer = ? ORDER BY angelegt',
      [besitzer],
    ))
      _aus(z),
  ];

  List<Albumregel> alle() => [
    for (final z in _sdb.db.select(
      'SELECT * FROM albumregeln ORDER BY besitzer, angelegt',
    ))
      _aus(z),
  ];

  /// Legt die Regel für [album] an oder ersetzt sie. Was eine frühere
  /// Regel schon hineingelegt hat, bleibt vermerkt.
  Albumregel setze({
    required String besitzer,
    required String album,
    required List<String> personen,
    required bool alle,
    DateTime? ab,
  }) {
    final rein = personen.toSet().toList();
    if (rein.isEmpty || rein.length > hoechstensPersonen) {
      throw ArgumentError('1 bis $hoechstensPersonen Personen');
    }
    _sdb.db.execute(
      'INSERT INTO albumregeln (besitzer, album, personen, alle, ab, '
      'angelegt) VALUES (?, ?, ?, ?, ?, ?) '
      'ON CONFLICT (besitzer, album) DO UPDATE SET '
      'personen = excluded.personen, alle = excluded.alle, ab = excluded.ab',
      [
        besitzer,
        album,
        jsonEncode(rein),
        alle ? 1 : 0,
        ab?.millisecondsSinceEpoch,
        _uhr().millisecondsSinceEpoch,
      ],
    );
    return regel(besitzer, album)!;
  }

  /// Das Album füllt sich nicht mehr selbst; was darin liegt, bleibt.
  bool entferne(String besitzer, String album) {
    _sdb.db.execute(
      'DELETE FROM albumregeln WHERE besitzer = ? AND album = ?',
      [besitzer, album],
    );
    final weg = _sdb.db.updatedRows > 0;
    _sdb.db.execute(
      'DELETE FROM albumregel_aufgenommen WHERE besitzer = ? AND album = ?',
      [besitzer, album],
    );
    return weg;
  }

  /// Was die Regel von [album] schon einmal hineingelegt hat.
  Set<String> aufgenommen(String besitzer, String album) => {
    for (final z in _sdb.db.select(
      'SELECT aufnahme FROM albumregel_aufgenommen '
      'WHERE besitzer = ? AND album = ?',
      [besitzer, album],
    ))
      z['aufnahme']! as String,
  };

  void vermerke(String besitzer, String album, Iterable<String> aufnahmen) {
    final s = _sdb.db.prepare(
      'INSERT OR IGNORE INTO albumregel_aufgenommen (besitzer, album, '
      'aufnahme) VALUES (?, ?, ?)',
    );
    try {
      _sdb.db.execute('BEGIN');
      for (final a in aufnahmen) {
        s.execute([besitzer, album, a]);
      }
      _sdb.db.execute('COMMIT');
    } catch (_) {
      _sdb.db.execute('ROLLBACK');
      rethrow;
    } finally {
      s.close();
    }
  }
}

/// Die Personen einer Regel, die es in [db] noch gibt – nach einem
/// Zusammenführen fehlt die eine oder andere.
Future<Map<String, String>> vorhandenePersonen(
  AppDatabase db,
  List<String> personen,
) async {
  if (personen.isEmpty) return const {};
  final zeilen = await db
      .customSelect(
        'SELECT id, name FROM people WHERE id IN '
        '(${List.filled(personen.length, '?').join(', ')})',
        variables: [for (final p in personen) Variable<String>(p)],
        readsFrom: {db.people},
      )
      .get();
  return {for (final z in zeilen) z.read<String>('id'): z.read<String>('name')};
}

/// Legt in das Album der Regel [r], was dazugehört und noch nie darin
/// lag. Gibt zurück, wie viele Aufnahmen dazukamen.
///
/// Fehlt bei „alle zusammen“ eine der Personen (zusammengeführt oder
/// gelöscht), legt die Regel nichts mehr hinein: Mit den übrigen allein
/// passten mehr Fotos, als der Besitzer gewählt hat – und das Album ist
/// womöglich mit anderen geteilt.
Future<int> fuelleAlbum(
  Kontobereich bereich,
  Albumregeln regeln,
  Albumregel r,
) async {
  final db = bereich.bibliothek.db;
  if (!(await db.alleAlben()).any((a) => a.id == r.album)) {
    regeln.entferne(r.besitzer, r.album);
    return 0;
  }
  final da = await vorhandenePersonen(db, r.personen);
  final personen = [
    for (final p in r.personen)
      if (da.containsKey(p)) p,
  ];
  if (personen.isEmpty || (r.alle && personen.length < r.personen.length)) {
    return 0;
  }
  final b = personenBedingung(personen, alle: r.alle);
  final ab = r.ab;
  final treffer = [
    for (final z
        in await db
            .customSelect(
              'SELECT id FROM assets WHERE $rasterSichtbar AND ${b.sql}'
              '${ab == null ? '' : ' AND file_created_at >= ?'}',
              variables: [...b.werte, if (ab != null) Variable<DateTime>(ab)],
              readsFrom: {db.assets, db.faces},
            )
            .get())
      z.read<String>('id'),
  ];
  final schon = regeln.aufgenommen(r.besitzer, r.album);
  final neu = [
    for (final id in treffer)
      if (!schon.contains(id)) id,
  ];
  if (neu.isEmpty) return 0;
  final drin = {
    for (final z in await (db.select(
      db.albumAssets,
    )..where((t) => t.albumId.equals(r.album))).get())
      z.assetId,
  };
  final dazu = [
    for (final id in neu)
      if (!drin.contains(id)) id,
  ];
  // Als Befehl wie jede Änderung am Album: So erfahren die Geräte des
  // Besitzers davon.
  for (var i = 0; i < dazu.length; i += 500) {
    await db.fuehreAus(
      AlbumFuellen(r.album, dazu.sublist(i, min(i + 500, dazu.length))),
    );
  }
  regeln.vermerke(r.besitzer, r.album, neu);
  return dazu.length;
}

/// Füllt die Alben aller Konten in einem festen Takt – neue Fotos und neu
/// erkannte Gesichter kommen über den Abgleich und die Auswertung, ohne
/// dass jemand Bescheid sagt.
class Albumregelablauf {
  Albumregelablauf({
    required this.konten,
    required this.bibliotheken,
    this.takt = const Duration(minutes: 10),
  });

  final Kontodienst konten;
  final Bibliotheken bibliotheken;
  final Duration takt;
  Timer? _wecker;
  Future<void>? _lauf;

  /// Ein Durchgang über alle Regeln; läuft schon einer, derselbe.
  Future<void> pruefe() => _lauf ??= _pruefe().whenComplete(() => _lauf = null);

  Future<void> _pruefe() async {
    final regeln = konten.albumregeln;
    final List<Albumregel> alle;
    try {
      alle = regeln.alle();
    } catch (e) {
      // Im Takt liefe ein Fehler in keine Anfrage, sondern beendete den
      // ganzen Server.
      protokoll('Albumregeln nicht gelesen: $e');
      return;
    }
    for (final r in alle) {
      final name = konten.konto(r.besitzer)?.name ?? r.besitzer;
      try {
        final n = await fuelleAlbum(
          await bibliotheken.fuer(r.besitzer),
          regeln,
          r,
        );
        if (n > 0) {
          protokoll(
            'Album ${r.album} von $name: '
            '${n == 1 ? 'eine Aufnahme' : '$n Aufnahmen'} selbst dazugelegt',
          );
        }
      } catch (e) {
        protokoll('Album ${r.album} von $name nicht gefüllt: $e');
      }
    }
  }

  void starte({Duration verzug = const Duration(minutes: 3)}) {
    _wecker = Timer(verzug, () {
      unawaited(pruefe());
      _wecker = Timer.periodic(takt, (_) => unawaited(pruefe()));
    });
  }

  void beende() => _wecker?.cancel();
}
