import 'anfragegrenzen.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:drift/drift.dart';
import 'package:http/http.dart' as http;
import 'package:kern/auswertung/gesicht_von_hand.dart';
import 'package:kern/db/database.dart';
import 'package:kern/db/listenangaben.dart';
import 'package:kern/db/rasterzeile.dart';
import 'package:kern/services/asset_format.dart' show bildendung;
import 'package:kern/services/asset_display_path.dart';
import 'package:kern/services/aufnahmeangaben.dart';
import 'package:kern/services/bibliothekseinstellungen.dart';
import 'package:kern/services/cube_lut.dart';
import 'package:kern/services/datumsvorschlag.dart';
import 'package:kern/services/develop_color.dart';
import 'package:kern/services/duplikatsuche.dart';
import 'package:kern/services/embedding_similarity.dart';
import 'package:kern/services/geometrie.dart' as g;
import 'package:kern/services/collage.dart';
import 'package:kern/services/import_service.dart'
    show Datumsbefund, ImportOutcome;
import 'package:kern/services/jpeg_angaben.dart';
import 'package:kern/services/gesichtsuebersicht.dart' as gesichtsuebersicht;
import 'package:kern/services/kartengruppen.dart';
import 'package:kern/services/laendernamen.dart';
import 'package:kern/services/ortsuebersicht.dart';
import 'package:kern/services/lebensbaumansicht.dart';
import 'package:kern/services/lebensbaum_bild.dart';
import 'package:kern/services/reiseuebersicht.dart';
import 'package:kern/services/verwandtschaftsgrad.dart';
import 'package:kern/services/wanderobjekte.dart';
import 'package:kern/services/rueckblick.dart';
import 'package:kern/services/sortierung.dart';
import 'package:kern/services/stammbaum.dart';
import 'package:kern/services/stammbaumansicht.dart';
import 'package:kern/services/zierbaum.dart';
import 'package:kern/protokoll.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'abgleich_api.dart';
import 'albumregeln.dart';
import 'albumteilungen.dart';
import 'papierkorb.dart';
import 'absender.dart';
import 'anmeldung_api.dart';
import 'bibliothek.dart';
import 'bibliotheken.dart';
import 'dateiantwort.dart';
import 'fassung.dart';
import 'freigabe_api.dart';
import 'konten/kontodienst.dart';
import 'nachlass.dart';
import 'konten_api.dart';
import 'gastpruefung.dart';
import 'oidc.dart';
import 'passkey_api.dart';
import 'packen.dart';
import 'rechnen.dart';
import 'sicherung.dart';
import 'speicher.dart';
import 'teilung_api.dart';
import 'suche_api.dart';
import 'umzug.dart';
import 'videofassung.dart';
import 'vollbild.dart';
import 'web.dart';
import 'rueckblick_api.dart';
import 'zeilen_json.dart';

/// Welche Fassung der Schnittstelle der Server spricht. Steigt, sobald sich
/// etwas so ändert, dass ein älterer Client es falsch verstünde.
///
/// 2: Konten und Geräte-Tokens statt des einen Schlüssels.
const protokollFassung = 2;

/// Die Schnittstelle unter `/api/v1`.
///
/// Ohne Anmeldung erreichbar sind nur das Lebenszeichen und die Wege der
/// Anmeldung selbst; alles andere braucht das Token eines Geräts und
/// arbeitet dann auf der Bibliothek von dessen Konto.
Handler baueApi({
  required Kontodienst konten,
  required Bibliotheken bibliotheken,
  Absender? absender,
  Oidc? oidc,
  Future<Map<String, Object?>> Function()? beschleunigerZustand,
  Speicherwaechter? speicher,
  Serversicherung? sicherung,
  Directory? web,
  Uri? oeffentlich,
  Gastpruefung? gastpruefung,
  http.Client? netz,
}) {
  final von = absender ?? Absender();
  final oberflaeche = web == null ? null : Webapi(konten, von, ordner: web);
  final anmeldung = Anmeldungsapi(konten, von, oidc);
  final passkeys = Passkeyapi(konten, von);
  final video = Videofassungen();
  final api = _Api(
    bibliotheken,
    beschleunigerZustand,
    video,
    netz,
    vollbilder: Vollbilder(),
    teilungen: konten.albumteilungen,
    regeln: konten.albumregeln,
    kontoname: (id) => konten.konto(id)?.name,
  );
  final freigabe = Freigabeapi(
    dienst: konten.freigaben,
    bibliotheken: bibliotheken,
    absender: von,
    video: video,
    webOrdner: web,
    oeffentlich: oeffentlich,
    beitraege: konten.beitraege,
    pruefung: gastpruefung,
    speicher: speicher,
  );
  final teilung = Teilungsapi(
    konten: konten,
    bibliotheken: bibliotheken,
    datei: api.dateiAus,
    speicher: speicher,
  );
  final nachlass = Nachlassapi(konten);
  final abgleich = Abgleichsapi(bibliotheken);
  final umzug = Umzugsdienst(bibliotheken);
  final suche = Suchapi(bibliotheken);
  final rueckblick = Rueckblickapi(bibliotheken);
  final rechnen = Rechenapi(bibliotheken);
  final kontenapi = Kontenapi(konten, bibliotheken);
  Future<Kontobereich> bereich(Request r) => bibliotheken.fuer(kontoVon(r).id);

  /// Bei vollem Speicher keine neuen Daten (siehe [Speicherwaechter]).
  Handler wennPlatz(Handler h) =>
      (r) => speicher?.voll ?? false ? _speicherVoll() : h(r);

  final r = Router()
    // Wer die Adresse im Browser öffnet, sah bisher nur „nicht angemeldet“
    // und hielt den Server für kaputt.
    ..get(
      '/',
      (Request _) => oberflaeche == null
          ? schlichteSeite(
              'Der Server läuft. Eine Weboberfläche hat er nicht: Verbunden '
              'wird über die App – am Rechner unter Einstellungen → Server, '
              'auf dem Telefon beim ersten Start – mit dieser Adresse.',
            )
          : schlichteSeite(
              'Der Server läuft. Verbunden wird über die App – am Rechner '
              'unter Einstellungen → Server, auf dem Telefon beim ersten '
              'Start – mit dieser Adresse. Oder im Browser:',
              linkZiel: '/app/',
              linkText: 'Weboberfläche öffnen',
            ),
    )
    ..get(
      '/api/v1/zustand',
      (Request r) => api.zustand(
        konten,
        oidc,
        einrichten: !konten.eingerichtet && von.ausDemHeimnetz(r),
      ),
    )
    ..post('/api/v1/einrichten', anmeldung.einrichten)
    ..get('/api/v1/konten', kontenapi.liste)
    ..post('/api/v1/konten', kontenapi.anlegen)
    ..post('/api/v1/konten/<id>/passwort', kontenapi.passwort)
    ..post(
      '/api/v1/konten/<id>/totp-zuruecksetzen',
      kontenapi.totpZuruecksetzen,
    )
    ..post('/api/v1/konten/<id>/entsperren', kontenapi.entsperren)
    ..delete('/api/v1/konten/<id>', kontenapi.entfernen)
    ..post('/api/v1/anmelden', anmeldung.anmelden)
    ..get(
      '/app',
      (Request _) => oberflaeche == null
          ? Response.notFound('nicht da')
          : Response.found('/app/', headers: {'cache-control': 'no-store'}),
    )
    ..get(
      '/app/',
      (Request r) => oberflaeche?.seite(r) ?? Response.notFound('nicht da'),
    )
    ..get(
      '/app/<name>',
      (Request r, String name) =>
          oberflaeche?.datei(r, name) ?? Response.notFound('nicht da'),
    )
    ..get(
      '/app/leaflet/<name>',
      (Request r, String name) =>
          oberflaeche?.datei(r, name, ordnerName: 'leaflet') ??
          Response.notFound('nicht da'),
    )
    ..get(
      '/app/leaflet/images/<name>',
      (Request r, String name) =>
          oberflaeche?.datei(r, name, ordnerName: 'leaflet/images') ??
          Response.notFound('nicht da'),
    )
    ..get(
      '/app/lebensbaum/<name>',
      (Request r, String name) =>
          oberflaeche?.datei(r, name, ordnerName: 'lebensbaum') ??
          Response.notFound('nicht da'),
    )
    ..get(
      '/app/maplibre/<name>',
      (Request r, String name) =>
          oberflaeche?.datei(r, name, ordnerName: 'maplibre') ??
          Response.notFound('nicht da'),
    )
    ..get(
      '/app/mp4muxer/<name>',
      (Request r, String name) =>
          oberflaeche?.datei(r, name, ordnerName: 'mp4muxer') ??
          Response.notFound('nicht da'),
    )
    ..get(
      '/app/schrift/<name>',
      (Request r, String name) =>
          oberflaeche?.datei(r, name, ordnerName: 'schrift') ??
          Response.notFound('nicht da'),
    )
    ..post(
      '/api/v1/web/anmelden',
      (Request r) => oberflaeche?.anmelden(r) ?? Response.notFound('nicht da'),
    )
    ..post(
      '/api/v1/web/anmelden/totp',
      (Request r) => oberflaeche?.totp(r) ?? Response.notFound('nicht da'),
    )
    ..post(
      '/api/v1/web/abmelden',
      (Request r) => oberflaeche?.abmelden(r) ?? Response.notFound('nicht da'),
    )
    ..get(
      '/api/v1/web/sitzung',
      (Request r) => oberflaeche?.sitzung(r) ?? Response.notFound('nicht da'),
    )
    ..post('/api/v1/anmelden/totp', anmeldung.totp)
    ..post(
      '/api/v1/web/anmelden/passkey',
      (Request r) => oberflaeche?.passkey(r) ?? Response.notFound('nicht da'),
    )
    ..post('/api/v1/anmelden/passkey/optionen', passkeys.anmeldeoptionen)
    ..post('/api/v1/anmelden/passkey', passkeys.anmeldenFuerGeraet)
    ..post('/api/v1/anmelden/passkey/einloesen', passkeys.einloesen)
    ..get('/api/v1/konto/passkeys', passkeys.liste)
    ..post('/api/v1/konto/passkeys/optionen', passkeys.anlegeoptionen)
    ..post('/api/v1/konto/passkeys/ticket', passkeys.ticket)
    ..post('/api/v1/konto/passkeys', passkeys.anlegen)
    ..delete('/api/v1/konto/passkeys/<id>', passkeys.entfernen)
    ..post('/api/v1/passkeys/ticket/optionen', passkeys.ticketoptionen)
    ..post('/api/v1/passkeys/ticket', passkeys.ticketanlegen)
    ..get('/api/v1/anmelden/oidc', anmeldung.oidcStart)
    ..get('/api/v1/anmelden/oidc/zurueck', anmeldung.oidcZurueck)
    ..post('/api/v1/anmelden/oidc/einloesen', anmeldung.oidcEinloesen)
    ..post('/api/v1/abmelden', anmeldung.abmelden)
    ..get('/api/v1/konto', anmeldung.konto)
    ..post('/api/v1/konto/passwort', anmeldung.passwort)
    ..post('/api/v1/konto/wiederherstellungscodes', anmeldung.codes)
    ..post('/api/v1/konto/oidc', anmeldung.oidcVerknuepfen)
    ..get('/api/v1/geraete', anmeldung.geraete)
    ..delete('/api/v1/geraete/<id>', anmeldung.geraetAbmelden)
    ..get('/api/v1/bibliothek', api.bibliothek)
    ..get('/api/v1/aufnahmen', api.aufnahmen)
    ..get('/api/v1/zeitleiste/monate', api.zeitleistenmonate)
    ..get('/api/v1/aufnahmen/<id>', api.aufnahme)
    ..get('/api/v1/aufnahmen/<id>/angaben', api.angaben)
    ..post('/api/v1/aufnahmen/<id>/gesichter', api.gesichtAnlegen)
    ..get('/api/v1/aufnahmen/<id>/<art>', api.datei)
    ..get('/api/v1/serien/<id>', api.serie)
    ..post('/api/v1/pruefsummen', api.pruefsummen)
    ..post('/api/v1/befehle', abgleich.befehle)
    ..get('/api/v1/abgleich/stand', abgleich.stand)
    ..get('/api/v1/abgleich/aenderungen', abgleich.aenderungen)
    ..post('/api/v1/abgleich/zeilen', abgleich.zeilen)
    ..get('/api/v1/abgleich/abzug', abgleich.abzug)
    ..get('/api/v1/dateien/<pfad|.+>', abgleich.datei)
    ..put(
      '/api/v1/dateien/<pfad|.+>',
      wennPlatz((Request r) => abgleich.dateiAblegen(r, r.params['pfad']!)),
    )
    ..post('/api/v1/suche/text', suche.text)
    ..get('/api/v1/suche', suche.suche)
    ..get('/api/v1/datierung', suche.datierung)
    ..get('/api/v1/suche/auswahl', suche.auswahl)
    ..get('/api/v1/intelligente-alben', suche.intelligenteAlben)
    ..post('/api/v1/intelligente-alben', suche.albumMerken)
    ..get('/api/v1/intelligente-alben/<id>', suche.inhaltDesAlbums)
    ..get('/api/v1/reisen', api.reisen)
    ..get('/api/v1/reisen/<id>', api.reiseAufnahmen)
    ..get('/api/v1/aktivitaeten/<id>', api.aktivitaet)
    ..get('/api/v1/spuren', api.spurkennungen)
    ..get('/api/v1/wanderobjekte', api.wanderobjekte)
    ..get('/api/v1/orte', api.orte)
    ..get('/api/v1/laender', api.laender)
    ..get('/api/v1/laender/aufnahmen', api.amOrt)
    ..get('/api/v1/statistik', api.statistik)
    ..get('/api/v1/einstellungen', api.einstellungen)
    ..get('/api/v1/entwickeln/<id>', api.entwickeln)
    ..get('/api/v1/stammbaum', api.stammbaum)
    ..get('/api/v1/lebensbaum', api.lebensbaum)
    ..get('/api/v1/duplikate', api.duplikate)
    ..get('/api/v1/aufnahmedaten', api.aufnahmedaten)
    ..post('/api/v1/aufnahmen/liste', api.liste)
    ..get('/api/v1/erinnerungen', api.erinnerungen)
    ..get('/api/v1/rueckblick', rueckblick.rueckblick)
    ..get('/api/v1/jahresrueckblick/<jahr>', rueckblick.jahresrueckblick)
    ..get('/api/v1/kalender', rueckblick.jahre)
    ..get('/api/v1/kalender/<jahr>', rueckblick.monate)
    ..get('/api/v1/kalender/<jahr>/<monat>', rueckblick.monat)
    ..get('/api/v1/papierkorb', api.papierkorb)
    ..post('/api/v1/papierkorb/leeren', api.papierkorbLeeren)
    // Collagen (#301) – die fertige ist ein neues Foto.
    ..post('/api/v1/collage', wennPlatz(api.collage))
    ..get('/api/v1/alben', api.alben)
    ..get('/api/v1/alben/<id>', api.album)
    // Alben zwischen Konten teilen (#105).
    ..get('/api/v1/konten/andere', teilung.andereKonten)
    ..get('/api/v1/kontobeitraege', teilung.neueBeitraege)
    // Partnerfreigabe (#293).
    ..get('/api/v1/partner', teilung.partner)
    ..put('/api/v1/partner/<konto>', teilung.partnerSetzen)
    ..delete('/api/v1/partner/<konto>', teilung.partnerEntfernen)
    ..delete('/api/v1/partner/von/<konto>', teilung.partnerVerlassen)
    // In der eigenen Zeitleiste zeigen (#299).
    ..put('/api/v1/partner/von/<konto>/zeitleiste', teilung.partnerZeitleiste)
    // Nachlasskontakt (#300).
    ..get('/api/v1/nachlass', nachlass.liste)
    ..put('/api/v1/nachlass/<konto>', nachlass.benennen)
    ..delete('/api/v1/nachlass/<konto>', nachlass.entfernen)
    ..post('/api/v1/nachlass/<konto>/ablehnen', nachlass.ablehnen)
    ..post('/api/v1/nachlass/von/<konto>/anfordern', nachlass.anfordern)
    ..delete('/api/v1/nachlass/von/<konto>/anfordern', nachlass.zurueckziehen)
    ..get('/api/v1/partner/von/<konto>/aufnahmen', teilung.partnerAufnahmen)
    ..get(
      '/api/v1/partner/von/<konto>/aufnahmen/<aufnahme>/<art>',
      teilung.partnerDatei,
    )
    ..post(
      '/api/v1/alben/<id>/kontobeitraege/gesehen',
      teilung.beitraegeGesehen,
    )
    ..get('/api/v1/alben/<id>/teilungen', teilung.vonAlbum)
    // Alben, die sich selbst füllen (#298).
    ..get('/api/v1/alben/<id>/regel', teilung.regel)
    ..put('/api/v1/alben/<id>/regel', teilung.regelSetzen)
    ..delete('/api/v1/alben/<id>/regel', teilung.regelEntfernen)
    // Kommentare und „Gefällt mir“ (#297), für den Besitzer …
    ..get('/api/v1/alben/<id>/aktivitaet', teilung.aktivitaetEigen)
    ..post('/api/v1/alben/<id>/kommentare', teilung.kommentierenEigen)
    ..delete('/api/v1/alben/<id>/kommentare/<k>', teilung.kommentarWegEigen)
    ..put('/api/v1/alben/<id>/gefaellt/<aufnahme>', teilung.gefaelltEigen)
    ..delete('/api/v1/alben/<id>/gefaellt/<aufnahme>', teilung.gefaelltEigen)
    // … und für den Empfänger.
    ..get('/api/v1/geteilt/<id>/aktivitaet', teilung.aktivitaetGeteilt)
    ..post('/api/v1/geteilt/<id>/kommentare', teilung.kommentierenGeteilt)
    ..delete('/api/v1/geteilt/<id>/kommentare/<k>', teilung.kommentarWegGeteilt)
    ..put('/api/v1/geteilt/<id>/gefaellt/<aufnahme>', teilung.gefaelltGeteilt)
    ..delete(
      '/api/v1/geteilt/<id>/gefaellt/<aufnahme>',
      teilung.gefaelltGeteilt,
    )
    ..put('/api/v1/alben/<id>/teilungen/<konto>', teilung.teile)
    ..delete('/api/v1/alben/<id>/teilungen/<konto>', teilung.nichtMehrTeilen)
    ..get('/api/v1/geteilt', teilung.mitMir)
    ..get('/api/v1/geteilt/<id>', teilung.album)
    ..delete('/api/v1/geteilt/<id>', teilung.verlassen)
    ..post('/api/v1/geteilt/<id>/beitrag', teilung.beitrag)
    ..delete(
      '/api/v1/geteilt/<id>/aufnahmen/<aufnahme>',
      teilung.beitragEntfernen,
    )
    ..get(
      '/api/v1/geteilt/<id>/aufnahmen/<aufnahme>/<art>',
      teilung.aufnahmedatei,
    )
    ..get('/api/v1/personen', api.personen)
    ..get('/api/v1/personen/<id>', api.person)
    ..get('/api/v1/personen/<id>/vorschlaege', api.personVorschlaege)
    ..get('/api/v1/gesichter/ohne-namen', api.gesichterOhneNamen)
    ..get('/api/v1/gesichter/ignoriert', api.gesichterIgnoriert)
    ..post('/api/v1/gesichter/unbenannte', api.unbenannteGesichter)
    // Teilen nach aussen (Issue #106): verwalten mit Anmeldung, ansehen ohne.
    ..post('/api/v1/freigaben', freigabe.anlegen)
    ..get('/api/v1/freigaben', freigabe.liste)
    ..delete('/api/v1/freigaben/<id>', freigabe.loeschen)
    ..get('/teilen/<link>', freigabe.seite)
    ..get('/api/v1/teilen/<link>', freigabe.inhalt)
    ..post('/api/v1/teilen/<link>/passwort', freigabe.passwort)
    ..post('/api/v1/teilen/<link>/beitrag', freigabe.beitrag)
    ..get('/api/v1/beitraege', freigabe.beitragsliste)
    ..get('/api/v1/beitraege/<id>/vorschau', freigabe.beitragVorschau)
    ..post(
      '/api/v1/beitraege/<id>/annehmen',
      (Request r, String id) => speicher?.voll ?? false
          ? _speicherVoll()
          : freigabe.beitragAnnehmen(r, id),
    )
    ..delete('/api/v1/beitraege/<id>', freigabe.beitragAblehnen)
    ..get('/api/v1/teilen/<link>/<id>/<art>', freigabe.datei)
    ..post('/api/v1/rechnen/auftraege', rechnen.auftraege)
    ..post('/api/v1/rechnen/ergebnis', rechnen.ergebnis)
    ..post('/api/v1/rechnen/zurueck', rechnen.zurueck)
    ..post('/api/v1/umzug/beginnen', umzug.beginnen)
    ..get('/api/v1/umzug/stand', umzug.stand)
    ..post('/api/v1/umzug/abschliessen', umzug.abschliessen)
    ..add(
      'OPTIONS',
      '/api/v1/umzug/hochladen',
      (Request r) => umzug.hochladen(r).optionen(r),
    )
    ..post(
      '/api/v1/umzug/hochladen',
      wennPlatz((Request r) => umzug.hochladen(r).anlegen(r)),
    )
    ..head(
      '/api/v1/umzug/hochladen/<id>',
      (Request r, String id) => umzug.hochladen(r).stand(r, id),
    )
    ..patch(
      '/api/v1/umzug/hochladen/<id>',
      (Request r, String id) => speicher?.voll ?? false
          ? _speicherVoll()
          : umzug.hochladen(r).anhaengen(r, id),
    )
    ..delete(
      '/api/v1/umzug/hochladen/<id>',
      (Request r, String id) => umzug.hochladen(r).verwerfen(r, id),
    )
    ..get(
      '/api/v1/speicher',
      (Request _) => _json(speicher?.alsJson() ?? const {'stufe': 'unbekannt'}),
    )
    ..get(
      '/api/v1/sicherung',
      (Request r) => _nurVerwalter(r, () async {
        return _json(
          sicherung == null ? const {'stufe': 'aus'} : await sicherung.stand(),
        );
      }),
    )
    ..post(
      '/api/v1/sicherung/einrichten',
      (Request r) => _nurVerwalter(r, () async {
        final s = sicherung;
        if (s == null) {
          return _json({
            'fehler': 'Kein Sicherungsziel eingestellt.',
          }, status: 409);
        }
        final k = jsonDecode(await r.readAsString());
        final pp = k is Map ? k['passphrase'] : null;
        if (pp is! String) {
          return _json({'fehler': 'passphrase fehlt'}, status: 400);
        }
        try {
          await s.einrichten(pp);
        } on ArgumentError catch (f) {
          return _json({'fehler': '${f.message}'}, status: 400);
        } on StateError catch (f) {
          return _json({'fehler': f.message}, status: 409);
        } on FileSystemException catch (f) {
          return _json({
            'fehler': 'Das Sicherungsziel ist nicht beschreibbar: ${f.message}',
          }, status: 409);
        }
        unawaited(s.jetzt());
        return _json(await s.stand());
      }),
    )
    ..post(
      '/api/v1/sicherung/ziel',
      (Request r) => _nurVerwalter(r, () async {
        final s = sicherung;
        if (s == null || !s.eingerichtet) {
          return _json({
            'fehler': 'Die Sicherung ist nicht eingerichtet.',
          }, status: 409);
        }
        try {
          await s.zielNeu();
        } on FileSystemException catch (f) {
          return _json({
            'fehler': 'Ziel nicht beschreibbar: ${f.message}',
          }, status: 409);
        }
        return _json(await s.stand());
      }),
    )
    ..post(
      '/api/v1/sicherung/jetzt',
      (Request r) => _nurVerwalter(r, () async {
        final s = sicherung;
        if (s == null || !s.eingerichtet) {
          return _json({
            'fehler': 'Die Sicherung ist nicht eingerichtet.',
          }, status: 409);
        }
        unawaited(s.jetzt());
        return _json(await s.stand(), status: 202);
      }),
    )
    ..get('/api/v1/auswertung', api.auswertung)
    ..post('/api/v1/auswertung', api.auswertungAnstossen)
    // Ein Foto in einem Stück, wie iOS es im Hintergrund schickt (#308).
    ..put(
      '/api/v1/sofort',
      wennPlatz(
        (Request r) async => (await bereich(r)).hochladen.inEinemStueck(r),
      ),
    )
    ..add(
      'OPTIONS',
      '/api/v1/hochladen',
      (Request r) async => (await bereich(r)).hochladen.optionen(r),
    )
    ..post(
      '/api/v1/hochladen',
      wennPlatz((Request r) async => (await bereich(r)).hochladen.anlegen(r)),
    )
    ..head(
      '/api/v1/hochladen/<id>',
      (Request r, String id) async => (await bereich(r)).hochladen.stand(r, id),
    )
    ..get(
      '/api/v1/hochladen/<id>',
      (Request r, String id) async =>
          (await bereich(r)).hochladen.status(r, id),
    )
    ..patch(
      '/api/v1/hochladen/<id>',
      (Request r, String id) async => speicher?.voll ?? false
          ? _speicherVoll()
          : (await bereich(r)).hochladen.anhaengen(r, id),
    )
    ..delete(
      '/api/v1/hochladen/<id>',
      (Request r, String id) async =>
          (await bereich(r)).hochladen.verwerfen(r, id),
    );
  return const Pipeline()
      .addMiddleware(packen)
      .addMiddleware(_sicherheitskoepfe)
      .addMiddleware(anfragegrenzen())
      .addMiddleware(
        anmeldungNoetig(
          konten,
          von,
          offen: {
            '',
            'api/v1/zustand',
            'api/v1/einrichten',
            'api/v1/anmelden',
            'api/v1/anmelden/totp',
            'api/v1/anmelden/oidc',
            'api/v1/anmelden/oidc/zurueck',
            'api/v1/anmelden/oidc/einloesen',
            'api/v1/web/anmelden',
            'api/v1/web/anmelden/totp',
            'api/v1/web/anmelden/passkey',
            'api/v1/anmelden/passkey/optionen',
            'api/v1/anmelden/passkey',
            'api/v1/anmelden/passkey/einloesen',
            'api/v1/passkeys/ticket/optionen',
            'api/v1/passkeys/ticket',
            'app',
          },
          offenPraefixe: {'app/', 'teilen/', 'api/v1/teilen/'},
        ),
      )
      .addHandler(r.call);
}

/// Was jede Antwort trägt: Der Browser soll nichts erraten, keine Adresse
/// weitergeben (die Rückwege der Anmeldung tragen Codes), nichts in eine
/// fremde Seite einbetten und nichts ausführen, was als Datei kommt – eine
/// JSON-Antwort oder ein Bild, direkt geöffnet, ist eine Seite ohne jedes
/// Recht. Die Oberfläche bringt ihre eigene, weitere Regel mit.
Middleware get _sicherheitskoepfe =>
    (innerer) => (anfrage) async {
      final antwort = await innerer(anfrage);
      final k = antwort.headers;
      final typ = k['content-type'] ?? '';
      return antwort.change(
        headers: {
          'x-content-type-options': 'nosniff',
          'referrer-policy': 'no-referrer',
          'x-frame-options': 'DENY',
          'cross-origin-opener-policy': 'same-origin',
          'cross-origin-resource-policy': 'same-origin',
          if (!k.containsKey('content-security-policy'))
            'content-security-policy':
                "default-src 'none'; frame-ancestors 'none'; sandbox",
          if (!k.containsKey('cache-control') &&
              typ.startsWith('application/json'))
            'cache-control': 'no-store',
        },
      );
    };

/// Nur für Verwalter; sonst 403.
Future<Response> _nurVerwalter(
  Request r,
  Future<Response> Function() erlaubt,
) async => kontoVon(r).verwalter
    ? erlaubt()
    : _json({'fehler': 'Nur für Verwalter.'}, status: 403);

/// 507 Insufficient Storage – der Client bricht ab, statt es weiter zu
/// versuchen.
Response _speicherVoll() =>
    _json({'fehler': 'Der Speicher des Servers ist voll.'}, status: 507);

Response _json(Object? daten, {int status = 200}) => Response(
  status,
  body: jsonEncode(daten),
  headers: {'content-type': 'application/json; charset=utf-8'},
);

class _Api {
  _Api(
    this.bibliotheken,
    this._beschleuniger,
    this.videofassungen,
    this._netz, {
    required this.vollbilder,
    this.teilungen,
    this.regeln,
    this.kontoname,
  });

  /// Mit wem die Alben geteilt sind (#105) – für die Albenliste; und wer
  /// seine Bibliothek in der Zeitleiste dieses Kontos zeigt (#299).
  final Albumteilungen? teilungen;

  /// Welche Alben sich selbst füllen (#298) – für die Albenliste.
  final Albumregeln? regeln;

  /// Der Name eines anderen Kontos – an den Fotos eines Partners.
  final String? Function(String konto)? kontoname;

  /// Für Overpass – nur in Tests gesetzt, sonst ein eigener je Abruf.
  final http.Client? _netz;

  final Bibliotheken bibliotheken;

  /// Für Browser, die ein Video nicht abspielen können – dieselben wie für
  /// geteilte Links.
  final Videofassungen videofassungen;

  /// Fotos in voller Auflösung für den Betrachter (#256).
  final Vollbilder vollbilder;
  final Future<Map<String, Object?>> Function()? _beschleuniger;

  Future<Kontobereich> _bereich(Request r) => bibliotheken.fuer(kontoVon(r).id);

  /// Lebenszeichen, ohne Anmeldung – für Docker, den Reverse Proxy und
  /// Clients, die wissen wollen, wie sie sich anmelden.
  /// Mit [einrichten], wenn es noch kein Konto gibt und die Anfrage aus
  /// dem Heimnetz kommt: Dann bietet die App an, das erste anzulegen.
  Response zustand(Kontodienst konten, Oidc? oidc, {bool einrichten = false}) =>
      _json({
        'dienst': 'photo-vault',
        'protokoll': protokollFassung,
        'funktionen': {
          'konfliktpruefung': 1,
          'importplan': 2,
          'albenTeilen': 1,
          // Endgültig löschen und die Frist des Papierkorbs (#296).
          'papierkorb': 1,
          // Kommentare und „Gefällt mir“ in geteilten Alben (#297).
          'kommentare': 1,
          // Alben, die sich selbst füllen (#298).
          'albumregeln': 1,
          // Partnerfreigabe eingeschränkt und in der Zeitleiste (#299).
          'partnerfreigabe': 2,
          // Fotos in einem Stück, wenn die Handy-App nicht läuft (#308).
          'sofort': 1,
          // Nachlasskontakt (#300).
          'nachlass': 1,
          // Collagen (#301).
          'collage': 1,
        },
        'fassung': serverFassung,
        if (serverCommit.isNotEmpty) 'commit': serverCommit,
        'anmeldung': {
          'totp': konten.totpPflicht,
          'oidc': oidc != null,
          'passkeys': true,
          // Nur von dort kann die Weboberfläche verknüpfen (#182).
          if (oidc case final o?) 'weboberflaeche': '${o.e.weboberflaeche}',
        },
        if (einrichten) 'einrichten': true,
      });

  Future<Response> bibliothek(Request anfrage) async {
    final db = (await _bereich(anfrage)).bibliothek.db;
    final anzahl = await db
        .customSelect(
          'SELECT count(*) AS n FROM assets WHERE $rasterSichtbar',
          readsFrom: {db.assets},
        )
        .getSingle();
    return _json({
      'schema': db.schemaVersion,
      'protokoll': protokollFassung,
      'aufnahmen': anzahl.read<int>('n'),
    });
  }

  /// Was die Auswertung gerade tut: `laeuft` und, wenn ja, die Stufe mit
  /// ihrem Fortschritt; dazu der Beschleuniger und seine Gegenproben.
  Future<Response> auswertung(Request anfrage) async {
    final d = (await _bereich(anfrage)).auswertung;
    return _json({
      'laeuft': d.laeuft,
      'stand': d.stand?.alsJson(),
      'beschleuniger': ?await _beschleuniger?.call(),
    });
  }

  /// Stösst einen Durchgang an, ohne die Ruhezeit abzuwarten. Antwortet
  /// sofort; der Durchgang läuft im Hintergrund.
  Future<Response> auswertungAnstossen(Request anfrage) async {
    unawaited((await _bereich(anfrage)).auswertung.jetzt());
    return _json({'laeuft': true}, status: 202);
  }

  /// Die Zeitleiste seitenweise, neueste zuerst.
  ///
  /// Weiterblättern über `nach` – den Wert `weiter` der vorigen Seite –
  /// statt über eine Seitenzahl: Kommt oben etwas dazu, verrutscht eine
  /// Seitenzahl, ein Lesezeichen auf die letzte Zeile nicht. Und die
  /// Abfrage bleibt in jeder Tiefe der Bibliothek gleich schnell.
  ///
  /// Mit `favoriten=1` nur die Favoriten – für die Bibliothek der
  /// Weboberfläche, wie auf dem Telefon.
  Future<Response> aufnahmen(Request anfrage) async {
    final db = (await _bereich(anfrage)).bibliothek.db;
    final q = anfrage.url.queryParameters;
    final anzahl = (int.tryParse(q['anzahl'] ?? '') ?? 300).clamp(1, 1000);
    final nurFavoriten = q['favoriten'] == '1';
    // Für die Liste (#195) die Angaben, die die Kachel nicht braucht.
    final voll = q['voll'] == '1';
    Future<List<Map<String, Object?>>> alsJson(List<Rasterzeile> zeilen) async {
      final mehr = voll
          ? await db.listenangaben([for (final z in zeilen) z.id])
          : const <String, Listenangaben>{};
      return [
        for (final z in zeilen)
          {
            ...zeileAlsJson(z),
            if (mehr[z.id] case final l?) ...listenangabenAlsJson(l),
          },
      ];
    }

    // Andere Reihenfolgen wie am Rechner (#194). Die Vorgabe blättert wie
    // bisher über ein Lesezeichen aus Zeit und Kennung; die übrigen über
    // die Stelle – für sie gibt es keinen Schlüssel, der überall passt.
    final sortierung = Rastersortierung.values
        .where((s) => s.name == q['sortierung'])
        .firstOrNull;
    if (sortierung != null && sortierung != rastersortierungVorgabe) {
      final ab = int.tryParse((q['nach'] ?? '').replaceFirst('o:', '')) ?? 0;
      final zeilen = await db
          .customSelect(
            'SELECT $rasterSpalten FROM assets WHERE $rasterSichtbar'
            '${nurFavoriten ? ' AND is_favorite = 1' : ''}'
            ' ORDER BY ${sortierungSql(sortierung)}, id DESC LIMIT ? OFFSET ?',
            variables: [Variable<int>(anzahl), Variable<int>(ab)],
            readsFrom: {db.assets},
          )
          .get();
      return _json({
        'aufnahmen': await alsJson([
          for (final z in zeilen) Rasterzeile.ausZeile(z),
        ]),
        'weiter': zeilen.length < anzahl ? null : 'o:${ab + zeilen.length}',
      });
    }
    final nach = _Lesezeichen.lies(q['nach']);
    final zeilen = await db
        .customSelect(
          'SELECT $rasterSpalten FROM assets WHERE $rasterSichtbar'
          '${nurFavoriten ? ' AND is_favorite = 1' : ''}'
          // Die erste Bedingung gibt dem Index eine Grenze: Am OR allein
          // ging er sonst bis zur Seite alles durch.
          '${nach == null ? '' : ' AND file_created_at <= ? AND (file_created_at < ? OR id < ?)'}'
          ' ORDER BY file_created_at DESC, id DESC LIMIT ?',
          variables: [
            if (nach != null) ...[
              Variable<DateTime>(nach.zeit),
              Variable<DateTime>(nach.zeit),
              Variable<String>(nach.id),
            ],
            Variable<int>(anzahl),
          ],
          readsFrom: {db.assets},
        )
        .get();
    final liste = [for (final z in zeilen) Rasterzeile.ausZeile(z)];
    // Die Fotos von Partnern, die dieses Konto in seiner Zeitleiste sehen
    // will (#299) – nach demselben Lesezeichen aus jeder Bibliothek
    // geholt und eingereiht. Favoriten sind persönlich und bleiben eigen.
    final partner = nurFavoriten
        ? const <_Partnerquelle>[]
        : await _partnerInZeitleiste(anfrage);
    if (partner.isEmpty) {
      return _json({
        'aufnahmen': await alsJson(liste),
        'weiter': liste.length < anzahl
            ? null
            : _Lesezeichen(liste.last.fileCreatedAt, liste.last.id).text,
      });
    }
    final alle = <({Rasterzeile z, _Partnerquelle? von})>[
      for (final z in liste) (z: z, von: null),
    ];
    for (final p in partner) {
      for (final z in await partnerzeilen(
        p.db,
        p.freigabe,
        anzahl: anzahl,
        nach: nach == null ? null : (zeit: nach.zeit, id: nach.id),
      )) {
        alle.add((z: z, von: p));
      }
    }
    alle.sort((a, b) {
      final c = b.z.fileCreatedAt.compareTo(a.z.fileCreatedAt);
      return c != 0 ? c : b.z.id.compareTo(a.z.id);
    });
    final seite = alle.take(anzahl).toList();
    final eigene = [
      for (final e in seite)
        if (e.von == null) e.z,
    ];
    final eigenJson = {
      for (final (i, j) in (await alsJson(eigene)).indexed) eigene[i].id: j,
    };
    final mehr = <String, Listenangaben>{};
    if (voll) {
      for (final p in partner) {
        mehr.addAll(
          await p.db.listenangaben([
            for (final e in seite)
              if (identical(e.von, p)) e.z.id,
          ]),
        );
      }
    }
    return _json({
      'aufnahmen': [
        for (final e in seite)
          if (e.von case final p?)
            {
              ...partnerzeileAlsJson(e.z),
              if (mehr[e.z.id] case final l?) ...listenangabenAlsJson(l),
              'konto': p.freigabe.besitzer,
              'von': p.name,
            }
          else
            eigenJson[e.z.id]!,
      ],
      'weiter': seite.length < anzahl
          ? null
          : _Lesezeichen(seite.last.z.fileCreatedAt, seite.last.z.id).text,
    });
  }

  /// Die Partner, deren Fotos das Konto der Anfrage in seiner Zeitleiste
  /// sehen will (#299).
  Future<List<_Partnerquelle>> _partnerInZeitleiste(Request anfrage) async {
    final t = teilungen;
    if (t == null) return const [];
    final quellen = <_Partnerquelle>[];
    for (final f in t.freigabenMit(kontoVon(anfrage).id)) {
      if (!f.inZeitleiste) continue;
      final name = kontoname?.call(f.besitzer);
      if (name == null) continue;
      try {
        final bereich = await bibliotheken.fuer(f.besitzer);
        quellen.add(_Partnerquelle(f, bereich.bibliothek.db, name));
      } catch (e) {
        // Eine Bibliothek, die sich nicht öffnen lässt, darf die eigene
        // Zeitleiste nicht mitreissen.
        protokoll('Bibliothek eines Partners nicht geöffnet: $e');
      }
    }
    return quellen;
  }

  /// Wie viele Aufnahmen die Zeitleiste je Monat zeigt, neueste zuerst –
  /// für den Ziehregler im Browser (#278). Er kennt so die ganze Zeitleiste,
  /// auch was noch nicht geladen ist. Die Monate in der Ortszeit des
  /// Servers, wie `aufgenommen` in jeder Zeile (siehe zeilen_json.dart).
  Future<Response> zeitleistenmonate(Request anfrage) async {
    final db = (await _bereich(anfrage)).bibliothek.db;
    final je = <String, int>{};
    Future<void> zaehle(
      AppDatabase db,
      String bedingung,
      List<Variable<Object>> werte,
    ) async {
      for (final z
          in await db
              .customSelect(
                "SELECT strftime('%Y-%m', file_created_at, 'unixepoch', 'localtime') "
                'AS m, COUNT(*) AS n FROM assets WHERE $rasterSichtbar$bedingung '
                'GROUP BY m',
                variables: werte,
                readsFrom: {db.assets},
              )
              .get()) {
        final m = z.read<String>('m');
        je[m] = (je[m] ?? 0) + z.read<int>('n');
      }
    }

    await zaehle(db, '', const []);
    // Mit den Fotos der Partner, wie die Zeitleiste sie zeigt (#299) – nur
    // in der gewohnten Reihenfolge, sonst fehlen sie dort.
    final sortierung = anfrage.url.queryParameters['sortierung'];
    final mitPartnern =
        sortierung == null || sortierung == rastersortierungVorgabe.name;
    for (final p
        in mitPartnern
            ? await _partnerInZeitleiste(anfrage)
            : const <_Partnerquelle>[]) {
      final b = freigabeBedingung(
        ab: p.freigabe.ab,
        personen: p.freigabe.personen,
      );
      await zaehle(p.db, b.sql, b.werte);
    }
    final monate = je.keys.toList()..sort((a, b) => b.compareTo(a));
    return _json({
      'monate': [
        for (final m in monate) {'monat': m, 'anzahl': je[m]},
      ],
    });
  }

  /// Die Reisen mit Zeitraum, Anzahl und Titelbild – für den Browser.
  /// Reisen und Aktivitäten für die Seite „Reisen“ im Browser – dieselbe
  /// Rechnung wie auf dem Telefon (siehe reiseuebersicht.dart im Kern).
  /// `sprache` bestimmt die Ländernamen.
  Future<Response> reisen(Request anfrage) async {
    final db = (await _bereich(anfrage)).bibliothek.db;
    final sprache = _sprache(anfrage);
    return _json({
      'reisen': [for (final k in await reisekarten(db)) _reiseJson(k, sprache)],
      'aktivitaeten': [
        for (final k in await aktivitaetskarten(db))
          _aktivitaetJson(k, sprache),
      ],
    });
  }

  Future<Response> reiseAufnahmen(Request anfrage, String id) async {
    final db = (await _bereich(anfrage)).bibliothek.db;
    final r = await db.reise(id);
    if (r == null) return _json({'fehler': 'unbekannt'}, status: 404);
    final sprache = _sprache(anfrage);
    final aufnahmen = await db.aufnahmenDerReise(id);
    return _json({
      'reise': {
        'id': r.id,
        'name': r.name,
        'von': r.von.toIso8601String(),
        'bis': r.bis.toIso8601String(),
        'notiz': r.notiz,
        'art': r.art,
        'anzahl': aufnahmen.length,
      },
      'aktivitaeten': [
        for (final k in await aktivitaetskarten(db, reiseId: id))
          _aktivitaetJson(k, sprache),
      ],
      'aufnahmen': [
        for (final a in aufnahmen) zeileAlsJson(Rasterzeile.aus(a)),
      ],
    });
  }

  /// Eine Aktivität: Angaben, Route aus den verorteten Aufnahmen, Strecke
  /// darauf und die Aufnahmen selbst.
  Future<Response> aktivitaet(Request anfrage, String id) async {
    final db = (await _bereich(anfrage)).bibliothek.db;
    final a = await aktivitaetsansicht(db, id);
    if (a == null) return _json({'fehler': 'unbekannt'}, status: 404);
    final k = a.aktivitaet;
    final reise = a.reise;
    return _json({
      'aktivitaet': {
        'id': k.id,
        'name': k.name,
        'art': k.art,
        'von': k.von.toIso8601String(),
        'bis': k.bis.toIso8601String(),
        'notiz': k.notiz,
        'reise': reise == null ? null : {'id': reise.id, 'name': reise.name},
        'anzahl': a.aufnahmen.length,
        'streckeKm': a.streckeKm,
        'ort': _ortJson(a.ort, _sprache(anfrage)),
      },
      'route': [
        for (final p in a.route)
          {
            'id': p.id,
            'breite': p.breite,
            'laenge': p.laenge,
            'zeit': p.zeit.toIso8601String(),
          },
      ],
      // Kompakt wie im Befehl: [breite, länge, höhe, zeit in ms].
      'spuren': [
        for (final x in a.spuren)
          {
            'id': x.spur.id,
            'name': x.spur.name,
            'laengeKm': x.spur.laengeKm,
            'aufstieg': ?x.spur.aufstieg,
            'abstieg': ?x.spur.abstieg,
            'punkte': [
              for (final p in x.punkte)
                [p.breite, p.laenge, p.hoehe, p.zeit?.millisecondsSinceEpoch],
            ],
          },
      ],
      'aufnahmen': [
        for (final x in a.aufnahmen) zeileAlsJson(Rasterzeile.aus(x)),
      ],
    });
  }

  /// Welche Spuren der Server kennt – ein verbundener Rechner reicht nach,
  /// was hier fehlt (spuren_nachreichen.dart).
  Future<Response> spurkennungen(Request anfrage) async {
    final db = (await _bereich(anfrage)).bibliothek.db;
    return _json({
      'kennungen': [for (final s in await db.alleSpuren()) s.id],
    });
  }

  /// Gipfel, Hütten und Quellen in einem Ausschnitt – für die Landschaft
  /// in Browser und Handy. Wie am Rechner zuerst aus der Bibliothek, sonst
  /// von Overpass, und dann gemerkt (`wanderobjekteAusBibliothek`).
  ///
  /// Höchstens zwei Grad je Richtung: Mehr fasst keine Tour, und eine
  /// grössere Frage ginge an einen ehrenamtlichen Dienst.
  Future<Response> wanderobjekte(Request anfrage) async {
    final q = anfrage.url.queryParameters;
    double? zahl(String n) => double.tryParse(q[n] ?? '');
    final sued = zahl('sued'), west = zahl('west');
    final nord = zahl('nord'), ost = zahl('ost');
    if (sued == null ||
        west == null ||
        nord == null ||
        ost == null ||
        sued < -90 ||
        nord > 90 ||
        west < -180 ||
        ost > 180 ||
        nord <= sued ||
        ost <= west ||
        nord - sued > 2 ||
        ost - west > 2) {
      return Response(400);
    }
    final db = (await _bereich(anfrage)).bibliothek.db;
    final punkte = await wanderobjekteAusBibliothek(
      db,
      sued: sued,
      west: west,
      nord: nord,
      ost: ost,
      netz: _netz,
    );
    return _json({
      'punkte': [
        for (final p in punkte)
          {
            'osmId': p.osmId,
            'art': p.art.name,
            'breite': p.breite,
            'laenge': p.laenge,
            'name': ?p.name,
            'hoehe': ?p.hoehe,
          },
      ],
    });
  }

  String _sprache(Request anfrage) =>
      anfrage.url.queryParameters['sprache'] == 'en' ? 'en' : 'de';

  /// Der Ort als Zeile ohne den Zusatz „weitere Orte“ – den setzt der
  /// Browser in seiner Sprache, er bekommt nur die Zahl.
  Map<String, Object?>? _ortJson(Ortsbezug? b, String sprache) {
    if (b == null) return null;
    final text = ortszeileText(
      (
        ort: b.ort,
        region: b.region,
        land: b.land,
        weitereOrte: 0,
        aufnahmen: b.aufnahmen,
      ),
      sprache,
      (_) => '',
    );
    return text == null ? null : {'text': text, 'weitere': b.weitereOrte};
  }

  Map<String, Object?> _reiseJson(Reisekarte k, String sprache) => {
    'id': k.reise.id,
    'name': k.reise.name,
    'von': k.reise.von.toIso8601String(),
    'bis': k.reise.bis.toIso8601String(),
    'art': k.reise.art,
    'anzahl': k.anzahl,
    'titelbild': k.titelbild?.id,
    'ort': _ortJson(k.ort, sprache),
  };

  Map<String, Object?> _aktivitaetJson(Aktivitaetskarte k, String sprache) => {
    'id': k.aktivitaet.id,
    'name': k.aktivitaet.name,
    'art': k.aktivitaet.art,
    'von': k.aktivitaet.von.toIso8601String(),
    'bis': k.aktivitaet.bis.toIso8601String(),
    'reiseId': k.aktivitaet.reiseId,
    'reisename': k.reisename,
    'anzahl': k.anzahl,
    'titelbild': k.titelbild?.id,
    'ort': _ortJson(k.ort, sprache),
  };

  /// Die Aufnahmen mit Ort als Punkte für die Karte im Browser, bei
  /// `?zoom=` zusammengefasst wie auf dem Telefon (siehe [kartengruppen]).
  /// Die Kennzahlen der Analyseseite des Rechners (LibraryStats) in Zahlen,
  /// damit der Browser dieselbe Statistik zeigt: Anzahl, Speicher, Aufnahmen
  /// je Jahr und Monat, häufigste Kameras.
  Future<Response> statistik(Request anfrage) async {
    final db = (await _bereich(anfrage)).bibliothek.db;
    final s = await db.loadLibraryStats();
    return _json({
      'insgesamt': s.totalCount,
      'fotos': s.imageCount,
      'videos': s.videoCount,
      'favoriten': s.favoriteCount,
      'papierkorb': s.trashedCount,
      'gesperrt': s.lockedCount,
      'bytes': s.totalSizeBytes,
      'proJahr': {for (final e in s.countsByYear.entries) '${e.key}': e.value},
      'proMonat': {
        for (final e in s.countsByMonth.entries) '${e.key}': e.value,
      },
      'kameras': [
        for (final k in s.topCameras) {'name': k.label, 'anzahl': k.count},
      ],
    });
  }

  /// Duplikatgruppen wie auf dem Rechner: dieselbe Suche
  /// ([findDuplicateGroups]) auf den Bildeinbettungen der Bibliothek, in
  /// einem eigenen Isolate, und je Gruppe das Foto, das die Regeln aus
  /// duplicate_selection.dart behalten würden.
  Future<Response> duplikate(Request anfrage) async {
    final schwelle =
        double.tryParse(anfrage.url.queryParameters['schwelle'] ?? '') ?? 0.92;
    if (schwelle < 0.5 || schwelle > 1) {
      return _json({'fehler': 'schwelle'}, status: 400);
    }
    final db = (await _bereich(anfrage)).bibliothek.db;
    final d = await _duplikate(db, schwelle);
    return _json({
      'einbettungen': d.einbettungen,
      'ausnahmen': d.ausnahmen,
      'schwelle': d.schwelle,
      'gruppen': [
        for (final g in d.gruppen)
          {
            'aufnahmen': [
              for (final a in g.aufnahmen) zeileAlsJson(Rasterzeile.aus(a)),
            ],
            'behalten': g.behalten.id,
            'loeschbar': [for (final a in g.loeschbar) a.id],
          },
      ],
    });
  }

  /// Die letzte Suche je Bibliothek: Sie braucht bei 100.000 Fotos rund
  /// 18 Sekunden, und die Seite fragt nach jeder Entscheidung neu. Gültig,
  /// solange sich Einbettungen und Ausnahmen nicht ändern, höchstens
  /// [_duplikateGueltig] lang: Sterne und Beschreibungen zählen dort mit.
  final _duplikatsuche =
      Expando<
        ({
          int stand,
          double schwelle,
          Set<String> ausnahmen,
          DateTime zeit,
          Duplikatergebnis ergebnis,
        })
      >();
  static const _duplikateGueltig = Duration(minutes: 10);

  Future<Duplikatergebnis> _duplikate(AppDatabase db, double schwelle) async {
    final ausnahmen = await db.duplikatAusnahmeSchluessel();
    final alt = _duplikatsuche[db];
    if (alt != null &&
        alt.stand == db.embeddingsGeneration &&
        alt.schwelle == schwelle &&
        DateTime.now().difference(alt.zeit) < _duplikateGueltig &&
        alt.ausnahmen.length == ausnahmen.length &&
        alt.ausnahmen.containsAll(ausnahmen)) {
      return alt.ergebnis;
    }
    final stand = db.embeddingsGeneration;
    final ergebnis = await sucheDuplikate(db, schwelle);
    _duplikatsuche[db] = (
      stand: stand,
      schwelle: schwelle,
      ausnahmen: ausnahmen,
      zeit: DateTime.now(),
      ergebnis: ergebnis,
    );
    return ergebnis;
  }

  /// Liest das Aufnahmedatum aus einer Datei der Bibliothek, für die
  /// Prüfung „Aufnahmedaten“ (#203). `null`, wenn die Datei fehlt.
  Future<Datumsbefund?> Function(String) _datumsleser(Bibliothek b) =>
      (pfad) async {
        final datei = b.pfade.absolute(pfad);
        if (!await datei.exists()) return null;
        return b.importe.pruefeAufnahmedatum(datei);
      };

  static Map<String, Object?> _vorschlagAlsJson(Datumsvorschlag v) => {
    'bisher': v.bisher.toIso8601String(),
    'bisherGeschaetzt': v.bisherGeschaetzt,
    'neu': v.neu.toUtc().toIso8601String(),
    'geschaetzt': v.geschaetzt,
    'quelle': v.quelle.name,
  };

  /// Die Aufnahmen, deren Dateiname ein anderes Datum nennt als die Zeile
  /// (#203), mit dem, was gelten sollte. Übernommen wird über den Befehl
  /// `aufnahmedatenSetzen`, wie am Rechner.
  Future<Response> aufnahmedaten(Request anfrage) async {
    final b = (await _bereich(anfrage)).bibliothek;
    final vorschlaege = await datumsvorschlaege(
      b.db,
      leseDatei: _datumsleser(b),
    );
    final ids = [for (final v in vorschlaege) v.id];
    final zeilen = <String, AssetData>{};
    for (var i = 0; i < ids.length; i += 500) {
      final stueck = ids.sublist(i, (i + 500).clamp(0, ids.length));
      for (final a in await (b.db.select(
        b.db.assets,
      )..where((t) => t.id.isIn(stueck))).get()) {
        zeilen[a.id] = a;
      }
    }
    return _json({
      'vorschlaege': [
        for (final v in vorschlaege)
          if (zeilen[v.id] case final a?)
            {
              'aufnahme': zeileAlsJson(Rasterzeile.aus(a)),
              ..._vorschlagAlsJson(v),
            },
      ],
    });
  }

  /// Alles, was die Info-Ansicht des Rechners zu einer Aufnahme zeigt:
  /// Datei, Kamera, Ort, Personen, Schlagwörter, Alben, Beschreibung, Serie.
  /// Die Rasterzeile liegt darunter, damit der Browser dieselben Schlüssel
  /// wie in den Listen sieht; `ort` und `kamera` werden hier ausführlicher.
  Future<Response> angaben(Request anfrage, String id) async {
    final b = (await _bereich(anfrage)).bibliothek;
    final db = b.db;
    final angaben = await aufnahmeangaben(db, id);
    if (angaben == null) return _json({'fehler': 'unbekannt'}, status: 404);
    final a = angaben.aufnahme;
    // Nennt der Dateiname ein anderes Datum, das gelten sollte (#203)?
    final datumsvorschlag = await datumsvorschlagFuer(
      db,
      id,
      leseDatei: _datumsleser(b),
    );
    return _json({
      ...zeileAlsJson(Rasterzeile.aus(a)),
      'importiert': a.importedAt.toIso8601String(),
      'bytes': a.fileSizeBytes,
      'format': a.dateiformat,
      'beschreibung': a.description,
      // In der Sprache der Oberfläche, wie auf dem Telefon.
      'kiBeschreibung': _sprache(anfrage) == 'de'
          ? (a.aiCaptionDe ?? a.aiCaption)
          : a.aiCaption,
      'text': a.ocrText,
      'transkript': a.transkript,
      'datumGeschaetzt': a.datumGeschaetzt,
      if (datumsvorschlag != null)
        'datumsvorschlag': _vorschlagAlsJson(datumsvorschlag),
      'bearbeitet': angaben.bearbeitet,
      // Von der Gesichtssuche ausgenommen (#191) – für den Schalter im
      // Betrachter.
      'gesichtssucheAus': a.faceScanExcluded,
      'kamera': {
        'hersteller': a.cameraMake,
        'modell': a.cameraModel,
        'objektiv': a.lensModel,
        'brennweite': a.focalLengthMm,
        'brennweite35': a.focalLength35mm,
        'blende': a.fNumber,
        'iso': a.iso,
        'belichtung': a.exposureTimeSeconds,
        'korrektur': a.exposureBiasEv,
      },
      if (a.latitude != null && a.longitude != null)
        'ort': {
          'breite': a.latitude,
          'laenge': a.longitude,
          'land': landAnzeige(a.locationCountry, _sprache(anfrage)),
          'region': a.locationState,
          'stadt': a.locationCity,
          'geerbt': a.ortGeerbt,
        },
      'personen': [
        for (final p in angaben.personen) {'id': p.id, 'name': p.name},
      ],
      // Jedes Gesicht für sich – zum Benennen und Ändern (Issue #166).
      'gesichter': [
        for (final (:gesicht, :person)
            in await gesichtsuebersicht.gesichterDerAufnahme(db, id))
          {
            'id': gesicht.id,
            'ausschnitt': gesicht.cropRelativePath,
            'kasten': gesichtskasten(gesicht),
            'person': person == null
                ? null
                : {'id': person.id, 'name': person.name},
            if (gesicht.isIgnored) 'beiseite': true,
          },
      ],
      'schlagwoerter': [
        for (final t in angaben.schlagwoerter) {'id': t.id, 'name': t.name},
      ],
      'alben': [
        for (final b in angaben.alben) {'id': b.id, 'name': b.name},
      ],
    });
  }

  /// Die Aufnahmen einer Serie (eines Stapels), Titelbild zuerst – im
  /// Raster steht nur das Titelbild, der Rest öffnet sich hierüber.
  Future<Response> serie(Request anfrage, String id) async {
    final db = (await _bereich(anfrage)).bibliothek.db;
    // Varianten heissen `variante:…`; der Browser schickt den Doppelpunkt
    // als %3A, und der Router reicht ihn so weiter (#219).
    final sichtbar = await serieZumAnsehen(db, Uri.decodeComponent(id));
    if (sichtbar.isEmpty) return _json({'fehler': 'unbekannt'}, status: 404);
    return _json({
      'aufnahmen': [for (final a in sichtbar) zeileAlsJson(Rasterzeile.aus(a))],
    });
  }

  /// Der Stammbaum um eine Person, wie der Rechner ihn zeigt: dasselbe
  /// Geflecht aus dem Kern ([geflechtUm]) – Haushalte je Generationsband
  /// und die Elternhäuser jeder Person. Gezeichnet wird im Browser.
  ///
  /// Ohne `fokus` die zuletzt am Rechner gewählte Person, sonst die erste
  /// mit Verwandtschaft; alle Personen kommen für die Auswahl mit. Ebenso
  /// `oben`, `unten` und `kreis` – wie weit der Baum reicht (#233); was
  /// gilt, steht in `optionen`.
  Future<Response> stammbaum(Request anfrage) async {
    final db = (await _bereich(anfrage)).bibliothek.db;
    final q = anfrage.url.queryParameters;
    final s = await stammbaumansicht(
      db,
      fokus: q['fokus'],
      oben: int.tryParse(q['oben'] ?? ''),
      unten: int.tryParse(q['unten'] ?? ''),
      kreis: q['kreis'],
    );
    final optionen = {
      'oben': s.umfang.oben,
      'unten': s.umfang.unten,
      'kreis': s.umfang.kreis.name,
      'maxGenerationen': geflechtMaxGenerationen,
    };
    final g = s.geflecht;
    if (g == null) {
      return _json({
        'fokus': null,
        'personen': [],
        'haushalte': [],
        'optionen': optionen,
      });
    }
    return _json({
      'fokus': s.fokus,
      'optionen': optionen,
      'personen': [
        for (final p in s.personen)
          {
            'id': p.id,
            'name': p.name,
            'geburt': p.geburtsdatum?.toIso8601String(),
            'tod': p.sterbedatum?.toIso8601String(),
            'bild': p.coverFaceCropPath,
            'geschlecht': p.geschlecht,
            'verwandt': s.verwandt.contains(p.id),
            // Was auf dem Schild steht, für alle im Bild – wie am Rechner
            // (#234). Die Bezeichnung setzt der Browser in seiner Sprache.
            if (s.schilder[p.id] case final x?) ...{
              'lebensspanne': x.lebensspanne,
              if (x.grad != null) 'grad': _gradJson(x.grad!),
              if (x.umweg case final u?)
                'umweg': {
                  'name': u.ueber.name,
                  'geschlecht': u.ueber.geschlecht,
                  'schritt': _gradJson(u.schritt),
                  'ueberGrad': _gradJson(u.ueberGrad),
                },
            },
          },
      ],
      'familienname': s.familienname,
      'haushalte': [
        for (final h in g.haushalte)
          {'id': h.id, 'personen': h.personen, 'band': g.band[h.id]},
      ],
      'elternhaeuser': g.elternhaeuserVon,
      'weitereOben': [
        for (final e in g.weitereOben.entries)
          if (e.value) e.key,
      ],
      'weitereUnten': [
        for (final e in g.weitereUnten.entries)
          if (e.value) e.key,
      ],
      'verschwiegen': g.verschwiegen,
      // Die Plätze, wie der Rechner sie rechnet (siehe stammbaumansicht).
      if (s.plan case final plan?)
        'plan': {
          'breite': plan.breite,
          'hoehe': plan.hoehe,
          'stammX': plan.stammX,
          // Die Zahlen, aus denen der Rechner das Schild baut – der
          // Browser malt danach dasselbe Schild (#234).
          'schild': _schildmasseJson,
          'schilder': [
            for (final x in plan.schilder)
              {
                'id': x.personId,
                'x': x.links,
                'y': x.oben,
                'b': x.breite,
                'h': x.hoehe,
              },
          ],
          'aeste': [
            for (final a in plan.aeste)
              {
                'id': a.personId,
                'x1': a.vonX,
                'y1': a.vonY,
                'x2': a.nachX,
                'y2': a.nachY,
                'ranke': rankenGroesse(a),
              },
          ],
          'paare': [
            for (final b in plan.baender)
              {'x1': b.vonX, 'x2': b.nachX, 'y': b.y},
          ],
        },
    });
  }

  /// Ein Verwandtschaftsgrad, wie ihn der Browser in Worte fasst –
  /// dieselbe Form wie beim Lebensbaum.
  static Map<String, Object?> _gradJson(Grad x) => {
    'art': x.art.name,
    if (x.aufwaerts != 0) 'aufwaerts': x.aufwaerts,
    if (x.abwaerts != 0) 'abwaerts': x.abwaerts,
    if (x.halb) 'halb': true,
    if (x.elternArt != null) 'elternArt': x.elternArt!.name,
  };

  static final Map<String, double> _schildmasseJson = () {
    const m = Schildmasse();
    return {
      'rundung': m.rundung,
      'randStark': m.randStark,
      'randSchwach': m.randSchwach,
      'polsterX': m.polsterX,
      'polsterY': m.polsterY,
      'schriftName': m.schriftName,
      'schriftNeben': m.schriftNeben,
      'portraitRadius': m.portraitRadius,
      'portraitAbstand': m.portraitAbstand,
      'zeichenGroesse': m.zeichenGroesse,
    };
  }();

  /// Die Einstellungen, die in der Bibliothek stehen und damit für jedes
  /// verbundene Gerät gelten – geändert wird über die Befehle.
  Future<Response> einstellungen(Request anfrage) async {
    final db = (await _bereich(anfrage)).bibliothek.db;
    final e = await bibliothekseinstellungen(db);
    return _json({
      'papierkorbLeeren': e.papierkorbLeeren,
      'papierkorbTage': e.papierkorbTage,
      'gesichtsschwelle': e.gesichtsschwelle,
      'vorschlaegeAb': e.vorschlaegeAb,
      'auswertenNachImport': e.auswertenNachImport,
      'sucheUebersetzen': e.sucheUebersetzen,
      'angabenSchuetzen': e.angabenSchuetzen,
    });
  }

  /// Was der Browser zum Entwickeln braucht: die gespeicherten Regler –
  /// unter den Spaltennamen, die `entwicklungSpeichern` erwartet –, aus
  /// welcher Datei er rechnet, und Tonkurve und Farbwürfel als fertige
  /// Texturen. Die Tabellen baut derselbe Code wie am Rechner
  /// (develop_color.dart); der Browser schlägt nur nach, wie der Shader.
  ///
  /// Rohformate und HEIC kann ein Browser nicht lesen: Er rechnet dann aus
  /// der Vorschau (`quelle: vorschau`).
  Future<Response> entwickeln(Request anfrage, String id) async {
    final b = (await _bereich(anfrage)).bibliothek;
    final db = b.db;
    final a = await db.assetById(id);
    if (a == null || a.isLocked || a.type != 'IMAGE') {
      return _json({'fehler': 'unbekannt'}, status: 404);
    }
    final e = await db.developSettingsForAsset(id);
    final format =
        (a.dateiformat ?? p.extension(a.originalFileName).replaceFirst('.', ''))
            .toLowerCase();
    final browserTauglich = const {
      'jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp', //
    }.contains(format);

    final kurve = toneCurveAus(e?.toneCurveJson);
    final mischer = colorMixerAus(e?.colorMixerJson);
    CubeLut? lut;
    final lutPfad = e?.lutPath;
    if (lutPfad != null && (e?.lutStrength ?? 0) > 0) {
      try {
        lut = parseCubeLut(await b.pfade.absolute(lutPfad).readAsString());
      } catch (_) {
        // Eine fehlende oder kaputte Tabelle wirkt eben nicht.
      }
    }
    return _json({
      'aufnahme': zeileAlsJson(Rasterzeile.aus(a)),
      'quelle': browserTauglich ? 'original' : 'vorschau',
      'entwickelt': a.developedRelativePath != null,
      'masken': (await db.masksForAsset(a.id)).length,
      'einstellungen': e == null
          ? null
          : {
              'exposure': e.exposure,
              'temperature': e.temperature,
              'tint': e.tint,
              'contrast': e.contrast,
              'shadows': e.shadows,
              'highlights': e.highlights,
              'sharpness': e.sharpness,
              'noise_reduction': e.noiseReduction,
              'clarity': e.clarity,
              'vignette': e.vignette,
              'lut_path': e.lutPath,
              'lut_strength': e.lutStrength,
              'lens_correction_enabled': e.lensCorrectionEnabled,
              'tone_curve_json': e.toneCurveJson,
              'color_mixer_json': e.colorMixerJson,
            },
      if (!kurve.istNeutral)
        'kurve': base64Encode(packCurveLutForTexture(buildCurveLut(kurve))),
      if (!mischer.istNeutral || lut != null) ...{
        'wuerfel': base64Encode(
          packColorCubeForTexture(
            buildColorCube(mischer, lut: lut, lutStaerke: e?.lutStrength ?? 1),
          ),
        ),
        'wuerfelKante': colorCubeSize,
      },
    });
  }

  /// Der Lebensbaum, wie ihn der Rechner zeichnet: dieselbe Anordnung aus
  /// dem Kern (lebensbaumplan/passendeVorlage bzw. das Familienbild aus
  /// dem Geflecht), die Vorlage mit ihren Flächen und Farben, und je Person
  /// was auf ihrem Schild steht. Die Verwandtschaft kommt als Grad – die
  /// Bezeichnung („Großmutter“) setzt der Browser in seiner Sprache.
  ///
  /// Ohne Angaben gilt, was am Rechner zuletzt eingestellt war.
  Future<Response> lebensbaum(Request anfrage) async {
    final db = (await _bereich(anfrage)).bibliothek.db;
    final q = anfrage.url.queryParameters;
    final l = await lebensbaumansicht(
      db,
      fokus: q['fokus'],
      richtung: q['richtung'],
      stil: q['stil'],
      kreis: q['kreis'],
      generationen: int.tryParse(q['generationen'] ?? ''),
      oben: int.tryParse(q['oben'] ?? ''),
      unten: int.tryParse(q['unten'] ?? ''),
    );
    final bild = l.bild;
    if (bild == null) return _json({'fokus': null, 'personen': []});
    List<double> r(g.Rect x) => [x.left, x.top, x.right, x.bottom];
    Map<String, Object?> grad(Grad x) => {
      'art': x.art.name,
      if (x.aufwaerts != 0) 'aufwaerts': x.aufwaerts,
      if (x.abwaerts != 0) 'abwaerts': x.abwaerts,
      if (x.halb) 'halb': true,
      if (x.elternArt != null) 'elternArt': x.elternArt!.name,
    };
    bool hatPortrait(String id) =>
        l.personen[id]?.person.coverFaceCropPath != null;
    final v = bild.vorlage;
    String datei(String asset) => p.basename(asset);
    final o = l.optionen;
    return _json({
      'fokus': l.fokus,
      'optionen': {
        'richtung': o.richtung.name,
        'stil': o.stil.name,
        'generationen': o.generationen,
        'oben': o.oben,
        'unten': o.unten,
        'kreis': o.kreis.name,
      },
      'alle': [
        for (final x in l.alle)
          {'id': x.id, 'name': x.name, 'verwandt': l.verwandt.contains(x.id)},
      ],
      'nachname': l.nachname,
      'fokusName': l.alle.firstWhere((x) => x.id == l.fokus).name,
      'hintergrund': datei(bild.hintergrund),
      'verschwiegen': bild.verschwiegen,
      'vorlage': {
        'groesse': [v.groesse.width, v.groesse.height],
        'titel': r(v.titel),
        if (v.untertitel != null) 'untertitel': r(v.untertitel!),
        'schrift': v.schrift.css,
        'nebenschrift': v.nebenschrift.css,
        if (v.schildBild != null) 'schildBild': datei(v.schildBild!),
      },
      'plaetze': [
        for (final pl in bild.plaetze)
          {
            'rahmen': r(pl.rahmen),
            'schrift': r(pl.schrift),
            'schriftMitPortrait': r(schriftUnterPortraits(pl, hatPortrait)),
            'kreise': [
              for (final (k, id) in portraitKreise(pl, hatPortrait))
                {'kreis': r(k), 'id': id},
            ],
            'personen': pl.personen,
            if (pl.amStamm) 'amStamm': true,
            if (pl.zuSetzen) 'zuSetzen': true,
          },
      ],
      'personen': {
        for (final MapEntry(key: id, value: x) in l.personen.entries)
          id: {
            'name': x.person.name,
            'lebensspanne': x.lebensspanne,
            'bild': x.person.coverFaceCropPath,
            'geschlecht': x.person.geschlecht,
            if (x.grad != null) 'grad': grad(x.grad!),
            if (x.umweg case final u?)
              'umweg': {
                'name': u.ueber.name,
                'geschlecht': u.ueber.geschlecht,
                'schritt': grad(u.schritt),
                'ueberGrad': grad(u.ueberGrad),
              },
          },
      },
    });
  }

  /// Die Orte der Bibliothek: Länder mit ihren Städten, je mit Anzahl und
  /// Titelbild (ortsuebersicht.dart) – Namen in der Sprache `?sprache=`.
  Future<Response> laender(Request anfrage) async {
    final db = (await _bereich(anfrage)).bibliothek.db;
    final sprache = anfrage.url.queryParameters['sprache'] == 'en'
        ? 'en'
        : 'de';
    Map<String, Object?> ort(Ort o) => {
      'anzahl': o.anzahl,
      'titelbild': o.titelbild,
      'miniatur': o.miniatur != null,
    };
    return _json({
      'laender': [
        for (final l in await ortsuebersicht(db))
          {
            'land': l.land.land,
            'name': landAnzeige(l.land.land, sprache),
            ...ort(l.land),
            'staedte': [
              for (final s in l.staedte) {'stadt': s.stadt, ...ort(s)},
            ],
          },
      ],
    });
  }

  /// Die Aufnahmen eines Landes (`?land=`) oder einer Stadt darin
  /// (`&stadt=`).
  Future<Response> amOrt(Request anfrage) async {
    final db = (await _bereich(anfrage)).bibliothek.db;
    final q = anfrage.url.queryParameters;
    final land = q['land'];
    if (land == null || land.isEmpty) {
      return _json({'fehler': 'land fehlt'}, status: 400);
    }
    final stadt = q['stadt'];
    return _json({
      'land': land,
      'stadt': stadt,
      'aufnahmen': [
        for (final r in await aufnahmenAmOrt(
          db,
          land: land,
          stadt: stadt == null || stadt.isEmpty ? null : stadt,
        ))
          zeileAlsJson(r),
      ],
    });
  }

  Future<Response> orte(Request anfrage) async {
    final db = (await _bereich(anfrage)).bibliothek.db;
    final zoom =
        (double.tryParse(anfrage.url.queryParameters['zoom'] ?? '') ?? 4)
            .clamp(0, 20)
            .toDouble();
    final gruppen = kartengruppenVon(
      await db.orteKurz(),
      zoom,
      breite: (o) => o.breite,
      laenge: (o) => o.laenge,
    );
    return _json({
      'gruppen': [
        for (final g in gruppen)
          {
            'breite': g.map((o) => o.breite).reduce((a, b) => a + b) / g.length,
            'laenge': g.map((o) => o.laenge).reduce((a, b) => a + b) / g.length,
            'anzahl': g.length,
            // Die Oberfläche fragt sie nur für eine einzelne Aufnahme oder
            // ganz nah ab. Bei wenig Zoom machten sie die Antwort 1000-mal so
            // gross (2 MB bei 100.000 Fotos).
            if (g.length == 1 || zoom >= 17) 'ids': [for (final o in g) o.id],
          },
      ],
    });
  }

  /// `{ids}` → die Zeilen dazu, in dieser Reihenfolge – für eine Gruppe
  /// der Karte und alles, was Kennungen hat, aber keine Zeilen.
  Future<Response> liste(Request anfrage) async {
    final db = (await _bereich(anfrage)).bibliothek.db;
    final Object? k;
    try {
      k = jsonDecode(await anfrage.readAsString());
    } on FormatException {
      return _json({'fehler': 'kein JSON'}, status: 400);
    }
    final ids = k is Map ? k['ids'] : null;
    if (ids is! List || ids.length > 5000) {
      return _json({'fehler': 'ids fehlen oder zu viele'}, status: 400);
    }
    final zeilen = await db.assetsByIds(ids.cast<String>());
    return _json({
      'aufnahmen': [
        for (final a in zeilen)
          if (!a.isTrashed && !a.isLocked) zeileAlsJson(Rasterzeile.aus(a)),
      ],
    });
  }

  /// „Vor x Jahren“ für den Browser – dieselbe Wahl wie am Rechner und auf
  /// dem Telefon (siehe `waehleRueckblick`).
  Future<Response> erinnerungen(Request anfrage) async {
    final db = (await _bereich(anfrage)).bibliothek.db;
    final heute = DateTime.now();
    final amTag = await db.assetsOnThisDay(heute);
    final imMonat = amTag.isEmpty
        ? await db.assetsInDiesemMonat(heute)
        : const <AssetData>[];
    final r = waehleRueckblick(
      amTag: amTag,
      imMonat: imMonat,
      wann: (a) => a.fileCreatedAt.toLocal(),
      heute: heute,
    );
    return _json({
      'art': r.art.name,
      'monat': heute.month,
      'gruppen': [
        for (final g in r.gruppen)
          {
            'jahreHer': g.jahreHer,
            'aufnahmen': [
              for (final a in g.dinge) zeileAlsJson(Rasterzeile.aus(a)),
            ],
          },
      ],
    });
  }

  /// Der Papierkorb – zurückholen geht über den Befehl `ausDemPapierkorb`.
  Future<Response> papierkorb(Request anfrage) async {
    final db = (await _bereich(anfrage)).bibliothek.db;
    return _json({
      'aufnahmen': [
        for (final a in await db.papierkorb()) zeileAlsJson(Rasterzeile.aus(a)),
      ],
    });
  }

  /// Löscht endgültig aus dem Papierkorb (#296): `{"ids": [...]}` die
  /// ausgewählten, `{"alle": true}` alles darin. Kein Befehl – Befehle
  /// ändern nur die Datenbank, hier gehen Dateien mit, und zwar erst, wenn
  /// die Zeilen sicher fort sind (siehe `leerePapierkorb`). Die Geräte
  /// erfahren es über den Abgleich.
  Future<Response> papierkorbLeeren(Request anfrage) async {
    final Object? k;
    try {
      k = jsonDecode(await anfrage.readAsString());
    } on FormatException {
      return _json({'fehler': 'kein JSON'}, status: 400);
    }
    final ids = k is Map ? k['ids'] : null;
    final alle = k is Map && k['alle'] == true;
    if (ids == null && !alle) {
      return _json({'fehler': 'ids oder alle fehlt'}, status: 400);
    }
    if (ids != null &&
        (ids is! List || ids.length > 50000 || ids.any((i) => i is! String))) {
      return _json({'fehler': 'ids'}, status: 400);
    }
    final konto = kontoVon(anfrage).id;
    final bereich = await _bereich(anfrage);
    final weg = await leereImBereich(
      bereich,
      konto,
      teilungen: teilungen,
      ids: alle ? null : (ids! as List).cast<String>(),
    );
    return _json({
      'geloescht': weg.length,
      'stand': await bereich.bibliothek.protokoll.stand(),
    });
  }

  /// Die Alben mit Anzahl und Titelbild – für den Browser.
  Future<Response> alben(Request anfrage) async {
    final db = (await _bereich(anfrage)).bibliothek.db;
    final liste = await db.alleAlben();
    final anzahlen = await db.albumAnzahlen();
    // Mit wie vielen Konten jedes Album geteilt ist.
    final geteilt = <String, int>{};
    for (final t
        in teilungen?.vonBesitzer(kontoVon(anfrage).id) ??
            const <Albumteilung>[]) {
      geteilt[t.album] = (geteilt[t.album] ?? 0) + 1;
    }
    final automatisch = {
      for (final r
          in regeln?.vonBesitzer(kontoVon(anfrage).id) ?? const <Albumregel>[])
        r.album,
    };
    final titelbilder = await db.albumTitelbilder(liste);
    return _json({
      'alben': [
        for (final a in liste)
          {
            'id': a.id,
            'name': a.name,
            'anzahl': anzahlen[a.id] ?? 0,
            'titelbild': titelbilder[a.id],
            'geteilt': ?geteilt[a.id],
            if (automatisch.contains(a.id)) 'automatisch': true,
          },
      ],
    });
  }

  Future<Response> album(Request anfrage, String id) async {
    final db = (await _bereich(anfrage)).bibliothek.db;
    final a = (await db.alleAlben()).where((x) => x.id == id).firstOrNull;
    if (a == null) return _json({'fehler': 'unbekannt'}, status: 404);
    final aufnahmen = await db.albumAufnahmen(id);
    // Was andere Konten in ein geteiltes Album gelegt haben (#105).
    final von =
        teilungen?.beitragende(
          kontoVon(anfrage).id,
          aufnahmen.map((x) => x.id),
        ) ??
        const {};
    return _json({
      'album': {'id': a.id, 'name': a.name},
      'aufnahmen': [
        for (final x in aufnahmen)
          {...zeileAlsJson(Rasterzeile.aus(x)), 'von': ?von[x.id]?.name},
      ],
    });
  }

  /// Die Personen mit Anzahl und Gesichtsausschnitt (ein Pfad für
  /// `/api/v1/dateien/…`), die mit den meisten Aufnahmen zuerst.
  Future<Response> personen(Request anfrage) async {
    final db = (await _bereich(anfrage)).bibliothek.db;
    final liste = await db.select(db.people).get();
    final anzahlen = await db.personenAnzahlen();
    final sortiert = [...liste]
      ..sort((a, b) => (anzahlen[b.id] ?? 0).compareTo(anzahlen[a.id] ?? 0));
    return _json({
      'personen': [
        for (final p in sortiert)
          {
            'id': p.id,
            'name': p.name,
            'anzahl': anzahlen[p.id] ?? 0,
            'bild': p.coverFaceCropPath,
          },
      ],
    });
  }

  /// Ein von Hand aufgezogenes Gesicht (Issue #190): `{kasten: [x, y, b, h],
  /// personId?}`, der Kasten in Anteilen des Bildes. Der Server schneidet
  /// es aus dem Original aus und bettet es ein; über den Abgleich kommt es
  /// zu allen Geräten – deren Kopien dürfen das nicht selbst.
  Future<Response> gesichtAnlegen(Request anfrage, String id) async {
    final b = (await _bereich(anfrage)).bibliothek;
    final Object? k;
    try {
      k = jsonDecode(await anfrage.readAsString());
    } on FormatException {
      return _json({'fehler': 'kein JSON'}, status: 400);
    }
    final kasten = k is Map ? k['kasten'] : null;
    if (kasten is! List ||
        kasten.length != 4 ||
        kasten.any((w) => w is! num || w < 0 || w > 1)) {
      return _json({'fehler': 'kasten fehlt'}, status: 400);
    }
    final [x, y, breite, hoehe] = [
      for (final w in kasten) (w as num).toDouble(),
    ];
    if (!gesichtsrahmenGrossGenug(breite, hoehe)) {
      return _json({'fehler': 'Rahmen zu klein'}, status: 400);
    }
    final personId = k is Map && k['personId'] is String
        ? k['personId'] as String
        : null;
    final person = personId == null
        ? null
        : await (b.db.select(
            b.db.people,
          )..where((t) => t.id.equals(personId))).getSingleOrNull();
    if (personId != null && person == null) {
      return _json({'fehler': 'Person unbekannt'}, status: 400);
    }
    final f = await b.auswertungen.gesichtVonHandAnlegen(
      assetId: id,
      x: x,
      y: y,
      breite: breite,
      hoehe: hoehe,
      personId: personId,
    );
    if (f == null) return _json({'fehler': 'unbekannt'}, status: 404);
    return _json({
      'gesicht': {
        'id': f.id,
        'ausschnitt': f.cropRelativePath,
        'aufnahme': f.assetId,
        'kasten': gesichtskasten(f),
        'person': person == null
            ? null
            : {'id': person.id, 'name': person.name},
      },
    }, status: 201);
  }

  /// Ähnliche Gesichter ohne Namen, zum Benennen – dieselbe Rechnung wie
  /// am Rechner (gesichtsuebersicht.dart).
  Future<Response> gesichterOhneNamen(Request anfrage) async {
    final db = (await _bereich(anfrage)).bibliothek.db;
    final o = await gesichtsuebersicht.gesichterOhneNamen(db);
    return _json({
      'gruppen': [
        for (final g in o.gruppen)
          {
            'gesichter': [for (final f in g.gesichter) _gesicht(f)],
            'vorschlag': g.vorschlag == null
                ? null
                : {
                    'id': g.vorschlag!.id,
                    'name': g.vorschlag!.name,
                    'bild': g.vorschlag!.coverFaceCropPath,
                  },
            'aehnlichkeit': g.aehnlichkeit,
          },
      ],
      'schwelle': o.schwelle,
      'einzeln': o.einzeln,
      'angesehen': o.angesehen,
      'gesamt': o.gesamt,
      // Auch wenn nichts mehr offen ist: Über „Ignoriert“ holt man
      // einzelne zurück (#192).
      'ignoriert': await db.ignoredFacesCount(),
    });
  }

  static Map<String, Object?> _gesicht(FaceData f) => {
    'id': f.id,
    'ausschnitt': f.cropRelativePath,
    // Für „Im Foto zeigen“ (Issue #189): der Ausschnitt allein sagt oft
    // nicht genug.
    'aufnahme': f.assetId,
    'kasten': gesichtskasten(f),
  };

  /// Die beiseitegelegten Gesichter, wie der Reiter „Ignoriert“ am
  /// Rechner: die ersten 200 und wie viele es insgesamt sind (#192).
  Future<Response> gesichterIgnoriert(Request anfrage) async {
    final db = (await _bereich(anfrage)).bibliothek.db;
    return _json({
      'gesichter': [for (final f in await db.ignoredFaces()) _gesicht(f)],
      'gesamt': await db.ignoredFacesCount(),
    });
  }

  /// Alle unbenannten Gesichter auf einmal ignorieren oder löschen – wie
  /// das Menü über „Ohne Namen“ am Rechner (#192). Die Kennungen sucht der
  /// Server heraus, weil der Browser keine Kopie hat; ausgeführt wird der
  /// Befehl, der sie beim Namen nennt, wie von jedem anderen Gerät.
  Future<Response> unbenannteGesichter(Request anfrage) async {
    final db = (await _bereich(anfrage)).bibliothek.db;
    final Object? k;
    try {
      k = jsonDecode(await anfrage.readAsString());
    } on FormatException {
      return _json({'fehler': 'kein JSON'}, status: 400);
    }
    final aktion = k is Map ? k['aktion'] : null;
    final List<String> ids;
    switch (aktion) {
      case 'ignorieren':
        ids = [for (final f in await db.allUnassignedFaces()) f.id];
        if (ids.isNotEmpty) {
          await db.fuehreAus(GesichterBeiseitelegen(ids, true));
        }
      case 'loeschen':
        ids = await db.unbenannteErkennungen();
        if (ids.isNotEmpty) await db.fuehreAus(GesichterLoeschen(ids));
      default:
        return _json({'fehler': 'aktion fehlt'}, status: 400);
    }
    return _json({'anzahl': ids.length});
  }

  /// Weitere Fotos einer Person zum Bestätigen – wie „Vorschläge suchen“
  /// am Rechner (gesichtsuebersicht.dart, weitereFotosVon).
  Future<Response> personVorschlaege(Request anfrage, String id) async {
    final db = (await _bereich(anfrage)).bibliothek.db;
    final w = await gesichtsuebersicht.weitereFotosVon(db, id);
    if (w == null) return _json({'fehler': 'unbekannt'}, status: 404);
    return _json({
      'schwelle': w.schwelle,
      'allgemein': w.allgemein,
      'vorschlaege': [
        for (final v in w.vorschlaege)
          {
            'id': v.gesicht.id,
            'ausschnitt': v.gesicht.cropRelativePath,
            'aufnahme': v.gesicht.assetId,
            'kasten': gesichtskasten(v.gesicht),
            'aehnlichkeit': v.aehnlichkeit,
          },
      ],
    });
  }

  Future<Response> person(Request anfrage, String id) async {
    final db = (await _bereich(anfrage)).bibliothek.db;
    final p = await (db.select(
      db.people,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (p == null) return _json({'fehler': 'unbekannt'}, status: 404);
    return _json({
      'person': {'id': p.id, 'name': p.name},
      'aufnahmen': [
        for (final x in await db.assetsFuerPersonen([id]))
          zeileAlsJson(Rasterzeile.aus(x)),
      ],
    });
  }

  Future<Response> aufnahme(Request anfrage, String id) async {
    final db = (await _bereich(anfrage)).bibliothek.db;
    final a = await db.assetById(id);
    if (a == null || a.isLocked) {
      return _json({'fehler': 'unbekannt'}, status: 404);
    }
    return _json(a.toJson());
  }

  /// Welche Dateien schon in der Bibliothek liegen: `{pruefsummen: [...]}`
  /// (SHA-256, hexadezimal) → `{vorhanden: {pruefsumme: kennung}}`.
  ///
  /// Für die Sicherung der Kamerarolle: Was schon da ist – etwa weil die
  /// Bibliothek vom Rechner umgezogen ist –, muss das Telefon nicht erst
  /// hochladen, damit der Server es als Dublette verwirft. Zählt auch,
  /// was im Papierkorb liegt; der Import nähme es ebenfalls nicht noch
  /// einmal.
  Future<Response> pruefsummen(Request anfrage) async {
    final k = jsonDecode(await anfrage.readAsString());
    final liste = k is Map ? k['pruefsummen'] : null;
    if (liste is! List || liste.length > 1000) {
      return _json({'fehler': 'pruefsummen fehlt oder zu viele'}, status: 400);
    }
    final summen = {
      for (final s in liste)
        if (s is String && _pruefsummeMuster.hasMatch(s)) s,
    }.toList();
    final db = (await _bereich(anfrage)).bibliothek.db;
    final vorhanden = <String, String>{};
    if (summen.isNotEmpty) {
      final zeilen =
          await (db.selectOnly(db.assets)
                ..addColumns([db.assets.checksum, db.assets.id])
                ..where(db.assets.checksum.isIn(summen)))
              .get();
      for (final z in zeilen) {
        vorhanden[z.read(db.assets.checksum)!] = z.read(db.assets.id)!;
      }
    }
    return _json({'vorhanden': vorhanden});
  }

  static final _pruefsummeMuster = RegExp(r'^[0-9a-f]{64}$');

  /// `miniatur`, `vorschau`, `ansicht`, `voll` oder `original` – mit
  /// Teilabruf (`Range`), damit sich ein Video abspielen lässt, ohne es
  /// ganz zu laden.
  Future<Response> datei(Request anfrage, String id, String art) async {
    final bereich = await _bereich(anfrage);
    final a = await bereich.bibliothek.db.assetById(id);
    if (a == null || a.isLocked) return Response.notFound(null);
    return dateiAus(anfrage, bereich, a, art);
  }

  /// Die Auslieferung zu [datei] für eine schon gefundene Aufnahme – auch
  /// für Alben, die ein anderes Konto teilt (#105).
  Future<Response> dateiAus(
    Request anfrage,
    Kontobereich bereich,
    AssetData a,
    String art,
  ) async {
    final b = bereich.bibliothek;
    if (art == 'abspielbar') return _abspielbar(anfrage, b, a);
    if (art == 'jpeg') return _alsJpeg(anfrage, b, a);
    if (art == 'voll') return _voll(anfrage, b, a);
    final relativ = switch (art) {
      'miniatur' => a.thumbnailRelativePath,
      // Was der Betrachter zeigt – wie in den Apps: restauriert,
      // entwickelt, gekürzt, Vorschau, Original (displayRelativePath).
      'ansicht' =>
        a.type == 'IMAGE'
            ? displayRelativePath(a)
            : (a.previewRelativePath ?? a.thumbnailRelativePath),
      'vorschau' =>
        a.previewRelativePath ??
            (a.type == 'IMAGE' ? a.relativePath : a.thumbnailRelativePath),
      'original' => a.relativePath,
      // Was der Betrachter abspielt – wie in den Apps: gekürzt, sonst das
      // Original.
      'wiedergabe' =>
        a.type == 'VIDEO' ? (a.trimmedRelativePath ?? a.relativePath) : null,
      _ => null,
    };
    if (relativ == null) return Response.notFound(null);
    final datei = b.pfade.absolute(relativ);
    // Die Pfade stammen aus der eigenen Datenbank. Geprüft wird trotzdem:
    // Was ausgeliefert wird, liegt in der Bibliothek, nirgends sonst.
    if (!p.isWithin(b.pfade.root.path, datei.path) || !await datei.exists()) {
      return Response.notFound(null);
    }
    return dateiAntwort(anfrage, datei);
  }

  /// Das Foto in voller Auflösung für den Betrachter (#256) – im Browser
  /// und auf dem Handy, die von HEIC und RAW bis 3.49.9 nur die Vorschau mit
  /// 2048 Punkten bekamen.
  ///
  /// Dasselbe Bild wie `ansicht`, nur nie die verkleinerte Vorschau (siehe
  /// [vollbildQuelle]). Was Browser und Handy selbst lesen, geht unverändert
  /// hinaus; alles andere als JPEG in Originalgrösse, ohne Angaben und
  /// damit ohne Ort (siehe [Vollbilder]). `422`, wenn es sich nicht wandeln
  /// lässt.
  Future<Response> _voll(Request anfrage, Bibliothek b, AssetData a) async {
    if (a.type != 'IMAGE') return Response.notFound(null);
    final relativ = vollbildQuelle(a);
    final quelle = b.pfade.absolute(relativ);
    if (!p.isWithin(b.pfade.root.path, quelle.path) || !await quelle.exists()) {
      return Response.notFound(null);
    }
    if (istDirektAnzeigbar(relativ)) return dateiAntwort(anfrage, quelle);
    final fertig = await vollbilder.bereit(
      Directory(p.join(b.ordner.path, 'vollbild')),
      a.id,
      quelle,
      () => _wandle(b, a, quelle, maxDimension: null),
    );
    if (fertig == null) {
      return _json({'fehler': 'nicht umwandelbar'}, status: 422);
    }
    return dateiAntwort(anfrage, fertig);
  }

  /// Eine Collage aus 2 bis 9 eigenen Fotos (#301): `{ids, vorlage?,
  /// format?, abstand?, ecken?, hintergrund?: "#rrggbb", vorschau?}`.
  /// Mit `vorschau` kommt ein kleines JPEG zurück, sonst 201 `{aufnahme,
  /// ausgang}` – die Collage liegt dann in der Bibliothek, aufgenommen zur
  /// Zeit des jüngsten Fotos darin.
  Future<Response> collage(Request anfrage) async {
    final bereich = await _bereich(anfrage);
    final b = bereich.bibliothek;
    final Object? k;
    try {
      k = jsonDecode(await anfrage.readAsString());
    } on FormatException {
      return _json({'fehler': 'kein JSON'}, status: 400);
    }
    if (k is! Map) return _json({'fehler': 'kein JSON'}, status: 400);
    final ids = k['ids'];
    if (ids is! List ||
        ids.length < collageMindestens ||
        ids.length > collageHoechstens ||
        ids.any((x) => x is! String)) {
      return _json({
        'fehler': '$collageMindestens bis $collageHoechstens Fotos',
      }, status: 400);
    }
    final aufnahmen = <AssetData>[];
    for (final id in ids.cast<String>()) {
      final a = await b.db.assetById(id);
      if (a == null || a.isTrashed || a.isLocked || a.type != 'IMAGE') {
        return _json({'fehler': 'Foto unbekannt'}, status: 404);
      }
      aufnahmen.add(a);
    }
    final vorlage = k['vorlage'], formatname = k['format'];
    final abstand = k['abstand'], ecken = k['ecken'];
    final hintergrund = k['hintergrund'];
    if ((vorlage != null && vorlage is! String) ||
        (formatname != null && formatname is! String) ||
        (abstand != null && abstand is! num) ||
        (ecken != null && ecken is! num) ||
        (hintergrund != null && hintergrund is! String)) {
      return _json({'fehler': 'Angaben unlesbar'}, status: 400);
    }
    final vorschau = k['vorschau'] == true;
    final format =
        Collageformat.namens(formatname as String?) ?? Collageformat.quadrat;
    // Die Vorschau in einem Viertel der Grösse – schnell genug zum Spielen.
    final teiler = vorschau ? 4 : 1;
    final auftrag0 = Collageauftrag(
      bilder: const [],
      vorlage: collagevorlage(aufnahmen.length, vorlage as String?),
      breite: format.breite ~/ teiler,
      hoehe: format.hoehe ~/ teiler,
      abstand: (abstand as num?)?.toDouble() ?? 0.01,
      ecken: (ecken as num?)?.toDouble() ?? 0,
      hintergrund: collagefarbe(hintergrund as String?),
      qualitaet: vorschau ? 80 : 92,
    );
    final kante = auftrag0.kante;
    final bilder = <Uint8List>[];
    for (final a in aufnahmen) {
      final datei = b.pfade.absolute(displayRelativePath(a));
      if (!p.isWithin(b.pfade.root.path, datei.path) || !await datei.exists()) {
        return _json({'fehler': 'Datei fehlt'}, status: 404);
      }
      final bytes = await _wandle(b, a, datei, maxDimension: kante);
      if (bytes == null) {
        return _json({'fehler': 'nicht umwandelbar'}, status: 422);
      }
      bilder.add(bytes);
    }
    final juengste = aufnahmen
        .map((a) => a.fileCreatedAt)
        .reduce((x, y) => x.isAfter(y) ? x : y);
    final jpeg = await zeichneCollage(
      Collageauftrag(
        bilder: bilder,
        vorlage: auftrag0.vorlage,
        breite: auftrag0.breite,
        hoehe: auftrag0.hoehe,
        abstand: auftrag0.abstand,
        ecken: auftrag0.ecken,
        hintergrund: auftrag0.hintergrund,
        qualitaet: auftrag0.qualitaet,
        zeit: juengste,
      ),
    );
    if (vorschau) {
      return Response.ok(
        jpeg,
        headers: {
          'content-type': 'image/jpeg',
          'content-length': '${jpeg.length}',
          'cache-control': 'private, no-store',
        },
      );
    }
    final ordner = await Directory.systemTemp.createTemp('pv_collage_');
    try {
      final datei = File(p.join(ordner.path, collageDateiname(juengste)));
      await datei.writeAsBytes(jpeg, flush: true);
      final ergebnis = await b.importe.importFile(datei.path);
      // Dieselbe Collage noch einmal: Sie liegt schon da.
      if (ergebnis.outcome == ImportOutcome.duplicateSkipped) {
        final da = await b.kennungFuer(sha256.convert(jpeg).toString());
        if (da != null) {
          return _json({'aufnahme': da, 'ausgang': ergebnis.outcome.name});
        }
      }
      final id = ergebnis.assetId;
      if (ergebnis.outcome != ImportOutcome.imported || id == null) {
        return _json({
          'fehler': 'Import gescheitert: ${ergebnis.error}',
        }, status: 500);
      }
      try {
        await b.nachbearbeitung.neueAufnahme(id);
      } catch (f) {
        protokoll('Nachbearbeitung einer Collage gescheitert: $f');
      }
      bereich.auswertung.anstossen();
      return _json({
        'aufnahme': id,
        'ausgang': ergebnis.outcome.name,
      }, status: 201);
    } finally {
      await ordner.delete(recursive: true);
    }
  }

  /// Wandelt [datei] von [a] in ein JPEG. Das Werkzeug richtet sich nach
  /// der Endung; ein Standbild unter einem Videonamen – `IMG_1711.MOV` mit
  /// HEIC-Inhalt – ging so an dcraw_emu und scheiterte (#265). Das Original
  /// bekommt deshalb eine Verknüpfung mit der Endung seines Inhalts (siehe
  /// [bildendung]); entwickelte und restaurierte Fassungen tragen ihre
  /// Endung zu Recht.
  Future<Uint8List?> _wandle(
    Bibliothek b,
    AssetData a,
    File datei, {
    required int? maxDimension,
    double quality = 0.9,
  }) async {
    final ist = p.extension(datei.path).toLowerCase();
    final soll = p.equals(datei.path, b.pfade.absolute(a.relativePath).path)
        ? bildendung(a.relativePath, a.dateiformat)
        : ist;
    if (soll == ist) {
      return b.bildwerkzeuge.convertToJpegBytes(
        datei,
        maxDimension: maxDimension,
        quality: quality,
      );
    }
    final ordner = await Directory.systemTemp.createTemp('pv_wandeln_');
    final verweis = Link(p.join(ordner.path, 'quelle$soll'));
    try {
      await verweis.create(datei.path);
      return await b.bildwerkzeuge.convertToJpegBytes(
        File(verweis.path),
        maxDimension: maxDimension,
        quality: quality,
      );
    } finally {
      // Erst der Verweis selbst, dann der leere Ordner – nie rekursiv,
      // damit nichts dem Verweis bis zum Original folgen kann.
      if (await verweis.exists()) await verweis.delete();
      await ordner.delete();
    }
  }

  /// Das Foto als JPEG zum Herunterladen und Teilen (#210) – für Browser und
  /// Telefon, die ein DNG, CR3 oder HEIC nicht selbst wandeln können.
  ///
  /// Gewandelt wird, was man sieht: restauriert, sonst entwickelt, sonst das
  /// Original – nie die verkleinerte Vorschau. Die entwickelte Fassung liegt
  /// höchstens 4096 px gross vor; mehr gibt es von ihr nicht.
  ///
  /// `kante` begrenzt die längere Seite in Pixeln (fehlt sie oder ist sie 0:
  /// volle Grösse), `qualitaet` liegt zwischen 1 und 100 (Vorgabe 90).
  /// Aufnahmezeitpunkt und Kamera kommen mit, der Ort nicht (siehe
  /// [mitAufnahmeangaben]).
  Future<Response> _alsJpeg(Request anfrage, Bibliothek b, AssetData a) async {
    if (a.type != 'IMAGE') return Response.notFound(null);
    final q = anfrage.url.queryParameters;
    final kante = int.tryParse(q['kante'] ?? '0');
    final qualitaet = int.tryParse(q['qualitaet'] ?? '90');
    if (kante == null ||
        kante < 0 ||
        kante > 65536 ||
        qualitaet == null ||
        qualitaet < 1 ||
        qualitaet > 100) {
      return _json({'fehler': 'kante oder qualitaet'}, status: 400);
    }
    final datei = b.pfade.absolute(
      a.restoredRelativePath ?? a.developedRelativePath ?? a.relativePath,
    );
    if (!p.isWithin(b.pfade.root.path, datei.path) || !await datei.exists()) {
      return Response.notFound(null);
    }
    final bytes = await _wandle(
      b,
      a,
      datei,
      maxDimension: kante == 0 ? null : kante,
      quality: qualitaet / 100,
    );
    if (bytes == null) {
      return _json({'fehler': 'nicht umwandelbar'}, status: 422);
    }
    final fertig = mitAufnahmeangaben(bytes, a);
    final name = '${p.basenameWithoutExtension(a.originalFileName)}.jpg';
    final einfach = name.replaceAll(RegExp(r'[^A-Za-z0-9._ -]'), '_');
    return Response.ok(
      fertig,
      headers: {
        'content-type': 'image/jpeg',
        'content-length': '${fertig.length}',
        'content-disposition':
            'attachment; filename="$einfach"; '
            "filename*=UTF-8''${Uri.encodeComponent(name)}",
        'cache-control': 'private, no-store',
      },
    );
  }

  /// Ein Video als H.264 (siehe [Videofassungen]): die fertige Fassung
  /// (mit `?pruefen=1` nur `{"bereit": true}`), sonst `202` mit
  /// `{"bereit": false}` – dann wird sie gerade erzeugt, und der Browser
  /// fragt gleich noch einmal. `422`, wenn sie sich nicht erzeugen lässt.
  Future<Response> _abspielbar(
    Request anfrage,
    Bibliothek b,
    AssetData a,
  ) async {
    if (a.type != 'VIDEO') return Response.notFound(null);
    // Aus dem, was der Betrachter zeigt: gekürzt, sonst das Original. Der
    // Name sagt, aus welchem – sonst bliebe nach dem Zurücknehmen einer
    // Kürzung die gekürzte Fassung liegen.
    final gekuerzt = a.trimmedRelativePath != null;
    final original = b.pfade.absolute(a.trimmedRelativePath ?? a.relativePath);
    if (!p.isWithin(b.pfade.root.path, original.path) ||
        !await original.exists()) {
      return Response.notFound(null);
    }
    final speicher = Directory(p.join(b.ordner.path, 'abspielbar'));
    final name = gekuerzt ? '${a.id}-gekuerzt' : a.id;
    final fertig = await videofassungen.bereit(speicher, name, original);
    // `?pruefen=1` fragt nur nach, ohne die Datei zu holen.
    if (fertig != null && anfrage.url.queryParameters['pruefen'] != null) {
      return _json({'bereit': true});
    }
    if (fertig != null) return dateiAntwort(anfrage, fertig);
    if (videofassungen.gescheitert.contains(
      Videofassungen.ziel(speicher, name).path,
    )) {
      return _json({
        'bereit': false,
        'fehler': 'nicht umwandelbar',
      }, status: 422);
    }
    return _json({'bereit': false}, status: 202);
  }
}

/// Wo eine Seite der Zeitleiste endet: Zeitpunkt und Kennung der letzten
/// Aufnahme, als Text für die Adresse.
/// Die Bibliothek eines Partners in der Zeitleiste (#299).
class _Partnerquelle {
  _Partnerquelle(this.freigabe, this.db, this.name);

  final Partnerfreigabe freigabe;
  final AppDatabase db;
  final String name;
}

class _Lesezeichen {
  const _Lesezeichen(this.zeit, this.id);

  final DateTime zeit;
  final String id;

  String get text => '${zeit.millisecondsSinceEpoch}~$id';

  static _Lesezeichen? lies(String? text) {
    if (text == null) return null;
    final i = text.indexOf('~');
    if (i < 0) return null;
    final ms = int.tryParse(text.substring(0, i));
    if (ms == null) return null;
    return _Lesezeichen(
      DateTime.fromMillisecondsSinceEpoch(ms),
      text.substring(i + 1),
    );
  }
}
