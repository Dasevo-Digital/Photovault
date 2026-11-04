import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show BooleanExpressionOperators, Variable;
import 'package:kern/db/database.dart';
import 'package:kern/db/rasterzeile.dart';
import 'package:kern/protokoll.dart';
import 'package:kern/services/import_service.dart' show ImportOutcome;
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';

import 'albumteilungen.dart';
import 'anmeldung_api.dart';
import 'bibliotheken.dart';
import 'gastbeitraege.dart';
import 'konten/kontodienst.dart';
import 'speicher.dart';
import 'zeilen_json.dart';

Response _json(Object? daten, {int status = 200}) => Response(
  status,
  body: jsonEncode(daten),
  headers: {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store',
  },
);

/// Liefert eine Datei einer Aufnahme aus – dieselbe Auslieferung wie für
/// die eigenen Aufnahmen (`/api/v1/aufnahmen/<id>/<art>`).
typedef Aufnahmedatei =
    Future<Response> Function(
      Request anfrage,
      Kontobereich bereich,
      AssetData aufnahme,
      String art,
    );

/// Alben zwischen Konten teilen (#105).
///
/// **Für den Besitzer:** Er teilt ein Album mit anderen Konten dieses
/// Servers, jedes für sich zum Ansehen oder zum Beitragen.
///
/// **Für den Empfänger:** Unter „Geteilt mit mir“ sieht er die Alben, mit
/// allem, was gerade darin liegt, in denselben Fassungen wie seine eigenen
/// Aufnahmen – die Konten eines Servers kennen sich. Gesperrte Aufnahmen
/// und der Papierkorb des Besitzers kommen nie dazu. Persönliche Marken
/// des Besitzers (Favorit, Bewertung, Farbe) bleiben bei ihm.
///
/// **Beiträge:** Was ein Empfänger mit Recht zum Beitragen schickt, kommt
/// ohne Prüfung und ohne Rückfrage in die Bibliothek des Besitzers und ins
/// Album – anders als bei Gästen über einen Link, die niemand kennt. Wer
/// es geschickt hat, steht in server.sqlite ([Albumteilungen]) und an
/// jeder Kachel.
class Teilungsapi {
  Teilungsapi({
    required this.konten,
    required this.bibliotheken,
    required this.datei,
    this.speicher,
    this.hoechstensBeitrag = 2 * 1024 * 1024 * 1024,
  });

  final Kontodienst konten;
  final Bibliotheken bibliotheken;
  final Aufnahmedatei datei;
  final Speicherwaechter? speicher;
  final int hoechstensBeitrag;

  Albumteilungen get _dienst => konten.albumteilungen;

  /// Was ein Empfänger von einer Aufnahme bekommt.
  static const _arten = {
    'miniatur',
    'ansicht',
    'vorschau',
    'voll',
    'original',
    'wiedergabe',
    'abspielbar',
    'jpeg',
  };

  // --- Für den Besitzer ----------------------------------------------------

  /// Die anderen Konten des Servers: `{konten: [{id, name}]}` – zur Wahl,
  /// mit wem geteilt wird.
  Response andereKonten(Request r) {
    final ich = kontoVon(r).id;
    return _json({
      'konten': [
        for (final k in konten.alle())
          if (k.id != ich) {'id': k.id, 'name': k.name},
      ]..sort((a, b) => '${a['name']}'.compareTo('${b['name']}')),
    });
  }

  Future<AlbumData?> _eigenesAlbum(Request r, String album) async {
    final db = (await bibliotheken.fuer(kontoVon(r).id)).bibliothek.db;
    return (await db.alleAlben()).where((a) => a.id == album).firstOrNull;
  }

  Map<String, Object?>? _empfaengerJson(Albumteilung t) {
    final k = konten.konto(t.empfaenger);
    if (k == null) return null;
    return {
      'id': t.id,
      'konto': k.id,
      'name': k.name,
      'beitragen': t.beitragen,
      'angelegt': t.angelegt.toUtc().toIso8601String(),
    };
  }

  /// Mit wem [album] geteilt ist, nach Namen: `{teilungen: [{id, konto,
  /// name, beitragen, angelegt}]}`.
  Future<Response> vonAlbum(Request r, String album) async {
    if (await _eigenesAlbum(r, album) == null) {
      return _json({'fehler': 'Album unbekannt'}, status: 404);
    }
    return _json({
      'teilungen': [
        for (final t in _dienst.vonAlbum(kontoVon(r).id, album))
          ?_empfaengerJson(t),
      ]..sort((a, b) => '${a['name']}'.compareTo('${b['name']}')),
    });
  }

  /// `{beitragen}` → teilt [album] mit [empfaenger] oder ändert sein Recht.
  Future<Response> teile(Request r, String album, String empfaenger) async {
    final ich = kontoVon(r).id;
    if (await _eigenesAlbum(r, album) == null) {
      return _json({'fehler': 'Album unbekannt'}, status: 404);
    }
    if (empfaenger == ich || konten.konto(empfaenger) == null) {
      return _json({'fehler': 'Konto unbekannt'}, status: 404);
    }
    final Object? k;
    try {
      k = jsonDecode(await r.readAsString());
    } on FormatException {
      return _json({'fehler': 'kein JSON'}, status: 400);
    }
    final beitragen = k is Map && k['beitragen'] == true;
    try {
      final t = _dienst.teile(
        besitzer: ich,
        album: album,
        empfaenger: empfaenger,
        beitragen: beitragen,
      );
      return _json(_empfaengerJson(t));
    } on StateError catch (e) {
      return _json({'fehler': e.message}, status: 409);
    }
  }

  /// Hört auf, [album] mit [empfaenger] zu teilen.
  Future<Response> nichtMehrTeilen(
    Request r,
    String album,
    String empfaenger,
  ) async {
    final ich = kontoVon(r).id;
    final t = _dienst
        .vonAlbum(ich, album)
        .where((t) => t.empfaenger == empfaenger)
        .firstOrNull;
    if (t == null) return _json({'fehler': 'unbekannt'}, status: 404);
    _dienst.entferne(t.id, ich);
    return Response(204);
  }

  /// Was andere Konten in die eigenen Alben gelegt haben und noch nicht
  /// angesehen ist (#295): `{alben: [{id, name, anzahl, von: [...],
  /// zuletzt, titelbild?}]}`, das jüngste zuerst. Gezählt wird nur, was
  /// noch im Album liegt.
  Future<Response> neueBeitraege(Request r) async {
    final ich = kontoVon(r).id;
    final neu = _dienst.neueBeitraege(ich);
    if (neu.isEmpty) return _json({'alben': const []});
    final db = (await bibliotheken.fuer(ich)).bibliothek.db;
    final alben = {for (final a in await db.alleAlben()) a.id: a};
    final liste = <Map<String, Object?>>[];
    for (final n in neu) {
      final album = alben[n.album];
      if (album == null) continue;
      final drin = {for (final a in await db.albumAufnahmen(album.id)) a.id};
      final noch = [
        for (final a in n.aufnahmen)
          if (drin.contains(a)) a,
      ];
      if (noch.isEmpty) continue;
      liste.add({
        'id': album.id,
        'name': album.name,
        'anzahl': noch.length,
        'von': n.von,
        'zuletzt': n.zuletzt.toUtc().toIso8601String(),
        'titelbild': noch.last,
      });
    }
    return _json({'alben': liste});
  }

  /// Der Besitzer hat [album] geöffnet: Seine neuen Beiträge sind gesehen.
  Future<Response> beitraegeGesehen(Request r, String album) async {
    _dienst.beitraegeGesehen(kontoVon(r).id, album);
    return Response(204);
  }

  // --- Kommentare und „Gefällt mir“ (#297) ----------------------------------
  //
  // Dieselben Wege für beide Seiten: der Besitzer unter
  // `/api/v1/alben/<Album>/…`, ein Empfänger unter
  // `/api/v1/geteilt/<Teilung>/…`. Wer das Album sehen darf, darf auch
  // etwas dazu sagen – auch ein Empfänger, der nur ansehen darf.

  /// Das Album hinter der Anfrage: das eigene [album] oder das der
  /// Teilung [teilung].
  Future<_Ort?> _ort(Request r, {String? album, String? teilung}) async {
    if (album != null) {
      final daten = await _eigenesAlbum(r, album);
      if (daten == null) return null;
      final b = await bibliotheken.fuer(kontoVon(r).id);
      return _Ort(kontoVon(r).id, daten, b.bibliothek.db);
    }
    final g = await _geteilt(r, teilung!);
    if (g == null) return null;
    return _Ort(g.teilung.besitzer, g.album, g.bereich.bibliothek.db);
  }

  Future<Set<String>> _drin(_Ort o) async => {
    for (final a in await o.db.albumAufnahmen(o.album.id)) a.id,
  };

  /// `{kommentare: [{id, aufnahme?, name, text, angelegt, eigener,
  /// loeschbar}], gefaellt: {Aufnahme: {anzahl, ich, namen}}}` – nur zu
  /// dem, was gerade im Album liegt.
  Future<Response> _aktivitaet(Request r, _Ort? o) async {
    if (o == null) return _json({'fehler': 'unbekannt'}, status: 404);
    final ich = kontoVon(r).id;
    final drin = await _drin(o);
    return _json({
      'kommentare': [
        for (final k in _dienst.kommentare(o.besitzer, o.album.id))
          if (k.aufnahme == null || drin.contains(k.aufnahme))
            {
              'id': k.id,
              'aufnahme': ?k.aufnahme,
              'name': k.name,
              'text': k.text,
              'angelegt': k.angelegt.toUtc().toIso8601String(),
              'eigener': k.von == ich,
              'loeschbar': k.von == ich || o.besitzer == ich,
            },
      ],
      'gefaellt': {
        for (final MapEntry(key: aufnahme, value: von)
            in _dienst.gefaelltIn(o.besitzer, o.album.id).entries)
          if (drin.contains(aufnahme))
            aufnahme: {
              'anzahl': von.length,
              'ich': von.contains(ich),
              'namen': [for (final k in von) ?konten.konto(k)?.name],
            },
      },
    });
  }

  /// `{text, aufnahme?}` → 201 mit dem Kommentar.
  Future<Response> _kommentiere(Request r, _Ort? o) async {
    if (o == null) return _json({'fehler': 'unbekannt'}, status: 404);
    final Object? k;
    try {
      k = jsonDecode(await r.readAsString());
    } on FormatException {
      return _json({'fehler': 'kein JSON'}, status: 400);
    }
    final text = k is Map ? k['text'] : null;
    final aufnahme = k is Map ? k['aufnahme'] : null;
    if (text is! String ||
        text.trim().isEmpty ||
        text.trim().length > Albumteilungen.kommentarHoechstens) {
      return _json({'fehler': 'Kommentar leer oder zu lang'}, status: 400);
    }
    if (aufnahme != null &&
        (aufnahme is! String || !(await _drin(o)).contains(aufnahme))) {
      return _json({'fehler': 'nicht im Album'}, status: 404);
    }
    final ich = kontoVon(r);
    final Albumkommentar neu;
    try {
      neu = _dienst.kommentiere(
        besitzer: o.besitzer,
        album: o.album.id,
        aufnahme: aufnahme as String?,
        von: ich.id,
        name: ich.name,
        text: text,
      );
    } on StateError catch (e) {
      return _json({'fehler': e.message}, status: 409);
    }
    return _json({
      'id': neu.id,
      'aufnahme': ?neu.aufnahme,
      'name': neu.name,
      'text': neu.text,
      'angelegt': neu.angelegt.toUtc().toIso8601String(),
      'eigener': true,
      'loeschbar': true,
    }, status: 201);
  }

  /// Den eigenen Kommentar entfernen – der Besitzer des Albums jeden.
  Response _kommentarWeg(Request r, _Ort? o, String kommentar) {
    if (o == null) return _json({'fehler': 'unbekannt'}, status: 404);
    final weg = _dienst.entferneKommentar(
      kommentar,
      besitzer: o.besitzer,
      album: o.album.id,
      konto: kontoVon(r).id,
    );
    return weg ? Response(204) : _json({'fehler': 'unbekannt'}, status: 404);
  }

  /// PUT: „Gefällt mir“; DELETE: nicht mehr.
  Future<Response> _gefaellt(Request r, _Ort? o, String aufnahme) async {
    if (o == null) return _json({'fehler': 'unbekannt'}, status: 404);
    if (!(await _drin(o)).contains(aufnahme)) {
      return _json({'fehler': 'nicht im Album'}, status: 404);
    }
    _dienst.gefaellt(
      o.besitzer,
      o.album.id,
      aufnahme,
      kontoVon(r).id,
      an: r.method == 'PUT',
    );
    return Response(204);
  }

  Future<Response> aktivitaetEigen(Request r, String album) async =>
      _aktivitaet(r, await _ort(r, album: album));
  Future<Response> aktivitaetGeteilt(Request r, String id) async =>
      _aktivitaet(r, await _ort(r, teilung: id));
  Future<Response> kommentierenEigen(Request r, String album) async =>
      _kommentiere(r, await _ort(r, album: album));
  Future<Response> kommentierenGeteilt(Request r, String id) async =>
      _kommentiere(r, await _ort(r, teilung: id));
  Future<Response> kommentarWegEigen(Request r, String album, String k) async =>
      _kommentarWeg(r, await _ort(r, album: album), k);
  Future<Response> kommentarWegGeteilt(Request r, String id, String k) async =>
      _kommentarWeg(r, await _ort(r, teilung: id), k);
  Future<Response> gefaelltEigen(Request r, String album, String a) async =>
      _gefaellt(r, await _ort(r, album: album), a);
  Future<Response> gefaelltGeteilt(Request r, String id, String a) async =>
      _gefaellt(r, await _ort(r, teilung: id), a);

  // --- Für den Empfänger ---------------------------------------------------

  /// Die Teilung [id] mit dem Album dahinter, wenn sie für das Konto der
  /// Anfrage bestimmt ist. Ist das Album weg, geht die Teilung mit.
  Future<_Geteilt?> _geteilt(Request r, String id) async {
    final t = _dienst.eine(id, kontoVon(r).id);
    if (t == null || t.empfaenger != kontoVon(r).id) return null;
    final bereich = await bibliotheken.fuer(t.besitzer);
    final album = (await bereich.bibliothek.db.alleAlben())
        .where((a) => a.id == t.album)
        .firstOrNull;
    if (album == null) {
      _dienst.entferneAlbum(t.besitzer, t.album);
      return null;
    }
    return _Geteilt(t, bereich, album);
  }

  /// Was mit dem Konto geteilt ist: `{alben: [{id, name, besitzer,
  /// beitragen, anzahl, titelbild?, titelstand?}]}` – `id` ist die
  /// Kennung der Teilung, nicht die des Albums.
  Future<Response> mitMir(Request r) async {
    final liste = <Map<String, Object?>>[];
    for (final t in _dienst.mitKonto(kontoVon(r).id)) {
      final g = await _geteilt(r, t.id);
      if (g == null) continue;
      final db = g.bereich.bibliothek.db;
      final titel = await db.albumTitelbild(g.album);
      liste.add({
        'id': t.id,
        'name': g.album.name,
        'besitzer': konten.konto(t.besitzer)?.name ?? '',
        'beitragen': t.beitragen,
        'anzahl': (await db.albumAnzahlen())[g.album.id] ?? 0,
        if (titel != null) 'titelbild': titel.id,
        if (titel != null) 'titelstand': bildstand(Rasterzeile.aus(titel)),
      });
    }
    return _json({'alben': liste});
  }

  /// Ein geteiltes Album: `{album: {id, name, besitzer, beitragen},
  /// aufnahmen: [...]}` – die Zeilen wie im eigenen Raster, ohne die
  /// Marken des Besitzers, dazu `von`, wenn ein anderes Konto sie
  /// beigetragen hat, und `eigene`, wenn es dieses war.
  Future<Response> album(Request r, String id) async {
    final g = await _geteilt(r, id);
    if (g == null) return _json({'fehler': 'unbekannt'}, status: 404);
    final aufnahmen = await g.bereich.bibliothek.db.albumAufnahmen(g.album.id);
    final von = _dienst.beitragende(
      g.teilung.besitzer,
      aufnahmen.map((a) => a.id),
    );
    final ich = kontoVon(r).id;
    return _json({
      'album': {
        'id': id,
        'name': g.album.name,
        'besitzer': konten.konto(g.teilung.besitzer)?.name ?? '',
        'beitragen': g.teilung.beitragen,
      },
      'aufnahmen': [
        for (final a in aufnahmen)
          {
            ...zeileAlsJson(Rasterzeile.aus(a))
              ..remove('favorit')
              ..remove('bewertung')
              ..remove('farbe'),
            if (von[a.id] case final b?) 'von': b.name,
            if (von[a.id]?.konto == ich) 'eigene': true,
          },
      ],
    });
  }

  /// Eine Datei einer Aufnahme aus einem geteilten Album – nur, was gerade
  /// darin liegt, oder die Videohälfte eines Live Photos darin.
  Future<Response> aufnahmedatei(
    Request r,
    String id,
    String aufnahme,
    String art,
  ) async {
    if (!_arten.contains(art)) return Response.notFound(null);
    final g = await _geteilt(r, id);
    if (g == null) return Response.notFound(null);
    final db = g.bereich.bibliothek.db;
    final a = await db.assetById(aufnahme);
    if (a == null || a.isLocked || a.isTrashed) return Response.notFound(null);
    final kandidaten = [a.id, ?a.linkedAssetId];
    final drin =
        await (db.select(db.albumAssets)..where(
              (t) => t.albumId.equals(g.album.id) & t.assetId.isIn(kandidaten),
            ))
            .get();
    if (drin.isEmpty) return Response.notFound(null);
    return datei(r, g.bereich, a, art);
  }

  /// Eine Aufnahme ins geteilte Album legen: der Körper ist die Datei,
  /// `?name=` ihr Name, `?geaendert=` ihre Änderungszeit in Millisekunden.
  /// → 201 `{aufnahme, ausgang}`; `ausgang` ist `imported` oder
  /// `duplicateSkipped` (dann lag sie beim Besitzer schon und kommt nur
  /// ins Album).
  Future<Response> beitrag(Request r, String id) async {
    final g = await _geteilt(r, id);
    if (g == null) return _json({'fehler': 'unbekannt'}, status: 404);
    if (!g.teilung.beitragen) {
      return _json({'fehler': 'nur ansehen'}, status: 403);
    }
    if (speicher?.voll ?? false) {
      return _json({'fehler': 'Der Speicher ist voll.'}, status: 507);
    }
    final laenge = int.tryParse(r.headers['content-length'] ?? '');
    if (laenge == null) return _json({'fehler': 'Länge fehlt'}, status: 411);
    if (laenge <= 0 || laenge > hoechstensBeitrag) {
      return _json({'fehler': 'Datei zu gross'}, status: 413);
    }
    final b = g.bereich.bibliothek;
    final q = r.url.queryParameters;
    // Ein Rest nach einem Absturz geht beim nächsten Öffnen der Bibliothek
    // (Bibliotheken.fuer).
    final ordner = await (await Directory(
      p.join(b.ordner.path, 'kontobeitraege'),
    ).create(recursive: true)).createTemp('beitrag_');
    try {
      final datei = File(
        p.join(ordner.path, Gastbeitraege.bereinigt(q['name'] ?? 'beitrag')),
      );
      var geschrieben = 0;
      final senke = datei.openWrite();
      try {
        await for (final stueck in r.read()) {
          geschrieben += stueck.length;
          if (geschrieben > laenge) break;
          senke.add(stueck);
        }
      } finally {
        await senke.close();
      }
      if (geschrieben != laenge) {
        return _json({'fehler': 'unvollständig'}, status: 400);
      }
      final geaendert = int.tryParse(q['geaendert'] ?? '');
      if (geaendert != null) {
        await datei.setLastModified(
          DateTime.fromMillisecondsSinceEpoch(geaendert),
        );
      }
      final ergebnis = await b.importe.importFile(datei.path);
      var aufnahme = ergebnis.assetId;
      if (ergebnis.outcome == ImportOutcome.imported && aufnahme != null) {
        final ich = kontoVon(r);
        _dienst.vermerkeBeitrag(
          besitzer: g.teilung.besitzer,
          aufnahme: aufnahme,
          von: ich.id,
          name: ich.name,
          album: g.album.id,
        );
        try {
          await b.nachbearbeitung.neueAufnahme(aufnahme);
        } catch (f) {
          protokoll('Nachbearbeitung eines Beitrags gescheitert: $f');
        }
        g.bereich.auswertung.anstossen();
      } else if (ergebnis.outcome == ImportOutcome.duplicateSkipped) {
        aufnahme = await b.kennungFuer(
          (await sha256.bind(datei.openRead()).first).toString(),
        );
      }
      if (aufnahme == null) {
        return _json({
          'fehler': 'Import gescheitert: ${ergebnis.error}',
        }, status: 415);
      }
      // Als Befehl wie jede Änderung am Album: So erfahren die Geräte des
      // Besitzers davon.
      await b.db.fuehreAus(AlbumFuellen(g.album.id, [aufnahme]));
      return _json({
        'aufnahme': aufnahme,
        'ausgang': ergebnis.outcome.name,
      }, status: 201);
    } finally {
      await ordner.delete(recursive: true);
    }
  }

  /// Nimmt eine Aufnahme, die das Konto der Anfrage beigetragen hat,
  /// wieder aus dem Album (#290). Liegt sie in keinem anderen Album des
  /// Besitzers, kommt sie in dessen Papierkorb – von dort holt er sie
  /// zurück, wenn er sie behalten will. → 200 `{papierkorb}`; 403, wenn
  /// sie nicht von diesem Konto kam.
  Future<Response> beitragEntfernen(
    Request r,
    String id,
    String aufnahme,
  ) async {
    final g = await _geteilt(r, id);
    if (g == null) return _json({'fehler': 'unbekannt'}, status: 404);
    final von = _dienst.beitragende(g.teilung.besitzer, [aufnahme])[aufnahme];
    if (von?.konto != kontoVon(r).id) {
      return _json({'fehler': 'nicht dein Beitrag'}, status: 403);
    }
    final db = g.bereich.bibliothek.db;
    final alben = {
      for (final z in await (db.select(
        db.albumAssets,
      )..where((t) => t.assetId.equals(aufnahme))).get())
        z.albumId,
    };
    if (!alben.contains(g.album.id)) {
      return _json({'fehler': 'nicht im Album'}, status: 404);
    }
    // Als Befehle wie jede andere Änderung: So erfahren die Geräte des
    // Besitzers davon.
    await db.fuehreAus(AusAlbumNehmen(g.album.id, [aufnahme]));
    final papierkorb = alben.length == 1;
    if (papierkorb) await db.fuehreAus(InDenPapierkorb([aufnahme]));
    return _json({'papierkorb': papierkorb});
  }

  /// Der Empfänger will das Album nicht mehr sehen.
  Future<Response> verlassen(Request r, String id) async {
    final ich = kontoVon(r).id;
    final t = _dienst.eine(id, ich);
    if (t == null || t.empfaenger != ich) {
      return _json({'fehler': 'unbekannt'}, status: 404);
    }
    _dienst.entferne(id, ich);
    return Response(204);
  }
  // --- Partnerfreigabe (#293) ---------------------------------------------
  //
  // Ein Konto lässt ein anderes seine ganze Bibliothek sehen – wie ein
  // geteiltes Album, nur ohne Album: die Zeitleiste, seitenweise, ohne
  // Gesperrtes und Papierkorb, ohne die Marken des Besitzers. Beitragen
  // geht hier nicht; dafür gibt es geteilte Alben.

  /// `{meine: [{konto, name}], mitMir: [{konto, name, anzahl, titelbild?,
  /// titelstand?}]}` – wen dieses Konto seine Bibliothek sehen lässt, und
  /// wessen Bibliothek es sieht.
  Future<Response> partner(Request r) async {
    final ich = kontoVon(r).id;
    final mitMir = <Map<String, Object?>>[];
    for (final besitzer in _dienst.partnerMit(ich)) {
      final k = konten.konto(besitzer);
      if (k == null) continue;
      final db = (await bibliotheken.fuer(besitzer)).bibliothek.db;
      final anzahl = await db
          .customSelect(
            'SELECT count(*) AS n FROM assets WHERE $rasterSichtbar',
          )
          .getSingle();
      final titel = await db
          .customSelect(
            'SELECT $rasterSpalten FROM assets WHERE $rasterSichtbar '
            'ORDER BY file_created_at DESC, id DESC LIMIT 1',
          )
          .getSingleOrNull();
      final t = titel == null ? null : Rasterzeile.ausZeile(titel);
      mitMir.add({
        'konto': k.id,
        'name': k.name,
        'anzahl': anzahl.read<int>('n'),
        'titelbild': ?t?.id,
        if (t != null) 'titelstand': bildstand(t),
      });
    }
    return _json({
      'meine': [
        for (final p in _dienst.partnerVon(ich))
          if (konten.konto(p) case final k?) {'konto': k.id, 'name': k.name},
      ],
      'mitMir': mitMir,
    });
  }

  /// Lässt [konto] die eigene Bibliothek sehen.
  Response partnerSetzen(Request r, String konto) {
    final ich = kontoVon(r).id;
    if (konto == ich || konten.konto(konto) == null) {
      return _json({'fehler': 'Konto unbekannt'}, status: 404);
    }
    _dienst.partnerSetzen(ich, konto);
    return Response(204);
  }

  /// Hört auf, [konto] die eigene Bibliothek sehen zu lassen.
  Response partnerEntfernen(Request r, String konto) {
    _dienst.partnerEntfernen(kontoVon(r).id, konto);
    return Response(204);
  }

  /// Will die Bibliothek von [konto] nicht mehr sehen.
  Response partnerVerlassen(Request r, String konto) {
    _dienst.partnerEntfernen(konto, kontoVon(r).id);
    return Response(204);
  }

  /// Die Zeitleiste von [konto], wenn es die Anfrage sie sehen lässt:
  /// `{name, aufnahmen: [...], weiter}` – `?nach=` blättert weiter (wie
  /// `/api/v1/aufnahmen`), `?anzahl=` höchstens 1000.
  Future<Response> partnerAufnahmen(Request r, String konto) async {
    if (!_dienst.istPartner(konto, kontoVon(r).id)) {
      return _json({'fehler': 'unbekannt'}, status: 404);
    }
    final db = (await bibliotheken.fuer(konto)).bibliothek.db;
    final q = r.url.queryParameters;
    final anzahl = (int.tryParse(q['anzahl'] ?? '') ?? 300).clamp(1, 1000);
    final nach = q['nach']?.split('~');
    final ab = nach != null && nach.length == 2
        ? (
            zeit: DateTime.fromMillisecondsSinceEpoch(
              int.tryParse(nach[0]) ?? 0,
            ),
            id: nach[1],
          )
        : null;
    final zeilen = await db
        .customSelect(
          'SELECT $rasterSpalten FROM assets WHERE $rasterSichtbar'
          '${ab == null ? '' : ' AND (file_created_at < ? OR (file_created_at = ? AND id < ?))'}'
          ' ORDER BY file_created_at DESC, id DESC LIMIT ?',
          variables: [
            if (ab != null) ...[
              Variable<DateTime>(ab.zeit),
              Variable<DateTime>(ab.zeit),
              Variable<String>(ab.id),
            ],
            Variable<int>(anzahl),
          ],
          readsFrom: {db.assets},
        )
        .get();
    final liste = [for (final z in zeilen) Rasterzeile.ausZeile(z)];
    return _json({
      'name': konten.konto(konto)?.name ?? '',
      'aufnahmen': [
        for (final z in liste)
          zeileAlsJson(z)
            ..remove('favorit')
            ..remove('bewertung')
            ..remove('farbe'),
      ],
      'weiter': liste.length < anzahl
          ? null
          : '${liste.last.fileCreatedAt.millisecondsSinceEpoch}~${liste.last.id}',
    });
  }

  /// Eine Datei aus der Bibliothek von [konto] – nichts Gesperrtes, nichts
  /// aus dem Papierkorb.
  Future<Response> partnerDatei(
    Request r,
    String konto,
    String aufnahme,
    String art,
  ) async {
    if (!_arten.contains(art) || !_dienst.istPartner(konto, kontoVon(r).id)) {
      return Response.notFound(null);
    }
    final bereich = await bibliotheken.fuer(konto);
    final a = await bereich.bibliothek.db.assetById(aufnahme);
    if (a == null || a.isLocked || a.isTrashed) return Response.notFound(null);
    return datei(r, bereich, a, art);
  }
}

/// Wo ein Kommentar hingehört: das Album von [besitzer].
class _Ort {
  _Ort(this.besitzer, this.album, this.db);

  final String besitzer;
  final AlbumData album;
  final AppDatabase db;
}

class _Geteilt {
  _Geteilt(this.teilung, this.bereich, this.album);

  final Albumteilung teilung;
  final Kontobereich bereich;
  final AlbumData album;
}
