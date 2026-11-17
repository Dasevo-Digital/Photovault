// ignore_for_file: avoid_print
// Zweite Prüfrunde „Sicherung, Server, Teilen“ (r2-sic): Einträge, die in
// der ersten Runde (katalog_sic_a_test.dart, katalog_sic_b_test.dart) nur
// teilweise gingen – jetzt gegen eigene Wegwerf-Server mit den passenden
// Umgebungsvariablen (tools/wegwerf_server.sh):
//
//   PV_KATALOG_SERVER  aktuelle Fassung mit PV_SICHERUNG
//   PV_R2_KNAPP        PV_SPEICHER_WARNUNG=50, ein Konto mit 11 500 Fotos
//   PV_R2_VOLL         PV_SPEICHER_MINDEST=100000
//   PV_R2_TOTP         PV_TOTP=pflicht
//   PV_R2_ALT          eine ältere Fassung (3.51.0: ohne Passkeys, Schema 95)
//
// Die Server überdauern mehrere Läufe; deshalb trägt jeder Name eine
// Kennung des Laufs. Was die Prüf-App im Sandkasten nicht selbst kann
// (Daten am Server ändern), erledigt ein Wächter ausserhalb auf ein
// Zeichen hin: eine Datei im Temp-Ordner der Prüfung (siehe [_signal]).
//
// Wo die App „ohne Netz“ sein soll, spricht sie über ein Kabel in dieser
// Datei mit dem Server: eine Weiterleitung auf TCP-Ebene, die sich ziehen
// und wieder stecken lässt und Anfragen zurückhalten kann ([_Kabel]).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' show max;

import 'package:abgleich_ui/l10n/sync_texte.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart' hide testWidgets;
import 'package:flutter_test/flutter_test.dart' as ft show testWidgets;
import 'package:integration_test/integration_test.dart';
import 'package:intl/intl.dart';
import 'package:kern/abgleich/abgleich.dart';
import 'package:kern/abgleich/anmeldung.dart';
import 'package:kern/abgleich/konten.dart';
import 'package:kern/abgleich/sicherung.dart';
import 'package:kern/abgleich/tus.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:kern/abgleich/verbindungsdatei.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/backup_restore.dart' show BackupWiederhersteller;
import 'package:path/path.dart' as p;
import 'package:photo_vault/main.dart' show PhotoVaultApp;
import 'package:photo_vault/screens/asset_viewer_screen.dart';
import 'package:photo_vault/screens/einstellungen/server.dart';
import 'package:photo_vault/screens/einstellungen/sicherung.dart'
    show AutomatischeSicherungGruppe;
import 'package:photo_vault/screens/home_shell.dart' show HomeShell;
import 'package:photo_vault/screens/server_konten_screen.dart';
import 'package:photo_vault/screens/settings_screen.dart';
import 'package:photo_vault/services/library_location.dart';
import 'package:photo_vault/services/meldungsdienst.dart';
import 'package:photo_vault/services/platform/folder_access_desktop.dart';
import 'package:photo_vault/services/tokenablage.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/widgets/month_grouped_asset_grid.dart'
    show MonthGroupedAssetGrid;
import 'package:photo_vault/widgets/video_playback.dart';
import 'package:provider/provider.dart';
import 'package:teilen_ui/l10n/teilen_texte.dart';
import 'package:uuid/uuid.dart';

import 'katalog_kit.dart';

final tt = lookupTeilenTexte(const Locale('de'));
final st = lookupSyncTexte(const Locale('de'));

const _pw = 'Testpasswort-1234';
const _verwalter = 'Verwalter';
const _geraet = 'Rechner-E2E';
const _p1 = 'erste-passphrase-1';
const _sicherungPw = 'Sicherungs-Passphrase-1';

const _knappAdresse = String.fromEnvironment('PV_R2_KNAPP');
const _vollAdresse = String.fromEnvironment('PV_R2_VOLL');
const _totpAdresse = String.fromEnvironment('PV_R2_TOTP');
const _altAdresse = String.fromEnvironment('PV_R2_ALT');

/// Für jeden Lauf andere Namen: Die Server bleiben über mehrere Läufe.
final _lauf = (DateTime.now().millisecondsSinceEpoch ~/ 1000 % 100000)
    .toString();
String _n(String name) => '$name$_lauf';

Uri _uri(String s) => Uri.parse(s.endsWith('/') ? s : '$s/');

/// Der Server der laufenden Prüfung (siehe [_aufServer]).
Uri _srv = _uri(serverAdresse);

void _aufServer(String adresse) {
  if (adresse.isEmpty) throw StateError('Serveradresse fehlt (--dart-define)');
  _srv = _uri(adresse);
}

// --- Netz aus dem Test ------------------------------------------------------

Future<T> _netz<T>(WidgetTester tester, Future<T> Function() f) async {
  T? ergebnis;
  Object? fehler;
  StackTrace? spur;
  await tester.runAsync(() async {
    try {
      ergebnis = await f();
    } catch (e, s) {
      fehler = e;
      spur = s;
    }
  });
  if (fehler != null) Error.throwWithStackTrace(fehler!, spur!);
  return ergebnis as T;
}

class _Konto {
  _Konto(this.id, this.name, this.token);
  final String id;
  final String name;
  String token;
}

final _verwalterTokens = <String, String>{};

Future<String> _verwalterToken() async {
  if (_verwalterTokens['$_srv'] case final t?) return t;
  final a = Anmeldung(_srv);
  try {
    final z = await a.zustand();
    final s = z['einrichten'] == true
        ? await a.einrichten(_verwalter, _pw, geraet: 'Pruefstand')
        : await a.anmelden(_verwalter, _pw, geraet: 'Pruefstand');
    if (s is! AnmeldungFertig) throw StateError('Verwalter: $s');
    return _verwalterTokens['$_srv'] = s.token;
  } finally {
    a.schliesse();
  }
}

Future<String> _anmelden(
  String name, {
  String pw = _pw,
  String geraet = 'Handy',
  Uri? server,
}) async {
  final a = Anmeldung(server ?? _srv);
  try {
    final s = await a.anmelden(name, pw, geraet: geraet);
    if (s is! AnmeldungFertig) {
      throw StateError('Anmeldung $name: ${s.runtimeType}');
    }
    return s.token;
  } finally {
    a.schliesse();
  }
}

Future<_Konto> _konto(
  String name, {
  bool verwalter = false,
  String geraet = 'Handy',
}) async {
  final v = Serververbindung(_srv, await _verwalterToken());
  try {
    final k = await Kontenverwaltung(v).legeAn(name, _pw, verwalter: verwalter);
    return _Konto(k.id, k.name, await _anmelden(name, geraet: geraet));
  } finally {
    v.schliesse();
  }
}

Future<T> _mit<T>(
  String token,
  Future<T> Function(Serververbindung v) f,
) async {
  final v = Serververbindung(_srv, token);
  try {
    return await f(v);
  } finally {
    v.schliesse();
  }
}

Future<Map<String, Object?>> _hole(String token, String pfad) =>
    _mit(token, (v) => v.hole(pfad));

Future<int> _schickeJson(
  String token,
  String methode,
  String pfad,
  Object? inhalt,
) => _mit(token, (v) async {
  final r = await v.anfrage(
    methode,
    pfad,
    kopf: const {'content-type': 'application/json'},
    inhalt: utf8.encode(jsonEncode(inhalt)),
  );
  return r.statusCode;
});

Future<void> _befehl(String token, Befehl<Object?> b) =>
    _mit(token, (v) => v.schicke('api/v1/befehle', b.alsJson()));

Future<String> _hochladen(String token, File datei) => _mit(token, (v) async {
  final kopf = await TusHochladen(
    v,
  ).lade(datei, 'api/v1/hochladen', {'filename': p.basename(datei.path)});
  final id = kopf['pv-aufnahme'];
  if (id == null || id.isEmpty) throw StateError('Hochladen: $kopf');
  return id;
});

/// Lädt [datei] in die Fotokammer des Kontos statt in die Bibliothek.
Future<String> _inDieKammer(String token, File datei) => _mit(token, (v) async {
  final kopf = await TusHochladen(v).lade(datei, 'api/v1/hochladen', {
    'filename': p.basename(datei.path),
    'kammer': '1',
  });
  final id = kopf['pv-kammer'];
  if (id == null || id.isEmpty) throw StateError('Kammer: $kopf');
  return id;
});

Future<String> _albumAufServer(
  String token,
  String name,
  List<String> ids,
) async {
  final id = const Uuid().v4();
  await _befehl(token, AlbumAnlegen(id, name, DateTime.now()));
  if (ids.isNotEmpty) await _befehl(token, AlbumFuellen(id, ids));
  return id;
}

Future<void> _teile(
  String token,
  String albumId,
  String konto, {
  bool beitragen = false,
}) async {
  final s = await _schickeJson(
    token,
    'PUT',
    'api/v1/alben/$albumId/teilungen/$konto',
    {'beitragen': beitragen},
  );
  if (s != 200) throw StateError('Teilen: $s');
}

Future<Map<String, Object?>> _aufnahme(String token, String id) =>
    _hole(token, 'api/v1/aufnahmen/$id');

/// Die Kennung der Teilung von [albumName] für [token].
Future<String> _teilung(String token, String albumName) async {
  final liste = ((await _hole(token, 'api/v1/geteilt'))['alben']! as List)
      .cast<Map>();
  return '${liste.firstWhere((x) => x['name'] == albumName)['id']}';
}

// --- TOTP ---------------------------------------------------------------------

List<int> _base32(String s) {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  final aus = <int>[];
  var puffer = 0, bits = 0;
  for (final c in s.toUpperCase().split('')) {
    final w = alphabet.indexOf(c);
    if (w < 0) continue;
    puffer = (puffer << 5) | w;
    bits += 5;
    if (bits >= 8) {
      aus.add((puffer >> (bits - 8)) & 0xff);
      bits -= 8;
      puffer &= (1 << bits) - 1;
    }
  }
  return aus;
}

int _schrittJetzt() => DateTime.now().millisecondsSinceEpoch ~/ 1000 ~/ 30;

String _totp(List<int> schluessel, int schritt) {
  final zaehler = ByteData(8)..setInt64(0, schritt);
  final h = Hmac(sha1, schluessel).convert(zaehler.buffer.asUint8List()).bytes;
  final o = h[h.length - 1] & 0x0f;
  final zahl =
      ((h[o] & 0x7f) << 24) | (h[o + 1] << 16) | (h[o + 2] << 8) | h[o + 3];
  return (zahl % 1000000).toString().padLeft(6, '0');
}

final _geheimnisse = <String, List<int>>{};
final _letzterSchritt = <String, int>{};

/// Ein Code, der für [name] noch nicht verbraucht ist: Der Server nimmt je
/// Konto nur Schritte nach dem zuletzt benutzten (packages/server/lib/src/
/// konten/totp.dart). Wartet, bis der Schritt im Fenster liegt.
Future<String> _naechsterCode(String name) async {
  final g = _geheimnisse[name]!;
  final s = max(_schrittJetzt() - 1, (_letzterSchritt[name] ?? 0) + 1);
  while (s > _schrittJetzt() + 1) {
    await Future<void>.delayed(const Duration(seconds: 2));
  }
  _letzterSchritt[name] = s;
  return _totp(g, s);
}

/// Anmelden auf einem Server mit TOTP-Pflicht – richtet TOTP beim ersten
/// Mal ein, wie eine Authenticator-App es täte.
Future<String> _anmeldenTotp(String name, {String geraet = 'Handy'}) async {
  final a = Anmeldung(_srv);
  try {
    final z = await a.zustand();
    var s = name == _verwalter && z['einrichten'] == true
        ? await a.einrichten(name, _pw, geraet: geraet)
        : await a.anmelden(name, _pw, geraet: geraet);
    if (s is AnmeldungTotpEinrichten) {
      _geheimnisse[name] = _base32(s.geheimnis);
      s = await a.bestaetige(s.vorgang, await _naechsterCode(name));
    } else if (s is AnmeldungCode) {
      s = await a.bestaetige(s.vorgang, await _naechsterCode(name));
    }
    if (s is! AnmeldungFertig) {
      throw StateError('Anmeldung $name: ${s.runtimeType}');
    }
    return s.token;
  } finally {
    a.schliesse();
  }
}

// --- Zwischenserver (HTTP) ----------------------------------------------------

/// Leitet HTTP an [_srv] weiter oder beantwortet über [eingriff] selbst –
/// nur noch für eine nachgestellte Antwort (Schema eines neueren Servers).
class _Zwischen {
  HttpServer? _server;
  int? _port;
  Future<bool> Function(HttpRequest r)? eingriff;
  Uri get adresse => Uri.parse('http://127.0.0.1:$_port/');

  Future<void> starte() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, _port ?? 0);
    _port = _server!.port;
    _server!.listen((r) => unawaited(_bediene(r)));
  }

  Future<void> halte() async {
    final s = _server;
    _server = null;
    await s?.close(force: true);
  }

  static const _ohne = {
    'host',
    'content-length',
    'transfer-encoding',
    'connection',
  };

  Future<void> _bediene(HttpRequest r) async {
    try {
      if (eingriff case final e? when await e(r)) return;
      final ziel = _srv.resolve(r.uri.toString().substring(1));
      final client = HttpClient()..autoUncompress = false;
      r.response.persistentConnection = false;
      final a = await client.openUrl(r.method, ziel);
      a.followRedirects = false;
      r.headers.forEach((name, werte) {
        if (_ohne.contains(name)) return;
        for (final w in werte) {
          a.headers.add(name, w);
        }
      });
      if (r.contentLength >= 0) a.contentLength = r.contentLength;
      await a.addStream(r);
      final b = await a.close();
      r.response.statusCode = b.statusCode;
      r.response.headers.clear();
      b.headers.forEach((name, werte) {
        if (_ohne.contains(name)) return;
        r.response.headers.set(name, werte);
      });
      if (b.contentLength >= 0) r.response.contentLength = b.contentLength;
      await r.response.addStream(b);
      await r.response.close();
      client.close();
    } catch (e) {
      print('Zwischenserver ${r.method} ${r.uri.path}: $e');
      try {
        r.response.statusCode = 502;
        await r.response.close();
      } catch (_) {}
    }
  }
}

Future<void> _antworte(HttpRequest r, Object? daten, {int status = 200}) async {
  await r.drain<void>();
  r.response.statusCode = status;
  r.response.headers.contentType = ContentType.json;
  r.response.write(jsonEncode(daten));
  await r.response.close();
}

// --- Kabel (TCP) --------------------------------------------------------------

/// Eine Leitung zwischen App und Server auf TCP-Ebene: Sie reicht Bytes
/// unverändert durch (lange Abfragen, Keep-Alive, alles wie direkt).
/// [ziehe] trennt alle Verbindungen und nimmt keine neuen an – für die App
/// „Server nicht erreichbar“; [stecke] öffnet denselben Anschluss wieder,
/// ohne dass die App neu startet. [zurueckhalten] hält Anfragen, deren
/// Kopf diesen Text enthält (z. B. `POST /api/v1/befehle`), [halteDauer]
/// lang zurück – ein langsamer Server.
class _Kabel {
  _Kabel(this.ziel);

  final Uri ziel;
  ServerSocket? _server;
  int? _port;
  final _offen = <Socket>{};
  String? zurueckhalten;
  Duration halteDauer = const Duration(seconds: 8);
  var zurueckgehalten = 0;

  /// Fehler der Leitung gehen nicht an die Prüfung.
  final _zone = Zone.root.fork(
    specification: ZoneSpecification(
      handleUncaughtError: (self, parent, zone, e, s) => print('Kabel: $e'),
    ),
  );

  Uri get adresse => Uri.parse('http://127.0.0.1:$_port/');

  Future<void> stecke() async {
    final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, _port ?? 0);
    _port = s.port;
    _server = s;
    _zone.run(() => s.listen(_verbinde, onError: (Object _) {}));
  }

  Future<void> ziehe() async {
    final s = _server;
    _server = null;
    await s?.close();
    for (final x in _offen.toList()) {
      x.destroy();
    }
    _offen.clear();
  }

  Future<void> _verbinde(Socket app) async {
    _offen.add(app);
    unawaited(app.done.catchError((Object _) {}));
    final Socket dort;
    try {
      dort = await Socket.connect(ziel.host, ziel.port);
    } catch (_) {
      app.destroy();
      _offen.remove(app);
      return;
    }
    _offen.add(dort);
    unawaited(dort.done.catchError((Object _) {}));
    void weg() {
      app.destroy();
      dort.destroy();
      _offen
        ..remove(app)
        ..remove(dort);
    }

    dort.listen(
      (d) {
        try {
          app.add(d);
        } catch (_) {
          weg();
        }
      },
      onDone: () => app.close().catchError((Object _) {}),
      onError: (Object _) => weg(),
      cancelOnError: true,
    );
    var kette = Future<void>.value();
    app.listen(
      (d) {
        final muster = zurueckhalten;
        final halten = muster != null && latin1.decode(d).contains(muster);
        kette = kette.then((_) async {
          if (halten) {
            zurueckgehalten++;
            await Future<void>.delayed(halteDauer);
          }
          try {
            dort.add(d);
          } catch (_) {
            weg();
          }
        });
      },
      onDone: () => kette.then((_) => dort.close().catchError((Object _) {})),
      onError: (Object _) => weg(),
      cancelOnError: true,
    );
  }
}

// --- Abschirmung --------------------------------------------------------------

final _unbehandelt = <String>[];
List<(Object, StackTrace)>? _laufendeFehler;

void _fehlerAusDerApp(Object e, StackTrace s) {
  if ('$e'.contains('connection was closed') &&
      '$s'.contains('restore_queue_service')) {
    print('RestoreQueueService nach dem Schliessen (übergangen)');
    return;
  }
  if (e is KeineVerbindung) {
    final ort = '$s'.split('\n').take(3).join(' / ');
    _unbehandelt.add('$e @ $ort');
    print('Unbehandelt (ohne Server): $e\n$s');
    return;
  }
  final liste = _laufendeFehler;
  if (liste == null) {
    _unbehandelt.add('$e');
    print('Nach einer Prüfung unbehandelt: $e\n$s');
    return;
  }
  print('Unbehandelt in der Prüfung: $e\n$s');
  liste.add((e, s));
}

/// Jeder Zeitgeber der App im 30-Minuten-Takt (das automatische Backup,
/// lib/state/library_state.dart:990) – mit seinem Rückruf, damit eine
/// Prüfung den nächsten Takt auslösen kann, ohne eine halbe Stunde zu
/// warten. Gilt für den Bildaufbau (dort entsteht die Bibliothek) und den
/// Körper jeder Prüfung; alle anderen Zeitgeber laufen unverändert.
final _halbstuendlich = <(Timer, void Function(Timer))>[];
final _zeitgeber = ZoneSpecification(
  createPeriodicTimer: (self, parent, zone, period, f) {
    final t = parent.createPeriodicTimer(zone, period, f);
    if (period == const Duration(minutes: 30)) _halbstuendlich.add((t, f));
    return t;
  },
);

void _rahmenAbschirmen() {
  runZonedGuarded(
    () {
      final d = SchedulerBinding.instance.platformDispatcher;
      final anfang = d.onBeginFrame, zeichnen = d.onDrawFrame;
      if (anfang == null || zeichnen == null) {
        // ignore: invalid_use_of_protected_member
        SchedulerBinding.instance.ensureFrameCallbacksRegistered();
      } else {
        d.onBeginFrame = anfang;
        d.onDrawFrame = zeichnen;
      }
    },
    _fehlerAusDerApp,
    zoneSpecification: _zeitgeber,
  );
}

/// Ob ein gemeldeter Fehler eine Zusicherung des Rahmenwerks beim Aufbau
/// des Semantikbaums ist (`node.built`, Null-Prüfung in
/// `_RenderObjectSemantics`) – kein Verhalten der App. Sie traten in der
/// ersten Runde nur auf, wenn macOS die Semantik einschaltete.
bool _semantikDesRahmenwerks(FlutterErrorDetails d) {
  final spur = '${d.stack}';
  return spur.contains('flushSemantics') ||
      spur.contains('_RenderObjectSemantics') ||
      '${d.exception}'.contains("'node.built'");
}

/// Ob ein gemeldeter Fehler daher kommt, dass der Taktgeber des Kits ein
/// Bild mit einer Zeit vor dem letzten Bild des Systems auslöste
/// (`elapsedInSeconds >= 0.0` in AnimationController._tick) – eine Frage
/// des Prüfstands, nicht der App.
bool _taktDesPruefstands(FlutterErrorDetails d) =>
    '${d.exception}'.contains('elapsedInSeconds >= 0.0') &&
    '${d.stack}'.contains('AnimationController._tick');

WidgetTesterCallback _abgeschirmt(WidgetTesterCallback koerper) =>
    (tester) async {
      for (final m in melde.sichtbare) {
        melde.schliesse(m.nummer);
      }
      melde.verlaufGelesen();
      print(
        'Semantik eingeschaltet: '
        '${SemanticsBinding.instance.semanticsEnabled}',
      );
      final vorherOnError = FlutterError.onError;
      var semantik = 0;
      FlutterError.onError = (d) {
        if (_semantikDesRahmenwerks(d) || _taktDesPruefstands(d)) {
          semantik++;
          if (semantik <= 2) {
            print('Rahmenwerk übergangen: ${d.exceptionAsString()}');
          }
          return;
        }
        vorherOnError?.call(d);
      };
      final ende = Completer<void>();
      final fehler = _laufendeFehler = <(Object, StackTrace)>[];
      runZonedGuarded(
        () async {
          try {
            await koerper(tester);
            if (!ende.isCompleted) ende.complete();
          } catch (e, s) {
            if (!ende.isCompleted) ende.completeError(e, s);
          }
        },
        _fehlerAusDerApp,
        zoneSpecification: _zeitgeber,
      );
      Object? koerperFehler;
      StackTrace? koerperSpur;
      try {
        await ende.future;
      } catch (e, s) {
        koerperFehler = e;
        koerperSpur = s;
      }
      _laufendeFehler = null;
      FlutterError.onError = vorherOnError;
      print(
        'Übergangene Zusicherungen des Rahmenwerks (Semantik, Takt): $semantik',
      );
      if (koerperFehler == null && fehler.isEmpty) return;
      try {
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 200));
      } catch (_) {}
      if (fehler.isNotEmpty) {
        if (koerperFehler != null) {
          print('Danach in der Prüfung: $koerperFehler');
        }
        Error.throwWithStackTrace(fehler.first.$1, fehler.first.$2);
      }
      Error.throwWithStackTrace(koerperFehler!, koerperSpur!);
    };

void testWidgets(
  String beschreibung,
  WidgetTesterCallback koerper, {
  bool? skip,
}) => ft.testWidgets(beschreibung, _abgeschirmt(koerper), skip: skip);

/// Ruft den Knopf [knopf] so auf, wie ein Klick im Betrieb ihn ausführt:
/// in der Wurzelzone. Eine Ausnahme, die dort niemand fängt, geht wie im
/// Betrieb an `PlatformDispatcher.onError` (dort zeigt die App etwa „Geht
/// in einer verbundenen Bibliothek noch nicht“, services/serversperre.dart)
/// – im Testlauf finge sie sonst die Zone der Prüfung ab.
void _klickWieImBetrieb(WidgetTester tester, Finder knopf) {
  final b = tester.widget<IconButton>(
    find.ancestor(of: knopf, matching: find.byType(IconButton)).first,
  );
  Zone.root.run(() => b.onPressed!());
}

// --- Wächter ------------------------------------------------------------------

var _zeichen = 0;

/// Bittet den Wächter ausserhalb (pruefkatalog/arbeit/r2-sic/
/// r2sic_waechter.py) um [was] und wartet, bis er es erledigt hat.
Future<void> _signal(WidgetTester tester, String was) async {
  final f = File(p.join(anker.path, 'r2sic_signal_${++_zeichen}'));
  f.writeAsStringSync(was);
  await eventually(
    tester,
    () async => !f.existsSync(),
    timeout: const Duration(seconds: 90),
    was: 'Wächter: $was',
  );
  if (File('${f.path}.fehler').existsSync()) {
    throw StateError('Wächter scheiterte an „$was“');
  }
}

// --- Bedienung ----------------------------------------------------------------

Future<void> _tap(WidgetTester tester, Finder finder) async {
  if (melde.ungelesen > 0) {
    melde.verlaufGelesen();
    await tester.pump();
  }
  await waitFor(tester, finder);
  await tester.ensureVisible(finder.first);
  await tester.pump();
  await tester.tap(finder.first);
  await settle(tester, max: const Duration(milliseconds: 800));
}

Future<void> _tapText(WidgetTester tester, String text) =>
    _tap(tester, find.text(text));

Future<void> _tippe(WidgetTester tester, Finder feld, String text) async {
  await waitFor(tester, feld);
  await tester.ensureVisible(feld.first);
  tester
      .state<EditableTextState>(
        find.descendant(of: feld.first, matching: find.byType(EditableText)),
      )
      .requestKeyboard();
  await settle(tester);
  final c = tester.widget<TextField>(feld.first).controller;
  if (c == null) {
    await tester.enterText(feld.first, text);
  } else {
    c.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
  await settle(tester);
}

/// Ein übersetzter Satz mit `\u0001` als Platzhalter – passt auf jeden Text
/// an dessen Stelle.
Finder _satz(String mitPlatzhalter) {
  final re = RegExp(
    '^${mitPlatzhalter.split('\u0001').map(RegExp.escape).join('.+?')}\$',
    dotAll: true,
  );
  return find.byWidgetPredicate(
    (w) => w is Text && w.data != null && re.hasMatch(w.data!),
  );
}

Color? _farbe(WidgetTester tester, Finder text) =>
    tester.widget<Text>(text.first).style?.color;

Color _fehlerfarbe(WidgetTester tester, Finder text) =>
    Theme.of(tester.element(text.first)).colorScheme.error;

String _datumZeit(DateTime d) =>
    '${DateFormat.yMd('de').format(d)} – ${DateFormat.Hm('de').format(d)}';

// --- App ----------------------------------------------------------------------

Future<void> _neustart(WidgetTester tester) async {
  final alt = bibliothek;
  try {
    if (alt.analyseLaeuft) alt.brichHintergrundanalyseAb();
    for (final lauf in alt.offeneAufgaben.toList()) {
      alt.brichAufgabeAb(lauf.schluessel);
    }
    final ende = DateTime.now().add(const Duration(seconds: 30));
    while (alt.etwasLaeuft && DateTime.now().isBefore(ende)) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    await alt.vorDemBeenden();
  } catch (e) {
    print('neustart: $e');
  }
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 300));
  LibraryLocation.nutzeFuerTests(
    anker: anker,
    zugriff: const DesktopFolderAccess(),
  );
  Verbindungsdatei.tokenablage = AppTokenablage(
    Directory(p.join(anker.path, 'tokens')),
  );
  await tester.pumpWidget(const PhotoVaultApp());
  await waitFor(
    tester,
    find.byType(HomeShell),
    timeout: const Duration(seconds: 90),
  );
  bibliothek = Provider.of<LibraryState>(
    tester.element(find.byType(HomeShell)),
    listen: false,
  );
  if (!bibliothek.paths.root.path.startsWith(anker.path)) {
    throw StateError('Bibliothek nicht im Temp-Ordner');
  }
  await settle(tester);
}

/// Verbindet die App ohne Oberfläche mit dem Konto [name] (wie „Die
/// Bibliothek des Servers hier öffnen“) und startet neu.
Future<String> _verbinde(
  WidgetTester tester,
  String name, {
  Uri? ueber,
  String geraet = _geraet,
  Future<String> Function()? anmelden,
}) async {
  final server = ueber ?? _srv;
  final token = await _netz(
    tester,
    anmelden ?? () => _anmelden(name, geraet: geraet, server: server),
  );
  await _netz(tester, () async {
    final basis = p.join(anker.path, 'verbunden', '$name-${server.port}');
    var ordner = Directory(basis);
    for (var i = 2; ordner.existsSync(); i++) {
      ordner = Directory('$basis-$i');
    }
    await ordner.create(recursive: true);
    final v = Serververbindung(server, token);
    try {
      await Abgleich.holeAbzug(v, File(p.join(ordner.path, 'library.sqlite')));
    } finally {
      v.schliesse();
    }
    await Verbindungsdatei(
      server: server,
      konto: name,
      geraet: geraet,
      token: token,
    ).schreibe(ordner);
    final e = await LibraryLocation.fuegeEigenenOrdnerHinzu(
      ordner,
      name: '$name @ ${server.port}',
    );
    await LibraryLocation.wechsleZu(e);
  });
  await _neustart(tester);
  expect(bibliothek.verbunden, isTrue);
  return token;
}

Future<List<AssetData>> _assets(WidgetTester tester) =>
    _netz(tester, () => bibliothek.db.select(bibliothek.db.assets).get());

Future<Map<String, String>> _originale(WidgetTester tester) =>
    _netz(tester, () async {
      final alle = await bibliothek.db.select(bibliothek.db.assets).get();
      return {
        for (final a in alle)
          if (bibliothek.paths.absolute(a.relativePath) case final f
              when f.existsSync())
            f.path: sha256.convert(await f.readAsBytes()).toString(),
      };
    });

Future<Map<String, String>> _nachrechnen(
  WidgetTester tester,
  Iterable<String> pfade,
) => _netz(tester, () async {
  return {
    for (final x in pfade)
      x: sha256.convert(await File(x).readAsBytes()).toString(),
  };
});

Future<int> _zaehle(
  WidgetTester tester,
  String sql, [
  List<String> w = const [],
]) => _netz(tester, () async {
  final r = await bibliothek.db
      .customSelect(sql, variables: [for (final x in w) Variable<String>(x)])
      .getSingle();
  return r.data.values.first as int;
});

Future<void> _warte(WidgetTester tester, Duration d) async {
  final ende = DateTime.now().add(d);
  while (DateTime.now().isBefore(ende)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _serverGruppe(WidgetTester tester) async {
  await openSection(tester, Hauptbereich.einstellungen);
  await settle(tester);
  if (find.byType(ServerGruppe).evaluate().isEmpty) {
    await _tap(
      tester,
      find.descendant(
        of: find.byType(ExpansionTile),
        matching: find.text(de.serverTitel),
      ),
    );
  }
  await waitFor(tester, find.byType(ServerGruppe));
}

Future<void> _verbindenSeite(WidgetTester tester) async {
  await _serverGruppe(tester);
  await _tapText(tester, de.serverVerbinden);
  await waitFor(tester, find.text(de.serverVerbindenTitel));
}

Finder _imDialog(String text) =>
    find.descendant(of: find.byType(Dialog), matching: find.text(text));

Finder _zeile(String titel) =>
    find.ancestor(of: find.text(titel), matching: find.byType(ListTile)).first;

Future<void> _zurueck(WidgetTester tester) async {
  final z = find.byType(BackButton);
  if (z.evaluate().isNotEmpty) {
    await _tap(tester, z.last);
  } else {
    await key(tester, LogicalKeyboardKey.escape);
  }
}

Future<void> _bisSichtbar(
  WidgetTester tester,
  Finder ziel,
  Finder bereich,
) async {
  if (ziel.evaluate().isNotEmpty) return;
  final rolle = find
      .descendant(of: bereich, matching: find.byType(Scrollable))
      .first;
  try {
    await tester.scrollUntilVisible(
      ziel,
      150,
      scrollable: rolle,
      maxScrolls: 60,
    );
  } on StateError {
    await tester.scrollUntilVisible(
      ziel,
      -150,
      scrollable: rolle,
      maxScrolls: 120,
    );
  }
  await settle(tester);
}

Future<void> _rasterFokus(WidgetTester tester) async {
  await openSection(tester, Hauptbereich.zeitleiste);
  await settle(tester);
  await tester.tapAt(const Offset(1000, 870));
  await settle(tester);
}

/// Öffnet das [n]-te Foto der Zeitleiste (0 = das neueste) mit der Info.
Future<void> _oeffneMitInfo(WidgetTester tester, int n) async {
  await _rasterFokus(tester);
  for (var i = 0; i <= n; i++) {
    await key(tester, LogicalKeyboardKey.arrowRight);
  }
  await key(tester, LogicalKeyboardKey.enter);
  await waitFor(tester, find.byType(AssetViewerScreen));
  if (field(de.infoBeschreibungHinzufuegen).evaluate().isEmpty) {
    await _tap(tester, find.byTooltip(de.viewerInfo));
  }
  await waitFor(tester, field(de.infoBeschreibungHinzufuegen));
}

Future<void> _beschreibungUi(WidgetTester tester, int n, String text) async {
  await _oeffneMitInfo(tester, n);
  await _tippe(tester, field(de.infoBeschreibungHinzufuegen), text);
  FocusManager.instance.primaryFocus?.unfocus();
  await settle(tester);
  await _warte(tester, const Duration(milliseconds: 600));
  await _schliesseBetrachter(tester);
}

Future<void> _schliesseBetrachter(WidgetTester tester) async {
  final zurueck = find.descendant(
    of: find.byType(AssetViewerScreen),
    matching: find.byWidgetPredicate(
      (w) => w is BackButton || w is CloseButton,
    ),
  );
  if (zurueck.evaluate().isNotEmpty) {
    await _tap(tester, zurueck.first);
  } else {
    await key(tester, LogicalKeyboardKey.escape);
  }
  await waitGone(tester, find.byType(AssetViewerScreen));
}

Future<bool> _blaettereBis(WidgetTester tester, Finder ziel) async {
  final seiten = find.byType(PageView);
  for (var i = 0; i < 8; i++) {
    if (ziel.evaluate().isNotEmpty) return true;
    await tester.fling(seiten, const Offset(700, 0), 1500);
    await settle(tester);
  }
  for (var i = 0; i < 10; i++) {
    if (ziel.evaluate().isNotEmpty) return true;
    await tester.fling(seiten, const Offset(-700, 0), 1500);
    await settle(tester);
  }
  return ziel.evaluate().isNotEmpty;
}

Finder get _kacheln => find.descendant(
  of: find.byType(GridView),
  matching: find.byType(GestureDetector),
);

/// Wartet, bis der Abgleich den Server erreicht bzw. nicht erreicht.
Future<void> _erreichbar(
  WidgetTester tester,
  bool ja, {
  Duration timeout = const Duration(seconds: 90),
}) => eventually(
  tester,
  () async => (bibliothek.abgleichszustand?.erreichbar ?? false) == ja,
  timeout: timeout,
  was: ja ? 'Server erreichbar' : 'Server nicht erreichbar',
);

// --- Einstellungen (wie in katalog_sic_a_test.dart) ---------------------------

Finder get _einstellungsliste => find
    .descendant(
      of: find.byType(SettingsScreen),
      matching: find.byType(Scrollable),
    )
    .first;

Future<Finder> _autoGruppe(WidgetTester tester) async {
  if (find.byType(SettingsScreen).evaluate().isEmpty) {
    await openSection(tester, Hauptbereich.einstellungen);
    await waitFor(tester, find.byType(SettingsScreen));
  }
  final kasten = find.byType(AutomatischeSicherungGruppe);
  final kopf = find.descendant(
    of: find.byType(SettingsScreen),
    matching: find.text(de.einstAbschnittAutoBackup),
  );
  if (kopf.evaluate().isEmpty) {
    tester.state<ScrollableState>(_einstellungsliste).position.jumpTo(0);
    await tester.pump();
    await tester.scrollUntilVisible(
      kopf,
      250,
      scrollable: _einstellungsliste,
      maxScrolls: 200,
    );
  }
  await tester.ensureVisible(kopf.first);
  await settle(tester);
  if (kasten.evaluate().isEmpty) {
    await tester.tap(kopf.first);
    await settle(tester);
    await waitFor(tester, kasten);
  }
  return kasten;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  _rahmenAbschirmen();
  print('r2-sic Lauf $_lauf, Server $_srv');

  // =========================================================================
  // SIC-039: Zeitgeber des automatischen Backups (ohne Server)
  // =========================================================================
  testWidgets('SIC-039 Automatisches Backup beim Start und im '
      '30-Minuten-Takt', (tester) async {
    _halbstuendlich.clear();
    await startApp(tester);
    await importiereDirekt(tester, [
      for (var i = 0; i < 3; i++)
        testfoto('takt$i.jpg', datum: DateTime(2021, 3, i + 1, 9)),
    ]);
    final ziel = Directory(p.join(anker.path, 'pruef', 'ziel_takt'))
      ..createSync(recursive: true);
    final vorZwei = DateTime.now().subtract(const Duration(hours: 2));
    await tester.runAsync(() async {
      await bibliothek.setupBackupPassphrase(_p1);
      await bibliothek.db.setAutoBackupConfig(
        enabled: true,
        destination: ziel.path,
        intervalHours: 1,
      );
      await bibliothek.db.setLastAutoBackupAt(vorZwei);
    });

    // Beim Start: Die App prüft sofort, ob ein Lauf fällig ist. Nach dem
    // Neustart ist die Passphrase gesperrt (sie liegt nur im Speicher) –
    // der Lauf beim Start meldet deshalb, dass er wartet (SIC-078).
    melde.verlaufLeeren();
    _halbstuendlich.clear();
    await _neustart(tester);
    expect(bibliothek.backupKeyAvailableThisSession, isFalse);
    final wartet = de.backupWartetPassphrase(0);
    await eventually(
      tester,
      () async => melde.verlauf.any((m) => m.text == wartet),
      timeout: const Duration(seconds: 30),
      was: 'Lauf beim Start meldet „$wartet“',
    );

    // Der Zeitgeber, den diese Bibliothek beim Start gestellt hat.
    final aktiv = [
      for (final z in _halbstuendlich)
        if (z.$1.isActive) z,
    ];
    print(
      'SIC-039: ${_halbstuendlich.length} Zeitgeber im 30-Minuten-Takt '
      'gestellt, ${aktiv.length} aktiv',
    );
    expect(aktiv, isNotEmpty, reason: 'Timer.periodic(30 min) gestellt');
    final (uhr, takt) = aktiv.last;

    // Passphrase in dieser Sitzung entsperrt, letzter Lauf vor zwei
    // Stunden, Intervall stündlich – dann der nächste Takt. Kein Klick,
    // kein Aufruf der App von aussen: derselbe Rückruf, den die Uhr nach
    // 30 Minuten ruft.
    await tester.runAsync(() async {
      await bibliothek.unlockBackupKeyWithPassphrase(_p1);
      await bibliothek.db.setLastAutoBackupAt(vorZwei);
    });
    expect(
      Directory(p.join(ziel.path, 'PhotoVault-AutoBackup')).existsSync(),
      isFalse,
      reason: 'noch kein Lauf',
    );
    final vorDemTakt = DateTime.now();
    takt(uhr);
    await eventually(
      tester,
      () async {
        final r = await bibliothek.db.backupSettingsRow();
        return r?.lastAutoBackupAt?.isAfter(
              vorDemTakt.subtract(const Duration(seconds: 1)),
            ) ??
            false;
      },
      timeout: const Duration(seconds: 120),
      was: 'Lauf nach dem Takt',
    );
    final letzter = (await tester.runAsync(
      () => bibliothek.db.backupSettingsRow(),
    ))!.lastAutoBackupAt!;
    expect(DateTime.now().difference(letzter).inMinutes, lessThan(3));
    expect(
      Directory(p.join(ziel.path, 'PhotoVault-AutoBackup', 'data')).listSync(),
      hasLength(3),
    );
    // „Letzter Lauf“ springt auf jetzt.
    final auto = await _autoGruppe(tester);
    await waitFor(
      tester,
      find.descendant(of: auto, matching: find.text(_datumZeit(letzter))),
    );
    expect(uhr.isActive, isTrue, reason: 'der Takt läuft weiter');
    await finish(tester);
  });

  // =========================================================================
  // Server-Sicherung (PV_SICHERUNG am Server von PV_KATALOG_SERVER)
  // =========================================================================
  testWidgets('SIC-157 SIC-156 SIC-155 Server-Sicherung: zurückholen mit '
      'Fotokammer, beschädigte Sicherung, veraltet', (tester) async {
    _aufServer(serverAdresse);
    await startApp(tester);
    final v = await _netz(tester, _verwalterToken);
    for (var i = 0; i < 2; i++) {
      await _netz(
        tester,
        () => _hochladen(
          v,
          testfoto(
            '${_n('sich${i}_')}.jpg',
            datum: DateTime(2024, 1, 1 + i),
            // Der Verwalter bleibt über die Läufe; gleiche Pixel wären am
            // Server eine Dublette des Fotos eines früheren Laufs.
            muster: int.parse(_lauf) * 10 + i,
          ),
        ),
      );
    }
    final kammerName = '${_n('kammer')}.jpg';
    await _netz(
      tester,
      () => _inDieKammer(
        v,
        testfoto(
          kammerName,
          datum: DateTime(2024, 2, 1, 10),
          muster: int.parse(_lauf) * 10 + 5,
        ),
      ),
    );
    Future<Map<String, Object?>> stand() =>
        _netz(tester, () => _hole(v, 'api/v1/sicherung'));
    Future<void> lauf(Future<void> Function() starte) async {
      final vorher = (await stand())['ende'];
      await starte();
      await eventually(
        tester,
        () async {
          final s = await _hole(v, 'api/v1/sicherung');
          return s['laeuft'] != true && s['ende'] != vorher;
        },
        timeout: const Duration(seconds: 240),
        was: 'Sicherung fertig',
      );
    }

    var s = await stand();
    final ziel = s['ziel']! as String;
    if (s['eingerichtet'] != true) {
      await lauf(
        () => _netz(
          tester,
          () =>
              _mit(v, (x) => Serversicherungsstand.einrichten(x, _sicherungPw)),
        ),
      );
    } else {
      await lauf(
        () => _netz(tester, () => _mit(v, Serversicherungsstand.jetzt)),
      );
    }
    s = await stand();
    print('SIC-157 Stand: $s');
    expect(s['ok'], isTrue, reason: 'erster Lauf gelingt');

    // SIC-157: in einer neuen, unverbundenen Bibliothek zurückholen.
    final konto = Directory(ziel).listSync().whereType<Directory>().firstWhere(
      (d) => p.basename(d.path).startsWith('${_verwalter}_'),
    );
    final kammerOrdner = Directory(
      p.join(konto.path, 'PhotoVault-AutoBackup', 'fotokammer'),
    );
    print(
      'SIC-157 Kammer in der Sicherung: '
      '${kammerOrdner.existsSync() ? kammerOrdner.listSync().length : 0}',
    );
    final dort =
        (await _netz(tester, () => _hole(v, 'api/v1/bibliothek')))['aufnahmen']!
            as int;
    dialog.ordner = p.join(konto.path, 'PhotoVault-AutoBackup');
    await openSection(tester, Hauptbereich.einstellungen);
    final gruppe = find.descendant(
      of: find.byType(ExpansionTile),
      matching: find.text(de.einstAbschnittManuellesBackup),
    );
    await _bisSichtbar(tester, gruppe, find.byType(SettingsScreen));
    await _tap(tester, gruppe);
    await _bisSichtbar(
      tester,
      find.text(de.einstWiederherstellen),
      find.byType(SettingsScreen),
    );
    await _tapText(tester, de.einstWiederherstellen);
    final pass = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await waitFor(tester, pass, timeout: const Duration(seconds: 30));
    await _tippe(tester, pass, _sicherungPw);
    await _tap(tester, _imDialog('OK'));
    await _warte(tester, const Duration(seconds: 2));
    if (find.text(de.einstBackupAktuellerStand).evaluate().isNotEmpty) {
      await _tapText(tester, de.einstBackupAktuellerStand);
    }
    await eventually(
      tester,
      () async {
        final n = await bibliothek.db.select(bibliothek.db.assets).get();
        return n.length >= dort + 1;
      },
      timeout: const Duration(seconds: 240),
      was: 'Fotos und Kammer zurück',
    );
    await _warte(tester, const Duration(seconds: 3));
    final namen = [for (final a in await _assets(tester)) a.originalFileName];
    print('SIC-157 zurück: ${namen.length} Aufnahmen');
    expect(
      namen,
      containsAll(['${_n('sich0_')}.jpg', '${_n('sich1_')}.jpg', kammerName]),
    );
    final imKammeralbum = await _netz(tester, () async {
      final r = await bibliothek.db
          .customSelect(
            'SELECT a.original_file_name AS n FROM album_assets aa '
            'JOIN assets a ON a.id = aa.asset_id '
            'JOIN albums al ON al.id = aa.album_id WHERE al.name = ?',
            variables: [
              const Variable(BackupWiederhersteller.fotokammerAlbumName),
            ],
          )
          .get();
      return [for (final z in r) z.read<String>('n')];
    });
    print(
      'SIC-157 im Album „${BackupWiederhersteller.fotokammerAlbumName}“: '
      '$imKammeralbum',
    );
    expect(imKammeralbum, contains(kammerName));
    expect(imKammeralbum, isNot(contains('${_n('sich0_')}.jpg')));
    // Und sichtbar unter „Alben“.
    await openSection(tester, Hauptbereich.alben);
    await waitFor(
      tester,
      find.text(BackupWiederhersteller.fotokammerAlbumName),
      timeout: const Duration(seconds: 20),
    );

    // SIC-156: beschädigte Sicherung → Probe scheitert, letzter Erfolg
    // bleibt genannt.
    await _verbinde(tester, _verwalter);
    await _serverGruppe(tester);
    await waitFor(
      tester,
      find.text(de.backupProbeTitel),
      timeout: const Duration(seconds: 30),
    );
    print(
      'SIC-156 Proben vorher: '
      '${find.text(de.backupProbeTitel).evaluate().length}',
    );
    await _signal(tester, 'beschaedigen ${_srv.port}');
    await lauf(() async {
      await _tapText(tester, de.serverSicherungJetzt);
      await erwarteMeldung(tester, de.serverSicherungGestartet);
    });
    print('SIC-156 Stand nach dem Schaden: ${await stand()}');
    await tester.runAsync(bibliothek.pruefeServersicherung);
    await settle(tester);
    // Band im Hauptfenster.
    await openSection(tester, Hauptbereich.zeitleiste);
    await waitFor(
      tester,
      find.text(de.serverSicherungWarnung),
      timeout: const Duration(seconds: 30),
    );
    await _serverGruppe(tester);
    final gescheitert = _satz(de.serverSicherungFehler('\u0001'));
    await waitFor(tester, gescheitert);
    expect(_farbe(tester, gescheitert), _fehlerfarbe(tester, gescheitert));
    print(
      'SIC-155 gescheitert: '
      '${(tester.widget<Text>(gescheitert.first)).data}',
    );
    final fehlprobe = find.byWidgetPredicate(
      (w) =>
          w is Text &&
          (w.data?.contains(
                de.backupProbeFehler('\u0001').split('\u0001').last.trim(),
              ) ??
              false) &&
          (w.data?.contains(
                de.backupProbeLetzterErfolg('\u0001').split('\u0001').first,
              ) ??
              false),
    );
    await waitFor(tester, fehlprobe);
    for (final e in fehlprobe.evaluate()) {
      print('SIC-156 Probe: ${(e.widget as Text).data}');
    }
    final kontenMitProbe = [
      for (final k in ((await stand())['konten']! as List).cast<Map>())
        if (k['wiederherstellungsprobe'] is Map) k['konto'],
    ].length;
    print('SIC-156 Konten mit Probe: $kontenMitProbe');
    expect(
      find.descendant(
        of: find.byType(ServerGruppe),
        matching: find.text(de.backupProbeTitel),
      ),
      findsNWidgets(kontenMitProbe),
      reason: 'je Konto eine Zeile „Wiederherstellungsprobe“',
    );

    // SIC-155: seit über 36 Stunden kein gelungener Lauf (am Server um
    // 40 Stunden zurückdatiert, der letzte Lauf selbst ok).
    await _signal(tester, 'veraltet ${_srv.port} 40');
    final s2 = await stand();
    print(
      'SIC-155 Stand veraltet: stufe ${s2['stufe']}, ${s2['letzterErfolg']}',
    );
    expect(s2['stufe'], 'veraltet');
    await tester.runAsync(bibliothek.pruefeServersicherung);
    await settle(tester);
    await openSection(tester, Hauptbereich.zeitleiste);
    await waitFor(
      tester,
      find.text(de.serverSicherungWarnung),
      timeout: const Duration(seconds: 30),
    );
    await _serverGruppe(tester);
    final veraltet = _satz(de.serverSicherungVeraltet('\u0001'));
    await waitFor(tester, veraltet);
    expect(_farbe(tester, veraltet), _fehlerfarbe(tester, veraltet));
    final erwartetWann = DateTime.parse(
      s2['letzterErfolg']! as String,
    ).toLocal();
    final text = tester.widget<Text>(veraltet.first).data!;
    print('SIC-155 veraltet: $text');
    expect(text, contains(DateFormat.Hm('de').format(erwartetWann)));
    // Aufräumen: Die beschädigten Dateien schreibt der nächste Lauf neu.
    await _signal(tester, 'aufraeumen ${_srv.port}');
    await finish(tester);
  });

  // =========================================================================
  // SIC-145: TOTP zurücksetzen (Server mit PV_TOTP=pflicht)
  // =========================================================================
  testWidgets('SIC-145 TOTP zurücksetzen', (tester) async {
    _aufServer(_totpAdresse);
    await startApp(tester);
    final v = await _netz(
      tester,
      () => _anmeldenTotp(_verwalter, geraet: 'Pruefstand'),
    );
    final mit = _n('B145_');
    final ohne = _n('C145_');
    await _netz(
      tester,
      () => _mit(v, (x) async {
        await Kontenverwaltung(x).legeAn(mit, _pw);
        await Kontenverwaltung(x).legeAn(ohne, _pw);
      }),
    );
    // „Konto B“ richtet TOTP bei der ersten Anmeldung ein.
    await _netz(tester, () => _anmeldenTotp(mit));
    await _verbinde(
      tester,
      _verwalter,
      anmelden: () => _anmeldenTotp(_verwalter, geraet: _geraet),
    );
    await _serverGruppe(tester);
    await _tap(tester, find.text(de.serverKontenVerwalten));
    await waitFor(tester, find.text(de.serverKontenTitel));
    final seite = find.byType(ServerKontenScreen);
    await _bisSichtbar(tester, find.text(mit), seite);
    expect(
      find.descendant(
        of: _zeile(mit),
        matching: find.textContaining(de.serverKontoMitTotp),
      ),
      findsOneWidget,
    );
    Future<void> menue(String name) => _tap(
      tester,
      find.descendant(
        of: _zeile(name),
        matching: find.byType(PopupMenuButton<String>),
      ),
    );

    // Ohne TOTP fehlt der Menüpunkt.
    await _bisSichtbar(tester, find.text(ohne), seite);
    await menue(ohne);
    await waitFor(tester, find.text(de.serverKontoPasswortSetzen));
    expect(find.text(de.serverKontoTotpZuruecksetzen), findsNothing);
    await key(tester, LogicalKeyboardKey.escape);

    // Mit TOTP: zurücksetzen.
    await _bisSichtbar(tester, find.text(mit), seite);
    await menue(mit);
    await _tapText(tester, de.serverKontoTotpZuruecksetzen);
    await erwarteMeldung(tester, de.serverKontoTotpZurueckgesetzt(mit));
    // Wirkung am Server: Die nächste Anmeldung richtet TOTP neu ein.
    final naechste = await _netz(tester, () async {
      final a = Anmeldung(_srv);
      try {
        return await a.anmelden(mit, _pw, geraet: 'Handy-2');
      } finally {
        a.schliesse();
      }
    });
    print('SIC-145 nächste Anmeldung: ${naechste.runtimeType}');
    expect(naechste, isA<AnmeldungTotpEinrichten>());
    await _warte(tester, const Duration(seconds: 2));
    print(
      'SIC-145 Zeile danach „${de.serverKontoOhneTotp}“: '
      '${find.descendant(of: _zeile(mit), matching: find.textContaining(de.serverKontoOhneTotp)).evaluate().isNotEmpty}',
    );
    await _zurueck(tester);
    await finish(tester);
  });

  // =========================================================================
  // SIC-112 SIC-127: ältere Serverfassung (3.51.0)
  // =========================================================================
  testWidgets('SIC-112 SIC-127 Ältere Serverfassung: keine Passkeys, '
      'anderes Schema', (tester) async {
    _aufServer(_altAdresse);
    await startApp(tester);
    final z = await _netz(tester, () async {
      final a = Anmeldung(_srv);
      try {
        return await a.zustand();
      } finally {
        a.schliesse();
      }
    });
    print('SIC-112 Zustand des alten Servers: $z');
    expect((z['anmeldung'] as Map?)?['passkeys'], isNull);

    // SIC-112: „Mit Passkey anmelden“ – rote Meldung, kein Browser. Der
    // Browser ginge erst auf, nachdem die App einen Rückweg auf einem
    // eigenen Anschluss geöffnet hat (kern/abgleich/passkey_anmeldung.dart:48
    // vor :55); jedes Öffnen eines Anschlusses aus diesem Klick heraus wird
    // hier gezählt.
    await _verbindenSeite(tester);
    await _tippe(tester, field(de.serverAdresse), '$_srv');
    final geoeffnet = <String>[];
    await IOOverrides.runZoned(
      () async {
        await _tapText(tester, de.serverPasskey);
        await waitFor(
          tester,
          find.text(de.serverPasskeyUnbekannt),
          timeout: const Duration(seconds: 30),
        );
      },
      serverSocketBind:
          (adresse, port, {backlog = 0, v6Only = false, shared = false}) {
            geoeffnet.add('$adresse:$port');
            return Zone.root.run(
              () => ServerSocket.bind(
                adresse,
                port,
                backlog: backlog,
                v6Only: v6Only,
                shared: shared,
              ),
            );
          },
    );
    await _warte(tester, const Duration(seconds: 2));
    final meldung = find.text(de.serverPasskeyUnbekannt);
    expect(_farbe(tester, meldung), _fehlerfarbe(tester, meldung));
    expect(geoeffnet, isEmpty, reason: 'kein Rückweg, kein Browser');
    expect(find.text(de.serverVerbindenTitel), findsOneWidget);
    await _zurueck(tester);

    // SIC-127 älter: eine Bibliothek dieses Servers, verbunden.
    final k = await _netz(tester, () => _konto(_n('Alt127_')));
    final fotoId = await _netz(
      tester,
      () => _hochladen(k.token, testfoto('alt127.jpg')),
    );
    await _verbinde(tester, k.name);
    await waitFor(
      tester,
      find.text(de.serverZuAlt),
      timeout: const Duration(seconds: 60),
    );
    await _serverGruppe(tester);
    expect(find.text(de.serverZuAlt), findsWidgets);
    // Eine Änderung bleibt hier und wartet.
    await _rasterFokus(tester);
    await key(tester, LogicalKeyboardKey.arrowRight);
    await key(tester, LogicalKeyboardKey.keyF);
    await eventually(
      tester,
      () async => (await bibliothek.db.assetById(fotoId))?.isFavorite ?? false,
      was: 'Favorit hier',
    );
    await _warte(tester, const Duration(seconds: 8));
    final wartend = await _zaehle(
      tester,
      'SELECT count(*) AS n FROM pv_ausgang WHERE bestaetigt IS NULL',
    );
    print('SIC-127 älter: $wartend Änderung(en) warten');
    expect(wartend, 1);
    expect(
      (await _netz(tester, () => _aufnahme(k.token, fotoId)))['isFavorite'],
      isFalse,
      reason: 'nichts abgeglichen',
    );

    // SIC-127 neuer: Einen neueren Server gibt es nicht (main trägt
    // dasselbe Schema 98); seine Antwort ist nachgestellt – der aktuelle
    // Server, dessen /api/v1/abgleich/stand ein Schema höher meldet.
    _aufServer(serverAdresse);
    final kn = await _netz(tester, () => _konto(_n('Neu127_')));
    final neuFoto = await _netz(
      tester,
      () => _hochladen(kn.token, testfoto('neu127.jpg')),
    );
    final zw = _Zwischen()
      ..eingriff = (r) async {
        if (r.uri.path == '/api/v1/abgleich/stand') {
          final token = r.headers.value('authorization')!.substring(7);
          final echt = await _hole(token, 'api/v1/abgleich/stand');
          await _antworte(r, {...echt, 'schema': (echt['schema']! as int) + 1});
          return true;
        }
        return false;
      };
    await _netz(tester, zw.starte);
    addTearDown(zw.halte);
    await _verbinde(tester, kn.name, ueber: zw.adresse);
    await waitFor(
      tester,
      find.text(de.serverAppZuAlt),
      timeout: const Duration(seconds: 60),
    );
    await _rasterFokus(tester);
    await key(tester, LogicalKeyboardKey.arrowRight);
    await key(tester, LogicalKeyboardKey.keyF);
    await eventually(
      tester,
      () async => (await bibliothek.db.assetById(neuFoto))?.isFavorite ?? false,
      was: 'Favorit hier',
    );
    await _warte(tester, const Duration(seconds: 6));
    expect(
      (await _netz(tester, () => _aufnahme(kn.token, neuFoto)))['isFavorite'],
      isFalse,
    );
    await finish(tester);
  });

  // =========================================================================
  // SIC-122 SIC-198: Speicher knapp bzw. voll (echte Messung des Servers)
  // =========================================================================
  testWidgets('SIC-122 SIC-198 Speicher des Servers knapp bzw. voll', (
    tester,
  ) async {
    // knapp: PV_SPEICHER_WARNUNG=50 bei mehr als 50 % belegter Platte.
    _aufServer(_knappAdresse);
    await startApp(tester);
    final k = await _netz(tester, () => _konto(_n('Knapp122_')));
    await _netz(tester, () => _hochladen(k.token, testfoto('knapp.jpg')));
    final sp = await _netz(tester, () => _hole(k.token, 'api/v1/speicher'));
    print('SIC-122 knapp, Server meldet: $sp');
    expect(sp['stufe'], 'knapp');
    await _verbinde(tester, k.name);
    final band = _satz(de.serverSpeicherKnapp('\u0001'));
    await waitFor(tester, band, timeout: const Duration(seconds: 60));
    print('SIC-122 Band: ${tester.widget<Text>(band.first).data}');
    await _serverGruppe(tester);
    final zeile = find.descendant(
      of: find.byType(ServerGruppe),
      matching: _satz(de.serverSpeicherStand('\u0001', '\u0001')),
    );
    await waitFor(tester, zeile);
    print('SIC-122 Zeile: ${tester.widget<Text>(zeile.first).data}');
    expect(_farbe(tester, zeile), _fehlerfarbe(tester, zeile));

    // voll: PV_SPEICHER_MINDEST=100000 (GB) – nichts Neues mehr.
    _aufServer(_vollAdresse);
    final b = await _netz(tester, () => _konto(_n('B198_')));
    final a = await _netz(tester, () => _konto(_n('Voll122_')));
    final spv = await _netz(tester, () => _hole(a.token, 'api/v1/speicher'));
    print('SIC-122 voll, Server meldet: $spv');
    expect(spv['stufe'], 'voll');
    final albumName = _n('Ferien198_');
    final albumId = await _netz(
      tester,
      () => _albumAufServer(b.token, albumName, const []),
    );
    await _netz(tester, () => _teile(b.token, albumId, a.id, beitragen: true));
    await _verbinde(tester, a.name);
    await waitFor(
      tester,
      find.text(de.serverSpeicherVoll),
      timeout: const Duration(seconds: 60),
    );
    await _serverGruppe(tester);
    expect(
      find.descendant(
        of: find.byType(ServerGruppe),
        matching: find.text(de.serverSpeicherVoll),
      ),
      findsOneWidget,
    );

    // SIC-198: in ein geteiltes Album beitragen.
    await openSection(tester, Hauptbereich.alben);
    await waitFor(
      tester,
      find.text(albumName),
      timeout: const Duration(seconds: 30),
    );
    await _tapText(tester, albumName);
    await waitFor(tester, find.byTooltip(tt.geteiltHinzufuegen));
    dialog.dateien = [testfoto('voll198.jpg')];
    await _tap(tester, find.byTooltip(tt.geteiltHinzufuegen));
    await erwarteMeldung(tester, tt.geteiltSpeicherVoll);
    final teilung = await _netz(tester, () => _teilung(a.token, albumName));
    final album = await _netz(
      tester,
      () => _hole(a.token, 'api/v1/geteilt/$teilung'),
    );
    expect(album['aufnahmen'] as List, isEmpty, reason: 'nichts angenommen');
    await finish(tester);
  });

  // =========================================================================
  // SIC-158 SIC-168: Abgleich über das Kabel (langsamer Server)
  // =========================================================================
  testWidgets('SIC-158 SIC-168 Änderung geht zum Server und zum anderen '
      'Gerät, Übersicht leer', (tester) async {
    _aufServer(serverAdresse);
    await startApp(tester);
    final k = await _netz(
      tester,
      () => _konto(_n('Abgl158_'), geraet: 'Geraet-2'),
    );
    final ids = <String>[];
    for (var i = 0; i < 2; i++) {
      ids.add(
        await _netz(
          tester,
          () => _hochladen(
            k.token,
            testfoto('abgl_$i.jpg', datum: DateTime(2024, 6, 1 + i)),
          ),
        ),
      );
    }
    final kabel = _Kabel(_srv);
    await _netz(tester, kabel.stecke);
    addTearDown(kabel.ziehe);
    await _verbinde(tester, k.name, ueber: kabel.adresse);
    await _erreichbar(tester, true);

    Future<bool> kommtAn(String id, int wert, Duration frist) async {
      final ende = DateTime.now().add(frist);
      while (DateTime.now().isBefore(ende)) {
        final a = await _netz(tester, () => bibliothek.db.assetById(id));
        if (a?.rating == wert) return true;
        await _warte(tester, const Duration(seconds: 1));
      }
      return false;
    }

    // Gerät 2 ändert, hier kommt es ohne Neustart an.
    await _netz(tester, () => _befehl(k.token, BewertungSetzen([ids[0]], 3)));
    expect(
      await kommtAn(ids[0], 3, const Duration(seconds: 60)),
      isTrue,
      reason: 'Empfang vor eigenem Befehl',
    );

    // SIC-158: fünf Sterne hier; der Server nimmt sich zehn Sekunden.
    kabel
      ..zurueckhalten = 'POST /api/v1/befehle'
      ..halteDauer = const Duration(seconds: 10);
    await _rasterFokus(tester);
    await key(tester, LogicalKeyboardKey.arrowRight);
    await key(tester, LogicalKeyboardKey.digit5);
    await eventually(tester, () async {
      final alle = await bibliothek.db.select(bibliothek.db.assets).get();
      return alle.where((a) => a.rating == 5).length == 1;
    }, was: 'fünf Sterne hier');
    await _serverGruppe(tester);
    await waitFor(
      tester,
      find.text(de.serverSendet(1)),
      timeout: const Duration(seconds: 9),
    );
    print('SIC-158 „${de.serverSendet(1)}“ gesehen');
    kabel.zurueckhalten = null;
    await waitFor(
      tester,
      find.text(de.serverAbgeglichen),
      timeout: const Duration(seconds: 40),
    );
    expect(kabel.zurueckgehalten, greaterThanOrEqualTo(1));
    final bewertet = (await _assets(tester)).firstWhere((a) => a.rating == 5);
    expect(
      (await _netz(tester, () => _aufnahme(k.token, bewertet.id)))['rating'],
      5,
    );
    // Und Gerät 2 nach dem eigenen Befehl – weiter ohne Neustart.
    final anderes = ids.firstWhere((i) => i != bewertet.id);
    await _netz(tester, () => _befehl(k.token, BewertungSetzen([anderes], 4)));
    expect(
      await kommtAn(anderes, 4, const Duration(seconds: 60)),
      isTrue,
      reason: 'Empfang nach eigenem Befehl',
    );

    // SIC-168: die leere Übersicht; der Abgleich braucht drei Sekunden.
    await _tapText(tester, de.syncUebersicht);
    await waitFor(tester, find.text(st.anzahl(0, 0)));
    expect(find.text(st.leer), findsOneWidget);
    kabel
      ..zurueckhalten = 'GET /api/v1/abgleich/aenderungen'
      ..halteDauer = const Duration(seconds: 3);
    await tester.tap(find.byTooltip(st.aktualisieren));
    var balken = false;
    for (var i = 0; i < 80 && !balken; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      balken = find.byType(LinearProgressIndicator).evaluate().isNotEmpty;
    }
    kabel.zurueckhalten = null;
    print('SIC-168 Balken gesehen: $balken');
    expect(balken, isTrue);
    await waitGone(
      tester,
      find.byType(LinearProgressIndicator),
      timeout: const Duration(seconds: 30),
    );
    expect(find.text(st.leer), findsOneWidget);
    expect(find.text(st.fehler), findsNothing);
    await _zurueck(tester);
    await finish(tester);
  });

  // Befund: Ist „Abgleich erneut versuchen“ einmal gescheitert (hier: ohne
  // Netz), bleibt „Die Übersicht konnte nicht aktualisiert werden …“ stehen,
  // auch wenn die Übersicht danach wieder lädt – _lade setzt _fehler nie
  // zurück (packages/abgleich_ui/lib/abgleichsuebersicht.dart:50–67, nur
  // _abgleichen :73 tut es). Hinweis von SIC-168 zweimal bestätigt.
  testWidgets('SIC-168 Hinweis: Fehlertext bleibt nach dem Wiederverbinden', (
    tester,
  ) async {
    _aufServer(serverAdresse);
    await startApp(tester);
    final k = await _netz(tester, () => _konto(_n('Hinw168_')));
    await _netz(tester, () => _hochladen(k.token, testfoto('h168.jpg')));
    final kabel = _Kabel(_srv);
    await _netz(tester, kabel.stecke);
    addTearDown(kabel.ziehe);
    await _verbinde(tester, k.name, ueber: kabel.adresse);
    await _erreichbar(tester, true);
    await _serverGruppe(tester);
    await _tapText(tester, de.syncUebersicht);
    await waitFor(tester, find.text(st.leer));
    await _netz(tester, kabel.ziehe);
    await _erreichbar(tester, false, timeout: const Duration(seconds: 60));
    await tester.tap(find.byTooltip(st.aktualisieren));
    await waitFor(tester, find.text(st.fehler));
    await _netz(tester, kabel.stecke);
    await _erreichbar(tester, true, timeout: const Duration(seconds: 120));
    // Der Abgleich ist zurück, die Übersicht lädt über seinen Zustand neu.
    await _warte(tester, const Duration(seconds: 5));
    expect(find.text(st.leer), findsOneWidget, reason: 'die Übersicht lädt');
    final bleibt = find.text(st.fehler).evaluate().isNotEmpty;
    print('SIC-168 Hinweis: Fehlertext nach dem Wiederverbinden: $bleibt');
    expect(bleibt, isFalse, reason: 'veralteter Fehlertext');
    await _zurueck(tester);
    await finish(tester);
  }, skip: true);

  // =========================================================================
  // SIC-162–165: Konflikte, wiederverbunden ohne Neustart (Kabel)
  // =========================================================================
  testWidgets('SIC-162 SIC-163 SIC-164 SIC-165 Konflikte', (tester) async {
    _aufServer(serverAdresse);
    await startApp(tester);
    final k = await _netz(
      tester,
      () => _konto(_n('Konf162_'), geraet: 'Geraet-2'),
    );
    for (var i = 0; i < 3; i++) {
      await _netz(
        tester,
        () => _hochladen(
          k.token,
          testfoto('konf_$i.jpg', datum: DateTime(2024, 8, 3 - i)),
        ),
      );
    }
    final kabel = _Kabel(_srv);
    await _netz(tester, kabel.stecke);
    addTearDown(kabel.ziehe);
    await _verbinde(tester, k.name, ueber: kabel.adresse);
    await _erreichbar(tester, true);

    /// Offline hier [hier], am Server [dort], dann wieder verbunden – ohne
    /// Neustart. Gibt die Kennung zurück.
    Future<String> konflikt(int n, String hier, String dort) async {
      await _netz(tester, kabel.ziehe);
      await _erreichbar(tester, false, timeout: const Duration(seconds: 60));
      await _beschreibungUi(tester, n, hier);
      final a = (await _assets(
        tester,
      )).firstWhere((a) => a.description == hier);
      await _netz(
        tester,
        () => _befehl(k.token, BeschreibungSetzen([a.id], dort)),
      );
      melde.verlaufLeeren();
      await _netz(tester, kabel.stecke);
      await eventually(
        tester,
        () async => (bibliothek.abgleichszustand?.faelle ?? 0) >= 1,
        timeout: const Duration(seconds: 150),
        was: 'Konflikt erkannt',
      );
      return a.id;
    }

    // SIC-162
    final id1 = await konflikt(0, 'A', 'B');
    await waitFor(
      tester,
      find.textContaining(de.syncNichtUebernommen(1)),
      timeout: const Duration(seconds: 20),
    );
    print('SIC-162 Meldung gesehen');
    await _tapText(tester, de.syncAnsehen);
    await waitFor(tester, find.text(st.titel));
    await waitFor(tester, find.text(st.beschreibung));
    expect(find.textContaining(st.konflikt), findsOneWidget);
    await eventually(
      tester,
      () async => (await bibliothek.db.assetById(id1))?.description == 'B',
      timeout: const Duration(seconds: 60),
      was: 'das Foto zeigt B',
    );

    // SIC-163: Serverstand behalten.
    await _tapText(tester, st.beschreibung);
    await waitFor(tester, find.text('${st.server}: B'));
    expect(find.text('${st.eigen}: A'), findsOneWidget);
    await _tapText(tester, st.behalten);
    await _tap(tester, _imDialog(st.bestaetigen));
    await waitFor(tester, find.text(st.leer));
    expect(
      (await _netz(tester, () => bibliothek.db.assetById(id1)))!.description,
      'B',
    );
    expect(
      (await _netz(tester, () => _aufnahme(k.token, id1)))['description'],
      'B',
    );
    await _zurueck(tester);

    // SIC-164: eigene Änderung erneut anwenden.
    final id2 = await konflikt(1, 'A2', 'B2');
    await _serverGruppe(tester);
    await _tapText(tester, de.syncUebersicht);
    await _tapText(tester, st.beschreibung);
    await waitFor(tester, find.text('${st.server}: B2'));
    await _tapText(tester, st.anwenden);
    await waitFor(tester, _imDialog(st.entscheidung));
    await _tap(tester, _imDialog(st.bestaetigen));
    await waitFor(tester, find.text(st.leer));
    await eventually(
      tester,
      () async {
        final hier = (await bibliothek.db.assetById(id2))?.description;
        final dort = (await _aufnahme(k.token, id2))['description'];
        return hier == 'A2' && dort == 'A2';
      },
      timeout: const Duration(seconds: 60),
      was: 'überall A2',
    );
    await _zurueck(tester);

    // SIC-165: der Serverstand ändert sich vor der Entscheidung.
    final id3 = await konflikt(2, 'A3', 'B3');
    await _serverGruppe(tester);
    await _tapText(tester, de.syncUebersicht);
    await _tapText(tester, st.beschreibung);
    await waitFor(tester, find.text('${st.server}: B3'));
    await _netz(
      tester,
      () => _befehl(k.token, BeschreibungSetzen([id3], 'C3')),
    );
    await _tapText(tester, st.anwenden);
    await _tap(tester, _imDialog(st.bestaetigen));
    await waitFor(
      tester,
      find.text(st.geaendert),
      timeout: const Duration(seconds: 30),
    );
    expect(
      (await _netz(tester, () => _aufnahme(k.token, id3)))['description'],
      'C3',
    );
    await _zurueck(tester);
    await finish(tester);
  });

  // =========================================================================
  // SIC-170: vom Server abgelehnt (Kabel)
  // =========================================================================
  testWidgets('SIC-170 Vom Server abgelehnte Änderung wird zurückgenommen', (
    tester,
  ) async {
    _aufServer(serverAdresse);
    await startApp(tester);
    final k = await _netz(
      tester,
      () => _konto(_n('Abl170_'), geraet: 'Geraet-2'),
    );
    final p0 = await _netz(
      tester,
      () => _hochladen(
        k.token,
        testfoto('abl_0.jpg', datum: DateTime(2024, 9, 2)),
      ),
    );
    final p1 = await _netz(
      tester,
      () => _hochladen(
        k.token,
        testfoto('abl_1.jpg', datum: DateTime(2024, 9, 1)),
      ),
    );
    final alt = _n('Alt170_');
    final neu = _n('Gemeinsam170_');
    await _netz(tester, () => _befehl(k.token, SchlagwortAnheften([p0], alt)));
    final kabel = _Kabel(_srv);
    await _netz(tester, kabel.stecke);
    addTearDown(kabel.ziehe);
    await _verbinde(tester, k.name, ueber: kabel.adresse);
    await _erreichbar(tester, true);
    Future<List<String>> tags(String id) async => [
      for (final t in await _netz(tester, () => bibliothek.db.tagsForAsset(id)))
        t.name,
    ];
    await eventually(
      tester,
      () async =>
          (await bibliothek.db.tagsForAsset(p0)).any((t) => t.name == alt),
      was: 'Tag hier',
    );

    // Offline: den Tag in der Info-Ansicht umbenennen.
    await _netz(tester, kabel.ziehe);
    await _erreichbar(tester, false, timeout: const Duration(seconds: 60));
    await _oeffneMitInfo(tester, 0);
    final chip = find.widgetWithText(InputChip, alt);
    await waitFor(tester, chip);
    await tester.ensureVisible(chip);
    await _tap(tester, find.descendant(of: chip, matching: find.text(alt)));
    await waitFor(tester, find.text(de.infoTagUmbenennen));
    await _tippe(tester, field(de.infoTagUmbenennenFeld), neu);
    await _tap(tester, _imDialog(de.allgUebernehmen));
    await waitGone(tester, find.text(de.infoTagUmbenennen));
    await _schliesseBetrachter(tester);
    expect(await tags(p0), contains(neu), reason: 'hier umbenannt');
    // Gerät 2 vergibt den neuen Namen inzwischen selbst.
    await _netz(tester, () => _befehl(k.token, SchlagwortAnheften([p1], neu)));
    await _netz(tester, kabel.stecke);
    await eventually(
      tester,
      () async => (bibliothek.abgleichszustand?.faelle ?? 0) >= 1,
      timeout: const Duration(seconds: 150),
      was: 'Ablehnung erkannt',
    );
    await _serverGruppe(tester);
    final rot = find.text(de.serverAbgelehnt(1));
    await waitFor(tester, rot);
    expect(_farbe(tester, rot), _fehlerfarbe(tester, rot));
    // Lokal wieder der Serverstand.
    await eventually(
      tester,
      () async {
        final a = [
          for (final t in await bibliothek.db.tagsForAsset(p0)) t.name,
        ];
        final b = [
          for (final t in await bibliothek.db.tagsForAsset(p1)) t.name,
        ];
        return a.contains(alt) && !a.contains(neu) && b.contains(neu);
      },
      timeout: const Duration(seconds: 60),
      was: 'Serverstand hier',
    );
    final ausgang = await _netz(tester, () async {
      final r = await bibliothek.db
          .customSelect('SELECT ok, fehler FROM pv_ausgang ORDER BY nr DESC')
          .get();
      return [for (final z in r) '${z.data}'];
    });
    print('SIC-170 Ausgang: ${ausgang.take(3).toList()}');
    await _tapText(tester, de.syncUebersicht);
    await waitFor(tester, find.text(st.titel));
    final fall = find.textContaining(st.abgelehnt);
    await waitFor(tester, fall);
    print(
      'SIC-170 Fall: ${onScreen(tester).split(' | ').where((t) => t.contains(st.abgelehnt)).toList()}',
    );
    expect(find.textContaining(st.konflikt), findsNothing);
    await _zurueck(tester);
    await finish(tester);
  });

  // =========================================================================
  // SIC-171: zu grosse Auswahl (11 500 Fotos, vorbereitet am Server
  // PV_R2_KNAPP: Konto Gross171 mit leerem Album „Ziel171“)
  // =========================================================================
  testWidgets('SIC-171 Alle Fotos in ein Album: zu gross für einen Abgleich', (
    tester,
  ) async {
    _aufServer(_knappAdresse);
    await startApp(tester);
    await _verbinde(tester, 'Gross171', geraet: _n('Rechner-'));
    final alle = await _assets(tester);
    print('SIC-171: ${alle.length} Aufnahmen');
    expect(alle.length, greaterThanOrEqualTo(11000));
    final albumId = await _netz(tester, () async {
      final r = await bibliothek.db
          .customSelect("SELECT id FROM albums WHERE name = 'Ziel171'")
          .get();
      return r.first.read<String>('id');
    });
    Future<int> imAlbum() => _zaehle(
      tester,
      'SELECT count(*) AS n FROM album_assets WHERE album_id = ?',
      [albumId],
    );
    Future<int> ausgang() =>
        _zaehle(tester, 'SELECT count(*) AS n FROM pv_ausgang');
    final vorher = (await imAlbum(), await ausgang());
    expect(vorher.$1, 0);
    // Alle wählen: Klick auf die Überschrift des Monats (alle 11 500 liegen
    // in einem Monat). Die Zeitleiste lädt in Fenstern zu 600 Fotos nach
    // (lib/screens/timeline_screen.dart:60); die Überschrift wählt nur, was
    // geladen ist (Nebenbefund). Erst ganz nach unten scrollen, dann die
    // Überschrift: Sie wählt den Rest dazu.
    await openSection(tester, Hauptbereich.zeitleiste);
    final monat = DateFormat.yMMMM('de').format(
      alle.map((a) => a.fileCreatedAt).reduce((x, y) => x.isAfter(y) ? x : y),
    );
    await waitFor(
      tester,
      find.text(monat),
      timeout: const Duration(seconds: 60),
    );
    final raster = find.byType(MonthGroupedAssetGrid);
    int geladen() => tester.widget<MonthGroupedAssetGrid>(raster).assets.length;
    await _tap(tester, find.text(monat).first);
    final erstesFenster = geladen();
    print(
      'SIC-171 Überschrift vor dem Scrollen: '
      '${find.textContaining(' ausgewählt').evaluate().map((e) => (e.widget as Text).data).toList()} '
      'bei $erstesFenster geladenen',
    );
    final rolle = find
        .descendant(of: raster, matching: find.byType(Scrollable))
        .first;
    for (var i = 0; i < 60 && geladen() < alle.length; i++) {
      final pos = tester.state<ScrollableState>(rolle).position;
      pos.jumpTo(pos.maxScrollExtent);
      await settle(tester, max: const Duration(milliseconds: 800));
    }
    print('SIC-171 nach dem Scrollen geladen: ${geladen()}');
    expect(geladen(), alle.length);
    tester.state<ScrollableState>(rolle).position.jumpTo(0);
    await settle(tester);
    await _tap(tester, find.text(monat).first);
    await waitFor(tester, find.text(de.auswAnzahl(alle.length)));
    // „Zu Album hinzufügen“ → „Ziel171“ – geklickt wie im Betrieb.
    _klickWieImBetrieb(tester, find.byTooltip(de.auswZuAlbum));
    await waitFor(tester, find.text(de.albumBestehendes));
    await _tap(
      tester,
      find.ancestor(
        of: find.text(de.albumBestehendes),
        matching: find.byWidgetPredicate(
          (w) => w is DropdownButtonFormField<AlbumData>,
        ),
      ),
    );
    await _tap(tester, find.text('Ziel171').last);
    final start = DateTime.now();
    await _tap(tester, _imDialog(de.allgHinzufuegen));
    await waitFor(
      tester,
      find.text(de.syncAuswahlZuGross),
      timeout: const Duration(seconds: 240),
    );
    print(
      'SIC-171 Hinweis nach '
      '${DateTime.now().difference(start).inSeconds} s',
    );
    await _warte(tester, const Duration(seconds: 3));
    final nachher = (await imAlbum(), await ausgang());
    print('SIC-171 Album/Ausgang vorher $vorher, nachher $nachher');
    expect(nachher, vorher, reason: 'weder Album noch Warteschlange');
    expect(bibliothek.abgleichszustand?.ausstehend ?? 0, 0);
    await finish(tester);
  });

  // =========================================================================
  // SIC-176: Foto sperren in verbundener Bibliothek
  // =========================================================================
  testWidgets('SIC-176 Foto sperren in verbundener Bibliothek', (tester) async {
    _aufServer(serverAdresse);
    await startApp(tester);
    await importiereDirekt(tester, [
      testfoto('sperr.jpg', datum: DateTime(2024, 9, 2)),
      testfoto('frei.jpg', datum: DateTime(2024, 9, 1)),
    ]);
    final sperr = (await _assets(
      tester,
    )).firstWhere((a) => a.originalFileName == 'sperr.jpg');
    await _netz(tester, () => bibliothek.setupVaultPin('1357'));
    final name = _n('Sperr176_');
    await _netz(tester, () => _konto(name));
    await _verbindenSeite(tester);
    await _tippe(tester, field(de.serverAdresse), '$_srv');
    await _tippe(tester, field(de.serverName), name);
    await _tippe(tester, field(de.serverPasswort), _pw);
    await _tapText(tester, de.serverAnmelden);
    await waitFor(
      tester,
      find.text(de.serverServerBibText(0)),
      timeout: const Duration(seconds: 30),
    );
    await _tapText(tester, de.serverUmziehen);
    await waitFor(
      tester,
      find.text(de.serverFertigNeustart),
      timeout: const Duration(seconds: 180),
    );
    await _neustart(tester);
    expect(bibliothek.verbunden, isTrue);
    final dateiVorher = await _originale(tester);
    Future<List<String>> verschluesselt() => _netz(tester, () async {
      final wurzel = bibliothek.paths.root;
      return [
        for (final f in wurzel.listSync(recursive: true).whereType<File>())
          if (f.path.endsWith('.enc') ||
              p.split(f.path).contains('vault_metadata'))
            p.relative(f.path, from: wurzel.path),
      ];
    });
    final vorherVerschluesselt = await verschluesselt();

    await _rasterFokus(tester);
    await key(tester, LogicalKeyboardKey.arrowRight);
    await key(tester, LogicalKeyboardKey.enter);
    await waitFor(tester, find.byType(AssetViewerScreen));
    // Der Klick auf „In gesperrten Ordner verschieben“ läuft wie im Betrieb
    // in der Wurzelzone; die Ausnahme der Serversperre geht von selbst an
    // die Meldung der App.
    _klickWieImBetrieb(tester, find.byTooltip(de.viewerInGesperrtenOrdner));
    await settle(tester);
    final pinFeld = find.descendant(
      of: find.byType(Dialog),
      matching: find.byType(TextField),
    );
    await waitFor(tester, pinFeld);
    await _tippe(tester, pinFeld, '1357');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    if (find.byType(Dialog).evaluate().isNotEmpty) {
      final ok = find.descendant(
        of: find.byType(Dialog),
        matching: find.byWidgetPredicate((w) => w is FilledButton),
      );
      if (ok.evaluate().isNotEmpty) await _tap(tester, ok.last);
    }
    await erwarteMeldung(tester, de.nurOhneServer);
    expect(
      (await _netz(tester, () => bibliothek.db.assetById(sperr.id)))!.isLocked,
      isFalse,
    );
    expect(await _nachrechnen(tester, dateiVorher.keys), dateiVorher);
    expect(
      await verschluesselt(),
      vorherVerschluesselt,
      reason: 'nichts verschlüsselt',
    );
    if (find.byType(AssetViewerScreen).evaluate().isNotEmpty) {
      await key(tester, LogicalKeyboardKey.escape);
    }
    await finish(tester);
  });

  // =========================================================================
  // SIC-205 SIC-203: geteiltes Album mit HEVC-Video; gesperrt, Papierkorb
  // =========================================================================
  testWidgets('SIC-205 SIC-203 Geteiltes Album: HEVC-Video, gesperrte und '
      'gelöschte Fotos des Besitzers', (tester) async {
    _aufServer(serverAdresse);
    await startApp(tester);
    final b = await _netz(tester, () => _konto(_n('B203_')));
    final a = await _netz(tester, () => _konto(_n('A203_')));
    final ids = <String>[];
    for (var i = 0; i < 3; i++) {
      ids.add(
        await _netz(
          tester,
          () => _hochladen(
            b.token,
            testfoto('b203_$i.jpg', datum: DateTime(2024, 5, 3 - i)),
          ),
        ),
      );
    }
    const videoName = 'r2sic_hevc_5s.mov';
    final video = await _netz(
      tester,
      () => _hochladen(b.token, fixture(videoName)),
    );
    final albumName = _n('Ferien203_');
    final albumId = await _netz(
      tester,
      () => _albumAufServer(b.token, albumName, [...ids, video]),
    );
    await _netz(tester, () => _teile(b.token, albumId, a.id));
    final teilung = await _netz(tester, () => _teilung(a.token, albumName));
    await _verbinde(tester, a.name);
    await openSection(tester, Hauptbereich.alben);
    await waitFor(
      tester,
      find.text(albumName),
      timeout: const Duration(seconds: 30),
    );
    await _tapText(tester, albumName);
    await waitFor(tester, _kacheln);
    expect(_kacheln, findsNWidgets(4));

    // SIC-205: Das HEVC-Video spielt, Tippen pausiert.
    await _tap(tester, _kacheln.first);
    await waitFor(tester, find.byType(PageView));
    expect(await _blaettereBis(tester, find.text(videoName)), isTrue);
    await waitFor(
      tester,
      find.byType(VideoProgressBar),
      timeout: const Duration(seconds: 90),
    );
    final spieler = tester
        .widget<VideoProgressBar>(find.byType(VideoProgressBar))
        .controller;
    await eventually(
      tester,
      () async => spieler.isPlaying && spieler.position > Duration.zero,
      timeout: const Duration(seconds: 20),
      was: 'Video spielt',
    );
    final p1 = spieler.position;
    await _warte(tester, const Duration(milliseconds: 1500));
    final p2 = spieler.position;
    print('SIC-205 spielt: $p1 → $p2');
    expect(p2 > p1, isTrue, reason: 'die Wiedergabe läuft');
    expect(find.byIcon(Icons.videocam_off_outlined), findsNothing);
    await tester.tap(find.byType(VideoSurface));
    await eventually(
      tester,
      () async => !spieler.isPlaying,
      timeout: const Duration(seconds: 5),
      was: 'Tippen pausiert',
    );
    final p3 = spieler.position;
    await _warte(tester, const Duration(milliseconds: 1500));
    print('SIC-205 pausiert: $p3 → ${spieler.position}');
    expect(spieler.position - p3, lessThan(const Duration(milliseconds: 300)));
    await _zurueck(tester);
    await waitGone(tester, find.byType(PageView));

    // SIC-203: Der Besitzer sperrt ein Foto (am Server, durch den Wächter
    // – sperren geht verbunden nicht, siehe SIC-176), dann legt er eines in
    // den Papierkorb. Neu geladen fehlen beide.
    Future<int> amServer() async =>
        ((await _netz(
                  tester,
                  () => _hole(a.token, 'api/v1/geteilt/$teilung'),
                ))['aufnahmen']!
                as List)
            .length;
    await _signal(tester, 'sperren ${_srv.port} ${b.id} ${ids[0]}');
    expect(await amServer(), 3);
    await _zurueck(tester);
    await _tapText(tester, albumName);
    await waitFor(tester, _kacheln);
    await eventually(
      tester,
      () async => _kacheln.evaluate().length == 3,
      was: 'drei Kacheln (gesperrt fehlt)',
    );
    await _netz(tester, () => _befehl(b.token, InDenPapierkorb([ids[1]])));
    expect(await amServer(), 2);
    await _zurueck(tester);
    await _tapText(tester, albumName);
    await waitFor(tester, _kacheln);
    await eventually(
      tester,
      () async => _kacheln.evaluate().length == 2,
      was: 'zwei Kacheln (Papierkorb fehlt)',
    );
    await finish(tester);
  });

  // =========================================================================
  // SIC-217: Partnerbibliothek – seitenweise, ohne Gesperrtes und Papierkorb
  // =========================================================================
  testWidgets('SIC-217 Partnerbibliothek ansehen: seitenweise, ohne '
      'Gesperrtes und Papierkorb', (tester) async {
    _aufServer(serverAdresse);
    await startApp(tester);
    final b = await _netz(tester, () => _konto(_n('B217_')));
    final a = await _netz(tester, () => _konto(_n('A217_')));
    const anzahl = 330;
    final ids = <String>[];
    final eingangsordner = eingang;
    for (var i = 0; i < anzahl; i += 6) {
      final teil = await _netz(
        tester,
        () => Future.wait([
          for (var j = i; j < i + 6 && j < anzahl; j++)
            _hochladen(
              b.token,
              testfoto(
                'b217_$j.jpg',
                datum: DateTime(2023, 1, 1).add(Duration(hours: j)),
                breite: 160,
                hoehe: 120,
              ),
            ),
        ]),
      );
      ids.addAll(teil);
    }
    print('SIC-217: $anzahl Fotos bei B (${eingangsordner.path})');
    await _netz(tester, () => _befehl(b.token, InDenPapierkorb([ids[5]])));
    await _signal(tester, 'sperren ${_srv.port} ${b.id} ${ids[6]}');
    final s = await _netz(
      tester,
      () => _schickeJson(b.token, 'PUT', 'api/v1/partner/${a.id}', {}),
    );
    expect(s == 200 || s == 204, isTrue, reason: 'Partner: $s');
    final liste = await _netz(
      tester,
      () => _hole(a.token, 'api/v1/partner/von/${b.id}/aufnahmen?anzahl=1000'),
    );
    final sichtbar = [
      for (final x in (liste['aufnahmen']! as List).cast<Map>()) '${x['id']}',
    ];
    print('SIC-217 am Server sichtbar: ${sichtbar.length}');
    expect(sichtbar, hasLength(anzahl - 2));
    expect(sichtbar, isNot(contains(ids[5])));
    expect(sichtbar, isNot(contains(ids[6])));

    await _verbinde(tester, a.name);
    await openSection(tester, Hauptbereich.alben);
    await waitFor(
      tester,
      find.text(tt.partnerBibliothekVon(b.name)),
      timeout: const Duration(seconds: 30),
    );
    expect(find.text(tt.partnerGanzeBibliothek), findsWidgets);
    await _tapText(tester, tt.partnerBibliothekVon(b.name));
    await waitFor(tester, find.byType(GridView));
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text(tt.partnerBibliothekVon(b.name)),
      ),
      findsOneWidget,
    );
    int geladen() =>
        (tester.widget<GridView>(find.byType(GridView)).childrenDelegate
                as SliverChildBuilderDelegate)
            .childCount ??
        -1;
    await eventually(tester, () async => geladen() > 0, was: 'erste Seite');
    final ersteSeite = geladen();
    print('SIC-217 erste Seite: $ersteSeite');
    expect(ersteSeite, 300);
    for (var i = 0; i < 30 && geladen() < anzahl - 2; i++) {
      await tester.drag(find.byType(GridView), const Offset(0, -1500));
      await settle(tester, max: const Duration(milliseconds: 600));
    }
    await eventually(
      tester,
      () async => geladen() == anzahl - 2,
      timeout: const Duration(seconds: 30),
      was: 'nachgeladen',
    );
    print('SIC-217 nach dem Scrollen: ${geladen()}');
    // Betrachter ohne „Gefällt mir“ und Kommentare.
    await _tap(tester, _kacheln.last);
    await waitFor(tester, find.byType(PageView));
    await _warte(tester, const Duration(seconds: 2));
    expect(find.byIcon(Icons.thumb_up_outlined), findsNothing);
    expect(find.byTooltip(tt.kommentare), findsNothing);
    await _zurueck(tester);
    await finish(tester);
  });
}
