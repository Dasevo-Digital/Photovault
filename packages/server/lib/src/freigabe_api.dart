import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' show max;

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:kern/db/database.dart';
import 'package:kern/protokoll.dart';
import 'package:kern/services/asset_display_path.dart';
import 'package:kern/services/dateikennung.dart';
import 'package:kern/services/import_service.dart'
    show ImportOutcome, ImportResult;
import 'package:kern/services/wasserzeichen.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';

import 'albumsicht.dart';
import 'absender.dart';
import 'anmeldung_api.dart';
import 'bibliothek.dart';
import 'bibliotheken.dart';
import 'dateiantwort.dart';
import 'freigaben.dart';
import 'gastbeitraege.dart';
import 'gastpruefung.dart';
import 'konten/bremse.dart';
import 'speicher.dart';
import 'teilbilder.dart';
import 'videofassung.dart';
import 'web.dart';
import 'zeitangaben.dart';

Response _json(Object? daten, {int status = 200, Map<String, String>? kopf}) =>
    Response(
      status,
      body: jsonEncode(daten),
      headers: {
        'content-type': 'application/json; charset=utf-8',
        'cache-control': 'no-store',
        ...?kopf,
      },
    );

/// Teilen nach aussen (Issue #106): Der Besitzer legt Freigaben für ein
/// Album oder eine Auswahl an; wer den Link hat, sieht genau diese
/// Aufnahmen – sonst nichts.
///
/// **Was ein Besucher bekommt:** Bilder, neu gerechnet und ohne
/// Metadaten (siehe [Teilbilder]), Videos als H.264 ohne Metadaten (siehe
/// [Videofassungen]); Originale nur, wenn der Besitzer Herunterladen
/// erlaubt hat. Keine Orte, keine Personen, keine Namen. Gesperrte
/// Aufnahmen und der Papierkorb kommen nie dazu, auch nicht über ein
/// Album.
///
/// **Was ihn aufhält:** Abgelaufene und gelöschte Freigaben antworten
/// wie unbekannte mit 404. Ein Passwort wird wie bei der Anmeldung je
/// Absender gebremst und je Freigabe nach Fehlversuchen gesperrt
/// ([Freigabedienst.pruefePasswort]); danach gilt ein Cookie zwölf Stunden.
class Freigabeapi {
  Freigabeapi({
    required this.dienst,
    required this.bibliotheken,
    required this.absender,
    required this.video,
    this.webOrdner,
    this.oeffentlich,
    Bremse? bremse,
    this.beitraege,
    Gastpruefung? pruefung,
    this.speicher,
    this.hoechstensBeitrag = 2 * 1024 * 1024 * 1024,
    this.hoechstensOffeneBytes = Gastbeitraege.hoechstensOffeneBytes,
    this.gleichzeitigJeAbsender = gastGleichzeitigJeAbsender,
    this.gleichzeitigJeFreigabe = gastGleichzeitigJeFreigabe,
    this.hoechstensInPruefung = gastHoechstensInPruefung,
    this.leerlauf = uploadLeerlauf,
  }) : bremse = bremse ?? Bremse(),
       pruefung = pruefung ?? Gastpruefung();

  final Freigabedienst dienst;
  final Bibliotheken bibliotheken;
  final Absender absender;
  final Videofassungen video;
  final Directory? webOrdner;

  /// Die Adresse von aussen (`PV_OEFFENTLICH`); sonst die der Anfrage.
  final Uri? oeffentlich;
  final Bremse bremse;
  final _teilbilder = Teilbilder();

  /// Was Gäste hochladen (Issue #106); ohne sie nimmt keine Freigabe
  /// etwas an.
  final Gastbeitraege? beitraege;

  /// Der abgeschottete Prüfprozess für ihre Dateien.
  final Gastpruefung pruefung;

  /// Bei vollem Speicher nehmen auch Freigaben nichts mehr an.
  final Speicherwaechter? speicher;

  /// Die grösste Datei, die ein Gast schicken darf.
  final int hoechstensBeitrag;

  /// Wie lange ein Beitrag ohne neues Stück stehen darf ([schreibeUpload]).
  final Duration leerlauf;

  /// Höchstens so viele Bytes in offenen Beiträgen je Freigabe (siehe
  /// [Gastbeitraege.hoechstensOffeneBytes]).
  final int hoechstensOffeneBytes;

  /// Wie viele Dateien ein Absender in der Stunde schicken darf.
  static const beitraegeJeStunde = 300;
  final _jeAbsender = <String, List<DateTime>>{};

  /// So viele Uploads eines Absenders zugleich. Die Seite schickt eine
  /// Datei nach der anderen; mehr braucht nur, wer mit mehreren Geräten
  /// hinter einem Anschluss sitzt (eine Feier im selben WLAN).
  static const gastGleichzeitigJeAbsender = 6;

  /// So viele Uploads zugleich auf einen Link. Mehr Gäste warten kurz:
  /// Die Seite versucht es nach einer 503 von selbst wieder.
  static const gastGleichzeitigJeFreigabe = 12;

  /// Nichts Neues mehr annehmen, solange so viele Beiträge auf die
  /// Prüfung warten – sie läuft einer nach dem anderen, und bis dahin
  /// liegen die Rohdateien auf der Platte. Einige hundert Fotos einer
  /// Feier passen hinein; wer mehr schickt, wartet, bis geprüft ist.
  static const gastHoechstensInPruefung = 1000;

  final int gleichzeitigJeAbsender;
  final int gleichzeitigJeFreigabe;
  final int hoechstensInPruefung;
  final _laufendJeAbsender = <String, int>{};
  final _laufendJeFreigabe = <String, int>{};

  /// Welche Beiträge gerade geprüft werden – nach einem Neustart wird
  /// der Rest wieder aufgenommen.
  final _inPruefung = <String>{};

  static const _keineSuche = {'x-robots-tag': 'noindex, nofollow'};

  // --- Für den Besitzer ----------------------------------------------------

  /// Wohin der Link zeigt: die Adresse von aussen – gesetzt, vom
  /// vertrauten Proxy gemeldet oder die, über die die Anfrage kam.
  String _basis(Request r) {
    final o = oeffentlich;
    if (o != null) {
      final s = o.toString();
      return s.endsWith('/') ? s.substring(0, s.length - 1) : s;
    }
    return absender.herkunft(r);
  }

  Future<Map<String, Object?>> _alsJson(
    Request r,
    Freigabe f,
    String? link,
    AppDatabase db, {
    Map<String, int>? gezaehlt,
  }) async {
    // Gezählt in der Datenbank, je Album einmal: Vorher lud jeder Link auf
    // ein Album alle dessen Zeilen, nur um sie zu zählen.
    final album = f.album;
    final int anzahl;
    if (album == null) {
      anzahl = f.aufnahmen!.length;
    } else {
      anzahl = gezaehlt?[album] ?? await db.sichtbareAnzahl(album);
      gezaehlt?[album] = anzahl;
    }
    final zeichen = dienst.wasserzeichenVon(f);
    return {
      'id': f.id,
      'titel': f.titel,
      // Nach einem ersetzten server.schluessel nicht mehr zu lesen: Die
      // Freigabe steht trotzdem da, damit man sie widerrufen kann.
      'link': link == null ? null : '${_basis(r)}/teilen/$link',
      if (link == null) 'linkUnlesbar': true,
      'art': f.album != null ? 'album' : 'auswahl',
      if (f.album != null) 'album': f.album,
      'anzahl': anzahl,
      'angelegt': f.angelegt.toUtc().toIso8601String(),
      'ablauf': f.ablauf?.toUtc().toIso8601String(),
      'passwort': f.mitPasswort,
      'herunterladen': f.herunterladen,
      'hochladen': f.hochladen,
      if (f.hochladen) 'beitraege': beitraege?.offen(f.id) ?? 0,
      // Immer, auch als `false`: Fehlt das Feld, kennt der Server keine
      // Wasserzeichen (vor #497), und die Apps legen keinen Link an, der
      // ohne das gewünschte Zeichen hinausginge.
      'wasserzeichen': f.mitWasserzeichen,
      if (zeichen != null && zeichen.text.isNotEmpty)
        'wasserzeichenText': zeichen.text,
      // Gesetzt, aber nicht mehr zu lesen: Miniatur und Ansicht antworten
      // dann mit 404 statt ohne Zeichen – hier steht, warum.
      if (f.mitWasserzeichen && zeichen == null) 'wasserzeichenUnlesbar': true,
      'aufrufe': f.aufrufe,
      'zuletzt': f.zuletzt?.toUtc().toIso8601String(),
    };
  }

  /// `{titel, album | ids, tage?, passwort?, herunterladen?, hochladen?,
  /// wasserzeichen?}` → die neue Freigabe mit ihrem Link.
  ///
  /// **`wasserzeichen`** (#497) im Format von `Wasserzeichen.alsJson`, und
  /// immer mit `bild`: einem PNG, das genau so eingerechnet wird. Auch ein
  /// Text kommt als Bild – gezeichnet vom Browser bzw. der App. Der Server
  /// zeichnet keinen Text: Das Bildpaket hat nur Bitmap-Schriften bis 48
  /// Punkt, vergrössert treppig und ohne die Zeichen jenseits von Latin-1
  /// (siehe kern/services/wasserzeichen.dart). Ein Zeichen, das sich nicht
  /// lesen lässt oder die Grenzen sprengt, wird abgelehnt (400) statt
  /// stillschweigend weggelassen – sonst ginge ein Link ohne das gewollte
  /// Zeichen hinaus.
  Future<Response> anlegen(Request r) async {
    final Object? k;
    try {
      k = jsonDecode(await r.readAsString());
    } on FormatException {
      return _json({'fehler': 'kein JSON'}, status: 400);
    }
    if (k is! Map) return _json({'fehler': 'kein JSON'}, status: 400);
    final titel = '${k['titel'] ?? ''}'.trim();
    if (titel.isEmpty || titel.length > 200) {
      return _json({'fehler': 'Titel fehlt'}, status: 400);
    }
    final konto = kontoVon(r);
    final db = (await bibliotheken.fuer(konto.id)).bibliothek.db;
    final album = k['album'];
    final ids = k['ids'];
    List<String>? aufnahmen;
    if (album is String) {
      final da = (await db.alleAlben()).any((a) => a.id == album);
      if (!da) return _json({'fehler': 'Album unbekannt'}, status: 404);
    } else if (ids is List && ids.isNotEmpty) {
      if (ids.length > Freigabedienst.hoechstensAufnahmen) {
        return _json({'fehler': 'zu viele Aufnahmen'}, status: 400);
      }
      final gewollt = {for (final x in ids) '$x'};
      // Nur, was es gibt und was nicht gesperrt oder im Papierkorb ist.
      aufnahmen = [
        for (final a in await db.assetsByIds(gewollt.toList()))
          if (!a.isLocked && !a.isTrashed) a.id,
      ];
      if (aufnahmen.isEmpty) {
        return _json({'fehler': 'keine Aufnahmen'}, status: 400);
      }
    } else {
      return _json({'fehler': 'album oder ids fehlt'}, status: 400);
    }
    final tage = k['tage'];
    if (tage != null && (tage is! int || tage < 1 || tage > 3650)) {
      return _json({'fehler': 'tage: 1 bis 3650'}, status: 400);
    }
    final passwort = k['passwort'];
    if (passwort != null &&
        (passwort is! String ||
            (passwort.isNotEmpty && passwort.length < 4) ||
            passwort.length > 200)) {
      return _json({'fehler': 'Passwort: mindestens 4 Zeichen'}, status: 400);
    }
    final hochladen = k['hochladen'] == true;
    if (hochladen && album is! String) {
      return _json({'fehler': 'Beiträge nur zu einem Album'}, status: 400);
    }
    Wasserzeichen? wasserzeichen;
    if (k['wasserzeichen'] case final roh?) {
      final gelesen = Wasserzeichen.ausJson(roh);
      final bild = gelesen?.bild;
      // Gespeichert wird nur, was hier gelesen und neu geschrieben ist:
      // das erste Bild, RGBA, nicht grösser, als es in einer Ansicht wird
      // (Wasserzeichenbild.normalisiert). In einem eigenen Isolate – das
      // Dekodieren soll keine andere Anfrage aufhalten.
      final normal = gelesen == null || bild == null
          ? null
          : await _normalisiertImIsolat(
              bild,
              (gelesen.groesse * ansichtKante).ceil(),
              ansichtKante,
            );
      if (gelesen == null || normal == null) {
        return _json({'fehler': wasserzeichenUngueltig}, status: 400);
      }
      wasserzeichen = gelesen.kopieMit(bild: normal);
    }
    final neu = await dienst.lege(
      konto: konto.id,
      titel: titel,
      album: album is String ? album : null,
      aufnahmen: aufnahmen,
      gueltig: tage is int ? Duration(days: tage) : null,
      passwortKlartext: passwort as String?,
      herunterladen: k['herunterladen'] == true,
      hochladen: hochladen && beitraege != null,
      wasserzeichen: wasserzeichen,
    );
    final f = (await dienst.von(
      konto.id,
    )).firstWhere((x) => x.freigabe.id == neu.id);
    return _json(await _alsJson(r, f.freigabe, f.link, db), status: 201);
  }

  /// Die Freigaben des Kontos: `{freigaben: [...], hinweis?}`.
  ///
  /// Lässt sich ein Link mit dem jetzigen `server.schluessel` nicht mehr
  /// lesen, steht die Freigabe mit `link: null` und `linkUnlesbar: true`
  /// da – widerrufen lässt sie sich weiter – und [linksUnlesbar] als
  /// `hinweis` darüber. Vorher antwortete die ganze Liste mit 500.
  Future<Response> liste(Request r) async {
    final konto = kontoVon(r);
    final db = (await bibliotheken.fuer(konto.id)).bibliothek.db;
    final alle = await dienst.von(konto.id);
    final gezaehlt = <String, int>{};
    return _json({
      'freigaben': [
        for (final x in alle)
          await _alsJson(r, x.freigabe, x.link, db, gezaehlt: gezaehlt),
      ],
      if (alle.any((x) => x.link == null)) 'hinweis': linksUnlesbar,
    });
  }

  /// Die Antwort auf ein Wasserzeichen, das sich nicht einrechnen lässt –
  /// die Weboberfläche übersetzt sie (texte.js).
  static const wasserzeichenUngueltig = 'Wasserzeichen ungültig';

  /// Die lange Seite der Miniatur und der Ansicht für Gäste. Breiter als in
  /// der Ansicht wird kein Wasserzeichen; so gross speichert es der Server
  /// höchstens.
  static const miniaturKante = 512;
  static const ansichtKante = 2560;

  /// Der Hinweis über der Liste, wenn Links nicht mehr zu lesen sind.
  static const linksUnlesbar =
      'Einige Links lassen sich mit dem jetzigen server.schluessel nicht '
      'mehr lesen – die Datei ist verloren gegangen oder ersetzt worden. '
      'Die alte zurücklegen, sonst diese Freigaben löschen und neu anlegen.';

  Future<Response> loeschen(Request r, String id) async {
    final konto = kontoVon(r).id;
    // Was Gäste beigetragen haben und noch nicht angenommen ist, geht mit.
    final offen = beitraege?.zu(id) ?? const <Gastbeitrag>[];
    final kennung = dienst
        .ohneLinkVon(konto)
        .where((f) => f.id == id)
        .firstOrNull
        ?.wasserzeichenKennung;
    if (!dienst.widerrufe(konto, id)) {
      return _json({'fehler': 'unbekannt'}, status: 404);
    }
    if (offen.isNotEmpty) {
      final b = (await bibliotheken.fuer(konto)).bibliothek;
      for (final x in offen) {
        await _raeumeWeg(b, x.id);
      }
    }
    if (kennung != null && !dienst.zeichenVon(konto).contains(kennung)) {
      await _raeumeZeichenWeg(
        (await bibliotheken.fuer(konto)).bibliothek,
        kennung,
      );
    }
    return _json({'geloescht': true});
  }

  /// Die Bilder mit dem Wasserzeichen [kennung] aus dem Zwischenspeicher
  /// der Gäste (#497) – gleich, nicht erst beim nächsten Aufräumen der
  /// Fassungen (`raeumeFassungenAuf` mit [Freigabedienst.zeichenVon]):
  /// Ohne den Link, der sie zeigte, sind sie nur noch unverschlüsselte
  /// Kopien auf der Platte. Teilen zwei Links desselben Kontos ein Zeichen,
  /// bleiben sie, bis der letzte geht.
  Future<void> _raeumeZeichenWeg(Bibliothek b, String kennung) async {
    final speicher = Directory(p.join(b.ordner.path, 'geteilt'));
    if (!await speicher.exists()) return;
    await for (final e in speicher.list(followLinks: false)) {
      if (e is! File) continue;
      if (teilbildAusName(p.basename(e.path))?.kennung != kennung) continue;
      try {
        await e.delete();
      } on FileSystemException {
        // Schon weg.
      }
    }
  }

  // --- Für Besucher --------------------------------------------------------

  Future<({Freigabe freigabe, Bibliothek bibliothek})?> _oeffne(
    String link,
  ) async {
    final f = dienst.fuer(link);
    if (f == null) return null;
    return (
      freigabe: f,
      bibliothek: (await bibliotheken.fuer(f.konto)).bibliothek,
    );
  }

  String _cookieName(Freigabe f) => 'pv_teilen_${f.id}';

  bool _zugelassen(Request r, Freigabe f) =>
      dienst.sitzungGilt(f, cookieWert(r, _cookieName(f)));

  Future<List<AssetData>> _aufnahmen(Freigabe f, AppDatabase db) async {
    if (f.album != null) return db.albumAufnahmen(f.album!);
    final liste = [
      for (final a in await db.assetsByIds(f.aufnahmen!))
        if (!a.isLocked && !a.isTrashed) a,
    ]..sort((a, b) => b.fileCreatedAt.compareTo(a.fileCreatedAt));
    return liste;
  }

  Future<bool> _gehoertDazu(Freigabe f, AppDatabase db, AssetData a) async {
    if (a.isLocked || a.isTrashed) return false;
    if (f.aufnahmen != null) return f.aufnahmen!.contains(a.id);
    final z =
        await (db.select(db.albumAssets)..where(
              (t) => t.albumId.equals(f.album!) & t.assetId.equals(a.id),
            ))
            .getSingleOrNull();
    return z != null;
  }

  /// Die Seite – dieselbe für jede Freigabe; was sie zeigt, holt sie sich.
  Future<Response> seite(Request r, String link) async {
    final ordner = webOrdner;
    final f = ordner == null ? null : File(p.join(ordner.path, 'teilen.html'));
    if (f == null || !await f.exists()) return Response.notFound('nicht da');
    return Response.ok(
      f.openRead(),
      headers: {
        'content-type': 'text/html; charset=utf-8',
        'cache-control': 'no-store',
        'content-security-policy': Webapi.csp,
        ..._keineSuche,
      },
    );
  }

  /// `{titel, herunterladen, ablauf, aufnahmen}`; 401 `{passwort: true}`,
  /// solange das Passwort fehlt.
  Future<Response> inhalt(Request r, String link) async {
    final o = await _oeffne(link);
    if (o == null) {
      return _json({'fehler': 'unbekannt'}, status: 404, kopf: _keineSuche);
    }
    final f = o.freigabe;
    if (!_zugelassen(r, f)) {
      return _json({'passwort': true}, status: 401, kopf: _keineSuche);
    }
    dienst.aufgerufen(f);
    final liste = await _aufnahmen(f, o.bibliothek.db);
    return _json({
      'titel': f.titel,
      'herunterladen': f.herunterladen,
      'hochladen': f.hochladen && beitraege != null,
      'ablauf': f.ablauf?.toUtc().toIso8601String(),
      'aufnahmen': [
        for (final a in liste)
          {
            'id': a.id,
            'art': a.type == 'VIDEO' ? 'video' : 'bild',
            'aufgenommen': a.anzeigeDatum.toIso8601String(),
            'datierung': ?a.kalenderdatierung?.alsJson(),
            if (a.widthPx != null) 'breite': a.widthPx,
            if (a.heightPx != null) 'hoehe': a.heightPx,
            if (a.durationSeconds != null) 'dauer': a.durationSeconds,
          },
      ],
    }, kopf: _keineSuche);
  }

  /// `{passwort}` → 204 mit Cookie; 401 bei falschem, 429 nach zu vielen
  /// – von dieser Adresse oder für diese Freigabe.
  Future<Response> passwort(Request r, String link) async {
    final adresse = absender.von(r);
    final warten = bremse.wartezeit(adresse);
    if (warten != null) {
      return _json(
        {'fehler': 'zu viele Versuche', 'warten': warten.inSeconds},
        status: 429,
        kopf: {'retry-after': '${warten.inSeconds + 1}'},
      );
    }
    final o = await _oeffne(link);
    if (o == null) return _json({'fehler': 'unbekannt'}, status: 404);
    final Object? k;
    try {
      k = jsonDecode(await r.readAsString());
    } on FormatException {
      return _json({'fehler': 'kein JSON'}, status: 400);
    }
    final klartext = k is Map ? '${k['passwort'] ?? ''}' : '';
    if (klartext.isEmpty || klartext.length > 200) {
      bremse.fehlschlag(adresse);
      return _json({'fehler': 'Passwort falsch'}, status: 401);
    }
    final ergebnis = await dienst.pruefePasswort(o.freigabe, klartext);
    if (ergebnis.warte case final w?) {
      return _json(
        {'fehler': 'zu viele Versuche', 'warten': w.inSeconds},
        status: 429,
        kopf: {'retry-after': '${w.inSeconds + 1}'},
      );
    }
    if (!ergebnis.stimmt) {
      bremse.fehlschlag(adresse);
      return _json({'fehler': 'Passwort falsch'}, status: 401);
    }
    final sicher = absender.verschluesselt(r);
    return Response(
      204,
      headers: {
        'set-cookie': [
          '${_cookieName(o.freigabe)}=${dienst.sitzung(o.freigabe)}',
          'Path=/',
          'Max-Age=${Freigabedienst.sitzungsdauer.inSeconds}',
          'HttpOnly',
          'SameSite=Lax',
          if (sicher) 'Secure',
        ].join('; '),
        'cache-control': 'no-store',
      },
    );
  }

  /// `miniatur` und `ansicht` (Bilder, ohne Metadaten), `video` (H.264,
  /// sonst 202 wie bei `abspielbar`), `original` (nur mit Herunterladen).
  ///
  /// **Das Wasserzeichen** der Freigabe (#497) steckt in Miniatur und
  /// Ansicht – auch in der Miniatur eines Videos, sie ist ein Bild. Nicht
  /// im `original`: Das hat der Besitzer ausdrücklich zum Herunterladen
  /// freigegeben, und es heisst Original, weil es Bit für Bit die Datei
  /// ist (der Dialog sagt das beim Anlegen). Nicht im `video`: Dafür
  /// müsste ffmpeg das Zeichen in jedes Bild legen und die Fassung je
  /// Zeichen eigens gerechnet werden – nicht Teil dieses Schritts; auch
  /// das sagt der Dialog.
  Future<Response> datei(Request r, String link, String id, String art) async {
    final o = await _oeffne(link);
    if (o == null) return Response.notFound(null, headers: _keineSuche);
    final f = o.freigabe;
    if (!_zugelassen(r, f)) return Response(401, headers: _keineSuche);
    final b = o.bibliothek;
    final a = await b.db.assetById(id);
    if (a == null || !await _gehoertDazu(f, b.db, a)) {
      return Response.notFound(null, headers: _keineSuche);
    }
    File? ausDer(String? relativ) {
      if (relativ == null) return null;
      final d = b.pfade.absolute(relativ);
      return p.isWithin(b.pfade.root.path, d.path) ? d : null;
    }

    final speicher = Directory(p.join(b.ordner.path, 'geteilt'));
    // Ein Zeichen ist gesetzt, aber seine Kennung fehlt: Dann gibt es keine
    // Bilder (404) statt solcher ohne Zeichen. Gelesen wird das Zeichen
    // erst, wenn ein Bild neu zu rechnen ist.
    final kennung = f.wasserzeichenKennung;
    if (f.mitWasserzeichen &&
        kennung == null &&
        (art == 'miniatur' || art == 'ansicht')) {
      return Response.notFound(null);
    }
    final Teilbildzeichen? zeichen = kennung == null
        ? null
        : (kennung: kennung, laden: () => dienst.wasserzeichenVon(f));
    switch (art) {
      case 'miniatur':
        final q = ausDer(a.thumbnailRelativePath);
        if (q == null || !await q.exists()) return Response.notFound(null);
        final d = await _teilbilder.fassung(
          speicher,
          teilbildName(a.id, 'm', kennung),
          q,
          kante: miniaturKante,
          zeichen: zeichen,
        );
        return d == null ? Response.notFound(null) : dateiAntwort(r, d);
      case 'ansicht':
        if (a.type == 'VIDEO') return Response.notFound(null);
        final q = ausDer(displayRelativePath(a));
        if (q == null || !await q.exists()) return Response.notFound(null);
        final d = await _teilbilder.fassung(
          speicher,
          teilbildName(a.id, 'a', kennung),
          q,
          kante: ansichtKante,
          zeichen: zeichen,
        );
        return d == null ? Response.notFound(null) : dateiAntwort(r, d);
      case 'video':
        if (a.type != 'VIDEO') return Response.notFound(null);
        final q = ausDer(a.trimmedRelativePath ?? a.relativePath);
        if (q == null || !await q.exists()) return Response.notFound(null);
        final name = a.trimmedRelativePath != null ? '${a.id}-gekuerzt' : a.id;
        final abspielbar = Directory(p.join(b.ordner.path, 'abspielbar'));
        final fertig = await video.bereit(abspielbar, name, q, gast: true);
        if (fertig != null) {
          return r.url.queryParameters['pruefen'] != null
              ? _json({'bereit': true})
              : dateiAntwort(r, fertig);
        }
        return video.gescheitert.contains(
              Videofassungen.ziel(abspielbar, name).path,
            )
            ? _json({'bereit': false}, status: 422)
            : _json({'bereit': false}, status: 202);
      case 'original':
        if (!f.herunterladen) return Response.notFound(null);
        final q = ausDer(a.relativePath);
        if (q == null || !await q.exists()) return Response.notFound(null);
        final antwort = await dateiAntwort(r, q);
        // Nur ASCII im einfachen Namen: dart:io lehnt alles andere in einer
        // Kopfzeile ab, und der Gast wartete ohne Antwort (#311).
        final einfach = a.originalFileName.replaceAll(
          RegExp(r'[^A-Za-z0-9._ -]'),
          '_',
        );
        return antwort.change(
          headers: {
            'content-disposition':
                'attachment; filename="$einfach"; '
                "filename*=UTF-8''${Uri.encodeComponent(a.originalFileName)}",
          },
        );
    }
    return Response.notFound(null);
  }

  // --- Beiträge von Gästen (Issue #106) ------------------------------------
  //
  // Ein Gast schickt eine Datei; sie landet als Beitrag im Ordner `gaeste`
  // der Bibliothek, läuft durch den abgeschotteten Prüfprozess
  // (gastpruefung.dart) und wartet dann auf den Besitzer. Erst sein Ja
  // nimmt die *geprüfte* Fassung in die Bibliothek und ins Album; das
  // Original des Gastes ist da längst gelöscht.

  Directory _ordner(Bibliothek b, String id) =>
      Directory(p.join(b.ordner.path, 'gaeste', id));

  Future<void> _raeumeWeg(Bibliothek b, String id) async {
    beitraege?.entferne(id);
    final d = _ordner(b, id);
    if (await d.exists()) await d.delete(recursive: true);
  }

  /// Ob [adresse] in der letzten Stunde schon [beitraegeJeStunde] Dateien
  /// geschickt hat; sonst zählt diese mit. Wie bei der [Bremse] rückt die
  /// gezählte Adresse ans Ende, und bei zu vielen Adressen gehen erst die
  /// abgelaufenen, dann die ältesten – vorher die zuerst eingetragene, auch
  /// wenn das die gerade gezählte war.
  bool _zuViele(String adresse) {
    final jetzt = DateTime.now();
    bool alt(DateTime t) => jetzt.difference(t) > const Duration(hours: 1);
    final liste = (_jeAbsender.remove(adresse) ?? <DateTime>[])
      ..removeWhere(alt);
    final zuViele = liste.length >= beitraegeJeStunde;
    if (!zuViele) liste.add(jetzt);
    if (_jeAbsender.length >= Bremse.hoechstensEintraege) {
      _jeAbsender.removeWhere((_, l) => l.isEmpty || alt(l.last));
      final ueber = _jeAbsender.length - Bremse.hoechstensEintraege * 9 ~/ 10;
      for (final k in _jeAbsender.keys.take(max(0, ueber)).toList()) {
        _jeAbsender.remove(k);
      }
    }
    _jeAbsender[adresse] = liste;
    return zuViele;
  }

  /// Eine Datei von einem Gast: der Körper ist die Datei, `?name=` ihr
  /// Name, `?von=` der Name des Gastes, `?geaendert=` ihre Änderungszeit
  /// in Millisekunden. → 202 `{id}`; geprüft wird danach.
  ///
  /// **Grenzen (#426).** 503 mit `Retry-After`, solange der Absender oder
  /// der Link schon genug gleichzeitig schickt oder zu viele Beiträge auf
  /// die Prüfung warten; 429 bei zu vielen Dateien je Stunde oder zu
  /// vielen offenen Beiträgen (Anzahl und Bytes) am Link; 507, wenn die
  /// Datei samt allem, was gerade ankommt, den Platz unter
  /// [Speicherwaechter.mindestFrei] drücken würde.
  Future<Response> beitrag(Request r, String link) async {
    // Nur aus der Seite der Freigabe: Ein Formular auf einer fremden
    // Seite soll niemandem Dateien unterschieben.
    final seite = r.headers['sec-fetch-site'];
    if (r.headers['x-pv-teilen'] != '1' ||
        (seite != null && seite != 'same-origin')) {
      return _json({'fehler': 'nicht erlaubt'}, status: 403);
    }
    final o = await _oeffne(link);
    final ablage = beitraege;
    if (o == null || ablage == null || !o.freigabe.hochladen) {
      return _json({'fehler': 'unbekannt'}, status: 404, kopf: _keineSuche);
    }
    final f = o.freigabe;
    if (!_zugelassen(r, f)) return _json({'passwort': true}, status: 401);
    if (speicher?.voll ?? false) {
      return _json({'fehler': 'Der Speicher ist voll.'}, status: 507);
    }
    final laenge = int.tryParse(r.headers['content-length'] ?? '');
    if (laenge == null) return _json({'fehler': 'Länge fehlt'}, status: 411);
    if (laenge <= 0 || laenge > hoechstensBeitrag) {
      return _json({'fehler': 'Datei zu gross'}, status: 413);
    }
    final adresse = absender.von(r);
    // Erst, was nur warten heisst (503, die Seite versucht es wieder) …
    if ((_laufendJeAbsender[adresse] ?? 0) >= gleichzeitigJeAbsender ||
        (_laufendJeFreigabe[f.id] ?? 0) >= gleichzeitigJeFreigabe) {
      return _spaeter(5);
    }
    if (ablage.inPruefung() >= hoechstensInPruefung) return _spaeter(30);
    // … dann, was erst der Besitzer wieder frei macht.
    if (ablage.offen(f.id) >= Gastbeitraege.hoechstensOffen ||
        ablage.offeneBytes(f.id) + laenge > hoechstensOffeneBytes ||
        _zuViele(adresse)) {
      return _json({'fehler': 'zu viele Dateien'}, status: 429);
    }
    // Ob diese Datei mit allem, was gerade ankommt, noch passt; zugesagt
    // wird mit dem Gelesenen (Speicherwaechter.sageZu, #483).
    final platz = speicher?.sageZu(laenge);
    if (speicher != null && platz == null) {
      return _json({'fehler': 'Der Speicher ist voll.'}, status: 507);
    }
    final q = r.url.queryParameters;
    final von = (q['von'] ?? '').trim();
    final eintrag = ablage.lege(
      freigabe: f.id,
      konto: f.konto,
      name: q['name'] ?? 'beitrag',
      von: von.isEmpty ? null : (von.length > 80 ? von.substring(0, 80) : von),
      groesse: laenge,
      absender: adresse,
    );
    _zaehle(_laufendJeAbsender, adresse, 1);
    _zaehle(_laufendJeFreigabe, f.id, 1);
    final b = o.bibliothek;
    final ordner = _ordner(b, eintrag.id);
    final roh = File(p.join(ordner.path, 'eingang'));
    var angekommen = false;
    try {
      await ordner.create(recursive: true);
      final geschrieben = await schreibeUpload(
        r.read(),
        roh,
        laenge: laenge,
        platz: platz,
        leerlauf: leerlauf,
      );
      if (geschrieben != laenge) {
        await _raeumeWeg(b, eintrag.id);
        return _json({'fehler': 'unvollständig'}, status: 400);
      }
      angekommen = true;
    } on TimeoutException {
      await _raeumeWeg(b, eintrag.id);
      return _json(
        {'fehler': 'Zeitüberschreitung'},
        status: 408,
        kopf: {'connection': 'close'},
      );
    } on SpeicherVoll {
      await _raeumeWeg(b, eintrag.id);
      return _json(
        {'fehler': 'Der Speicher ist voll.'},
        status: 507,
        kopf: {'connection': 'close'},
      );
    } catch (e) {
      await _raeumeWeg(b, eintrag.id);
      rethrow;
    } finally {
      _zaehle(_laufendJeAbsender, adresse, -1);
      _zaehle(_laufendJeFreigabe, f.id, -1);
      platz?.gib(geschrieben: angekommen);
    }
    final geaendert = zeitAusText(q['geaendert']);
    unawaited(_pruefe(b, eintrag.id, roh, geaendert));
    return _json({'id': eintrag.id}, status: 202);
  }

  /// 503 mit `Retry-After`: gerade zu viel auf einmal, gleich wieder.
  static Response _spaeter(int sekunden) => _json(
    {'fehler': 'gerade zu viele Dateien auf einmal', 'warten': sekunden},
    status: 503,
    kopf: {'retry-after': '$sekunden'},
  );

  static void _zaehle(Map<String, int> zaehler, String wer, int um) {
    final n = (zaehler[wer] ?? 0) + um;
    if (n <= 0) {
      zaehler.remove(wer);
    } else {
      zaehler[wer] = n;
    }
  }

  Future<void> _pruefe(
    Bibliothek b,
    String id,
    File roh,
    int? geaendert,
  ) async {
    if (!_inPruefung.add(id)) return;
    try {
      // Nur die ersten Bytes, ohne Decoder: Bild oder nicht entscheidet,
      // wie lange der Prüfprozess darf.
      final kopf = await roh.openRead(0, 64).expand((x) => x).toList();
      final ergebnis = await pruefung.pruefe(
        roh,
        Directory(p.join(roh.parent.path, 'geprueft')),
        video: kennungAus(kopf) == null,
      );
      final befund = {...ergebnis.befund, 'geaendert': ?geaendert};
      beitraege?.geprueft(id, ok: ergebnis.ok, befund: befund);
      if (!ergebnis.ok) {
        final g = Directory(p.join(roh.parent.path, 'geprueft'));
        if (await g.exists()) await g.delete(recursive: true);
      }
    } catch (e) {
      protokoll('Gastbeitrag $id: Prüfung gescheitert – $e');
      beitraege?.geprueft(
        id,
        ok: false,
        befund: {'grund': 'Prüfung gescheitert'},
      );
    } finally {
      // Die Bytes des Gastes werden nicht aufgehoben.
      if (await roh.exists()) await roh.delete();
      _inPruefung.remove(id);
    }
  }

  Map<String, Object?> _beitragJson(Gastbeitrag x, Map<String, Freigabe> f) {
    final bf = x.befund;
    return {
      'id': x.id,
      'freigabe': {'id': x.freigabe, 'titel': f[x.freigabe]?.titel},
      'name': x.name,
      'von': x.von,
      'groesse': x.groesse,
      'zustand': x.zustand,
      'art': ?bf['art'],
      'breite': ?bf['breite'],
      'hoehe': ?bf['hoehe'],
      'dauer': ?bf['dauer'],
      'aufgenommen': ?bf['aufgenommen'],
      'grund': ?bf['grund'],
      'angelegt': x.angelegt.toUtc().toIso8601String(),
    };
  }

  /// Die Beiträge aller Freigaben des Kontos und wie geprüft wird.
  Future<Response> beitragsliste(Request r) async {
    final konto = kontoVon(r).id;
    final ablage = beitraege;
    if (ablage == null) return _json({'beitraege': const []});
    final b = (await bibliotheken.fuer(konto)).bibliothek;
    final liste = ablage.von(konto);
    // Nach einem Neustart: was noch wartete, weiter prüfen.
    for (final x in liste) {
      if (x.zustand != 'pruefung' || _inPruefung.contains(x.id)) continue;
      final roh = File(p.join(_ordner(b, x.id).path, 'eingang'));
      if (await roh.exists()) {
        unawaited(_pruefe(b, x.id, roh, null));
      } else {
        ablage.geprueft(x.id, ok: false, befund: {'grund': 'unterbrochen'});
      }
    }
    final freigaben = {for (final f in dienst.ohneLinkVon(konto)) f.id: f};
    final a = await pruefung.abschottung;
    return _json({
      'beitraege': [
        for (final x in ablage.von(konto)) _beitragJson(x, freigaben),
      ],
      'abgeschottet': a.ohneNetz,
    });
  }

  Future<({Gastbeitrag beitrag, Bibliothek bibliothek})?> _eigener(
    Request r,
    String id,
  ) async {
    final konto = kontoVon(r).id;
    final x = beitraege?.eines(konto, id);
    if (x == null) return null;
    return (
      beitrag: x,
      bibliothek: (await bibliotheken.fuer(konto)).bibliothek,
    );
  }

  /// Die Vorschau der geprüften Fassung.
  Future<Response> beitragVorschau(Request r, String id) async {
    final e = await _eigener(r, id);
    if (e == null || e.beitrag.zustand != 'bereit') {
      return Response.notFound(null);
    }
    final d = File(
      p.join(_ordner(e.bibliothek, id).path, 'geprueft', 'vorschau.jpg'),
    );
    return await d.exists() ? dateiAntwort(r, d) : Response.notFound(null);
  }

  /// Nimmt die geprüfte Fassung in die Bibliothek und ins Album.
  Future<Response> beitragAnnehmen(Request r, String id) async {
    final e = await _eigener(r, id);
    if (e == null) return _json({'fehler': 'unbekannt'}, status: 404);
    final x = e.beitrag;
    if (x.zustand != 'bereit') {
      return _json({'fehler': 'noch nicht geprüft'}, status: 409);
    }
    final b = e.bibliothek;
    final ordner = _ordner(b, id);
    final endung = '${x.befund['endung'] ?? ''}';
    final sauber = File(p.join(ordner.path, 'geprueft', 'sauber$endung'));
    final zuImport = Directory(p.join(ordner.path, 'import'));
    if (const {'.jpg', '.mp4'}.contains(endung) &&
        !await sauber.exists() &&
        await zuImport.exists()) {
      // Ein früherer Versuch scheiterte nach dem Umbenennen und liess die
      // Datei im Ordner `import` liegen; danach hiess es immer „Datei
      // fehlt“. Zurück an ihren Platz.
      final reste = await zuImport
          .list()
          .where((d) => d is File && p.extension(d.path) == endung)
          .toList();
      if (reste.length == 1) await (reste.single as File).rename(sauber.path);
    }
    if (!const {'.jpg', '.mp4'}.contains(endung) || !await sauber.exists()) {
      return _json({'fehler': 'Datei fehlt'}, status: 410);
    }
    // Unter dem Namen des Gastes, mit der Endung der neuen Fassung – der
    // Import nimmt den Namen aus dem Pfad.
    final grund = p.basenameWithoutExtension(x.name);
    await zuImport.create();
    final datei = await sauber.rename(
      p.join(zuImport.path, '${grund.isEmpty ? 'beitrag' : grund}$endung'),
    );
    // Was auch scheitert: Die Datei geht an ihren Platz zurück, und der
    // Beitrag lässt sich noch einmal annehmen oder ablehnen.
    Future<void> zurueck() async {
      if (await datei.exists()) await datei.rename(sauber.path);
      if (await zuImport.exists()) await zuImport.delete(recursive: true);
    }

    final ImportResult ergebnis;
    String? aufnahme;
    try {
      // Auch eine Zeit, die vor dieser Prüfung gespeichert wurde.
      if (zeitpunktAus(x.befund['geaendert']) case final zeit?) {
        await datei.setLastModified(zeit);
      }
      ergebnis = await b.importe.importFile(datei.path);
      aufnahme = ergebnis.assetId;
      if (ergebnis.outcome == ImportOutcome.imported && aufnahme != null) {
        try {
          await b.nachbearbeitung.neueAufnahme(aufnahme);
        } catch (f) {
          protokoll('Nachbearbeitung eines Gastbeitrags gescheitert: $f');
        }
        (await bibliotheken.fuer(x.konto)).auswertung.anstossen();
      } else if (ergebnis.outcome == ImportOutcome.duplicateSkipped) {
        aufnahme = await b.kennungFuer(
          (await sha256.bind(datei.openRead()).first).toString(),
        );
        // Liegt sie gesperrt oder im Papierkorb, holt der Beitrag eines
        // Gastes sie nicht ins Album; der Beitrag bleibt zum Ablehnen.
        if (aufnahme != null && await b.verborgen(aufnahme)) {
          await zurueck();
          return _json({
            'fehler':
                'Diese Aufnahme liegt schon in der Bibliothek, gesperrt oder '
                'im Papierkorb. Ins Album kommt sie so nicht.',
          }, status: 409);
        }
      }
      if (aufnahme == null) {
        await zurueck();
        return _json({
          'fehler': 'Import gescheitert: ${ergebnis.error}',
        }, status: 500);
      }
      // Ohne den Link: Den braucht es hier nicht, und nach einem
      // ersetzten server.schluessel liesse er sich nicht lesen.
      final album = dienst
          .ohneLinkVon(x.konto)
          .where((f) => f.id == x.freigabe)
          .firstOrNull
          ?.album;
      // Ein inzwischen gelöschtes Album fällt weg, das Foto kommt trotzdem
      // herein – wie bei einer Regel mit gelöschtem Zielalbum (IMP-024).
      // Vorher lag es danach in einem Album, das es nicht gibt, und war nur
      // noch über den Link zu sehen.
      if (album != null && await b.db.albumVorhanden(album)) {
        await b.db.fuehreAus(
          AlbumFuellen(album, [await b.db.sichtbareFassung(aufnahme)]),
        );
      }
    } catch (_) {
      await zurueck();
      rethrow;
    }
    await _raeumeWeg(b, id);
    return _json({'aufnahme': aufnahme, 'ausgang': ergebnis.outcome.name});
  }

  /// Lehnt einen Beitrag ab: Er verschwindet samt Dateien.
  Future<Response> beitragAblehnen(Request r, String id) async {
    final e = await _eigener(r, id);
    if (e == null) return _json({'fehler': 'unbekannt'}, status: 404);
    await _raeumeWeg(e.bibliothek, id);
    return _json({'geloescht': true});
  }
}

/// [Wasserzeichenbild.normalisiert] in einem eigenen Isolate – auf oberster
/// Ebene, damit der Abschluss nichts aus [Freigabeapi] mitnimmt.
Future<Uint8List?> _normalisiertImIsolat(
  Uint8List bild,
  int breite,
  int hoehe,
) => Isolate.run(
  () => Wasserzeichenbild.normalisiert(
    bild,
    hoechstensBreite: breite,
    hoechstensHoehe: hoehe,
  ),
);
