import 'dart:convert';

import 'package:kern/db/database.dart';
import 'package:kern/db/rasterzeile.dart';
import 'package:kern/services/laendernamen.dart';
import 'package:kern/services/rueckblickseite.dart';
import 'package:shelf/shelf.dart';

import 'anmeldung_api.dart';
import 'bibliotheken.dart';
import 'zeilen_json.dart';

Response _json(Object? daten, {int status = 200}) => Response(
  status,
  body: jsonEncode(daten),
  headers: {'content-type': 'application/json; charset=utf-8'},
);

/// „Rückblick“ und „Kalender“ für den Browser – dieselben Rechnungen wie am
/// Rechner und auf dem Telefon (rueckblickseite.dart im Kern, Issue #185).
class Rueckblickapi {
  Rueckblickapi(this.bibliotheken);

  final Bibliotheken bibliotheken;

  Future<AppDatabase> _db(Request anfrage) async =>
      (await bibliotheken.fuer(kontoVon(anfrage).id)).bibliothek.db;

  /// Der Tag des Browsers (`?heute=JJJJ-MM-TT`), nicht der des Servers:
  /// Um Mitternacht liegt der Server womöglich in einer anderen Zeitzone.
  static DateTime _heute(Request anfrage) {
    final h = DateTime.tryParse(anfrage.url.queryParameters['heute'] ?? '');
    final jetzt = DateTime.now();
    return h == null
        ? DateTime(jetzt.year, jetzt.month, jetzt.day)
        : DateTime(h.year, h.month, h.day);
  }

  static List<Map<String, Object?>> _zeilen(Iterable<AssetData> a) => [
    for (final x in a) zeileAlsJson(Rasterzeile.aus(x)),
  ];

  static String _tag(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// `GET /api/v1/rueckblick?heute=` → Familientage, Erinnerungen der
  /// letzten zwei Wochen, gemerkte Erinnerungen, die schönsten Reisen und
  /// das Jahr für den Jahresrückblick.
  Future<Response> rueckblick(Request anfrage) async {
    final db = await _db(anfrage);
    final heute = _heute(anfrage);
    final tage = await familientageMitFotos(db, heute: heute);
    final e = await erinnerungsstand(db, heute: heute);
    return _json({
      'jahr': jahresrueckblickJahr(heute),
      'familientage': [
        for (final f in tage)
          {
            'art': f.tag.art.name,
            'jahre': f.tag.jahre,
            'inTagen': f.tag.inTagen,
            'verstorben': f.tag.verstorben,
            'rund': f.tag.rund,
            'namen': f.namen,
            'aufnahmen': _zeilen(f.fotos),
          },
      ],
      'gemerkt': [
        for (final g in e.gemerkt)
          if (g.dinge.isNotEmpty)
            {'id': g.e.id, 'titel': g.e.titel, 'aufnahmen': _zeilen(g.dinge)},
      ],
      'letzte': [
        for (final l in e.letzte)
          {
            'kennung': erinnerungsKennung(l.tag, l.jahreHer),
            'tag': _tag(l.tag),
            'jahreHer': l.jahreHer,
            'aufnahmen': _zeilen(l.dinge),
          },
      ],
      'reisen': [
        for (final r in e.reisen)
          {
            'id': r.reise.id,
            'name': r.reise.name,
            'von': r.reise.von.toIso8601String(),
            'bis': r.reise.bis.toIso8601String(),
            'lieblinge': r.lieblinge,
          },
      ],
    });
  }

  /// `GET /api/v1/jahresrueckblick/<jahr>?sprache=` → Zahlen, Monate,
  /// Auswahl, Personen und Reisen eines Jahres.
  Future<Response> jahresrueckblick(Request anfrage, String jahr) async {
    final j = int.tryParse(jahr);
    if (j == null || j < 1800 || j > 2200) {
      return _json({'fehler': 'jahr'}, status: 400);
    }
    final sprache = anfrage.url.queryParameters['sprache'] == 'en'
        ? 'en'
        : 'de';
    final i = await jahresinhalt(await _db(anfrage), j);
    final z = i.zahlen;
    return _json({
      'jahr': j,
      'fotos': z.fotos,
      'videos': z.videos,
      'tage': z.tage,
      'laender': [for (final l in z.laender) landAnzeige(l, sprache)]..sort(),
      'orte': z.orte.length,
      'jeMonat': z.jeMonat,
      'staerksterMonat': z.staerksterMonat,
      'auswahl': _zeilen(i.auswahl),
      'personen': [
        for (final p in i.personen)
          {
            'id': p.person.id,
            'name': p.person.name,
            'bild': p.person.coverFaceCropPath,
            'anzahl': p.anzahl,
          },
      ],
      'reisen': [
        for (final r in i.reisen)
          {
            'id': r.id,
            'name': r.name,
            'von': r.von.toIso8601String(),
            'bis': r.bis.toIso8601String(),
          },
      ],
    });
  }

  Map<String, Object?> _feld(Kalenderfeld f) => {
    'nummer': f.nummer,
    'anzahl': f.anzahl,
    if (f.titelbild case final t?)
      'titelbild': zeileAlsJson(Rasterzeile.aus(t)),
  };

  /// `GET /api/v1/kalender` → die Jahre mit Aufnahmen, neueste zuerst.
  Future<Response> jahre(Request anfrage) async => _json({
    'jahre': [
      for (final f in await kalenderjahre(await _db(anfrage))) _feld(f),
    ],
  });

  /// `GET /api/v1/kalender/<jahr>` → die Monate mit Aufnahmen.
  Future<Response> monate(Request anfrage, String jahr) async {
    final j = int.tryParse(jahr);
    if (j == null) return _json({'fehler': 'jahr'}, status: 400);
    return _json({
      'jahr': j,
      'monate': [
        for (final f in await kalendermonate(await _db(anfrage), j)) _feld(f),
      ],
    });
  }

  /// `GET /api/v1/kalender/<jahr>/<monat>` → die Aufnahmen des Monats,
  /// neueste zuerst.
  Future<Response> monat(Request anfrage, String jahr, String monat) async {
    final j = int.tryParse(jahr), m = int.tryParse(monat);
    if (j == null || m == null || m < 1 || m > 12) {
      return _json({'fehler': 'monat'}, status: 400);
    }
    return _json({
      'jahr': j,
      'monat': m,
      'aufnahmen': _zeilen(await (await _db(anfrage)).aufnahmenImMonat(j, m)),
    });
  }
}
