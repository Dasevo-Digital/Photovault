// ignore_for_file: avoid_print
// Zweite Prüfrunde, Prüfer r2-ki: KI-Einträge, die in der ersten Runde
// teilweise oder ungeprüft blieben (pruefkatalog/teile/KI.json), mit dem,
// was der Prüfstand jetzt hat – Sprachvideos aus say und ffmpeg (unter
// pruefkatalog/fixtures, r2ki_*), freie Porträts und alte Fotos aus
// pruefkatalog/fixtures-ml, eine ältere Serverfassung und ein Wegwerf-Server,
// der sich aus Sicht der App anhalten lässt.
//
// Hier stehen auch die Netzhilfen für katalog_r2_ki_ort_test.dart,
// katalog_r2_ki_modelle_test.dart und katalog_r2_ki_neustart_test.dart:
//
// * [Netzweiche] (HttpOverrides) leitet jeden Abruf an einen fremden
//   Rechner zur [Attrappe] um – einem TLS-Server auf 127.0.0.1 mit einem
//   Wegwerf-Zertifikat aus pruefkatalog/arbeit/r2-ki. Sie liefert künstliche
//   Kartenkacheln, Geländehöhen (Terrarium) und eine leere
//   Overpass-Antwort und schreibt jeden Abruf mit. So verlässt kein Abruf
//   der App den Rechner. Ausnahme: [Netzweiche.offen] für den
//   Modell-Download aus den Katalog-Adressen.
// * [Vermittler] steht zwischen App und Wegwerf-Server, schreibt Pfade und
//   Anmeldung mit und lässt sich anhalten – für die App ist der Server
//   dann weg wie ein beendeter Prozess.
//
// Laufen lassen nur über die Warteschlange (Quelle: Worktree pruefrunde2):
//   PV_E2E_REPO=…/pruefrunde2 PV_E2E_SERVER=1 PV_E2E_KARTEN=an \
//   PV_E2E_ARGS='--dart-define=PV_R2_ALTSERVER=http://127.0.0.1:18880' \
//   …/pruefkatalog/tools/e2e_queue.sh r2-ki integration_test/katalog_r2_ki_test.dart
// PV_R2_ALTSERVER ist ein Wegwerf-Server der Fassung 3.49.3 (eigener
// Worktree server-alt-r2ki, tools/wegwerf_server.sh mit PV_SERVER_REPO).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:kern/db/database.dart';
import 'package:kern/services/bildwerkzeuge.dart' show Bildwerkzeuge;
import 'package:kern/services/model_catalog.dart';
import 'package:kern/services/textstellen.dart' show Textstelle;
import 'package:path/path.dart' as p;
import 'package:photo_vault/screens/asset_viewer_screen.dart';
import 'package:photo_vault/screens/automation_rules_screen.dart';
import 'package:photo_vault/screens/face_review_screen.dart';
import 'package:photo_vault/screens/settings_screen.dart';
import 'package:photo_vault/services/meldungsdienst.dart' show melde;
import 'package:photo_vault/services/native_image_converter.dart'
    show AppBildwerkzeuge;
import 'package:photo_vault/widgets/gesichtsrahmen.dart';

import 'katalog_ans_test.dart' as ans;
import 'katalog_ki_test.dart' as ki;
import 'katalog_kit.dart';

// =============================================================================
// Gemeinsame Hilfen (auch für die übrigen katalog_r2_ki_*-Dateien)
// =============================================================================

/// Arbeitsordner dieses Prüfers (Zertifikat der Attrappe).
const r2Arbeit = String.fromEnvironment('PV_R2_ARBEIT');

/// Wegwerf-Server der Fassung 3.49.3 (ohne `funktionen.importplan`).
const altServer = String.fromEnvironment('PV_R2_ALTSERVER');

/// Obergrenze je Prüfung.
const lang = Timeout(Duration(minutes: 25));

/// Freie Porträts, alte Fotos und Bildinhalte (pruefkatalog/fixtures-ml).
String get mlFixtures => p.join(p.dirname(fixturesOrdner), 'fixtures-ml');

/// Eine Datei aus fixtures-ml, in den Eingang kopiert.
File mlFixture(String relativ, {String? als}) {
  final q = File(p.join(mlFixtures, relativ));
  if (!q.existsSync()) throw StateError('Fixture fehlt: ${q.path}');
  return q.copySync(p.join(eingang.path, als ?? p.basename(relativ)));
}

bool findet(Finder f) {
  try {
    return f.evaluate().isNotEmpty;
  } on StateError {
    return false;
  }
}

/// Die Kennung der Aufnahme mit dem Dateinamen [name].
Future<String> idVon(WidgetTester tester, String name) async {
  final z = await ki.sql(
    tester,
    'SELECT id FROM assets WHERE original_file_name = ?',
    [name],
  );
  if (z.isEmpty) throw StateError('Keine Aufnahme $name');
  return z.first['id']! as String;
}

// --- Netz --------------------------------------------------------------------

bool istLokal(String host) =>
    host == '127.0.0.1' || host == 'localhost' || host == '::1';

/// Ein Abruf bei der [Attrappe].
class Abruf {
  Abruf(this.host, this.pfad, this.methode, this.anmeldung);
  final String host;
  final String pfad;
  final String methode;
  final bool anmeldung;
  final zeit = DateTime.now();
  @override
  String toString() => '$methode $host$pfad${anmeldung ? ' (Anmeldung)' : ''}';
}

/// Lenkt jeden Abruf an einen fremden Rechner zur [Attrappe] um.
class Netzweiche extends HttpOverrides {
  /// Nur für den Modell-Download aus den Katalog-Adressen.
  bool offen = false;
  Attrappe? attrappe;

  /// Abrufe, die ohne Attrappe abgewiesen wurden.
  final abgewiesen = <Uri>[];

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _Weiche(super.createHttpClient(context), this);
}

final netzweiche = Netzweiche();
final attrappe = Attrappe();

/// Ein HttpClient, der selbst entscheidet, wohin verbunden wird – auch
/// wenn die App eine eigene Verbindungsfabrik setzt (Kartenkacheln): Die
/// wird nur für lokale Ziele benutzt.
class _Weiche implements HttpClient {
  _Weiche(this._innen, this._w) {
    _innen.connectionFactory = _verbinde;
  }

  final HttpClient _innen;
  final Netzweiche _w;
  Future<ConnectionTask<Socket>> Function(Uri, String?, int?)? _eigene;

  Future<ConnectionTask<Socket>> _verbinde(Uri uri, String? ph, int? pp) {
    if (_w.offen || istLokal(uri.host)) {
      final eigene = _eigene;
      if (eigene != null) return eigene(uri, ph, pp);
      return uri.scheme == 'https'
          ? SecureSocket.startConnect(uri.host, uri.port)
          : Socket.startConnect(uri.host, uri.port);
    }
    final a = _w.attrappe;
    if (a == null || !a.laeuft) {
      _w.abgewiesen.add(uri);
      return Future.error(
        SocketException('Netz in der Prüfung gesperrt: ${uri.host}'),
      );
    }
    return uri.scheme == 'https'
        ? SecureSocket.startConnect(
            InternetAddress.loopbackIPv4,
            a.tlsPort,
            onBadCertificate: (_) => true,
          )
        : Socket.startConnect(InternetAddress.loopbackIPv4, a.port);
  }

  @override
  bool get autoUncompress => _innen.autoUncompress;
  @override
  set autoUncompress(bool v) => _innen.autoUncompress = v;
  @override
  Duration? get connectionTimeout => _innen.connectionTimeout;
  @override
  set connectionTimeout(Duration? v) => _innen.connectionTimeout = v;
  @override
  Duration get idleTimeout => _innen.idleTimeout;
  @override
  set idleTimeout(Duration v) => _innen.idleTimeout = v;
  @override
  int? get maxConnectionsPerHost => _innen.maxConnectionsPerHost;
  @override
  set maxConnectionsPerHost(int? v) => _innen.maxConnectionsPerHost = v;
  @override
  String? get userAgent => _innen.userAgent;
  @override
  set userAgent(String? v) => _innen.userAgent = v;
  @override
  void addCredentials(Uri url, String realm, HttpClientCredentials c) =>
      _innen.addCredentials(url, realm, c);
  @override
  void addProxyCredentials(
    String host,
    int port,
    String realm,
    HttpClientCredentials c,
  ) => _innen.addProxyCredentials(host, port, realm, c);
  @override
  set authenticate(
    Future<bool> Function(Uri url, String scheme, String? realm)? f,
  ) => _innen.authenticate = f;
  @override
  set authenticateProxy(
    Future<bool> Function(String host, int port, String scheme, String? realm)?
    f,
  ) => _innen.authenticateProxy = f;
  @override
  set badCertificateCallback(
    bool Function(X509Certificate cert, String host, int port)? callback,
  ) => _innen.badCertificateCallback = callback;
  @override
  set connectionFactory(
    Future<ConnectionTask<Socket>> Function(
      Uri url,
      String? proxyHost,
      int? proxyPort,
    )?
    f,
  ) => _eigene = f;
  @override
  set findProxy(String Function(Uri url)? f) => _innen.findProxy = f;
  @override
  set keyLog(Function(String line)? callback) => _innen.keyLog = callback;
  @override
  void close({bool force = false}) => _innen.close(force: force);
  @override
  Future<HttpClientRequest> open(
    String method,
    String host,
    int port,
    String path,
  ) => _innen.open(method, host, port, path);
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) =>
      _innen.openUrl(method, url);
  @override
  Future<HttpClientRequest> get(String host, int port, String path) =>
      _innen.get(host, port, path);
  @override
  Future<HttpClientRequest> getUrl(Uri url) => _innen.getUrl(url);
  @override
  Future<HttpClientRequest> post(String host, int port, String path) =>
      _innen.post(host, port, path);
  @override
  Future<HttpClientRequest> postUrl(Uri url) => _innen.postUrl(url);
  @override
  Future<HttpClientRequest> put(String host, int port, String path) =>
      _innen.put(host, port, path);
  @override
  Future<HttpClientRequest> putUrl(Uri url) => _innen.putUrl(url);
  @override
  Future<HttpClientRequest> delete(String host, int port, String path) =>
      _innen.delete(host, port, path);
  @override
  Future<HttpClientRequest> deleteUrl(Uri url) => _innen.deleteUrl(url);
  @override
  Future<HttpClientRequest> patch(String host, int port, String path) =>
      _innen.patch(host, port, path);
  @override
  Future<HttpClientRequest> patchUrl(Uri url) => _innen.patchUrl(url);
  @override
  Future<HttpClientRequest> head(String host, int port, String path) =>
      _innen.head(host, port, path);
  @override
  Future<HttpClientRequest> headUrl(Uri url) => _innen.headUrl(url);
}

/// Das „Netz“ der Prüfung: künstliche Kacheln, Höhen und Overpass auf
/// 127.0.0.1, mit Mitschrift.
class Attrappe {
  HttpServer? _tls;
  HttpServer? _klar;
  final abrufe = <Abruf>[];
  final _vorrat = <String, Uint8List>{};

  bool get laeuft => _tls != null;
  int get tlsPort => _tls!.port;
  int get port => _klar!.port;

  Future<void> starte() async {
    if (_tls != null) return;
    final ctx = SecurityContext()
      ..useCertificateChain(p.join(r2Arbeit, 'attrappe.crt'))
      ..usePrivateKey(p.join(r2Arbeit, 'attrappe.key'));
    _tls = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, ctx);
    _klar = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _tls!.listen((r) => unawaited(_bediene(r)));
    _klar!.listen((r) => unawaited(_bediene(r)));
  }

  Future<void> _bediene(HttpRequest r) async {
    final host = (r.headers.host ?? '').toLowerCase();
    abrufe.add(
      Abruf(
        host,
        r.uri.path,
        r.method,
        r.headers.value(HttpHeaders.authorizationHeader) != null,
      ),
    );
    try {
      await r.drain<void>();
      final inhalt = _inhalt(host, r.uri.path);
      final antwort = r.response;
      if (inhalt == null) {
        antwort.statusCode = 404;
        await antwort.close();
        return;
      }
      antwort.headers.contentType = inhalt.$1;
      // Mit Frischeangabe 0: Der Kachelspeicher der Karte versteht
      // „no-store“ nicht und hielte die Kachel sonst sieben Tage; so fragt
      // jeder spätere Abruf wieder hier nach.
      antwort.headers.set(HttpHeaders.cacheControlHeader, 'max-age=0');
      // Ohne Date-Kopfzeile scheitert der Kachelspeicher an max-age.
      antwort.headers.set(
        HttpHeaders.dateHeader,
        HttpDate.format(DateTime.now()),
      );
      antwort.contentLength = inhalt.$2.length;
      antwort.add(inhalt.$2);
      await antwort.close();
    } catch (e) {
      print('Attrappe: $e');
    }
  }

  (ContentType, Uint8List)? _inhalt(String host, String pfad) {
    if (host.contains('overpass')) {
      return (
        ContentType.json,
        Uint8List.fromList(utf8.encode('{"version":0.6,"elements":[]}')),
      );
    }
    final hoehen = RegExp(
      r'/terrarium/(\d+)/(\d+)/(\d+)\.png$',
    ).firstMatch(pfad);
    if (hoehen != null) {
      final z = int.parse(hoehen[1]!);
      final x = int.parse(hoehen[2]!);
      final y = int.parse(hoehen[3]!);
      return (
        ContentType('image', 'png'),
        _vorrat.putIfAbsent('h$z/$x/$y', () => hoehenkachel(z, x, y)),
      );
    }
    final esri = RegExp(r'/tile/(\d+)/(\d+)/(\d+)$').firstMatch(pfad);
    final xyz = RegExp(
      r'/(\d+)/(\d+)/(\d+)(@2x)?\.(png|jpe?g)$',
    ).firstMatch(pfad);
    if (esri == null && xyz == null) return null;
    final ueber = pfad.contains('/Reference/') || host.contains('waymarked');
    return (
      ContentType('image', 'png'),
      _vorrat.putIfAbsent(
        '$host${ueber ? 'u' : ''}',
        () => kartenkachel(host, ueberlagerung: ueber),
      ),
    );
  }

  /// Abrufe seit [index], als Liste.
  List<Abruf> seit(int index) => abrufe.sublist(index);
}

/// Eine Terrarium-Höhenkachel: Hügel um 1000 m, stetig über die
/// Kachelgrenzen (Höhe = R·256 + G + B/256 − 32768).
Uint8List hoehenkachel(int z, int x, int y) {
  final bild = img.Image(width: 256, height: 256);
  final n = 256.0 * (1 << z);
  for (var j = 0; j < 256; j++) {
    for (var i = 0; i < 256; i++) {
      final gx = (x * 256 + i) / n;
      final gy = (y * 256 + j) / n;
      final h =
          1000 +
          350 *
              math.sin(gx * 2 * math.pi * 2500) *
              math.cos(gy * 2 * math.pi * 2500);
      final v = h + 32768;
      final ganz = v.floor();
      bild.setPixelRgb(i, j, ganz >> 8, ganz & 255, ((v - ganz) * 256).floor());
    }
  }
  return Uint8List.fromList(img.encodePng(bild, level: 1));
}

/// Eine einfarbige Kachel je Anbieter (Überlagerungen durchsichtig mit
/// einer Linie).
Uint8List kartenkachel(String host, {required bool ueberlagerung}) {
  final bild = img.Image(width: 256, height: 256, numChannels: 4);
  final h = host.codeUnits.fold<int>(7, (s, c) => (s * 31 + c) & 0xffffff);
  final farbe = img.ColorRgba8(
    60 + h % 150,
    60 + (h >> 8) % 150,
    60 + (h >> 16) % 150,
    255,
  );
  if (!ueberlagerung) {
    img.fill(bild, color: farbe);
  }
  img.drawLine(
    bild,
    x1: 0,
    y1: 0,
    x2: 255,
    y2: 255,
    color: farbe,
    thickness: 3,
  );
  img.drawLine(
    bild,
    x1: 0,
    y1: 255,
    x2: 255,
    y2: 0,
    color: farbe,
    thickness: 3,
  );
  return Uint8List.fromList(img.encodePng(bild, level: 1));
}

/// Schaltet das Netz der App auf die Attrappe – einmal je Prozess, vor
/// der ersten Prüfung (die Kachel-Clients der App sind Einzelstücke).
void netzAufAttrappe() {
  HttpOverrides.global = netzweiche;
  setUpAll(() async {
    await attrappe.starte();
    netzweiche.attrappe = attrappe;
  });
}

// --- Wegwerf-Server über den Vermittler ----------------------------------------

typedef Durchgang = ({
  String methode,
  String pfad,
  bool anmeldung,
  int? status,
  bool selbst,
});

/// Reicht alles an [ziel] weiter, schreibt mit und lässt sich anhalten.
class Vermittler {
  Vermittler(this.ziel);

  final Uri ziel;
  HttpServer? _server;
  HttpClient? _client;
  final abrufe = <Durchgang>[];

  /// Antwortet selbst (Rückgabe `true`) statt weiterzureichen.
  Future<bool> Function(HttpRequest r)? selbst;

  String get adresse => 'http://127.0.0.1:${_server!.port}';
  bool get laeuft => _server != null;

  Future<void> starte() async {
    _client = HttpClient()..autoUncompress = false;
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen((r) => unawaited(_bediene(r)));
  }

  static const _ohne = {'host', 'content-length', 'transfer-encoding'};

  Future<void> _bediene(HttpRequest r) async {
    final anmeldung = r.headers.value(HttpHeaders.authorizationHeader) != null;
    try {
      final eigen = selbst;
      if (eigen != null && await eigen(r)) {
        abrufe.add((
          methode: r.method,
          pfad: r.uri.path,
          anmeldung: anmeldung,
          status: r.response.statusCode,
          selbst: true,
        ));
        return;
      }
      final hin = await _client!.openUrl(
        r.method,
        ziel.replace(
          path: r.uri.path,
          query: r.uri.hasQuery ? r.uri.query : null,
        ),
      );
      hin.followRedirects = false;
      r.headers.forEach((name, werte) {
        if (_ohne.contains(name)) return;
        for (final w in werte) {
          hin.headers.add(name, w);
        }
      });
      if (r.contentLength >= 0) hin.contentLength = r.contentLength;
      await hin.addStream(r);
      final zurueck = await hin.close();
      r.response.statusCode = zurueck.statusCode;
      zurueck.headers.forEach((name, werte) {
        if (_ohne.contains(name) || name == 'connection') return;
        for (final w in werte) {
          r.response.headers.add(name, w);
        }
      });
      if (zurueck.contentLength >= 0) {
        r.response.contentLength = zurueck.contentLength;
      }
      await r.response.addStream(zurueck);
      await r.response.close();
      abrufe.add((
        methode: r.method,
        pfad: r.uri.path,
        anmeldung: anmeldung,
        status: zurueck.statusCode,
        selbst: false,
      ));
    } catch (e) {
      abrufe.add((
        methode: r.method,
        pfad: r.uri.path,
        anmeldung: anmeldung,
        status: null,
        selbst: false,
      ));
      try {
        r.response.statusCode = 502;
        await r.response.close();
      } catch (_) {}
    }
  }

  /// Für die App ist der Server jetzt weg: keine Verbindung mehr, offene
  /// werden gekappt.
  Future<void> halteAn() async {
    final s = _server;
    _server = null;
    await s?.close(force: true);
    _client?.close(force: true);
  }
}

/// Verbindet die Bibliothek mit dem Server unter [adresse] („konto-a“,
/// beim ersten Mal als erstes Konto angelegt), öffnet die Bibliothek des
/// Servers und startet neu.
Future<void> verbinde(WidgetTester tester, String adresse) async {
  await ki.einstellungsgruppe(tester, de.serverTitel);
  await ki.tippe(tester, find.text(de.serverVerbinden));
  await ki.eintragen(tester, field(de.serverAdresse), adresse);
  await ki.eintragen(tester, field(de.serverName), 'konto-a');
  await ki.eintragen(tester, field(de.serverPasswort), 'pruef-passwort-123');
  await ki.tippe(tester, find.text(de.serverAnmelden));
  await ki.pumpe(tester, 2000);
  if (findet(field(de.serverPasswortWiederholen))) {
    await enter(
      tester,
      field(de.serverPasswortWiederholen),
      'pruef-passwort-123',
    );
    await ki.tippe(tester, find.text(de.serverErstesAnlegen));
    await ki.pumpe(tester, 2000);
  }
  if (findet(find.text(de.serverWeiter))) {
    await ki.tippe(tester, find.text(de.serverWeiter));
  }
  await waitFor(
    tester,
    find.text(de.serverServerBib),
    timeout: const Duration(seconds: 30),
  );
  await ki.tippe(tester, find.text(de.serverServerBib));
  await waitFor(
    tester,
    find.text(de.einstNeustartTitel),
    timeout: const Duration(seconds: 60),
  );
  await ki.neustart(tester);
  expect(bibliothek.verbunden, isTrue);
}

/// Bildwerkzeuge wie unter Linux und Windows: kein Vision, also keine
/// Texterkennung ohne Modell.
class OhneTexterkennung extends AppBildwerkzeuge {
  const OhneTexterkennung();

  @override
  bool get liestTextSelbst => false;

  @override
  Future<List<Textstelle>?> recognizeText(File file) async => null;
}

// --- Gesichter -----------------------------------------------------------------

const _gesichterAbfrage =
    'SELECT id, asset_id, person_id, is_ignored, box_x, box_y, box_w, box_h '
    'FROM faces ORDER BY asset_id, box_x';

Future<List<Map<String, Object?>>> gesichter(WidgetTester tester) =>
    ki.sql(tester, _gesichterAbfrage);

/// Wie [gesichter], aber ohne runAsync – für Bedingungen von [eventually],
/// die schon darin laufen.
Future<List<Map<String, Object?>>> gesichterDirekt() async => [
  for (final z in await bibliothek.db.customSelect(_gesichterAbfrage).get())
    z.data,
];

double _d(Object? v) => (v as num).toDouble();

/// Überdeckung zweier Gesichtsrahmen (Schnitt durch Vereinigung).
double iou(Map<String, Object?> a, Map<String, Object?> b) {
  final ax = _d(a['box_x']), ay = _d(a['box_y']);
  final aw = _d(a['box_w']), ah = _d(a['box_h']);
  final bx = _d(b['box_x']), by = _d(b['box_y']);
  final bw = _d(b['box_w']), bh = _d(b['box_h']);
  final iw = math.max(0.0, math.min(ax + aw, bx + bw) - math.max(ax, bx));
  final ih = math.max(0.0, math.min(ay + ah, by + bh) - math.max(ay, by));
  final schnitt = iw * ih;
  final ganz = aw * ah + bw * bh - schnitt;
  return ganz <= 0 ? 0 : schnitt / ganz;
}

Finder rahmen(String gesichtId) => find.byWidgetPredicate(
  (w) => w is Gesichtsrahmen && w.gesicht.id == gesichtId,
);

Finder get fotoflaeche => find.descendant(
  of: find.byType(FaceReviewScreen),
  matching: find.byType(AspectRatio),
);

/// Öffnet „Gesichter bearbeiten“ für [id] (über den Betrachter).
Future<void> gesichterBearbeiten(
  WidgetTester tester,
  List<String> ids,
  String id,
) async {
  await ki.betrachter(tester, ids, id);
  await ki.rechtsklick(tester, find.byType(PageView));
  await ki.tippe(tester, find.text(de.viewerGesichterBearbeiten));
  await ki.pumpe(tester, 1500);
  await waitFor(tester, find.byType(FaceReviewScreen));
  await waitFor(tester, fotoflaeche, timeout: const Duration(seconds: 30));
  await ki.pumpe(tester, 600);
}

/// Schliesst „Gesichter bearbeiten“ und den Betrachter.
Future<void> allesZu(WidgetTester tester) async {
  for (final typ in [FaceReviewScreen, AssetViewerScreen]) {
    while (findet(find.byType(typ))) {
      Navigator.of(tester.element(find.byType(typ).last)).pop();
      await ki.pumpe(tester, 600);
    }
  }
}

// --- Regeln ----------------------------------------------------------------------

Future<void> regelNeu(WidgetTester tester) async {
  await ki.tippe(tester, find.byTooltip(de.regelNeu));
  await waitFor(tester, find.text(de.regelNeuTitel));
}

Future<void> bedingung(WidgetTester tester, String art) async {
  final auswahl = find.ancestor(
    of: find.text(de.regelBedingung),
    matching: find.byType(DropdownButtonFormField<String>),
  );
  await ki.tippe(tester, auswahl);
  await ki.tippe(tester, find.text(art).last);
}

// --- Info im Betrachter ------------------------------------------------------------

/// Der Text unter „Gesprochen“ (ein SelectableText) in der offenen Info.
String gesprochenerText(WidgetTester tester) => [
  for (final e in find.byType(SelectableText).evaluate())
    (e.widget as SelectableText).data ?? '',
].join(' | ');

Future<String> infoTexte(
  WidgetTester tester,
  List<String> ids,
  String id,
) async {
  await ki.betrachter(tester, ids, id);
  await ki.tippe(tester, find.byTooltip(de.viewerInfo));
  await ki.pumpe(tester, 1200);
  final texte = onScreen(tester);
  return texte;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  netzAufAttrappe();
  setUp(melde.alleSchliessen);

  // ------------------------------------------------------------- Gesichter

  /// KI-059 – mit [doppelPruefen] zusätzlich die Befundprüfung: Neben dem
  /// zugeordneten Gesicht entsteht keine zweite, unbenannte Erkennung.
  Future<void> ki059(WidgetTester tester, {required bool doppelPruefen}) async {
    await startApp(
      tester,
      modelle: ki.dateienVon([
        ModelCatalog.faceDetection,
        ModelCatalog.faceRecognition,
        ModelCatalog.eyeState,
      ]),
    );
    await ki.autoAus(tester);
    await ki.warteRuhe(tester);
    // Foto 1: zwei freie Porträts nebeneinander; Foto 2 wird ausgenommen;
    // Foto 3 bleibt unbenannt und wird neu erkannt.
    img.Image lies(String n) => img.decodeJpg(
      File(p.join(mlFixtures, 'gesichter', n)).readAsBytesSync(),
    )!;
    final a = lies('person_a_1.jpg');
    final b = lies('person_b_1.jpg');
    final paar = img.Image(
      width: a.width + b.width,
      height: math.max(a.height, b.height),
    );
    img.compositeImage(paar, a, dstX: 0, dstY: 0);
    img.compositeImage(paar, b, dstX: a.width, dstY: 0);
    final f1 = File(p.join(eingang.path, 'paar.jpg'))
      ..writeAsBytesSync(img.encodeJpg(paar, quality: 92));
    await importiereDirekt(tester, [
      f1,
      mlFixture('gesichter/person_c_1.jpg'),
      mlFixture('gesichter/person_b_2.jpg'),
    ]);
    final id1 = await idVon(tester, 'paar.jpg');
    final id2 = await idVon(tester, 'person_c_1.jpg');
    final id3 = await idVon(tester, 'person_b_2.jpg');
    final alle = [id1, id2, id3];

    // Vorher einmal „Fehlende“: So gibt es erkannte Gesichter.
    await ki.aufgaben(tester);
    await ki.kartenknopf(
      tester,
      de.werkzGesichterScannenTitel,
      de.aufgFehlende,
    );
    await ki.warteAufLauf(tester, 'gesichter');
    await ki.pumpe(tester);
    await ki.kartenknopf(
      tester,
      de.werkzGesichterScannenTitel,
      de.allgSchliessen,
    );
    final erkannt = await gesichter(tester);
    print('KI-059 erkannt: $erkannt');
    final aufPaar = [
      for (final f in erkannt)
        if (f['asset_id'] == id1) f,
    ];
    expect(aufPaar.length, 2, reason: 'zwei Gesichter auf dem Paar');
    final a1 = aufPaar.firstWhere((f) => _d(f['box_x']) < 0.5);
    final b1 = aufPaar.firstWhere((f) => _d(f['box_x']) >= 0.5);
    final b2 = erkannt.where((f) => f['asset_id'] == id3).toList();
    expect(b2, hasLength(1), reason: 'Foto 3 hat ein Gesicht');
    final c1 = erkannt.where((f) => f['asset_id'] == id2).toList();
    expect(c1, isNotEmpty, reason: 'Foto 2 hat ein Gesicht');

    // Foto 1 in „Gesichter bearbeiten“: Die Erkennung links löschen und
    // das Gesicht von Hand einzeichnen, „Person A“ zuordnen; das rechte
    // beiseitelegen.
    await gesichterBearbeiten(tester, alle, id1);
    await waitFor(tester, rahmen(a1['id']! as String));
    await ki.rechtsklick(tester, rahmen(a1['id']! as String));
    await ki.tippe(tester, find.text(de.gesichtErkennungLoeschen));
    await waitGone(tester, rahmen(a1['id']! as String));
    await ki.tippe(tester, find.byTooltip(de.gesichtManuellHinzufuegen));
    final r = tester.getRect(fotoflaeche.first);
    final start =
        r.topLeft +
        Offset(_d(a1['box_x']) * r.width, _d(a1['box_y']) * r.height);
    final ende =
        start + Offset(_d(a1['box_w']) * r.width, _d(a1['box_h']) * r.height);
    final zug = await tester.startGesture(start, kind: PointerDeviceKind.mouse);
    for (var i = 1; i <= 12; i++) {
      await zug.moveTo(Offset.lerp(start, ende, i / 12)!);
      await tester.pump(const Duration(milliseconds: 30));
    }
    await zug.up();
    await ki.pumpe(tester, 800);
    await waitFor(tester, find.text(de.gesichtNeuBenennen));
    await enter(
      tester,
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'Person A',
    );
    await ki.tippe(tester, find.text(de.personAnlegenAktion('Person A')));
    await eventually(
      tester,
      () async => (await gesichterDirekt()).any(
        (f) => f['asset_id'] == id1 && f['person_id'] != null,
      ),
      was: 'Handgesicht „Person A“',
    );
    await ki.pumpe(tester, 800);
    await waitFor(tester, rahmen(b1['id']! as String));
    await ki.rechtsklick(tester, rahmen(b1['id']! as String));
    await ki.tippe(tester, find.text(de.gesichtIgnorieren));
    await eventually(
      tester,
      () async => (await gesichterDirekt()).any(
        (f) => f['id'] == b1['id'] && f['is_ignored'] == 1,
      ),
      was: 'rechtes Gesicht beiseitegelegt',
    );
    await allesZu(tester);

    // Foto 2 ausnehmen (Rechtsklick auf eine freie Stelle).
    await gesichterBearbeiten(tester, alle, id2);
    final r2 = tester.getRect(fotoflaeche.first);
    await tester.tapAt(
      r2.topLeft + Offset(r2.width * 0.92, r2.height * 0.92),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await ki.pumpe(tester, 500);
    await ki.tippe(tester, find.text(de.gesichtNichtMehrDurchsuchen));
    await erwarteMeldung(tester, de.gesichtNichtMehrDurchsuchtHinweis);
    expect((await ki.aufnahme(tester, id2)).faceScanExcluded, isTrue);
    await allesZu(tester);

    final vorher = await gesichter(tester);
    print('KI-059 vor „Alle“: $vorher');
    final hand = vorher.singleWhere(
      (f) => f['asset_id'] == id1 && f['person_id'] != null,
    );
    expect(iou(hand, a1), greaterThan(0.5), reason: 'Handrahmen über A');
    await ki.sqlAusfuehren(
      tester,
      "DELETE FROM ergebnisherkunft WHERE art = 'gesichter'",
    );

    // „Gesichter scannen – Alle“.
    await ki.aufgaben(tester);
    await ki.kartenknopf(
      tester,
      de.werkzGesichterScannenTitel,
      de.aufgModusAlle,
    );
    await ki.warteAufLauf(tester, 'gesichter');
    final lauf = bibliothek.lauf('gesichter')!;
    expect(lauf.gesamt, 2, reason: 'das ausgenommene Foto zählt nicht');
    final nachher = await gesichter(tester);
    print('KI-059 nach „Alle“: $nachher');

    // Person A ist noch da.
    expect(
      nachher.where(
        (f) => f['id'] == hand['id'] && f['person_id'] == hand['person_id'],
      ),
      hasLength(1),
    );
    // Das beiseitegelegte bleibt beiseite und kommt nicht neu.
    expect(nachher.singleWhere((f) => f['id'] == b1['id'])['is_ignored'], 1);
    expect(
      nachher.where(
        (f) => f['asset_id'] == id1 && f['id'] != b1['id'] && iou(f, b1) > 0.3,
      ),
      isEmpty,
      reason: 'beiseitegelegtes Gesicht kam neu',
    );
    // Das ausgenommene Foto wurde übersprungen.
    expect(
      [
        for (final f in nachher)
          if (f['asset_id'] == id2) f['id'],
      ],
      [for (final f in c1) f['id']],
    );
    expect(
      await ki.zahl(
        tester,
        "SELECT count(*) FROM ergebnisherkunft WHERE asset_id = ? AND art = 'gesichter'",
        [id2],
      ),
      0,
    );
    // Foto 3: die unbenannte Erkennung neu erzeugt (neue Kennung, selbe
    // Stelle).
    final neu3 = nachher.where((f) => f['asset_id'] == id3).toList();
    expect(neu3, hasLength(1));
    expect(neu3.single['id'], isNot(b2.single['id']));
    expect(neu3.single['person_id'], isNull);
    expect(iou(neu3.single, b2.single), greaterThan(0.7));
    // In der Oberfläche steht „Person A“ weiter am Foto.
    await gesichterBearbeiten(tester, alle, id1);
    expect(
      find.descendant(
        of: find.byType(FaceReviewScreen),
        matching: find.text('Person A'),
      ),
      findsWidgets,
    );
    await allesZu(tester);

    // Zuletzt (Befundprüfung): Neben dem zugeordneten Gesicht entsteht
    // keine zweite, unbenannte Erkennung an derselben Stelle.
    final doppelt = [
      for (final f in nachher)
        if (f['asset_id'] == id1 &&
            f['id'] != hand['id'] &&
            f['person_id'] == null &&
            f['is_ignored'] == 0 &&
            iou(f, hand) > 0.3)
          f,
    ];
    print('KI-059 unbenannt über Person A: $doppelt');
    if (doppelPruefen) {
      expect(
        doppelt,
        isEmpty,
        reason: 'Befund: unbenannte Doppelerkennung über Person A',
      );
    }
    await finish(tester);
  }

  testWidgets(
    timeout: lang,
    'KI-059 Gesichter scannen – Alle mit echten Gesichtern',
    (tester) => ki059(tester, doppelPruefen: false),
  );

  // Behoben in #420: Der Scan lässt jede Stelle aus, an der schon ein
  // Gesicht steht – benannt, beiseitegelegt oder unbenannt
  // (belegteGesichtsstellen in rechenhilfe.dart).
  testWidgets(
    timeout: lang,
    'KI-059 Befundpruefung keine Doppelerkennung ueber Person A',
    (tester) => ki059(tester, doppelPruefen: true),
  );

  // --------------------------------------------------------------- Unschärfe

  testWidgets(
    timeout: lang,
    'KI-064 Unschärfewert und Suchfilter „Nur unscharfe Fotos“',
    (tester) async {
      await startApp(tester);
      await ki.autoAus(tester);
      await ki.warteRuhe(tester);
      final scharf = img.Image(width: 640, height: 480);
      for (var y = 0; y < 480; y++) {
        for (var x = 0; x < 640; x++) {
          final w = ((x ~/ 8) + (y ~/ 8)).isEven ? 255 : 0;
          scharf.setPixelRgb(x, y, w, w, w);
        }
      }
      final weich = img.gaussianBlur(img.Image.from(scharf), radius: 12);
      final fs = File(p.join(eingang.path, 'scharf.jpg'))
        ..writeAsBytesSync(img.encodeJpg(scharf, quality: 95));
      final fw = File(p.join(eingang.path, 'weich.jpg'))
        ..writeAsBytesSync(img.encodeJpg(weich, quality: 95));
      await importiereDirekt(tester, [fs, fw]);
      final ids = [
        await idVon(tester, 'scharf.jpg'),
        await idVon(tester, 'weich.jpg'),
      ];
      // „Analyse laufen lassen“ – ohne Modell.
      await ki.aufgaben(tester);
      await ki.kartenknopf(
        tester,
        de.werkzAllesNachholenTitel,
        de.aufgJetztStarten,
      );
      await eventually(
        tester,
        () async {
          for (final id in ids) {
            if ((await bibliothek.db.assetById(id))?.sharpnessScore == null) {
              return false;
            }
          }
          return true;
        },
        timeout: const Duration(minutes: 3),
        was: 'Unschärfewerte',
      );
      await ki.warteRuhe(tester);
      final s = (await ki.aufnahme(tester, ids[0])).sharpnessScore!;
      final w = (await ki.aufnahme(tester, ids[1])).sharpnessScore!;
      print('KI-064 Unschärfe: scharf $s, weich $w');
      await ki.aufgaben(tester);
      await ki.zurKarte(tester, de.aufgUnschaerfeTitel);
      expect(
        ki.texteIn(ki.karte(de.aufgUnschaerfeTitel)),
        contains(de.aufgOffeneFotos(0)),
      );
      // Suche: Filter „Nur unscharfe Fotos anzeigen“.
      await openSection(tester, Hauptbereich.suche);
      await ans.oeffneSuchoptionen(tester);
      await ans.imBlatt(tester, de.suchoptNurUnscharfe);
      await ans.optionenSuchen(tester);
      await eventually(
        tester,
        () async => ans.treffer(tester).isNotEmpty,
        was: 'Treffer',
      );
      final t = ans.treffer(tester);
      print('KI-064 Treffer mit Filter: $t');
      expect(t, contains('weich.jpg'));
      expect(t, isNot(contains('scharf.jpg')));
      await finish(tester);
    },
  );

  // ------------------------------------------------------------- Sprache

  testWidgets(
    timeout: lang,
    'KI-103 Gesprochenes in einem Video wird erkannt',
    (tester) async {
      await startApp(
        tester,
        modelle: ki.dateienVon([ModelCatalog.spracherkennung]),
      );
      await ki.autoAus(tester);
      await ki.warteRuhe(tester);
      await importiereDirekt(tester, [fixture('r2ki_sprache_de.mp4')]);
      final id = await idVon(tester, 'r2ki_sprache_de.mp4');
      await ki.analyseUeberKarte(tester);
      final a = await ki.aufnahme(tester, id);
      print('KI-103 Transkript: „${a.transkript}“ (${a.transkriptSprache})');
      expect(a.transkriptGeprueft, isTrue);
      final text = (a.transkript ?? '').toLowerCase();
      // Gesprochen: „Der rote Ballon fliegt langsam über die grüne Wiese.“
      for (final wort in ['ballon', 'fliegt', 'wiese']) {
        expect(text, contains(wort), reason: wort);
      }
      await infoTexte(tester, [id], id);
      expect(find.text(de.infoGesprochen), findsOneWidget);
      final gezeigt = gesprochenerText(tester).toLowerCase();
      print('KI-103 unter „Gesprochen“: „$gezeigt“');
      expect(gezeigt, contains('ballon'));
      expect(gezeigt, contains('wiese'));
      await ki.betrachterZu(tester);
      await ki.aufgaben(tester);
      await ki.zurKarte(tester, de.aufgTranskripteTitel);
      expect(
        ki.texteIn(ki.karte(de.aufgTranskripteTitel)),
        contains(de.aufgOffeneFotos(0)),
      );
      await finish(tester);
    },
  );

  testWidgets(timeout: lang, 'KI-104 Video mit Rauschen gilt als gehoert', (
    tester,
  ) async {
    await startApp(
      tester,
      modelle: ki.dateienVon([ModelCatalog.spracherkennung]),
    );
    await ki.autoAus(tester);
    await ki.warteRuhe(tester);
    await importiereDirekt(tester, [
      fixture('r2ki_rauschen.mp4'),
      fixture('video_hoch_3s.mov'),
    ]);
    final ids = [
      await idVon(tester, 'r2ki_rauschen.mp4'),
      await idVon(tester, 'video_hoch_3s.mov'),
    ];
    await ki.analyseUeberKarte(tester);
    for (final id in ids) {
      final a = await ki.aufnahme(tester, id);
      print('KI-104 ${a.originalFileName}: „${a.transkript}“');
      expect(a.transkriptGeprueft, isTrue, reason: a.originalFileName);
      await infoTexte(tester, ids, id);
      final gesprochen = findet(find.text(de.infoGesprochen));
      print('KI-104 ${a.originalFileName}: „Gesprochen“ $gesprochen');
      await ki.betrachterZu(tester);
      expect(
        (a.transkript ?? '').trim(),
        isEmpty,
        reason: 'erfundene Wörter in ${a.originalFileName}',
      );
      expect(gesprochen, isFalse, reason: a.originalFileName);
    }
    await ki.aufgaben(tester);
    await ki.kartenknopf(tester, de.aufgTranskripteTitel, de.aufgFehlende);
    await ki.warteAufLauf(tester, 'transkripte');
    await ki.pumpe(tester);
    expect(
      ki.texteIn(ki.karte(de.aufgTranskripteTitel)),
      contains(de.werkzAlleVideosGehoert),
    );
    await finish(tester);
  });

  testWidgets(
    timeout: lang,
    'KI-106 Langes Video: nur die erste halbe Stunde',
    (tester) async {
      await startApp(
        tester,
        modelle: ki.dateienVon([ModelCatalog.spracherkennung]),
      );
      await ki.autoAus(tester);
      await ki.warteRuhe(tester);
      await importiereDirekt(tester, [fixture('r2ki_lang_35min.mp4')]);
      final id = await idVon(tester, 'r2ki_lang_35min.mp4');
      final dauer = (await ki.aufnahme(tester, id)).durationSeconds;
      print('KI-106 Laufzeit: $dauer s');
      expect(dauer, greaterThan(34 * 60));
      await ki.analyseUeberKarte(tester, timeout: const Duration(minutes: 15));
      final a = await ki.aufnahme(tester, id);
      print('KI-106 Transkript: „${a.transkript}“');
      final text = (a.transkript ?? '').toLowerCase();
      // Minute 2: „Die kleine Katze schläft auf dem warmen Sofa.“
      expect(text, contains('katze'));
      // Minute 32: „Das blaue Fahrrad steht vor der alten Scheune.“
      for (final wort in ['fahrrad', 'scheune', 'blaue']) {
        expect(text, isNot(contains(wort)), reason: wort);
      }
      await infoTexte(tester, [id], id);
      expect(find.text(de.infoGesprochen), findsOneWidget);
      final gezeigt = gesprochenerText(tester).toLowerCase();
      print('KI-106 unter „Gesprochen“: „$gezeigt“');
      expect(gezeigt, contains('katze'));
      expect(gezeigt, isNot(contains('fahrrad')));
      await ki.betrachterZu(tester);
      await finish(tester);
    },
  );

  // ------------------------------------------------------------ Videobilder

  testWidgets(
    timeout: lang,
    'KI-107 Videostandbilder machen Szenen aus der Mitte auffindbar',
    (tester) async {
      await startApp(tester, modelle: ki.dateienVon([ModelCatalog.clip]));
      await ki.autoAus(tester);
      await ki.warteRuhe(tester);
      // 30 s: Sonnenblume, von Sekunde 8 bis 22 ein Zebra, dann wieder die
      // Sonnenblume. Das Standbild des Imports (0,5 s) zeigt die Blume.
      await importiereDirekt(tester, [
        fixture('r2ki_szenen2_30s.mp4'),
        fixture('video_5s.mp4'),
        mlFixture('inhalt/animals_penguin.jpg'),
        mlFixture('inhalt/flowers_dahlia.jpg'),
        mlFixture('inhalt/nature_leaf.jpg'),
        mlFixture('inhalt/sports_tennis.jpg'),
      ]);
      final lang30 = await idVon(tester, 'r2ki_szenen2_30s.mp4');
      final kurz = await idVon(tester, 'video_5s.mp4');
      expect(
        (await ki.aufnahme(tester, lang30)).durationSeconds,
        closeTo(30, 1),
      );
      Set<String> bilddateien() => {
        for (final e in bibliothek.paths.root.listSync(recursive: true))
          if (e is File &&
              RegExp(
                r'\.(jpe?g|png|webp|heic)$',
                caseSensitive: false,
              ).hasMatch(e.path))
            e.path,
      };
      await ki.aufgaben(tester);
      await ki.kartenknopf(tester, de.aufgEmbeddingsTitel, de.aufgFehlende);
      await ki.warteAufLauf(tester, 'embeddings');

      Future<List<String>> zebra() async {
        await openSection(tester, Hauptbereich.zeitleiste);
        await openSection(tester, Hauptbereich.suche);
        await ans.sucheNachTyp(tester, de.suchoptTypKontext, 'zebra');
        await eventually(
          tester,
          () async => ans.treffer(tester).isNotEmpty,
          was: 'Treffer',
        );
        return ans.treffer(tester);
      }

      final vorher = await zebra();
      print('KI-107 „zebra“ vor den Standbildern: $vorher');
      final dateienVorher = bilddateien();
      await ki.aufgaben(tester);
      await ki.kartenknopf(tester, de.aufgVideobilderTitel, de.aufgFehlende);
      await ki.warteAufLauf(tester, 'videobilder');
      await ki.pumpe(tester);
      expect(
        ki.texteIn(ki.karte(de.aufgVideobilderTitel)),
        contains(de.aufgFertigMit(2)),
      );
      final eingebettet = await ki.zahl(
        tester,
        'SELECT count(*) FROM videoeinbettungen WHERE asset_id = ?',
        [lang30],
      );
      print('KI-107 Einbettungen des langen Videos: $eingebettet');
      expect(eingebettet, greaterThanOrEqualTo(2));
      expect(
        await ki.zahl(
          tester,
          'SELECT count(*) FROM videoeinbettungen WHERE asset_id = ?',
          [kurz],
        ),
        0,
      );
      expect((await ki.aufnahme(tester, kurz)).videobilderGeprueft, isTrue);
      expect(bilddateien(), dateienVorher, reason: 'keine Standbilder');
      final nachher = await zebra();
      print('KI-107 „zebra“ nach den Standbildern: $nachher');
      // Vorher steht das Video (Standbild: Sonnenblume) hinter dem
      // Pinguin, nachher (Zebra aus der Mitte) ganz vorn.
      const video = 'r2ki_szenen2_30s.mp4';
      expect(nachher.first, video);
      expect(
        vorher.indexOf(video),
        greaterThan(vorher.indexOf('animals_penguin.jpg')),
        reason: 'vorher fand nur das erste Standbild (Sonnenblume)',
      );
      await finish(tester);
    },
  );

  // --------------------------------------------------------------- Datierung

  Future<List<String>> alteFotosImport(WidgetTester tester) async {
    await importiereDirekt(tester, [
      for (final n in [
        'alt_berge',
        'alt_fluss',
        'alt_kirche',
        'alt_mutter',
        'alt_quellen',
      ])
        mlFixture('alt/$n.jpg'),
      mlFixture('ohne_datum/lotus_ohne_datum.jpg'),
      mlFixture('ohne_datum/tennis_ohne_datum.jpg'),
    ]);
    final zeilen = await ki.sql(tester, 'SELECT id FROM assets');
    return [for (final z in zeilen) z['id']! as String];
  }

  Future<Map<String, DateTime>> daten(
    WidgetTester tester,
    List<String> ids,
  ) async => {
    for (final id in ids) id: (await ki.aufnahme(tester, id)).fileCreatedAt,
  };

  Future<void> datierungOeffnen(WidgetTester tester) async {
    await ki.werkzeug(tester, de.datierungTitel);
    await ki.pumpe(tester, 3000);
    print('Datierung: ${onScreen(tester)}');
  }

  testWidgets(timeout: lang, 'KI-113 Einzelne Schaetzung uebernehmen', (
    tester,
  ) async {
    await startApp(tester, modelle: ki.dateienVon([ModelCatalog.clip]));
    await ki.autoAus(tester);
    await ki.warteRuhe(tester);
    final ids = await alteFotosImport(tester);
    for (final id in ids) {
      final x = await ki.aufnahme(tester, id);
      print('KI-113 ${x.originalFileName}: geschätzt ${x.datumGeschaetzt}');
    }
    await ki.analyseUeberKarte(tester);
    await datierungOeffnen(tester);
    final knoepfe = find.widgetWithText(TextButton, de.datierungUebernehmen);
    final belastbar = knoepfe.evaluate().length;
    print('KI-113 belastbare Schätzungen: $belastbar');
    expect(belastbar, greaterThan(0));
    final vorher = await daten(tester, ids);
    final summen = {
      for (final id in ids)
        id: ki.sha(
          bibliothek.paths.absolute(
            (await ki.aufnahme(tester, id)).relativePath,
          ),
        ),
    };
    await ki.tippe(tester, knoepfe.first);
    await erwarteMeldung(tester, de.datierungUebernommen(1));
    expect(find.text(de.datierungIstUebernommen), findsOneWidget);
    final nachher = await daten(tester, ids);
    final geaendert = [
      for (final id in ids)
        if (nachher[id] != vorher[id]) id,
    ];
    expect(geaendert, hasLength(1));
    final x = await ki.aufnahme(tester, geaendert.single);
    print('KI-113 übernommen: ${x.originalFileName} → ${x.fileCreatedAt}');
    expect(x.fileCreatedAt.month, 7);
    expect(x.fileCreatedAt.day, 1);
    expect(x.fileCreatedAt.hour, 12);
    expect(x.fileCreatedAt.minute, 0);
    expect(x.datumGeschaetzt, isTrue);
    expect(
      find.text(de.datierungUm('${x.fileCreatedAt.year}')),
      findsWidgets,
      reason: 'Jahr der Kachel',
    );
    expect(ki.sha(bibliothek.paths.absolute(x.relativePath)), summen[x.id]);
    // Das Foto öffnen: Datum und „geschätzt“ in der Info.
    final info = await infoTexte(tester, ids, x.id);
    print('KI-113 Info: $info');
    expect(info, contains(DateFormat.yMMMd('de').format(x.fileCreatedAt)));
    expect(info, contains(de.infoDatumGeschaetzt));
    await ki.betrachterZu(tester);
    await finish(tester);
  });

  testWidgets(
    timeout: lang,
    'KI-114 Alle Schaetzungen auf einmal uebernehmen',
    (tester) async {
      await startApp(tester, modelle: ki.dateienVon([ModelCatalog.clip]));
      await ki.autoAus(tester);
      await ki.warteRuhe(tester);
      final ids = await alteFotosImport(tester);
      await ki.analyseUeberKarte(tester);
      await datierungOeffnen(tester);
      final knoepfe = find.widgetWithText(TextButton, de.datierungUebernehmen);
      final n = knoepfe.evaluate().length;
      print('KI-114 belastbare Schätzungen: $n');
      expect(n, greaterThan(0));
      final unsicher = find
          .textContaining(RegExp(r'^zu unsicher'))
          .evaluate()
          .length;
      final vorher = await daten(tester, ids);
      final alle = find.text(de.datierungAlleUebernehmen(n));
      expect(alle, findsOneWidget);
      await ki.tippe(tester, alle);
      await erwarteMeldung(tester, de.datierungUebernommen(n));
      final null0 = find.ancestor(
        of: find.text(de.datierungAlleUebernehmen(0)),
        matching: find.byType(FilledButton),
      );
      expect(tester.widget<FilledButton>(null0).onPressed, isNull);
      final nachher = await daten(tester, ids);
      final geaendert = [
        for (final id in ids)
          if (nachher[id] != vorher[id]) id,
      ];
      expect(geaendert, hasLength(n), reason: 'genau die belastbaren');
      for (final id in geaendert) {
        final d = nachher[id]!;
        expect([d.month, d.day, d.hour], [7, 1, 12]);
      }
      // Schliessen und wieder öffnen.
      await openSection(tester, Hauptbereich.zeitleiste);
      await datierungOeffnen(tester);
      expect(find.text(de.datierungIstUebernommen), findsNWidgets(n));
      expect(
        find.textContaining(RegExp(r'^zu unsicher')).evaluate().length,
        unsicher,
        reason: 'unsichere unverändert',
      );
      expect(
        tester
            .widget<FilledButton>(
              find.ancestor(
                of: find.text(de.datierungAlleUebernehmen(0)),
                matching: find.byType(FilledButton),
              ),
            )
            .onPressed,
        isNull,
      );
      await finish(tester);
    },
  );

  // ------------------------------------------------------------------ Regeln

  testWidgets(
    timeout: lang,
    'KI-172 Serverpruefung Dateinamensregel bei aelterem Server',
    skip: altServer.isEmpty,
    (tester) async {
      await startApp(tester);
      final zustand = await tester.runAsync(() async {
        final c = HttpClient();
        try {
          final antwort = await (await c.getUrl(
            Uri.parse('$altServer/api/v1/zustand'),
          )).close();
          return jsonDecode(await utf8.decodeStream(antwort))
              as Map<String, Object?>;
        } finally {
          c.close();
        }
      });
      print('KI-172 Zustand des alten Servers: $zustand');
      expect((zustand!['funktionen'] as Map?)?['importplan'], isNull);
      await verbinde(tester, altServer);
      await ki.werkzeug(tester, de.werkzRegelnTitel);
      await waitFor(tester, find.byType(AutomationRulesScreen));
      await regelNeu(tester);
      await ki.eintragen(tester, field(de.regelNameFeld), 'Namensregel');
      await bedingung(tester, de.regelAusloeserDateiname);
      await ki.eintragen(tester, field(de.regelDateinameWert), 'Urlaub');
      await ki.eintragen(tester, field(de.presetNeuesAlbum), 'Namen');
      await ki.tippe(tester, find.text(de.allgSpeichern));
      await erwarteMeldung(tester, de.importPlanServerAlt);
      await ki.pumpe(tester, 800);
      expect(await ki.zahl(tester, 'SELECT count(*) FROM automation_rules'), 0);
      expect(
        await ki.zahl(
          tester,
          "SELECT count(*) FROM albums WHERE name = 'Namen'",
        ),
        0,
      );
      expect(
        find.descendant(
          of: find.byType(AutomationRulesScreen),
          matching: find.text('Namensregel'),
        ),
        findsNothing,
      );
      await finish(tester);
    },
  );

  // ------------------------------------------------------------ Rechenhilfe

  testWidgets(
    timeout: lang,
    'KI-175 KI-178 Serverpruefung Rechenhilfe ohne Modell und ohne Server',
    skip: serverAdresse.isEmpty,
    (tester) async {
      final vermittler = Vermittler(Uri.parse(serverAdresse));
      await tester.runAsync(vermittler.starte);
      addTearDown(vermittler.halteAn);
      await startApp(tester);
      // KI-175 wie unter Linux und Windows: kein Vision.
      final macos = Bildwerkzeuge.standard;
      Bildwerkzeuge.standard = const OhneTexterkennung();
      addTearDown(() => Bildwerkzeuge.standard = macos);
      await verbinde(tester, vermittler.adresse);
      expect(bibliothek.auswertungen.bildwerkzeuge.liestTextSelbst, isFalse);
      await ki.einstellungsgruppe(tester, de.serverTitel);
      final hilfe = ki.schalter(de.serverRechenhilfe);
      await ki.sichtbar(tester, hilfe, SettingsScreen);
      await ki.tippe(tester, hilfe);
      await waitFor(tester, find.text(de.serverRechenzeit));
      await waitFor(tester, find.text(de.serverRechenhilfeKeinModell));

      // Unter macOS (Vision liest Text): kein „kein Modell“.
      Bildwerkzeuge.standard = macos;
      await ki.neustart(tester);
      expect(bibliothek.auswertungen.bildwerkzeuge.liestTextSelbst, isTrue);
      await ki.einstellungsgruppe(tester, de.serverTitel);
      await ki.sichtbar(
        tester,
        ki.schalter(de.serverRechenhilfe),
        SettingsScreen,
      );
      expect(
        tester.widget<SwitchListTile>(ki.schalter(de.serverRechenhilfe)).value,
        isTrue,
      );
      await waitFor(
        tester,
        find.textContaining('Wartet auf Arbeit'),
        timeout: const Duration(seconds: 60),
      );
      expect(find.text(de.serverRechenhilfeKeinModell), findsNothing);

      // KI-178: Server weg.
      await tester.runAsync(vermittler.halteAn);
      await waitFor(
        tester,
        find.text(de.serverRechenhilfeOffline),
        timeout: const Duration(minutes: 3),
      );
      // Ausschalten: „Wann rechnen“ und Status verschwinden.
      await ki.sichtbar(
        tester,
        ki.schalter(de.serverRechenhilfe),
        SettingsScreen,
      );
      await ki.tippe(tester, ki.schalter(de.serverRechenhilfe));
      await waitGone(tester, find.text(de.serverRechenzeit));
      expect(find.text(de.serverRechenhilfeOffline), findsNothing);
      await ki.neustart(tester);
      await ki.einstellungsgruppe(tester, de.serverTitel);
      await ki.sichtbar(
        tester,
        ki.schalter(de.serverRechenhilfe),
        SettingsScreen,
      );
      expect(
        tester.widget<SwitchListTile>(ki.schalter(de.serverRechenhilfe)).value,
        isFalse,
      );
      expect(find.text(de.serverRechenzeit), findsNothing);
      await finish(tester);
    },
  );
}
