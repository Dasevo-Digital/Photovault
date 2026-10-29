import 'dart:convert';

import 'package:drift/drift.dart';

import '../db/database.dart';
import 'abgleichsplan.dart';

/// Eine Zeile im Abgleich: Tabelle, Schlüssel und ihr jetziger Inhalt –
/// `null`, wenn es sie nicht (mehr) gibt.
class Zeilenstand {
  const Zeilenstand(this.tabelle, this.schluessel, this.werte);

  final String tabelle;

  /// Die Werte des Primärschlüssels, in der Reihenfolge der Tabelle.
  final List<Object?> schluessel;

  /// Spalte → Wert; `null` heisst gelöscht.
  final Map<String, Object?>? werte;

  Map<String, Object?> alsJson() => {
    't': tabelle,
    's': [for (final w in schluessel) wertAlsJson(w)],
    'z': werte == null
        ? null
        : {for (final e in werte!.entries) e.key: wertAlsJson(e.value)},
  };

  static Zeilenstand ausJson(Map<String, Object?> j) {
    final z = j['z'] as Map?;
    return Zeilenstand(
      j['t']! as String,
      [for (final w in (j['s']! as List)) wertAusJson(w)],
      z == null
          ? null
          : {for (final e in z.entries) '${e.key}': wertAusJson(e.value)},
    );
  }
}

/// SQLite-Werte als JSON: Zahlen, Text und `null` wie sie sind, Bytes als
/// `{"b": base64}`.
Object? wertAlsJson(Object? w) => w is Uint8List ? {'b': base64.encode(w)} : w;

Object? wertAusJson(Object? w) =>
    w is Map ? Uint8List.fromList(base64.decode(w['b']! as String)) : w;

/// Wie eine Tabelle gebaut ist: ihre Spalten und ihr Primärschlüssel.
class _Bau {
  _Bau(this.spalten, this.schluessel);
  final List<String> spalten;
  final List<String> schluessel;
}

/// Schreibt mit, welche Zeilen sich ändern, und liest und schreibt Zeilen
/// für den Abgleich – auf dem Server wie in der App.
///
/// **Mitschreiben.** Je abgeglichener Tabelle drei Trigger tragen jede
/// eingefügte, geänderte und gelöschte Zeile mit fortlaufender Nummer in
/// `pv_aenderungen` ein – nur den Schlüssel, nicht den Inhalt; wer sie
/// abholt, liest den jetzigen Stand. Ob mitgeschrieben wird, sagt
/// `pv_schalter.mitschreiben`: Auf dem Server immer (-1), in der App nur,
/// solange ein Befehl vorweggenommen wird – dann steht dort seine Nummer
/// in der Warteschlange.
///
/// **Neu bei jedem Öffnen.** Eine Migration der App legt Tabellen neu an,
/// und mit einer Tabelle verschwinden ihre Trigger. [richteEin] baut sie
/// deshalb jedes Mal aus dem Schema, wie es gerade ist.
class Protokoll {
  Protokoll(this.db);

  final AppDatabase db;
  final _bau = <String, _Bau>{};

  /// Richtet Tabellen und Trigger ein. [mitschreiben]: -1 auf dem Server,
  /// 0 in der App.
  Future<void> richteEin({required int mitschreiben}) async {
    await db.customStatement(
      'CREATE TABLE IF NOT EXISTS pv_aenderungen ('
      'seq INTEGER PRIMARY KEY AUTOINCREMENT, '
      'tabelle TEXT NOT NULL, schluessel TEXT NOT NULL, '
      'ausgang INTEGER NOT NULL DEFAULT -1)',
    );
    await db.customStatement(
      'CREATE INDEX IF NOT EXISTS pv_aenderungen_zeile '
      'ON pv_aenderungen(tabelle, schluessel)',
    );
    await db.customStatement(
      'CREATE TABLE IF NOT EXISTS pv_schalter ('
      'id INTEGER PRIMARY KEY CHECK (id = 0), mitschreiben INTEGER NOT NULL, '
      'frei INTEGER NOT NULL DEFAULT 0)',
    );
    final spalten = {
      for (final c
          in await db.customSelect('PRAGMA table_info(pv_schalter)').get())
        c.read<String>('name'),
    };
    if (!spalten.contains('frei')) {
      await db.customStatement(
        'ALTER TABLE pv_schalter ADD COLUMN frei INTEGER NOT NULL DEFAULT 0',
      );
    }
    await db.customStatement(
      'INSERT INTO pv_schalter (id, mitschreiben, frei) VALUES (0, ?, 0) '
      'ON CONFLICT(id) DO UPDATE SET mitschreiben = excluded.mitschreiben, '
      'frei = 0',
      [mitschreiben],
    );
    for (final t
        in await db
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type = 'trigger' "
              "AND name LIKE 'pv_aenderung_%'",
            )
            .get()) {
      await db.customStatement('DROP TRIGGER "${t.read<String>('name')}"');
    }
    _bau.clear();
    for (final tabelle in await abgeglicheneTabellen()) {
      final b = await _bauVon(tabelle);
      String schluessel(String zeile) =>
          'json_array(${b.schluessel.map((s) => '$zeile."$s"').join(', ')})';
      const wenn = 'WHEN (SELECT mitschreiben FROM pv_schalter) <> 0';
      const ausgang = '(SELECT mitschreiben FROM pv_schalter)';
      String eintrag(String zeile) =>
          'INSERT INTO pv_aenderungen (tabelle, schluessel, ausgang) '
          "VALUES ('$tabelle', ${schluessel(zeile)}, $ausgang);";
      await db.customStatement(
        'CREATE TRIGGER "pv_aenderung_${tabelle}_i" AFTER INSERT ON "$tabelle" '
        '$wenn BEGIN ${eintrag('NEW')} END',
      );
      await db.customStatement(
        'CREATE TRIGGER "pv_aenderung_${tabelle}_u" AFTER UPDATE ON "$tabelle" '
        '$wenn BEGIN ${eintrag('OLD')} ${eintrag('NEW')} END',
      );
      await db.customStatement(
        'CREATE TRIGGER "pv_aenderung_${tabelle}_d" AFTER DELETE ON "$tabelle" '
        '$wenn BEGIN ${eintrag('OLD')} END',
      );
    }
  }

  /// Das Sicherheitsnetz einer Kopie: Ein Schreibzugriff auf eine
  /// abgeglichene Tabelle bricht ab (`pv_nur_ueber_server`), wenn er weder
  /// aus dem Abgleich kommt ([frei]) noch aus einem vorweggenommenen Befehl
  /// (`mitschreiben`). Sonst wiche die Kopie unbemerkt vom Server ab – und
  /// bliebe es, denn der Server schickt eine Zeile erst wieder, wenn sie
  /// sich bei ihm ändert.
  ///
  /// **Temporäre Trigger:** Sie gelten nur für diese Verbindung und sind
  /// beim nächsten Öffnen fort. Eine Migration beim Start der App läuft
  /// deshalb ungehindert, und eine Kopie, deren Abgleich nicht läuft, ist
  /// nicht gesperrt.
  Future<void> richteSchutzEin() async {
    const wenn =
        'WHEN (SELECT frei FROM pv_schalter) = 0 '
        'AND (SELECT mitschreiben FROM pv_schalter) = 0';
    const abbruch = "BEGIN SELECT RAISE(ABORT, 'pv_nur_ueber_server'); END";
    for (final tabelle in await abgeglicheneTabellen()) {
      final teilweise = Abgleichsplan.geteilteSpalten[tabelle];
      if (teilweise == null) {
        for (final (art, kurz) in [
          ('INSERT', 'i'),
          ('UPDATE', 'u'),
          ('DELETE', 'd'),
        ]) {
          await db.customStatement(
            'CREATE TEMP TRIGGER IF NOT EXISTS "pv_schutz_${tabelle}_$kurz" '
            'BEFORE $art ON main."$tabelle" $wenn $abbruch',
          );
        }
      } else {
        // In geteilten Tabellen schützt es nur die geteilten Spalten – die
        // übrigen stellt jeder Rechner für sich ein.
        final b = await _bauVon(tabelle);
        final geschuetzt = [
          for (final s in teilweise)
            if (!b.schluessel.contains(s)) '"$s"',
        ];
        if (geschuetzt.isEmpty) continue;
        await db.customStatement(
          'CREATE TEMP TRIGGER IF NOT EXISTS "pv_schutz_${tabelle}_u" '
          'BEFORE UPDATE OF ${geschuetzt.join(', ')} ON main."$tabelle" '
          '$wenn $abbruch',
        );
      }
    }
  }

  /// Führt [arbeit] mit offenem Sicherheitsnetz aus – für den Abgleich
  /// selbst.
  Future<T> frei<T>(Future<T> Function() arbeit) async {
    await db.customStatement('UPDATE pv_schalter SET frei = 1');
    try {
      return await arbeit();
    } finally {
      await db.customStatement('UPDATE pv_schalter SET frei = 0');
    }
  }

  /// Die Tabellen, die abgeglichen werden (siehe [Abgleichsplan]).
  Future<List<String>> abgeglicheneTabellen() async => [
    for (final z
        in await db
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name",
            )
            .get())
      if (Abgleichsplan.abgeglichen(z.read<String>('name')))
        z.read<String>('name'),
  ];

  Future<_Bau> _bauVon(String tabelle) async {
    final schon = _bau[tabelle];
    if (schon != null) return schon;
    final info = await db.customSelect('PRAGMA table_info("$tabelle")').get();
    if (info.isEmpty) throw ArgumentError('Tabelle $tabelle gibt es nicht');
    final geteilt = Abgleichsplan.geteilteSpalten[tabelle];
    final spalten = [
      for (final c in info)
        if (geteilt == null || geteilt.contains(c.read<String>('name')))
          c.read<String>('name'),
    ];
    final schluessel = [
      for (final c
          in info.toList()
            ..sort((a, b) => a.read<int>('pk').compareTo(b.read<int>('pk'))))
        if (c.read<int>('pk') > 0) c.read<String>('name'),
    ];
    if (schluessel.isEmpty) {
      throw StateError('Tabelle $tabelle hat keinen Primärschlüssel');
    }
    return _bau[tabelle] = _Bau(spalten, schluessel);
  }

  /// Streicht Einträge, die ein späterer für dieselbe Zeile überholt hat.
  /// Wer ab irgendeiner Nummer abholt, bekommt danach dieselben Zeilen –
  /// nur jede einmal. Gibt zurück, wie viele gestrichen wurden.
  Future<int> verdichte() => db.customUpdate(
    'DELETE FROM pv_aenderungen WHERE seq < ('
    'SELECT max(p.seq) FROM pv_aenderungen p '
    'WHERE p.tabelle = pv_aenderungen.tabelle '
    'AND p.schluessel = pv_aenderungen.schluessel)',
    updateKind: UpdateKind.delete,
  );

  /// Die höchste Nummer im Protokoll – der Stand, bis zu dem es reicht.
  Future<int> stand() async =>
      (await db
              .customSelect(
                'SELECT coalesce(max(seq), 0) AS s FROM pv_aenderungen',
              )
              .getSingle())
          .read<int>('s');

  /// Welche Zeilen sich nach [nach] geändert haben, höchstens [anzahl]
  /// Einträge des Protokolls, mit ihrem jetzigen Inhalt. [bis] ist die
  /// letzte gelesene Nummer, `nach` der nächsten Abfrage.
  Future<({int bis, List<Zeilenstand> zeilen, bool mehr})> seit(
    int nach, {
    int anzahl = 500,
  }) async {
    final eintraege = await db
        .customSelect(
          'SELECT seq, tabelle, schluessel FROM pv_aenderungen '
          'WHERE seq > ? ORDER BY seq LIMIT ?',
          variables: [Variable<int>(nach), Variable<int>(anzahl + 1)],
        )
        .get();
    final mehr = eintraege.length > anzahl;
    final genommen = mehr ? eintraege.sublist(0, anzahl) : eintraege;
    final bis = genommen.isEmpty ? nach : genommen.last.read<int>('seq');
    // Jede Zeile einmal, an der Stelle ihrer letzten Änderung.
    final gesehen = <String>{};
    final schluessel = <(String, String)>[];
    for (final e in genommen.reversed) {
      final k =
          '${e.read<String>('tabelle')}\u0000${e.read<String>('schluessel')}';
      if (gesehen.add(k)) {
        schluessel.add((
          e.read<String>('tabelle'),
          e.read<String>('schluessel'),
        ));
      }
    }
    final zeilen = <Zeilenstand>[];
    for (final (tabelle, s) in schluessel.reversed) {
      if (!Abgleichsplan.abgeglichen(tabelle)) continue;
      zeilen.add(await lies(tabelle, (jsonDecode(s) as List).cast<Object?>()));
    }
    return (bis: bis, zeilen: zeilen, mehr: mehr);
  }

  /// Der jetzige Stand einer Zeile.
  Future<Zeilenstand> lies(String tabelle, List<Object?> schluessel) async {
    final b = await _bauVon(tabelle);
    final z = await db
        .customSelect(
          'SELECT ${b.spalten.map((s) => '"$s"').join(', ')} FROM "$tabelle" '
          'WHERE ${b.schluessel.map((s) => '"$s" = ?').join(' AND ')}',
          variables: [for (final w in schluessel) _variable(w)],
        )
        .getSingleOrNull();
    return Zeilenstand(
      tabelle,
      schluessel,
      z == null ? null : {for (final s in b.spalten) s: z.data[s]},
    );
  }

  /// Liest Schlüssel gebündelt; auch fehlende Zeilen behalten ihre Position.
  Future<List<Zeilenstand>> liesViele(
    List<(String, List<Object?>)> ziele,
  ) async {
    final gruppen = <String, List<List<Object?>>>{};
    for (final (t, k) in ziele) {
      gruppen.putIfAbsent(t, () => []).add(k);
    }
    final ergebnis = <String, Map<String, Object?>>{};
    for (final e in gruppen.entries) {
      final b = await _bauVon(e.key);
      for (var i = 0; i < e.value.length; i += 100) {
        final keys = e.value.skip(i).take(100).toList();
        if (keys.any((k) => k.length != b.schluessel.length)) {
          throw const FormatException('pv_sync_basis');
        }
        final where = b.schluessel.map((s) => '"$s" = ?').join(' AND ');
        final rows = await db
            .customSelect(
              'SELECT ${b.spalten.map((s) => '"$s"').join(', ')} FROM "${e.key}" WHERE '
              '${List.filled(keys.length, '($where)').join(' OR ')}',
              variables: [
                for (final k in keys)
                  for (final w in k) _variable(w),
              ],
            )
            .get();
        for (final row in rows) {
          final key = [for (final k in b.schluessel) row.data[k]];
          ergebnis['${e.key}\u0000${jsonEncode(key)}'] = {
            for (final s in b.spalten) s: row.data[s],
          };
        }
      }
    }
    return [
      for (final (t, k) in ziele)
        Zeilenstand(t, k, ergebnis['$t\u0000${jsonEncode(k)}']),
    ];
  }

  /// Wie viele Werte der Primärschlüssel von [tabelle] hat. Der Server
  /// prüft damit fremde Abgleichsanfragen, bevor er Werte an SQLite bindet.
  Future<int> schluessellaenge(String tabelle) async =>
      (await _bauVon(tabelle)).schluessel.length;

  /// Schreibt [zeilen] in die Datenbank – ohne mitzuschreiben – und
  /// meldet drift, welche Tabellen sich geändert haben. Gibt die Tabellen
  /// zurück.
  Future<Set<String>> wendeAn(List<Zeilenstand> zeilen) async {
    final tabellen = <String>{};
    for (final z in zeilen) {
      if (!Abgleichsplan.abgeglichen(z.tabelle)) continue;
      final b = await _bauVon(z.tabelle);
      tabellen.add(z.tabelle);
      final wo = b.schluessel.map((s) => '"$s" = ?').join(' AND ');
      final werte = z.werte;
      if (werte == null) {
        await db.customStatement(
          'DELETE FROM "${z.tabelle}" WHERE $wo',
          z.schluessel,
        );
        continue;
      }
      final spalten = [
        for (final s in b.spalten)
          if (werte.containsKey(s)) s,
      ];
      final teilweise = Abgleichsplan.geteilteSpalten.containsKey(z.tabelle);
      final aendern = [
        for (final s in spalten)
          if (!b.schluessel.contains(s)) '"$s" = excluded."$s"',
      ];
      // Ganze Zeilen ersetzen; bei geteilten Tabellen nur die geteilten
      // Spalten – die übrigen gehören diesem Rechner.
      await db.customStatement(
        '${teilweise ? 'INSERT' : 'INSERT OR REPLACE'} INTO "${z.tabelle}" '
        '(${spalten.map((s) => '"$s"').join(', ')}) '
        'VALUES (${List.filled(spalten.length, '?').join(', ')})'
        '${teilweise && aendern.isNotEmpty ? ' ON CONFLICT(${b.schluessel.map((s) => '"$s"').join(', ')}) DO UPDATE SET ${aendern.join(', ')}' : ''}',
        [for (final s in spalten) werte[s]],
      );
    }
    // Diese Zeilen gehen an den Abfragen vorbei, die den Stand der
    // Einbettungen sonst selbst hochzählen. Ohne diese Zeile fand die
    // Inhaltssuche eines verbundenen Rechners die Fotos nicht, deren
    // Einbettung der Server inzwischen geliefert hatte – solange der
    // Vorrat warm blieb, und jede Suche hielt ihn warm.
    if (tabellen.any(_beruehrtEinbettungen.contains)) {
      db.einbettungenVeraendert();
    }
    return tabellen;
  }

  /// Tabellen, deren Zeilen das Ergebnis von `allEmbeddings` verschieben:
  /// die Einbettungen selbst und die Aufnahmen (Papierkorb, Sperre).
  static const _beruehrtEinbettungen = {
    'assets',
    'image_embeddings',
    'videoeinbettungen',
  };

  static Variable _variable(Object? w) => switch (w) {
    null => const Variable(null),
    final int i => Variable<int>(i),
    final double d => Variable<double>(d),
    final String s => Variable<String>(s),
    final Uint8List b => Variable<Uint8List>(b),
    _ => throw ArgumentError('Wert $w lässt sich nicht abfragen'),
  };
}
