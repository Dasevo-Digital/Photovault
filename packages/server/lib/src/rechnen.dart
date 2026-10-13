import 'dart:convert';

import 'package:kern/auswertung/rechenhilfe.dart';
import 'package:kern/db/database.dart';
import 'package:shelf/shelf.dart';
import 'package:uuid/uuid.dart';

import 'anmeldung_api.dart';
import 'bibliotheken.dart';

Response _json(Object? daten, {int status = 200}) => Response(
  status,
  body: jsonEncode(daten),
  headers: {'content-type': 'application/json; charset=utf-8'},
);

/// Wer gerade an welcher Aufnahme rechnet – die Rechner, denen der Server
/// Aufträge gab, und der Server selbst (Issue #104).
///
/// **Mit Ablaufzeit:** Ein Rechner, der zugeklappt wird, meldet sich nicht
/// ab. Nach [dauer] ist seine Aufnahme wieder frei, und der nächste nimmt
/// sie.
///
/// **Was geliefert ist, bleibt geliefert:** Ein Durchgang des Servers hat
/// seine Liste beim Beginn geholt. Liefert ein Rechner in der Zwischenzeit,
/// nimmt der Server dieselbe Aufnahme nicht noch einmal ([neuerDurchgang]
/// vergisst das, wenn die Datenbank wieder die Wahrheit sagt).
class Rechenvergabe implements Vergabe {
  Rechenvergabe({
    this.dauer = const Duration(minutes: 10),
    DateTime Function()? uhr,
  }) : _uhr = uhr ?? DateTime.now;

  final Duration dauer;
  final DateTime Function() _uhr;

  final _vergeben = <String, _Vergabe>{};
  final _jeAuftrag = <String, String>{};
  final _geliefert = <String>{};

  /// Was ein Rechner nicht rechnen konnte – bekommt kein Rechner wieder,
  /// solange der Server läuft; der Server selbst rechnet es.
  final _ausgelassen = <String>{};

  static String _schluessel(Rechenart art, String aufnahme) =>
      '${art.name}/$aufnahme';

  bool _frei(String s) {
    final v = _vergeben[s];
    if (v == null) return true;
    if (v.bis.isAfter(_uhr())) return false;
    _vergeben.remove(s);
    _jeAuftrag.remove(v.id);
    return true;
  }

  @override
  bool nimm(Rechenart art, String aufnahme) {
    final s = _schluessel(art, aufnahme);
    if (_geliefert.contains(s) || !_frei(s)) return false;
    _vergeben[s] = _Vergabe(_selbst, _selbst, art, aufnahme, _uhr().add(dauer));
    return true;
  }

  @override
  void gib(Rechenart art, String aufnahme) {
    final s = _schluessel(art, aufnahme);
    if (_vergeben[s]?.an == _selbst) _vergeben.remove(s);
  }

  static const _selbst = '';

  /// Gibt [aufnahme] für [art] an [geraet]; die Kennung des Auftrags oder
  /// `null`, wenn sie gerade jemand anderes hat.
  String? vergib(Rechenart art, String aufnahme, String geraet) {
    final s = _schluessel(art, aufnahme);
    if (_geliefert.contains(s) || _ausgelassen.contains(s) || !_frei(s)) {
      return null;
    }
    final id = const Uuid().v4();
    _vergeben[s] = _Vergabe(id, geraet, art, aufnahme, _uhr().add(dauer));
    _jeAuftrag[id] = s;
    return id;
  }

  /// Der Auftrag [id] von [geraet], solange er gilt.
  ({Rechenart art, String aufnahme})? auftrag(String id, String geraet) {
    final s = _jeAuftrag[id];
    final v = s == null ? null : _vergeben[s];
    if (v == null || v.id != id || v.an != geraet) return null;
    if (!v.bis.isAfter(_uhr())) return null;
    return (art: v.art, aufnahme: v.aufnahme);
  }

  void geliefert(String id) {
    final s = _jeAuftrag.remove(id);
    if (s == null) return;
    _vergeben.remove(s);
    _geliefert.add(s);
  }

  void zurueck(String id, {bool auslassen = false}) {
    final s = _jeAuftrag.remove(id);
    if (s == null) return;
    _vergeben.remove(s);
    if (auslassen) _ausgelassen.add(s);
  }

  /// Ein Durchgang des Servers beginnt und holt seine Liste frisch.
  void neuerDurchgang() => _geliefert.clear();

  /// Wie viele Aufträge gerade an Rechner vergeben sind.
  int get anRechner => _vergeben.values.where((v) => v.an != _selbst).length;
}

class _Vergabe {
  _Vergabe(this.id, this.an, this.art, this.aufnahme, this.bis);
  final String id;
  final String an;
  final Rechenart art;
  final String aufnahme;
  final DateTime bis;
}

/// `/api/v1/rechnen/…` – Aufträge für verbundene Rechner.
class Rechenapi {
  Rechenapi(this.bibliotheken);

  final Bibliotheken bibliotheken;

  static const _hoechstens = 20;

  /// `{arten, teile?, anzahl?}` → `{auftraege: [...], gueltig: Sekunden}`.
  ///
  /// [arten]: was der Rechner kann (`bildanalyse`, `texterkennung`,
  /// `bildbeschreibung`); [teile]: welche Teile der Bildanalyse.
  Future<Response> auftraege(Request anfrage) async {
    final k = await _koerper(anfrage);
    if (k == null) return _json({'fehler': 'kein JSON'}, status: 400);
    final arten = <Rechenart>{
      for (final a in (k['arten'] as List?) ?? const [])
        ?Rechenart.values.asNameMap()[a],
    };
    final teile = {
      for (final t in (k['teile'] as List?) ?? Bildanalyseteil.alle)
        if (Bildanalyseteil.alle.contains(t)) t as String,
    };
    final anzahl = ((k['anzahl'] as num?)?.toInt() ?? 5).clamp(1, _hoechstens);
    final bereich = await bibliotheken.fuer(kontoVon(anfrage).id);
    final db = bereich.bibliothek.db;
    final vergabe = bereich.vergabe;
    final geraet = geraetVon(anfrage).id;
    final aus = <Map<String, Object?>>[];

    Future<void> nimm(
      Rechenart art,
      Iterable<(String, String, Set<String>)> kandidaten, {
      bool deutsch = false,
    }) async {
      for (final (aufnahme, datei, offen) in kandidaten) {
        if (aus.length >= anzahl) return;
        final id = vergabe.vergib(art, aufnahme, geraet);
        if (id == null) continue;
        aus.add(
          Rechenauftrag(
            id: id,
            art: art,
            aufnahme: aufnahme,
            datei: datei,
            teile: offen,
            deutsch: deutsch,
          ).alsJson(),
        );
      }
    }

    if (arten.contains(Rechenart.bildanalyse)) {
      await nimm(Rechenart.bildanalyse, [
        for (final c in await db.assetsForCombinedImageAnalysis())
          if (_offen(c, teile) case final offen when offen.isNotEmpty)
            (c.asset.id, _datei(c.asset), offen),
      ]);
    }
    if (arten.contains(Rechenart.texterkennung)) {
      await nimm(Rechenart.texterkennung, [
        for (final a in await db.assetsForOcrBackfill())
          (a.id, _datei(a), const <String>{}),
      ]);
    }
    if (arten.contains(Rechenart.bildbeschreibung)) {
      await nimm(Rechenart.bildbeschreibung, [
        for (final a in await db.assetsForCaptionBackfill())
          (a.id, _datei(a), const <String>{}),
      ], deutsch: await db.uebersetzeBeschreibungen());
    }
    return _json({'auftraege': aus, 'gueltig': vergabe.dauer.inSeconds});
  }

  static Set<String> _offen(
    ({AssetData asset, bool hatEmbedding}) c,
    Set<String> teile,
  ) => {
    if (c.asset.sharpnessScore == null) Bildanalyseteil.schaerfe,
    if (!c.asset.facesScanned) Bildanalyseteil.gesichter,
    if (!c.hatEmbedding) Bildanalyseteil.clip,
  }.intersection(teile);

  /// Die Datei, aus der gerechnet wird – dieselbe wie bei den Läufen des
  /// Servers (`Auswertungen.decodableFile`).
  static String _datei(AssetData asset) =>
      asset.previewRelativePath ?? asset.relativePath;

  /// `{auftrag, ergebnis}` – trägt ein, was der Rechner lieferte.
  Future<Response> ergebnis(Request anfrage) async {
    final k = await _koerper(anfrage);
    final id = k?['auftrag'];
    final roh = k?['ergebnis'];
    if (id is! String || roh is! Map) {
      return _json({'fehler': 'auftrag oder ergebnis fehlt'}, status: 400);
    }
    final bereich = await bibliotheken.fuer(kontoVon(anfrage).id);
    final a = bereich.vergabe.auftrag(id, geraetVon(anfrage).id);
    if (a == null) {
      return _json({'fehler': 'Auftrag abgelaufen oder fremd'}, status: 409);
    }
    final Rechenergebnis e;
    try {
      e = Rechenergebnis.ausJson(roh.cast<String, Object?>());
    } catch (fehler) {
      return _json({'fehler': 'ergebnis unlesbar: $fehler'}, status: 400);
    }
    final mangel = _mangel(e);
    if (mangel != null) return _json({'fehler': mangel}, status: 400);
    await bereich.bibliothek.auswertungen.trageEin(
      Rechenauftrag(id: id, art: a.art, aufnahme: a.aufnahme, datei: ''),
      e,
    );
    bereich.vergabe.geliefert(id);
    // Was auf dem Ergebnis aufbaut (Schlagwörter aus der Einbettung, die
    // Wiedererkennung aus den Gesichtern), rechnet der Server danach.
    bereich.auswertung.anstossen();
    return _json({'ok': true});
  }

  /// `{auftrag, auslassen?}` – gibt einen Auftrag zurück, ohne Ergebnis.
  /// Mit `auslassen` (die Datei liess sich nicht rechnen) bekommt ihn kein
  /// Rechner wieder.
  Future<Response> zurueck(Request anfrage) async {
    final k = await _koerper(anfrage);
    final id = k?['auftrag'];
    if (id is! String) return _json({'fehler': 'auftrag fehlt'}, status: 400);
    final bereich = await bibliotheken.fuer(kontoVon(anfrage).id);
    if (bereich.vergabe.auftrag(id, geraetVon(anfrage).id) != null) {
      bereich.vergabe.zurueck(id, auslassen: k?['auslassen'] == true);
    }
    return _json({'ok': true});
  }

  /// Was an einem Ergebnis nicht stimmen kann – ein Rechner ist ein Gerät
  /// desselben Kontos, aber seine Zahlen gehen ungesehen in die Bibliothek.
  static String? _mangel(Rechenergebnis e) {
    bool endlich(Iterable<double> w) => w.every((x) => x.isFinite);
    if (e.clip case final c? when c.length < 64 || c.length > 4096) {
      return 'clip: Länge ${c.length}';
    }
    if (e.clip case final c? when !endlich(c)) return 'clip: nicht endlich';
    if (e.schaerfe case final s? when !s.isFinite) return 'schaerfe';
    final g = e.gesichter ?? const [];
    if (g.length > 200) return 'gesichter: zu viele';
    for (final f in g) {
      if (!endlich([f.x, f.y, f.breite, f.hoehe, f.schaerfe]) ||
          f.x < -0.1 ||
          f.y < -0.1 ||
          f.breite <= 0 ||
          f.hoehe <= 0 ||
          f.x + f.breite > 1.1 ||
          f.y + f.hoehe > 1.1) {
        return 'gesichter: Lage';
      }
      if (f.ausschnitt.length > 2 * 1024 * 1024) return 'gesichter: Ausschnitt';
      if (f.merkmal case final m? when !endlich(m)) return 'gesichter: Merkmal';
    }
    if ((e.beschreibung?.length ?? 0) > 4000) return 'beschreibung: zu lang';
    final text = e.textstellen?.fold(0, (n, s) => n + s.text.length) ?? 0;
    if (text > 200000) return 'textstellen: zu lang';
    return null;
  }

  static Future<Map<String, Object?>?> _koerper(Request anfrage) async {
    try {
      final k = jsonDecode(await anfrage.readAsString());
      return k is Map ? k.cast<String, Object?>() : null;
    } on FormatException {
      return null;
    }
  }
}
