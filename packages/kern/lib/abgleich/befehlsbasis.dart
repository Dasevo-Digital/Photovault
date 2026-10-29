import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../db/database.dart';
import 'protokoll.dart';
import 'abgleichsplan.dart';

/// Ein Vergleich betrifft nur die durch den Befehl geänderten Spalten.
/// Änderungen an anderen Angaben oder Analyseergebnissen bleiben unabhängig.
/// Übertragen werden Hashes; alte Beschreibungen oder Ortsangaben werden
/// nicht zusätzlich in einer unverschlüsselten Warteschlange gespeichert.
class Befehlsbasis {
  const Befehlsbasis({
    required this.tabelle,
    required this.schluessel,
    required this.spalten,
    required this.vorher,
    required this.nachher,
    this.gewollt,
    this.fotos = const [],
  });
  final String tabelle;
  final List<Object?> schluessel;
  final List<String> spalten;
  final String vorher, nachher;
  final Map<String, Object?>? gewollt;
  final List<String> fotos;

  Map<String, Object?> alsJson() => {
    't': tabelle,
    's': schluessel,
    'spalten': spalten,
    'vorher': vorher,
    'nachher': nachher,
  };
  Map<String, Object?> vorschauJson() => {
    ...alsJson(),
    'gewollt': gewollt,
    'fotos': fotos,
  };

  static Befehlsbasis ausJson(Map<String, Object?> j) {
    final s = (j['s'] as List).cast<Object?>();
    final spalten = (j['spalten'] as List).cast<String>();
    final vorher = j['vorher'] as String, nachher = j['nachher'] as String;
    if (s.isEmpty ||
        s.length > 16 ||
        spalten.isEmpty ||
        spalten.length > 256 ||
        s.any((s) => s is! String && s is! num && s is! bool && s != null) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(vorher) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(nachher)) {
      throw const FormatException('pv_sync_basis');
    }
    return Befehlsbasis(
      tabelle: j['t'] as String,
      schluessel: s,
      spalten: spalten,
      vorher: vorher,
      nachher: nachher,
      gewollt: (j['gewollt'] as Map?)?.cast<String, Object?>(),
      fotos: (j['fotos'] as List? ?? const []).cast<String>(),
    );
  }

  static String hash(Map<String, Object?>? row, List<String> spalten) => sha256
      .convert(
        utf8.encode(
          jsonEncode(
            row == null
                ? null
                : {
                    for (final s in spalten.toList()..sort())
                      s: wertAlsJson(row[s]),
                  },
          ),
        ),
      )
      .toString();

  /// Eine zurückgerollte Datenbanktransaktion ermittelt die tatsächlich
  /// betroffenen Zeilen. Befehle führen ausschließlich Datenbankarbeit aus;
  /// Beobachter werden für die Probe nicht aufgerufen.
  static Future<List<Befehlsbasis>> ermittle(
    Protokoll p,
    Befehl<Object?> befehl,
  ) async {
    List<Zeilenstand> neu;
    try {
      await p.db.transaction<void>(() async {
        await p.db.customStatement('UPDATE pv_schalter SET mitschreiben = -2');
        await befehl.anwenden(p.db);
        final zeilen = <Zeilenstand>[];
        for (final r
            in await p.db
                .customSelect(
                  'SELECT DISTINCT tabelle, schluessel FROM pv_aenderungen WHERE ausgang = -2',
                )
                .get()) {
          zeilen.add(
            await p.lies(
              r.read<String>('tabelle'),
              (jsonDecode(r.read<String>('schluessel')) as List)
                  .cast<Object?>(),
            ),
          );
        }
        // INSERT OR IGNORE und ein Löschen einer bereits fehlenden
        // Zuordnung erzeugen keinen Trigger. Auch diese ausdrückliche
        // Absicht muss einen später abweichenden Serverstand erkennen.
        final w = befehl.werte;
        final ziele = <(String, List<Object?>)>[];
        if (befehl is AlbumFuellen || befehl is AusAlbumNehmen) {
          for (final id in w['ids'] as List) {
            ziele.add(('album_assets', [w['albumId'], id]));
          }
        }
        if (befehl is SchlagwortAnheftenPerKennung ||
            befehl is SchlagwortLoesen) {
          ziele.add(('asset_tags', [w['id'], w['schlagwortId']]));
        }
        if (befehl is SchlagwortAnheften || befehl is SchlagwortAbnehmen) {
          final tag =
              await (p.db.select(p.db.tags)
                    ..where((t) => t.name.equals(w['name'] as String)))
                  .getSingleOrNull();
          if (tag != null) {
            for (final id in w['ids'] as List) {
              ziele.add(('asset_tags', [id, tag.id]));
            }
          }
        }
        for (final (t, key) in ziele) {
          if (!zeilen.any(
            (z) =>
                z.tabelle == t && jsonEncode(z.schluessel) == jsonEncode(key),
          )) {
            zeilen.add(await p.lies(t, key));
          }
        }
        throw _ProbeFertig(zeilen);
      }, requireNew: true);
      throw StateError('pv_sync_probe');
    } on _ProbeFertig catch (e) {
      neu = e.zeilen;
    }
    if (neu.length > 50000) throw const FormatException('pv_sync_auswahl');
    final result = <Befehlsbasis>[];
    final weitereFotos = <String>{};
    for (final n in neu) {
      final alt = await p.lies(n.tabelle, n.schluessel);
      final zeile = n.werte ?? alt.werte;
      if (zeile?['face_id'] case final String id) {
        final gesicht = await p.lies('faces', [id]);
        if (gesicht.werte?['asset_id'] case final String foto) {
          weitereFotos.add(foto);
        }
      }
      // Rückmeldungen werden angehängt. Ihre automatische lokale Nummer
      // bezeichnet nicht eine inzwischen am Server angelegte Rückmeldung.
      if (n.tabelle == 'face_match_feedback' &&
          alt.werte == null &&
          n.werte != null) {
        continue;
      }
      final alle = <String>{
        ...alt.werte?.keys ?? [],
        ...n.werte?.keys ?? [],
        if (n.tabelle == 'asset_tags') ...['asset_id', 'tag_id', 'quelle'],
        if (n.tabelle == 'album_assets') ...['album_id', 'asset_id'],
      };
      final spalten = alt.werte == null || n.werte == null
          ? alle.toList()
          : alle
                .where(
                  (s) =>
                      jsonEncode(wertAlsJson(alt.werte?[s])) !=
                      jsonEncode(wertAlsJson(n.werte?[s])),
                )
                .toList();
      // Auch ein bewusst erneut gesetzter gleicher Wert ist eine Absicht.
      if (n.tabelle == 'assets') {
        spalten.addAll(switch (befehl.art) {
          'favoritSetzen' => ['is_favorite'],
          'bewertungSetzen' => ['rating'],
          'farbmarkeSetzen' => ['color_label'],
          'beschreibungSetzen' => ['description'],
          _ => <String>[],
        });
      }
      if (spalten.isEmpty) spalten.addAll(alle);
      if (n.tabelle == 'assets') spalten.addAll(['is_locked', 'is_trashed']);
      if (spalten.isEmpty) continue;
      final felder = spalten.toSet().toList()..sort();
      final row = n.werte ?? alt.werte;
      final foto = row != null
          ? row[n.tabelle == 'assets' ? 'id' : 'asset_id']
          : n.tabelle == 'asset_tags'
          ? n.schluessel.first
          : n.tabelle == 'album_assets'
          ? n.schluessel.last
          : null;
      result.add(
        Befehlsbasis(
          tabelle: n.tabelle,
          schluessel: n.schluessel,
          spalten: felder,
          // Eine unverändert nachgereichte ältere Spur darf am Server
          // noch fehlen. Ein abweichender vorhandener Stand bleibt geschützt.
          vorher:
              befehl is SpurAnlegen &&
                  const {'spuren', 'spurpunkte'}.contains(n.tabelle) &&
                  hash(alt.werte, felder) == hash(n.werte, felder)
              ? hash(null, felder)
              : hash(alt.werte, felder),
          nachher: hash(n.werte, felder),
          gewollt: n.werte == null
              ? null
              : {for (final s in felder) s: wertAlsJson(n.werte![s])},
          fotos: foto is String ? [foto] : const [],
        ),
      );
    }
    final vorhanden = result
        .where((b) => b.tabelle == 'assets')
        .map((b) => b.schluessel.single)
        .toSet();
    for (final id in {
      ...weitereFotos,
      ...result.expand((b) => b.fotos),
    }.difference(vorhanden)) {
      final row = await p.lies('assets', [id]);
      const felder = ['is_locked', 'is_trashed'];
      final h = hash(row.werte, felder);
      result.add(
        Befehlsbasis(
          tabelle: 'assets',
          schluessel: [id],
          spalten: felder,
          vorher: h,
          nachher: h,
          gewollt: row.werte == null
              ? null
              : {for (final s in felder) s: wertAlsJson(row.werte![s])},
          fotos: [id],
        ),
      );
    }
    return result;
  }

  /// Auf dem Server innerhalb derselben Transaktion wie das Anwenden.
  static Future<bool> passt(Protokoll p, List<Befehlsbasis> basis) async {
    if (basis.isEmpty) return true;
    final tabellen = (await p.abgeglicheneTabellen()).toSet();
    final schemaSpalten = <String, Set<String>>{};
    for (final b in basis) {
      if (!tabellen.contains(b.tabelle) ||
          b.schluessel.length != await p.schluessellaenge(b.tabelle)) {
        throw const FormatException('pv_sync_basis');
      }
      final row = await p.lies(b.tabelle, b.schluessel);
      // Auch bei gelöschten Zeilen gegen das Schema validieren.
      final spalten = schemaSpalten[b.tabelle] ??=
          Abgleichsplan.geteilteSpalten[b.tabelle] ??
          {
            for (final r
                in await p.db
                    .customSelect('PRAGMA table_info("${b.tabelle}")')
                    .get())
              r.read<String>('name'),
          };
      if (b.spalten.any((s) => !spalten.contains(s))) {
        throw const FormatException('pv_sync_basis');
      }
      final ist = hash(row.werte, b.spalten);
      if (ist != b.vorher && ist != b.nachher) return false;
    }
    return true;
  }
}

class _ProbeFertig implements Exception {
  const _ProbeFertig(this.zeilen);
  final List<Zeilenstand> zeilen;
}
