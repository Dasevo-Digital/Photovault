import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:kern/abgleich/kachelumleitung.dart' show serverKartenquellen;
import 'package:kern/protokoll.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';

import 'dateiantwort.dart';
import 'fassung.dart';
import 'fassungen_aufraeumen.dart';

/// Kartenkacheln für die angemeldeten Geräte (#180): beim Anbieter
/// geholt, auf der Platte vorgehalten und von dort ausgeliefert.
///
/// **Warum.** Bis 3.66 holte jedes Gerät seine Kacheln selbst bei
/// OpenStreetMap und OpenTopoMap, auch der Browser jedes Besuchers. Die
/// Anbieter bekamen so dessen IP-Adresse samt der Gegend, die er ansah.
/// Jetzt fragt nur noch der Server, mit seiner eigenen Kennung ([kennung]),
/// und wer dieselbe Gegend noch einmal ansieht, bekommt sie von der
/// Platte.
///
/// **Kein offener Vermittler.** Nur die Quellen aus [serverKartenquellen],
/// nur Stufen, für die es dort echte Kacheln gibt, und nur Koordinaten, die
/// auf dieser Stufe existieren; alles andere ist 404, ohne dass der
/// Anbieter gefragt wird. Und nur für angemeldete Konten wie jeder Weg
/// unter `/api/v1`.
///
/// **Vorgehalten, solange der Anbieter sagt, mindestens aber [mindestens].**
/// Die Nutzungsregeln von OpenStreetMap verlangen, Kacheln
/// zwischenzuspeichern und eine Woche lang nicht neu zu holen. Wie lange
/// eine Kachel gilt, steht in der Änderungszeit ihrer Datei – so braucht
/// es keine zweite Datei je Kachel, und das Aufräumen
/// ([begrenzeZwischenspeicher], höchstens [grenze] Bytes) wirft zuerst
/// die, die am frühesten ablaufen.
///
/// **Zurückhaltend.** Höchstens [gleichzeitig] Abrufe auf einmal und
/// dieselbe Kachel nur einmal, auch wenn mehrere Geräte sie zugleich
/// wollen. Geholt wird nur, was ein Gerät anfragt – beim Ansehen und beim
/// Vorladen am Rechner, nie von sich aus. Sagt der Anbieter 429 oder 503,
/// oder scheitern drei Abrufe in Folge, wird er [ruhe] lang nicht mehr
/// gefragt – sonst wartete bei einem Ausfall jede Kachel des Bildschirms
/// auf ihre eigene Frist. Ein einzelner Fehler legt den Stil nicht für alle
/// Konten lahm.
///
/// **Ist der Anbieter weg, gilt die alte Kachel.** Eine abgelaufene Kopie
/// ist besser als ein Loch; sie geht mit `max-age=0` hinaus, damit das
/// Gerät beim nächsten Mal wieder fragt. Ohne Kopie: 502.
class Kartenkacheln {
  Kartenkacheln(
    this.ordner, {
    http.Client? netz,
    this.grenze = 1024 * 1024 * 1024,
    this.gleichzeitig = 4,
    this.mindestens = const Duration(days: 7),
    this.frist = const Duration(seconds: 15),
    this.ruhe = const Duration(seconds: 30),
    DateTime Function()? uhr,
  }) : _netz =
           netz ??
           // Hinter einem Proxy (`HTTPS_PROXY`), wie ihn ein Server ohne
           // eigenen Weg ins Internet braucht; dart:io fragt ihn sonst nicht.
           IOClient(
             HttpClient()..findProxy = HttpClient.findProxyFromEnvironment,
           ),
       _uhr = uhr ?? DateTime.now;

  /// Wohin die Kacheln kommen (`<PV_DATEN>/kartenkacheln`), flach als
  /// `<stil>-<z>-<x>-<y>.png`.
  final Directory ordner;

  /// Höchstens so viele Bytes; gut 50.000 Kacheln.
  final int grenze;
  final int gleichzeitig;
  final Duration mindestens;

  /// Wie lange ein Abruf beim Anbieter dauern darf, samt Inhalt.
  final Duration frist;
  final Duration ruhe;

  final http.Client _netz;
  final DateTime Function() _uhr;

  /// Wie der Server sich beim Anbieter ausweist: die Software und ihre
  /// Fassung, sonst nichts – kein Rechnername, keine Adresse.
  static const kennung = 'PhotoVault-Server/$serverFassung';

  /// Mehr nimmt keine Haltbarkeit an – auch wenn ein Anbieter zehn Jahre
  /// nennt.
  static const _laengstens = Duration(days: 365);

  /// Eine Kachel hat 10 bis 60 KB. Was viel grösser ist, ist keine.
  static const _hoechstensBytes = 2 * 1024 * 1024;

  final _laufend = <String, Future<_Abruf>>{};
  final _ruheBis = <String, DateTime>{};
  final _fehlerInFolge = <String, int>{};
  Future<void>? _aufraeumen;
  var _nochmal = false;
  File? _zuletzt;
  var _aktiv = 0;
  final _wartend = Queue<Completer<void>>();

  /// Bis zum nächsten Aufräumen – nicht nach jeder Kachel, das hiesse bei
  /// vollem Speicher jedes Mal zehntausende Dateien ansehen. Beim ersten
  /// Schreiben nach dem Start gleich, danach alle 5 % der [grenze].
  var _bisAufraeumen = 0;

  /// `GET /api/v1/karte/<stil>/<z>/<x>/<y>.png`
  Future<Response> kachel(
    Request anfrage,
    String stil,
    String z,
    String x,
    String y,
  ) async {
    final quelle = serverKartenquellen[stil];
    final zi = int.tryParse(z), xi = int.tryParse(x), yi = int.tryParse(y);
    if (quelle == null ||
        zi == null ||
        xi == null ||
        yi == null ||
        zi < 0 ||
        zi > quelle.hoechsteStufe ||
        xi < 0 ||
        yi < 0 ||
        xi >= 1 << zi ||
        yi >= 1 << zi) {
      return _nichtDa();
    }
    final datei = File(p.join(ordner.path, '$stil-$zi-$xi-$yi.png'));
    final gilt = await _giltBis(datei);
    if (gilt != null && gilt.isAfter(_uhr())) {
      if (await _ausliefern(anfrage, datei, gilt) case final r?) return r;
    }
    final abruf = await _laufend.putIfAbsent(
      datei.path,
      () => _hole(stil, Uri.https(quelle.host, '/$zi/$xi/$yi.png'), datei)
          .whenComplete(() {
            // Mit Block: `remove` gäbe dieses Future selbst zurück, und
            // `whenComplete` wartete darauf – auf sich selbst.
            _laufend.remove(datei.path);
          }),
    );
    if (abruf case _Geholt(gilt: final neu)) {
      return await _ausliefern(anfrage, datei, neu) ?? _gestoert();
    }
    // Die alte Kopie, solange es keine neue gibt.
    if (gilt != null) {
      if (await _ausliefern(anfrage, datei, null) case final r?) return r;
    }
    return abruf is _Fehlt ? _nichtDa() : _gestoert();
  }

  void schliesse() => _netz.close();

  Future<DateTime?> _giltBis(File datei) async {
    final s = await datei.stat();
    return s.type == FileSystemEntityType.notFound ? null : s.modified;
  }

  /// Die Datei, mit dem, was von ihrer Haltbarkeit übrig ist – `null`,
  /// wenn sie das Aufräumen gerade genommen hat.
  Future<Response?> _ausliefern(
    Request anfrage,
    File datei,
    DateTime? gilt,
  ) async {
    try {
      final antwort = await dateiAntwort(anfrage, datei);
      final rest = gilt == null
          ? 0
          : math.max(0, gilt.difference(_uhr()).inSeconds);
      return antwort.change(
        headers: {'cache-control': 'private, max-age=$rest'},
      );
    } on FileSystemException {
      return null;
    }
  }

  Future<_Abruf> _hole(String stil, Uri adresse, File datei) async {
    await _platz();
    try {
      final bis = _ruheBis[stil];
      if (bis != null && _uhr().isBefore(bis)) return const _Gestoert();
      final (status, kopf, bytes) = await _abruf(adresse);
      if (status == 200 &&
          (kopf['content-type'] ?? '').startsWith('image/png') &&
          bytes.isNotEmpty) {
        final gilt = _uhr().add(_haltbarkeit(kopf));
        await _lege(datei, bytes, gilt);
        _fehlerInFolge.remove(stil);
        return _Geholt(gilt);
      }
      // 404 ist eine Antwort und keine Störung: Die Kachel gibt es nicht,
      // oder OpenTopoMap rendert sie noch (siehe kachelNochmalVersuchen in
      // der App). 429 und 503 heissen ausdrücklich: in Ruhe lassen. Eine
      // Fehlerseite oder ein 500 erst, wenn es sich wiederholt.
      if (status == 404) {
        _fehlerInFolge.remove(stil);
        return const _Fehlt();
      }
      _gescheitert(stil, sofort: status == 429 || status == 503);
      return const _Gestoert();
    } on FileSystemException catch (f) {
      // Die Platte, nicht der Anbieter: kein Grund, ihn zu schonen.
      protokoll('Kartenkachel nicht abgelegt: ${f.message}');
      return const _Gestoert();
    } on Object catch (f) {
      if (f is! http.ClientException &&
          f is! IOException &&
          f is! TimeoutException &&
          f is! _ZuGross) {
        rethrow;
      }
      _gescheitert(stil);
      return const _Gestoert();
    } finally {
      _frei();
    }
  }

  void _gescheitert(String stil, {bool sofort = false}) {
    final n = (_fehlerInFolge[stil] ?? 0) + 1;
    _fehlerInFolge[stil] = n;
    if (sofort || n >= 3) {
      _ruheBis[stil] = _uhr().add(ruhe);
      _fehlerInFolge.remove(stil);
    }
  }

  Future<(int, Map<String, String>, Uint8List)> _abruf(Uri adresse) async {
    final abbruch = Completer<void>();
    Future<(int, Map<String, String>, Uint8List)> lauf() async {
      final r = await _netz.send(
        http.AbortableRequest('GET', adresse, abortTrigger: abbruch.future)
          ..headers['user-agent'] = kennung,
      );
      if ((r.contentLength ?? 0) > _hoechstensBytes) throw const _ZuGross();
      final bytes = BytesBuilder(copy: false);
      await for (final teil in r.stream) {
        bytes.add(teil);
        if (bytes.length > _hoechstensBytes) throw const _ZuGross();
      }
      return (r.statusCode, r.headers, bytes.takeBytes());
    }

    try {
      return await lauf().timeout(frist);
    } catch (_) {
      // Die Verbindung wirklich abräumen, nicht nur das Warten aufgeben.
      if (!abbruch.isCompleted) abbruch.complete();
      rethrow;
    }
  }

  /// Wie lange die Kachel gilt: was der Anbieter sagt (`max-age`, sonst
  /// `Expires`), aber nie weniger als [mindestens].
  Duration _haltbarkeit(Map<String, String> kopf) {
    Duration? angabe;
    final alter = int.tryParse(kopf['age'] ?? '') ?? 0;
    final max = RegExp(
      r'(?:^|[,\s])max-age=(\d+)',
    ).firstMatch(kopf['cache-control'] ?? '');
    if (max != null) {
      final s = int.tryParse(max[1]!);
      if (s != null) angabe = Duration(seconds: s - alter);
    } else if (kopf['expires'] case final ablauf?) {
      try {
        final datum = kopf['date'];
        angabe = HttpDate.parse(
          ablauf,
        ).difference(datum == null ? _uhr() : HttpDate.parse(datum));
      } on HttpException {
        // Kein Datum – dann eben die Vorgabe.
      }
    }
    if (angabe == null || angabe < mindestens) return mindestens;
    return angabe > _laengstens ? _laengstens : angabe;
  }

  Future<void> _lege(File datei, Uint8List bytes, DateTime gilt) async {
    await ordner.create(recursive: true);
    final teil = File('${datei.path}.teil');
    await teil.writeAsBytes(bytes);
    // Vor dem Umbenennen: Wer die Datei sieht, sieht auch ihre Frist.
    await teil.setLastModified(gilt);
    await teil.rename(datei.path);
    _bisAufraeumen -= bytes.length;
    _zuletzt = datei;
    if (_bisAufraeumen <= 0) {
      _bisAufraeumen = grenze ~/ 20;
      _raeumeAuf();
    }
  }

  /// Hält den Speicher unter [grenze] – neben der Anfrage, nicht in ihr:
  /// Bei vollem Speicher sieht das Aufräumen zehntausende Dateien an, und
  /// die Kachel, die es auslöst, hielte so lange einen der Abrufplätze.
  /// Kommt unterdessen genug Neues dazu, läuft es danach gleich noch einmal.
  void _raeumeAuf() {
    if (_aufraeumen != null) {
      _nochmal = true;
      return;
    }
    _aufraeumen = () async {
      do {
        _nochmal = false;
        try {
          final behalten = _zuletzt;
          if (behalten != null) {
            await begrenzeZwischenspeicher(ordner, grenze, behalten: behalten);
          }
        } on Object catch (f) {
          protokoll('Kartenkacheln nicht aufgeräumt: $f');
        }
      } while (_nochmal);
    }().whenComplete(() => _aufraeumen = null);
  }

  /// Wartet, bis ein laufendes Aufräumen fertig ist – für Tests.
  Future<void> aufraeumenFertig() async {
    for (var l = _aufraeumen; l != null; l = _aufraeumen) {
      await l;
    }
  }

  Future<void> _platz() async {
    if (_aktiv < gleichzeitig) {
      _aktiv++;
      return;
    }
    final c = Completer<void>();
    _wartend.add(c);
    // Der Platz wird übergeben, nicht freigegeben und neu genommen.
    await c.future;
  }

  void _frei() {
    if (_wartend.isNotEmpty) {
      _wartend.removeFirst().complete();
    } else {
      _aktiv--;
    }
  }

  static Response _nichtDa() => Response.notFound(
    'nicht da',
    headers: {
      'content-type': 'text/plain; charset=utf-8',
      'cache-control': 'no-store',
    },
  );

  static Response _gestoert() => Response(
    502,
    body: jsonEncode({'fehler': 'Der Kartendienst antwortet gerade nicht.'}),
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store',
    },
  );
}

sealed class _Abruf {
  const _Abruf();
}

final class _Geholt extends _Abruf {
  const _Geholt(this.gilt);
  final DateTime gilt;
}

/// Der Anbieter sagt 404.
final class _Fehlt extends _Abruf {
  const _Fehlt();
}

/// Keine brauchbare Antwort.
final class _Gestoert extends _Abruf {
  const _Gestoert();
}

class _ZuGross implements Exception {
  const _ZuGross();
}
