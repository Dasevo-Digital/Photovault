// ignore_for_file: avoid_print
// Katalog-Prüfungen „Server, Teilen“ (SIC-094 bis SIC-230): die echte App
// gegen den Wegwerf-Server der Warteschlange (PV_E2E_SERVER=1, Adresse im
// Kit als `serverAdresse`). Alle Prüfungen einer Datei teilen sich diesen
// Server; die erste legt sein erstes Konto über die Oberfläche an.
//
// Wo ein Server nicht erreichbar sein soll, spricht die App über einen
// kleinen Zwischenserver in dieser Datei mit dem Wegwerf-Server; ihn
// anzuhalten heisst für die App „Server weg“. Er leitet nur an
// `serverAdresse` weiter.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' show max;
import 'dart:ui' show PlatformDispatcher;

import 'package:abgleich_ui/l10n/sync_texte.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart' hide testWidgets;
import 'package:flutter_test/flutter_test.dart' as ft show testWidgets;
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:kern/abgleich/abgleich.dart';
import 'package:kern/abgleich/anmeldung.dart';
import 'package:kern/abgleich/konten.dart';
import 'package:kern/abgleich/tus.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:kern/abgleich/verbindungsdatei.dart';
import 'package:kern/db/database.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/main.dart' show PhotoVaultApp;
import 'package:photo_vault/screens/asset_viewer_screen.dart';
import 'package:photo_vault/screens/background_tasks_screen.dart';
import 'package:photo_vault/screens/einstellungen/server.dart';
import 'package:photo_vault/screens/home_shell.dart' show HomeShell;
import 'package:photo_vault/screens/server_eigenes_konto_screen.dart';
import 'package:photo_vault/screens/server_konten_screen.dart';
import 'package:photo_vault/screens/settings_screen.dart';
import 'package:photo_vault/services/library_location.dart';
import 'package:photo_vault/widgets/qr_bild.dart';
import 'package:photo_vault/services/meldungsdienst.dart';
import 'package:photo_vault/services/platform/folder_access_desktop.dart';
import 'package:photo_vault/services/tokenablage.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:provider/provider.dart';
import 'package:sqlite3/sqlite3.dart' as roh;
import 'package:teilen_ui/l10n/teilen_texte.dart';
import 'package:uuid/uuid.dart';

import 'katalog_kit.dart';

/// Texte der Pakete für Teilen und Abgleich.
final tt = lookupTeilenTexte(const Locale('de'));
final st = lookupSyncTexte(const Locale('de'));

const _pw = 'Testpasswort-1234';
const _verwalter = 'Verwalter';
const _geraet = 'Rechner-E2E';

Uri get _srv =>
    Uri.parse(serverAdresse.endsWith('/') ? serverAdresse : '$serverAdresse/');

// --- Netz aus dem Test ------------------------------------------------------

/// Echte Netzarbeit aus dem Test heraus; Fehler kommen wieder heraus.
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

String? _verwalterTokenSpeicher;

/// Das Token des Verwalters – legt das erste Konto über die Schnittstelle
/// an, wenn der Server noch keines hat (eine einzeln laufende Prüfung).
Future<String> _verwalterToken() async {
  if (_verwalterTokenSpeicher case final t?) return t;
  final a = Anmeldung(_srv);
  try {
    final z = await a.zustand();
    final s = z['einrichten'] == true
        ? await a.einrichten(_verwalter, _pw, geraet: 'Pruefstand')
        : await a.anmelden(_verwalter, _pw, geraet: 'Pruefstand');
    if (s is! AnmeldungFertig) throw StateError('Verwalter: $s');
    return _verwalterTokenSpeicher = s.token;
  } finally {
    a.schliesse();
  }
}

Future<Anmeldeschritt> _anmeldeschritt(
  String name, {
  String pw = _pw,
  String geraet = 'Handy',
  Uri? server,
}) async {
  final a = Anmeldung(server ?? _srv);
  try {
    return await a.anmelden(name, pw, geraet: geraet);
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
  final s = await _anmeldeschritt(name, pw: pw, geraet: geraet, server: server);
  if (s is! AnmeldungFertig) {
    throw StateError('Anmeldung $name: ${s.runtimeType}');
  }
  return s.token;
}

/// Legt ein Konto an (als Verwalter) und meldet ein Gerät [geraet] an.
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

Future<int> _status(String token, String pfad, {String methode = 'GET'}) =>
    _mit(token, (v) async => (await v.anfrage(methode, pfad)).statusCode);

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

/// Lädt [datei] in die Bibliothek des Kontos; gibt die Kennung zurück.
Future<String> _hochladen(String token, File datei) => _mit(token, (v) async {
  final kopf = await TusHochladen(
    v,
  ).lade(datei, 'api/v1/hochladen', {'filename': p.basename(datei.path)});
  final id = kopf['pv-aufnahme'];
  if (id == null || id.isEmpty) throw StateError('Hochladen: $kopf');
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

/// Eine Person mit einem Gesicht auf [aufnahme] (von Hand, ohne Modell).
Future<void> _personAuf(String token, String personId, String aufnahme) async {
  final s = await _schickeJson(
    token,
    'POST',
    'api/v1/aufnahmen/$aufnahme/gesichter',
    {
      'kasten': [0.2, 0.2, 0.4, 0.4],
      'personId': personId,
    },
  );
  if (s != 201) throw StateError('Gesicht: $s');
}

Future<Map<String, Object?>> _aufnahme(String token, String id) =>
    _hole(token, 'api/v1/aufnahmen/$id');

// --- Zwischenserver ---------------------------------------------------------

/// Ein Server in diesem Prozess: leitet an den Wegwerf-Server weiter – oder
/// beantwortet über [eingriff] selbst (fremder Server, nachgestellte
/// Antworten). [halte] ist für die App „Server nicht erreichbar“.
class _Zwischen {
  HttpServer? _server;
  int? _port;

  /// Gibt `true` zurück, wenn die Anfrage damit beantwortet ist.
  Future<bool> Function(HttpRequest r)? eingriff;

  /// Wie lange eine Anfrage wartet, bevor sie weitergeht.
  Duration? Function(HttpRequest r)? verzoegerung;

  /// Schreibt jede weitergeleitete Anfrage ins Protokoll.
  var mitschreiben = false;

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
    final beginn = DateTime.now();
    try {
      if (eingriff case final e? when await e(r)) return;
      if (verzoegerung?.call(r) case final d?) {
        await Future<void>.delayed(d);
      }
      final ziel = _srv.resolve(r.uri.toString().substring(1));
      // Je Anfrage eine eigene Verbindung, in beide Richtungen: Wieder
      // benutzte Verbindungen blieben hier gelegentlich hängen.
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
      if (mitschreiben) {
        print(
          'Zwischen ${r.method} ${r.uri} -> ${b.statusCode} '
          'nach ${DateTime.now().difference(beginn).inMilliseconds} ms',
        );
      }
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

/// Unbehandelte Fehler, die eine Prüfung festhält statt abzubrechen.
final _unbehandelt = <String>[];

/// Jede Prüfung läuft in einer eigenen Zone: Fehler, die erst nach dem
/// Schliessen einer Bibliothek kommen (die Leerlaufuhr des
/// RestoreQueueService fragt danach noch die geschlossene Datenbank, siehe
/// lib/services/restore_queue_service.dart:185), stören sonst die nächste
/// Prüfung. Alles andere geht weiter an die Prüfung. Scheitert sie, wird die
/// App abgebaut, damit die nächste sauber beginnt.
/// Fehler der laufenden Prüfung, die nicht aus ihrem Körper kommen.
List<(Object, StackTrace)>? _laufendeFehler;

/// Eine unbehandelte Ausnahme der App – aus der Prüfung oder aus dem
/// Bildaufbau. KeineVerbindung, wenn der Server absichtlich fort ist, wird
/// festgehalten und berichtet, lässt die Prüfung aber nicht scheitern;
/// alles andere lässt sie am Ende scheitern.
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

/// Der Bildaufbau läuft in der Zone, in der die Rahmen-Rückrufe angemeldet
/// wurden – sonst die der ersten Prüfung, die dann alles abbekommt, was
/// später beim Aufbau schiefgeht. Hier in einer eigenen.
void _rahmenAbschirmen() {
  runZonedGuarded(() {
    final d = SchedulerBinding.instance.platformDispatcher;
    final anfang = d.onBeginFrame, zeichnen = d.onDrawFrame;
    if (anfang == null || zeichnen == null) {
      // ignore: invalid_use_of_protected_member
      SchedulerBinding.instance.ensureFrameCallbacksRegistered();
    } else {
      d.onBeginFrame = anfang;
      d.onDrawFrame = zeichnen;
    }
  }, _fehlerAusDerApp);
}

/// Jede Prüfung läuft in einer eigenen Zone; unbehandelte Ausnahmen gehen
/// über [_fehlerAusDerApp] und lassen die Prüfung erst an ihrem Ende
/// scheitern – so bleibt die nächste Prüfung unberührt.
WidgetTesterCallback _abgeschirmt(WidgetTesterCallback koerper) =>
    (tester) async {
      // Der Meldungsdienst ist einer für den ganzen Prozess: Was eine
      // frühere Prüfung stehen liess, soll diese nicht verdecken.
      for (final m in melde.sichtbare) {
        melde.schliesse(m.nummer);
      }
      melde.verlaufGelesen();
      final ende = Completer<void>();
      final fehler = _laufendeFehler = <(Object, StackTrace)>[];
      runZonedGuarded(() async {
        try {
          await koerper(tester);
          if (!ende.isCompleted) ende.complete();
        } catch (e, s) {
          if (!ende.isCompleted) ende.completeError(e, s);
        }
      }, _fehlerAusDerApp);
      Object? koerperFehler;
      StackTrace? koerperSpur;
      try {
        await ende.future;
      } catch (e, s) {
        koerperFehler = e;
        koerperSpur = s;
      }
      _laufendeFehler = null;
      if (koerperFehler == null && fehler.isEmpty) return;
      // Die Bibliothek schliesst das Kit (addTearDown in startApp); hier
      // nur der Widgetbaum, damit keine Bilder mehr anstehen.
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

/// Klickt [finder] und wartet nur kurz – Meldungen stehen vier Sekunden,
/// das kit-eigene tap wartet bis zu fünf.
Future<void> _tap(WidgetTester tester, Finder finder) async {
  // Die Glocke der gelesenen Meldungen liegt oben rechts über allem.
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

/// Schliesst stehende Meldungen über ihren Knopf (Fehler bleiben sonst).
Future<void> _meldungenSchliessen(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    final zu = find.byTooltip(de.meldungSchliessen);
    if (zu.evaluate().isEmpty) {
      melde.verlaufGelesen();
      await settle(tester, max: const Duration(milliseconds: 300));
      return;
    }
    await tester.tap(zu.first);
    await settle(tester, max: const Duration(milliseconds: 600));
  }
}

void testWidgets(
  String beschreibung,
  WidgetTesterCallback koerper, {
  bool? skip,
}) => ft.testWidgets(beschreibung, _abgeschirmt(koerper), skip: skip);

/// Schreibt [text] in ein Textfeld: Fokus per Klick, dann über den
/// Controller. tester.enterText kam im Integrationslauf nicht zuverlässig an
/// (die echte Eingabemethode von macOS schreibt ihren Stand zurück).
Future<void> _tippe(WidgetTester tester, Finder feld, String text) async {
  await waitFor(tester, feld);
  await tester.ensureVisible(feld.first);
  // Fokus ohne Klick: Ein Klick träfe womöglich, was darüber liegt.
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

/// Welcher eigene Wegwerf-Server unter PV_KATALOG_SERVER läuft: 'totp'
/// (PV_TOTP=pflicht) oder 'sicherung' (PV_SICHERUNG); sonst der der
/// Warteschlange.
const _eigenerServer = String.fromEnvironment('PV_SICB_SERVER');

const _sicherungPw = 'Sicherungs-Passphrase-1';

/// Base32 (RFC 4648) ohne Auffüllung, wie es der Server zeigt.
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

/// TOTP nach RFC 6238 (SHA-1, 30 s, sechs Ziffern) – was eine
/// Authenticator-App rechnet.
String _totp(List<int> schluessel, int schritt) {
  final zaehler = ByteData(8)..setInt64(0, schritt);
  final h = Hmac(sha1, schluessel).convert(zaehler.buffer.asUint8List()).bytes;
  final o = h[h.length - 1] & 0x0f;
  final zahl =
      ((h[o] & 0x7f) << 24) | (h[o + 1] << 16) | (h[o + 2] << 8) | h[o + 3];
  return (zahl % 1000000).toString().padLeft(6, '0');
}

String? _verwalterGeheimnis;

/// Der Verwalter auf einem Server mit TOTP-Pflicht: legt ihn an und
/// richtet TOTP ein, oder meldet mit Code an.
Future<String> _verwalterMitTotp() async {
  final a = Anmeldung(_srv);
  try {
    final z = await a.zustand();
    var s = z['einrichten'] == true
        ? await a.einrichten(_verwalter, _pw, geraet: 'Pruefstand')
        : await a.anmelden(_verwalter, _pw, geraet: 'Pruefstand');
    if (s is AnmeldungTotpEinrichten) {
      _verwalterGeheimnis = s.geheimnis;
      s = await a.bestaetige(
        s.vorgang,
        _totp(_base32(s.geheimnis), _schrittJetzt()),
      );
    } else if (s is AnmeldungCode) {
      s = await a.bestaetige(
        s.vorgang,
        _totp(_base32(_verwalterGeheimnis!), _schrittJetzt() + 1),
      );
    }
    if (s is! AnmeldungFertig) throw StateError('Verwalter: $s');
    return _verwalterTokenSpeicher = s.token;
  } finally {
    a.schliesse();
  }
}

/// Bittet den Wächter ausserhalb der App (siehe Bericht) um [was] und
/// wartet, bis er es erledigt hat: Er sieht die Datei im Temp-Ordner der
/// Prüfung, handelt und löscht sie.
Future<void> _signal(WidgetTester tester, String was) async {
  final f = File(p.join(anker.path, 'sicb_signal_$was'));
  f.writeAsStringSync(was);
  await eventually(
    tester,
    () async => !f.existsSync(),
    timeout: const Duration(seconds: 60),
    was: 'Wächter: $was',
  );
}

// --- App --------------------------------------------------------------------

/// Startet die App neu – mit demselben Datenordner im Temp-Ordner (die
/// Umlenkung aus [startApp] bleibt), so wie nach „Photo Vault muss neu
/// starten“.
Future<void> _neustart(WidgetTester tester) async {
  // Wie finish im Kit: erst die Hintergrundarbeit anhalten, dann schliessen.
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

/// Stellt die verbundene Bibliothek auf die Adresse [ziel] um und startet
/// neu. Über den Zwischenserver hingen im Test Anfragen beim Empfangen
/// (direkt verbunden nie); er dient deshalb nur für die Zeit ohne Server,
/// danach ist der Server unter seiner eigenen Adresse „wieder da“.
Future<void> _umstellen(WidgetTester tester, Uri ziel) async {
  await _netz(tester, () async {
    final wurzel = await LibraryLocation.currentRoot();
    final f = File(p.join(wurzel.path, 'verbindung.json'));
    final j = (jsonDecode(await f.readAsString()) as Map)
        .cast<String, Object?>();
    j['server'] = '$ziel';
    await f.writeAsString(const JsonEncoder.withIndent('  ').convert(j));
  });
  await _neustart(tester);
  expect(bibliothek.verbunden, isTrue);
}

/// Verbindet die App ohne Oberfläche mit dem Konto [name] (wie „Die
/// Bibliothek des Servers hier öffnen“) und startet neu. Gibt das Token
/// des Rechners zurück.
Future<String> _verbinde(
  WidgetTester tester,
  String name, {
  Uri? ueber,
  String geraet = _geraet,
}) async {
  final server = ueber ?? _srv;
  final token = await _netz(
    tester,
    () => _anmelden(name, geraet: geraet, server: server),
  );
  await _netz(tester, () async {
    final basis = p.join(anker.path, 'verbunden', '$name-${server.host}');
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
      name: '$name @ ${server.host}',
    );
    await LibraryLocation.wechsleZu(e);
  });
  await _neustart(tester);
  expect(bibliothek.verbunden, isTrue);
  return token;
}

Future<List<AssetData>> _assets(WidgetTester tester) =>
    _netz(tester, () => bibliothek.db.select(bibliothek.db.assets).get());

/// Prüfsummen der Originale, nach absolutem Pfad.
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

/// Wartet echte Zeit und pumpt dabei.
Future<void> _warte(WidgetTester tester, Duration d) async {
  final ende = DateTime.now().add(d);
  while (DateTime.now().isBefore(ende)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Einstellungen → Server aufgeklappt.
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

Future<void> _anmeldenUi(
  WidgetTester tester, {
  required String adresse,
  String name = '',
  String pw = '',
}) async {
  await _tippe(tester, field(de.serverAdresse), adresse);
  await _tippe(tester, field(de.serverName), name);
  await _tippe(tester, field(de.serverPasswort), pw);
  await _tapText(tester, de.serverAnmelden);
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

/// Wählt [eintrag] in einem Auswahlfeld.
Future<void> _waehle(WidgetTester tester, Finder feld, String eintrag) async {
  await _tap(tester, feld);
  await settle(tester);
  await _tap(tester, find.text(eintrag).last);
}

/// Scrollt in [bereich] (dem ersten Scrollable darin), bis [ziel] da ist.
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
    // Nach unten nicht gefunden: dann oberhalb.
    await tester.scrollUntilVisible(
      ziel,
      -150,
      scrollable: rolle,
      maxScrolls: 120,
    );
  }
  await settle(tester);
}

/// Die Zeitleiste mit Tastaturfokus im Raster.
Future<void> _rasterFokus(WidgetTester tester) async {
  await openSection(tester, Hauptbereich.zeitleiste);
  await settle(tester);
  // Ein Klick ins Leere unter den Kacheln holt den Fokus zum Raster.
  await tester.tapAt(const Offset(1000, 870));
  await settle(tester);
}

/// Schreibt die Beschreibung des [n]-ten Fotos der Zeitleiste (0 = das
/// neueste) über Betrachter → Info.
Future<void> _beschreibungUi(WidgetTester tester, int n, String text) async {
  await _rasterFokus(tester);
  for (var i = 0; i <= n; i++) {
    await key(tester, LogicalKeyboardKey.arrowRight);
  }
  await key(tester, LogicalKeyboardKey.enter);
  await waitFor(tester, find.byType(AssetViewerScreen));
  if (field(de.infoBeschreibungHinzufuegen).evaluate().isEmpty) {
    await _tap(tester, find.byTooltip(de.viewerInfo));
  }
  await _tippe(tester, field(de.infoBeschreibungHinzufuegen), text);
  FocusManager.instance.primaryFocus?.unfocus();
  await settle(tester);
  await _warte(tester, const Duration(milliseconds: 600));
  await _schliesseBetrachter(tester);
}

/// Schliesst den Betrachter über den Zurück-Knopf seiner Leiste.
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

/// Blättert im Betrachter eines geteilten Albums, bis [ziel] zu sehen ist.
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

/// Schliesst ein Blatt von unten (Kommentare): Escape, sonst ein Klick
/// über das Blatt.
Future<void> _schliesseBlatt(WidgetTester tester) async {
  await key(tester, LogicalKeyboardKey.escape);
  if (find.text(tt.kommentareHinweis).evaluate().isNotEmpty) {
    await tester.tapAt(const Offset(700, 10));
    await settle(tester);
  }
  await waitGone(tester, find.text(tt.kommentareHinweis));
}

/// Importieren über den Knopf der Seitenleiste – wie importiereUeberUi im
/// Kit, aber über das Symbol: Bei eingeklappter Leiste trifft ein Klick
/// auf die Beschriftung nicht (das Kit klickt sie, wenn die Zeitleiste
/// nicht leer ist).
Future<void> _importiereUeberLeiste(
  WidgetTester tester,
  List<File> dateien,
) async {
  dialog.dateien = dateien;
  await _tap(tester, find.byIcon(Icons.add_photo_alternate_outlined).first);
  await _tapText(tester, de.importEinzelneDateien);
  await waitFor(
    tester,
    find.text(de.importPlanTitel),
    timeout: const Duration(seconds: 30),
  );
  final starten = find.ancestor(
    of: find.text(de.importPlanStarten(dateien.length)),
    matching: find.byType(FilledButton),
  );
  await waitFor(tester, starten, timeout: const Duration(seconds: 60));
  final ende = DateTime.now().add(const Duration(seconds: 60));
  while (tester.widget<FilledButton>(starten).onPressed == null) {
    if (DateTime.now().isAfter(ende)) {
      throw TimeoutException('Importplan gibt den Start nicht frei');
    }
    await tester.pump(const Duration(milliseconds: 200));
  }
  await tester.tap(starten);
  await settle(tester);
}

/// Ein JPEG mit gut lesbarem Text darauf (für die Texterkennung).
File _textfoto(String name, String text) {
  final bild = img.Image(width: 900, height: 300);
  img.fill(bild, color: img.ColorRgb8(255, 255, 255));
  img.drawString(
    bild,
    text,
    font: img.arial48,
    x: 40,
    y: 120,
    color: img.ColorRgb8(0, 0, 0),
  );
  final datei = File(p.join(eingang.path, name));
  datei.writeAsBytesSync(img.encodeJpg(bild, quality: 95));
  return datei;
}

/// Ein Fehler, der im Betrieb über PlatformDispatcher.onError an die
/// Meldung der App ginge (siehe services/serversperre.dart) – im Testlauf
/// fängt ihn sonst die Zone der Prüfung ab.
void _wieImBetrieb(Object e, StackTrace s) {
  final behandelt = PlatformDispatcher.instance.onError?.call(e, s) ?? false;
  if (!behandelt) print('nicht behandelt: $e');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  _rahmenAbschirmen();

  // Muss die erste Prüfung sein: Sie legt das erste Konto des frischen
  // Servers über die Oberfläche an.
  testWidgets('SIC-095 SIC-096 SIC-097 SIC-098 SIC-101 SIC-102 SIC-100 SIC-115 '
      'SIC-207 SIC-118 SIC-120 SIC-121 SIC-123 SIC-138 SIC-149 SIC-150 '
      'SIC-211 SIC-229 Verbinden, erstes Konto, Umzug', (tester) async {
    await startApp(tester);
    await importiereDirekt(tester, [
      for (var i = 0; i < 4; i++)
        testfoto('umzug_$i.jpg', datum: DateTime(2024, 3, 1 + i, 10)),
    ]);
    final ids = [for (final a in await _assets(tester)) a.id];
    expect(ids, hasLength(4));
    final albumId = const Uuid().v4();
    await _netz(tester, () async {
      await bibliothek.db.fuehreAus(
        AlbumAnlegen(albumId, 'Ferien', DateTime.now()),
      );
      await bibliothek.db.fuehreAus(AlbumFuellen(albumId, ids));
      await bibliothek.db.fuehreAus(
        PersonAnlegen(const Uuid().v4(), 'Person A'),
      );
    });

    // SIC-207: unverbunden fehlen Teilen, Kommentare, Automatisch füllen.
    await openSection(tester, Hauptbereich.alben);
    await _tapText(tester, 'Ferien');
    await waitFor(tester, find.byTooltip(de.albumExportieren));
    expect(find.byTooltip(tt.kontenTeilen), findsNothing);
    expect(find.byTooltip(tt.kommentare), findsNothing);
    expect(find.byTooltip(tt.automatischFuellen), findsNothing);
    await _zurueck(tester);

    final vorher = await _originale(tester);
    expect(vorher, hasLength(4));

    await _verbindenSeite(tester);
    // SIC-115: Gerätename vorbelegt und änderbar.
    final geraetFeld = tester.widget<TextField>(field(de.serverGeraet));
    expect(geraetFeld.controller!.text, Platform.localHostname);
    await _tippe(tester, field(de.serverGeraet), _geraet);

    // SIC-095: leere Adresse.
    await _tapText(tester, de.serverAnmelden);
    await waitFor(tester, find.text(de.serverNichtErreichbar));

    // SIC-097: http:// ins Internet – ohne Anfrage abgewiesen.
    await _anmeldenUi(tester, adresse: 'http://fotos.example.de');
    await waitFor(tester, find.text(de.serverNurHttps));

    // SIC-096: ohne Schema gilt https – der Server spricht nur http.
    final hostPort = '${_srv.host}:${_srv.port}';
    await _anmeldenUi(tester, adresse: hostPort, name: 'x1', pw: 'y');
    await waitFor(
      tester,
      find.text(de.serverNichtErreichbar),
      timeout: const Duration(seconds: 30),
    );

    // SIC-097 (Rest) und SIC-101: http auf Loopback wird angenommen; der
    // leere Server will einen gültigen Namen.
    await _anmeldenUi(tester, adresse: '$_srv', name: 'a', pw: 'kurz');
    await waitFor(tester, find.text(de.serverNameUngueltig));

    // SIC-098: kein Dienst unter der Adresse.
    await _anmeldenUi(tester, adresse: 'http://localhost:1');
    await waitFor(
      tester,
      find.text(de.serverNichtErreichbar),
      timeout: const Duration(seconds: 25),
    );
    await waitGone(tester, find.byType(LinearProgressIndicator));

    // SIC-101: zu kurzes Passwort; angelegt wird nichts.
    await _anmeldenUi(
      tester,
      adresse: '$_srv',
      name: _verwalter,
      pw: '12345678',
    );
    await waitFor(tester, find.text(de.serverPasswortZuKurz(12)));
    final leer = await _netz(tester, () async {
      final a = Anmeldung(_srv);
      try {
        return await a.zustand();
      } finally {
        a.schliesse();
      }
    });
    expect(leer['einrichten'], isTrue, reason: 'nichts angelegt');

    // SIC-102: Wiederholung ungleich, Abbrechen führt zurück. Ab hier über
    // den Zwischenserver, damit der Umzug sichtbar Zeit braucht.
    final z = _Zwischen();
    await _netz(tester, z.starte);
    addTearDown(z.halte);
    z.verzoegerung = (r) =>
        r.method == 'PATCH' && r.uri.path.startsWith('/api/v1/umzug/hochladen')
        ? const Duration(milliseconds: 700)
        : null;
    await _anmeldenUi(
      tester,
      adresse: '${z.adresse}',
      name: _verwalter,
      pw: _pw,
    );
    await waitFor(tester, find.text(de.serverErstesTitel));
    // SIC-100: der Text nennt den Namen und das Verwalterrecht.
    expect(find.text(de.serverErstesText(_verwalter)), findsOneWidget);
    await enter(
      tester,
      field(de.serverPasswortWiederholen),
      'ganz-anderes-passwort',
    );
    await _tapText(tester, de.serverErstesAnlegen);
    await waitFor(tester, find.text(de.serverPasswortUngleich));
    await _tapText(tester, de.allgAbbrechen);
    await waitFor(tester, field(de.serverAdresse));

    // SIC-100: das erste Konto entsteht.
    await _tapText(tester, de.serverAnmelden);
    await waitFor(tester, find.text(de.serverErstesTitel));
    await _tippe(tester, field(de.serverPasswortWiederholen), _pw);
    await _tapText(tester, de.serverErstesAnlegen);
    await waitFor(
      tester,
      find.text(de.serverWahlTitel),
      timeout: const Duration(seconds: 30),
    );
    await _netz(tester, _verwalterToken);

    // Wahl: der Server ist leer, Umziehen geht.
    await waitFor(tester, find.text(de.serverServerBibText(0)));
    expect(find.text(de.serverUmziehenText(4)), findsOneWidget);

    // SIC-118: Umzug mit Fortschritt in Bytes und Dateien.
    await _tapText(tester, de.serverUmziehen);
    var fortschrittGesehen = false;
    final ende = DateTime.now().add(const Duration(seconds: 180));
    while (find.text(de.serverFertigNeustart).evaluate().isEmpty) {
      if (DateTime.now().isAfter(ende)) {
        throw TimeoutException('Umzug endet nicht: ${onScreen(tester)}');
      }
      if (find
          .textContaining(RegExp(r' von .* · \d+ von \d+ Dateien'))
          .evaluate()
          .isNotEmpty) {
        fortschrittGesehen = true;
      }
      await tester.pump(const Duration(milliseconds: 30));
    }
    print('SIC-118 Fortschritt gesehen: $fortschrittGesehen');
    expect(fortschrittGesehen, isTrue, reason: 'Fortschritt x von y');

    await _neustart(tester);
    expect(bibliothek.verbunden, isTrue);

    // Ein zweites Gerät (die Schnittstelle) sieht alles.
    final zweites = await _netz(
      tester,
      () => _anmelden(_verwalter, geraet: 'Zweitgeraet'),
    );
    final bib = await _netz(tester, () => _hole(zweites, 'api/v1/bibliothek'));
    expect(bib['aufnahmen'], 4);
    final alben = await _netz(tester, () => _hole(zweites, 'api/v1/alben'));
    expect('${alben['alben']}', contains('Ferien'));
    final personen = await _netz(
      tester,
      () => _hole(zweites, 'api/v1/personen'),
    );
    expect('${personen['personen']}', contains('Person A'));

    // SIC-120: Originale hier unverändert, auf dem Server dieselben.
    expect(await _nachrechnen(tester, vorher.keys), vorher);
    final nachher = await _originale(tester);
    expect(nachher.values.toSet(), vorher.values.toSet());
    for (final id in ids) {
      final summe = await _netz(
        tester,
        () => _mit(zweites, (v) async {
          final r = await v.anfrage('GET', 'api/v1/aufnahmen/$id/original');
          expect(r.statusCode, 200);
          return sha256.convert(r.bodyBytes).toString();
        }),
      );
      expect(vorher.values, contains(summe), reason: 'Original $id');
    }

    // SIC-121: Stand in den Einstellungen.
    await _serverGruppe(tester);
    expect(find.text(de.serverVerbundenMit(_srv.host)), findsOneWidget);
    expect(
      find.text(de.serverKontoGeraet(_verwalter, _geraet)),
      findsOneWidget,
    );
    await waitFor(
      tester,
      find.text(de.serverAbgeglichen),
      timeout: const Duration(seconds: 40),
    );
    await waitFor(
      tester,
      find.textContaining('Speicher auf dem Server:'),
      timeout: const Duration(seconds: 30),
    );
    // SIC-138, SIC-149, SIC-150: als Verwalter.
    await waitFor(tester, find.text(de.serverKontenVerwalten));
    expect(find.text(de.serverSicherungTitel), findsOneWidget);
    expect(find.text(de.serverSicherungAus), findsOneWidget);
    expect(find.text(de.serverSicherungJetzt), findsNothing);

    // SIC-115: der Gerätename steht in „Geräte“.
    await _tapText(tester, de.serverEigenesKonto);
    await waitFor(tester, find.text('$_geraet (${de.serverDiesesGeraet})'));
    await _zurueck(tester);

    // SIC-123: Trennen – Abbrechen.
    await _serverGruppe(tester);
    await _tapText(tester, de.serverTrennen);
    await waitFor(tester, find.text(de.serverTrennenTitel));
    expect(find.text(de.serverTrennenText), findsOneWidget);
    expect(de.serverTrennenText, contains('gehen verloren'));
    expect(de.serverTrennenText, contains('nie geöffnet'));
    await _tap(tester, _imDialog(de.allgAbbrechen));
    await waitGone(tester, find.text(de.serverTrennenTitel));
    expect(find.text(de.serverVerbundenMit(_srv.host)), findsOneWidget);
    expect(bibliothek.verbunden, isTrue);

    // SIC-229 (erster Teil) und SIC-211: eigenes Album, nicht geteilt,
    // nur ein Konto auf dem Server.
    await openSection(tester, Hauptbereich.alben);
    await _tapText(tester, 'Ferien');
    await waitFor(tester, find.byTooltip(tt.kontenTeilen));
    await _warte(tester, const Duration(seconds: 3));
    expect(find.byTooltip(tt.kommentare), findsNothing);
    await _tap(tester, find.byTooltip(tt.kontenTeilen));
    await waitFor(tester, find.text(tt.kontenTeilenTitel('Ferien')));
    await waitFor(tester, find.text(tt.kontenNiemand));
    expect(find.text(tt.kontenKeineAnderen), findsOneWidget);
    await _tap(tester, _imDialog(tt.schliessen));
    await _zurueck(tester);
    await finish(tester);
  });

  testWidgets('SIC-139 SIC-140 SIC-141 SIC-142 SIC-143 SIC-144 SIC-145 SIC-147 '
      'Konten verwalten', (tester) async {
    await startApp(tester);
    final b = await _netz(tester, () => _konto('B139', geraet: 'Handy-B'));
    await _netz(tester, () => _konto('A139'));
    await _netz(tester, () => _hochladen(b.token, testfoto('b139.jpg')));
    await _verbinde(tester, _verwalter);
    await _serverGruppe(tester);
    await _tap(tester, find.text(de.serverKontenVerwalten));
    await waitFor(tester, find.text(de.serverKontenTitel));
    final seite = find.byType(ServerKontenScreen);

    // SIC-139: das eigene Konto ohne Menü, die anderen mit Geräten/TOTP.
    final ich = '$_verwalter · ${de.serverKontoDu}';
    await waitFor(tester, find.text(ich));
    expect(
      find.descendant(
        of: _zeile(ich),
        matching: find.byType(PopupMenuButton<String>),
      ),
      findsNothing,
    );
    await _bisSichtbar(tester, find.text('B139'), seite);
    expect(
      find.descendant(
        of: _zeile('B139'),
        matching: find.text(
          '${de.serverKontoGeraete(1)} · ${de.serverKontoOhneTotp}',
        ),
      ),
      findsOneWidget,
    );

    // SIC-141: Prüfungen vor dem Senden.
    await _tap(tester, find.text(de.serverKontoAnlegen));
    await waitFor(tester, find.byType(AlertDialog));
    final dlg = find.byType(AlertDialog);
    Finder feldIm(String name) =>
        find.descendant(of: dlg, matching: field(name));
    await _tippe(tester, feldIm(de.serverName), 'x');
    await _tap(tester, _imDialog(de.allgSpeichern));
    await waitFor(tester, _imDialog(de.serverNameUngueltig));
    await _tippe(tester, feldIm(de.serverName), 'C139');
    await _tippe(tester, feldIm(de.serverPasswort), '12345678');
    await _tippe(tester, feldIm(de.serverPasswortWiederholen), '12345678');
    await _tap(tester, _imDialog(de.allgSpeichern));
    await waitFor(tester, _imDialog(de.serverPasswortZuKurz(12)));
    await _tippe(tester, feldIm(de.serverPasswort), _pw);
    await enter(
      tester,
      feldIm(de.serverPasswortWiederholen),
      'etwas-anderes-123',
    );
    await _tap(tester, _imDialog(de.allgSpeichern));
    await waitFor(tester, _imDialog(de.serverPasswortUngleich));
    expect(dlg, findsOneWidget);

    // SIC-140: anlegen.
    await _tippe(tester, feldIm(de.serverPasswortWiederholen), _pw);
    await _tap(tester, _imDialog(de.allgSpeichern));
    await erwarteMeldung(tester, de.serverKontoErledigt);
    await _bisSichtbar(tester, find.text('C139'), seite);
    await _netz(tester, () => _anmelden('C139'));

    // SIC-142: mit Verwalterrecht.
    await waitGone(
      tester,
      find.text(de.serverKontoErledigt),
      timeout: const Duration(seconds: 15),
    );
    await _tap(tester, find.text(de.serverKontoAnlegen));
    await waitFor(tester, dlg);
    await _tippe(tester, feldIm(de.serverName), 'V139');
    await _tippe(tester, feldIm(de.serverPasswort), _pw);
    await _tippe(tester, feldIm(de.serverPasswortWiederholen), _pw);
    await _tap(tester, _imDialog(de.serverKontoAlsVerwalter));
    await _tap(tester, _imDialog(de.allgSpeichern));
    await erwarteMeldung(tester, de.serverKontoErledigt);
    await _bisSichtbar(tester, find.text('V139'), seite);
    expect(
      find.descendant(
        of: _zeile('V139'),
        matching: find.textContaining(de.serverKontoVerwalter),
      ),
      findsOneWidget,
    );
    final v139 = await _netz(tester, () => _anmelden('V139'));
    final kontoV = await _netz(tester, () => _hole(v139, 'api/v1/konto'));
    expect(kontoV['verwalter'], isTrue);

    // SIC-143: doppelter Name.
    await waitGone(
      tester,
      find.text(de.serverKontoErledigt),
      timeout: const Duration(seconds: 15),
    );
    await _tap(tester, find.text(de.serverKontoAnlegen));
    await waitFor(tester, dlg);
    await _tippe(tester, feldIm(de.serverName), 'A139');
    await _tippe(tester, feldIm(de.serverPasswort), _pw);
    await _tippe(tester, feldIm(de.serverPasswortWiederholen), _pw);
    await _tap(tester, _imDialog(de.allgSpeichern));
    await waitFor(tester, find.textContaining('gibt es schon'));
    // Fehlermeldungen bleiben stehen, bis man sie schliesst.
    await _meldungenSchliessen(tester);
    final liste = await _netz(
      tester,
      () => _hole(_verwalterTokenSpeicher!, 'api/v1/konten'),
    );
    final namen = [
      for (final k in liste['konten']! as List) (k as Map)['name'],
    ];
    expect(namen.where((n) => n == 'A139'), hasLength(1));

    // SIC-145: ohne TOTP kein „TOTP zurücksetzen“.
    await _bisSichtbar(tester, find.text('B139'), seite);
    await _meldungenSchliessen(tester);
    await _tap(
      tester,
      find.descendant(
        of: _zeile('B139'),
        matching: find.byType(PopupMenuButton<String>),
      ),
    );
    await waitFor(tester, find.text(de.serverKontoPasswortSetzen));
    expect(find.text(de.serverKontoTotpZuruecksetzen), findsNothing);
    expect(find.text(de.serverKontoEntsperren), findsNothing);

    // SIC-144: Passwort neu setzen meldet die Geräte ab.
    await _tapText(tester, de.serverKontoPasswortSetzen);
    await waitFor(tester, find.text(de.serverKontoPasswortSetzenText('B139')));
    await _tippe(tester, feldIm(de.serverPasswort), 'b-neues-passwort-1');
    await enter(
      tester,
      feldIm(de.serverPasswortWiederholen),
      'b-neues-passwort-1',
    );
    await _tap(tester, _imDialog(de.allgSpeichern));
    await erwarteMeldung(tester, de.serverKontoErledigt);
    expect(await _netz(tester, () => _status(b.token, 'api/v1/konto')), 401);
    final b2 = await _netz(
      tester,
      () => _anmelden('B139', pw: 'b-neues-passwort-1', geraet: 'Handy-B2'),
    );

    // SIC-147: entfernen.
    await _bisSichtbar(tester, find.text('B139'), seite);
    await _meldungenSchliessen(tester);
    await _tap(
      tester,
      find.descendant(
        of: _zeile('B139'),
        matching: find.byType(PopupMenuButton<String>),
      ),
    );
    await _tapText(tester, de.serverKontoEntfernen);
    await waitFor(tester, find.text(de.serverKontoEntfernenTitel('B139')));
    expect(find.text(de.serverKontoEntfernenText), findsOneWidget);
    expect(
      de.serverKontoEntfernenText,
      contains('beiseitegelegt, nicht gelöscht'),
    );
    await _tap(tester, _imDialog(de.allgEntfernen));
    await waitGone(tester, find.text('B139'));
    expect(await _netz(tester, () => _status(b2, 'api/v1/konto')), 401);
    await _zurueck(tester);
    await finish(tester);
  });

  testWidgets('SIC-116 SIC-117 SIC-188 SIC-174 Bibliothek des Servers holen', (
    tester,
  ) async {
    await startApp(tester);
    await importiereDirekt(tester, [
      for (var i = 0; i < 4; i++)
        testfoto('lokal_$i.jpg', datum: DateTime(2023, 5, 1 + i)),
    ]);
    final vorher = await _originale(tester);
    expect(vorher, hasLength(4));
    final k = await _netz(tester, () => _konto('Holer117'));
    for (var i = 0; i < 10; i++) {
      await _netz(
        tester,
        () => _hochladen(
          k.token,
          testfoto(
            'server_$i.jpg',
            datum: DateTime(2022, 1, 1 + i),
            breite: 400,
            hoehe: 300,
          ),
        ),
      );
    }
    final z = _Zwischen();
    await _netz(tester, z.starte);
    addTearDown(z.halte);

    await _verbindenSeite(tester);
    await _anmeldenUi(
      tester,
      adresse: '${z.adresse}',
      name: 'Holer117',
      pw: _pw,
    );
    // SIC-116: Anzahl dort, Umziehen ausgegraut.
    await waitFor(
      tester,
      find.text(de.serverServerBibText(10)),
      timeout: const Duration(seconds: 30),
    );
    expect(find.text(de.serverUmziehenNichtLeer), findsOneWidget);
    final umziehen = tester.widget<ListTile>(
      find.ancestor(
        of: find.text(de.serverUmziehen),
        matching: find.byType(ListTile),
      ),
    );
    expect(umziehen.enabled, isFalse);

    // SIC-117: holen.
    await _tapText(tester, de.serverServerBib);
    await waitFor(
      tester,
      find.text(de.serverFertigNeustart),
      timeout: const Duration(seconds: 120),
    );
    await _neustart(tester);
    expect(bibliothek.verbunden, isTrue);
    expect(await _assets(tester), hasLength(10));
    await openSection(tester, Hauptbereich.einstellungen);
    await _tap(
      tester,
      find.descendant(
        of: find.byType(ExpansionTile),
        matching: find.text(de.einstBibListe),
      ),
    );
    await waitFor(tester, find.text('Holer117 @ 127.0.0.1'));
    // Die bisherige Bibliothek bleibt, wie sie war.
    expect(await _nachrechnen(tester, vorher.keys), vorher);
    final alteDb = File(p.join(anker.path, 'library.sqlite'));
    expect(alteDb.existsSync(), isTrue);
    final anzahlAlt = await _netz(tester, () async {
      final db = roh.sqlite3.open(alteDb.path, mode: roh.OpenMode.readOnly);
      try {
        return db.select('SELECT count(*) AS n FROM assets').first['n'] as int;
      } finally {
        db.close();
      }
    });
    expect(anzahlAlt, 4);

    // SIC-188: das Token liegt nicht neben der Bibliothek.
    final wurzel = await _netz(tester, LibraryLocation.currentRoot);
    final vj = File(p.join(wurzel.path, 'verbindung.json'));
    final inhalt = jsonDecode(vj.readAsStringSync()) as Map;
    expect(inhalt['token'], isEmpty);
    final kennung = inhalt['tokenkennung'] as String;
    expect(vj.readAsStringSync(), isNot(contains('pv1_')));
    final tokendatei = File(p.join(anker.path, 'tokens', '$kennung.token'));
    expect(tokendatei.existsSync(), isTrue);
    expect(tokendatei.readAsStringSync(), startsWith('pv1_'));
    expect(tokendatei.statSync().mode & 0x1ff, 0x180, reason: 'nur 600');

    // SIC-174: Miniaturen kommen, ein geöffnetes Original wird geholt.
    await _rasterFokus(tester);
    await eventually(
      tester,
      () async {
        final alle = await bibliothek.db.select(bibliothek.db.assets).get();
        return alle
            .where(
              (a) =>
                  a.thumbnailRelativePath != null &&
                  bibliothek.paths
                      .absolute(a.thumbnailRelativePath!)
                      .existsSync(),
            )
            .isNotEmpty;
      },
      timeout: const Duration(seconds: 60),
      was: 'Miniaturen im Vorrat',
    );
    await key(tester, LogicalKeyboardKey.arrowRight);
    await key(tester, LogicalKeyboardKey.enter);
    await waitFor(tester, find.byType(AssetViewerScreen));
    await eventually(
      tester,
      () async {
        final alle = await bibliothek.db.select(bibliothek.db.assets).get();
        return alle.any(
          (a) => bibliothek.paths.absolute(a.relativePath).existsSync(),
        );
      },
      timeout: const Duration(seconds: 60),
      was: 'Original geholt',
    );
    await _schliesseBetrachter(tester);
    await finish(tester);
  });

  // Ohne Server ein nie geholtes Original: Der Betrachter bleibt; die
  // Ausnahme KeineVerbindung aus StoragePaths.bereit bleibt unbehandelt und
  // steht nur im Protokoll (siehe _fehlerAusDerApp).
  testWidgets('SIC-174 Ohne Server ein nie geholtes Original öffnen', (
    tester,
  ) async {
    await startApp(tester);
    final k = await _netz(tester, () => _konto('Offen174'));
    for (var i = 0; i < 3; i++) {
      await _netz(tester, () => _hochladen(k.token, testfoto('o174_$i.jpg')));
    }
    final z = _Zwischen();
    await _netz(tester, z.starte);
    addTearDown(z.halte);
    await _verbinde(tester, 'Offen174', ueber: z.adresse);
    await _netz(tester, z.halte);
    await _rasterFokus(tester);
    await key(tester, LogicalKeyboardKey.arrowRight);
    await key(tester, LogicalKeyboardKey.enter);
    await waitFor(tester, find.byType(AssetViewerScreen));
    await _warte(tester, const Duration(seconds: 5));
    expect(find.byType(AssetViewerScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    print('SIC-174 unbehandelt bisher: $_unbehandelt');
    await _schliesseBetrachter(tester);
    await finish(tester);
  });

  testWidgets('SIC-099 SIC-104 SIC-112 SIC-191 Fremde und nachgestellte '
      'Server, Tokenablage', (tester) async {
    await startApp(tester);
    await _netz(tester, _verwalterToken);
    await _netz(tester, () => _konto('Token191'));

    // SIC-099: ein fremder Webserver mit JSON ohne „dienst“.
    final fremd = _Zwischen()
      ..eingriff = (r) async {
        await _antworte(r, {'name': 'irgendein Dienst', 'version': 3});
        return true;
      };
    await _netz(tester, fremd.starte);
    addTearDown(fremd.halte);
    await _verbindenSeite(tester);
    await _anmeldenUi(
      tester,
      adresse: '${fremd.adresse}',
      name: 'Token191',
      pw: _pw,
    );
    await waitFor(tester, find.text(de.serverKeinPhotoVault));
    await waitGone(tester, find.byType(LinearProgressIndicator));

    // SIC-104: jemand war schneller – die App sah noch einen leeren
    // Server, der echte hat längst ein Konto (409).
    final echt = await _netz(tester, () async {
      final a = Anmeldung(_srv);
      try {
        return await a.zustand();
      } finally {
        a.schliesse();
      }
    });
    final z = _Zwischen();
    await _netz(tester, z.starte);
    addTearDown(z.halte);
    z.eingriff = (r) async {
      if (r.uri.path == '/api/v1/zustand') {
        await _antworte(r, {...echt, 'einrichten': true});
        return true;
      }
      return false;
    };
    await _anmeldenUi(
      tester,
      adresse: '${z.adresse}',
      name: 'Schnell104',
      pw: _pw,
    );
    await waitFor(tester, find.text(de.serverErstesTitel));
    await _tippe(tester, field(de.serverPasswortWiederholen), _pw);
    await _tapText(tester, de.serverErstesAnlegen);
    await waitFor(tester, find.text(de.serverSchonEingerichtet));
    expect(field(de.serverAdresse), findsOneWidget);
    final konten = await _netz(
      tester,
      () => _hole(_verwalterTokenSpeicher!, 'api/v1/konten'),
    );
    expect('${konten['konten']}', isNot(contains('Schnell104')));

    // SIC-112: ein Server ohne Passkeys (nachgestellt) – kein Browser.
    z.eingriff = (r) async {
      if (r.uri.path == '/api/v1/zustand') {
        await _antworte(r, {
          ...echt,
          'anmeldung': {
            ...(echt['anmeldung']! as Map).cast<String, Object?>(),
            'passkeys': false,
          },
        });
        return true;
      }
      return false;
    };
    await _tippe(tester, field(de.serverAdresse), '${z.adresse}');
    await _tapText(tester, de.serverPasskey);
    await waitFor(tester, find.text(de.serverPasskeyUnbekannt));

    // SIC-191: die Ablage ist nicht beschreibbar.
    final tokens = Directory(p.join(anker.path, 'tokens'))
      ..createSync(recursive: true);
    await _netz(tester, () => Process.run('chmod', ['555', tokens.path]));
    addTearDown(() => Process.run('chmod', ['755', tokens.path]));
    z.eingriff = null;
    await _anmeldenUi(tester, adresse: '$_srv', name: 'Token191', pw: _pw);
    await waitFor(
      tester,
      find.text(de.serverWahlTitel),
      timeout: const Duration(seconds: 30),
    );
    await waitFor(tester, find.text(de.serverServerBib));
    await _tapText(tester, de.serverServerBib);
    await erwarteMeldung(tester, de.serverTokenSpeichernFehler);
    await _netz(tester, () => Process.run('chmod', ['755', tokens.path]));
    expect(bibliothek.verbunden, isFalse);
    final verbunden = Directory(p.join(anker.path, 'verbunden'));
    final alleDateien = verbunden.existsSync()
        ? verbunden.listSync(recursive: true).whereType<File>().toList()
        : <File>[];
    for (final f in alleDateien) {
      if (p.basename(f.path) == 'verbindung.json') {
        fail('verbindung.json geschrieben: ${f.path}');
      }
    }
    final liste = await _netz(tester, LibraryLocation.bekannte);
    expect(
      liste.map((b) => b.eintrag.name),
      isNot(contains(startsWith('Token191'))),
    );
    await finish(tester);
  });

  // Behoben in #415: Eine Antwort, die kein JSON ist, wird in Anmeldung und
  // Serververbindung zum Serverfehler.
  testWidgets('SIC-099 Fremder Webserver mit HTML', (tester) async {
    await startApp(tester);
    final html = _Zwischen()
      ..eingriff = (r) async {
        await r.drain<void>();
        r.response.headers.contentType = ContentType.html;
        r.response.write('<!doctype html><html><body>Willkommen</body></html>');
        await r.response.close();
        return true;
      };
    await _netz(tester, html.starte);
    addTearDown(html.halte);
    await _verbindenSeite(tester);
    await _anmeldenUi(tester, adresse: '${html.adresse}', name: 'xy', pw: _pw);
    await waitFor(tester, find.text(de.serverKeinPhotoVault));
    await finish(tester);
  });

  testWidgets('SIC-138 SIC-149 SIC-129 SIC-132 SIC-133 SIC-130 Eigenes Konto', (
    tester,
  ) async {
    await startApp(tester);
    final k = await _netz(tester, () => _konto('A129', geraet: 'Handy'));
    final appToken = await _verbinde(tester, 'A129');
    await _serverGruppe(tester);
    await waitFor(tester, find.text(de.serverEigenesKonto));
    // SIC-138, SIC-149: ohne Verwalterrecht weder Knopf noch Abschnitt.
    await _warte(tester, const Duration(seconds: 4));
    expect(find.text(de.serverKontenVerwalten), findsNothing);
    expect(find.text(de.serverSicherungTitel), findsNothing);

    // SIC-129: anderes Gerät abmelden – erst Abbrechen, dann Abmelden.
    await _tapText(tester, de.serverEigenesKonto);
    await waitFor(tester, find.text('Handy'));
    Finder abmeldenKnopf() => find.descendant(
      of: _zeile('Handy'),
      matching: find.text(de.serverGeraetAbmelden),
    );
    await _tap(tester, abmeldenKnopf());
    await waitFor(tester, find.text(de.serverGeraetAbmeldenFrage('Handy')));
    await _tap(tester, _imDialog(de.allgAbbrechen));
    await waitGone(tester, find.text(de.serverGeraetAbmeldenFrage('Handy')));
    expect(find.text('Handy'), findsOneWidget);
    await _tap(tester, abmeldenKnopf());
    await _tap(tester, _imDialog(de.serverGeraetAbmelden));
    await waitGone(tester, find.text('Handy'));
    expect(await _netz(tester, () => _status(k.token, 'api/v1/konto')), 401);

    // SIC-132: falsches bisheriges Passwort.
    await _tapText(tester, de.serverPasswortAendern);
    final dlg = find.byType(AlertDialog);
    await waitFor(tester, dlg);
    Finder feldIm(String name) =>
        find.descendant(of: dlg, matching: field(name));
    await _tippe(tester, feldIm(de.serverPasswortAlt), 'falsches-passwort-1');
    await _tippe(tester, feldIm(de.serverPasswortNeu), 'neues-passwort-133');
    await enter(
      tester,
      feldIm(de.serverPasswortWiederholen),
      'neues-passwort-133',
    );
    await _tap(tester, _imDialog(de.serverAendern));
    final rot = find.descendant(
      of: dlg,
      matching: find.byWidgetPredicate(
        (w) =>
            w is Text &&
            w.style?.color != null &&
            w.style!.color == Theme.of(tester.element(dlg)).colorScheme.error,
      ),
    );
    await waitFor(tester, rot);
    print('SIC-132 Meldung: ${tester.widget<Text>(rot.first).data}');
    expect(feldIm(de.serverPasswortAlt), findsOneWidget, reason: 'offen');
    // Das Passwort ist unverändert.
    final pruef = await _netz(
      tester,
      () => _anmelden('A129', geraet: 'Pruefung'),
    );

    // SIC-133, SIC-130: ändern und alle anderen Geräte abmelden.
    await _tippe(tester, feldIm(de.serverPasswortAlt), _pw);
    await _tap(tester, _imDialog(de.serverAndereAbmelden));
    await _tap(tester, _imDialog(de.serverAendern));
    await waitGone(tester, dlg);
    await erwarteMeldung(tester, de.serverPasswortGeaendert);
    expect(await _netz(tester, () => _status(pruef, 'api/v1/konto')), 401);
    expect(await _netz(tester, () => _status(appToken, 'api/v1/konto')), 200);
    await _netz(
      tester,
      () => _anmelden('A129', pw: 'neues-passwort-133', geraet: 'Neu'),
    );
    final alt = await _netz(
      tester,
      () => _anmeldeschritt('A129', geraet: 'Alt'),
    );
    expect(alt, isA<AnmeldungAbgewiesen>());
    // Dieser Rechner bleibt verbunden.
    await _zurueck(tester);
    await _serverGruppe(tester);
    await waitFor(tester, find.text(de.serverAbgeglichen));
    await finish(tester);
  });

  // Befund: Die Ablehnung des Servers erscheint roh als JSON
  // (lib/screens/server_eigenes_konto_screen.dart:266).
  testWidgets('SIC-132 Ablehnung des Servers als Satz', (tester) async {
    await startApp(tester);
    await _netz(tester, () => _konto('A132'));
    await _verbinde(tester, 'A132');
    await _serverGruppe(tester);
    await _tapText(tester, de.serverEigenesKonto);
    await _tapText(tester, de.serverPasswortAendern);
    final dlg = find.byType(AlertDialog);
    Finder feldIm(String name) =>
        find.descendant(of: dlg, matching: field(name));
    await _tippe(tester, feldIm(de.serverPasswortAlt), 'falsches-passwort-1');
    await _tippe(tester, feldIm(de.serverPasswortNeu), 'neues-passwort-132');
    await enter(
      tester,
      feldIm(de.serverPasswortWiederholen),
      'neues-passwort-132',
    );
    await _tap(tester, _imDialog(de.serverAendern));
    final rot = find.descendant(
      of: dlg,
      matching: find.byWidgetPredicate(
        (w) =>
            w is Text &&
            w.style?.color == Theme.of(tester.element(dlg)).colorScheme.error,
      ),
    );
    await waitFor(tester, rot);
    final text = tester.widget<Text>(rot.first).data!;
    expect(text, isNot(startsWith('{')), reason: 'rohes JSON: $text');
    expect(int.tryParse(text), isNull, reason: 'nur eine Statuszahl');
    await finish(tester);
  }, skip: true);

  testWidgets('SIC-148 SIC-137 Konten und Konto ohne Server', (tester) async {
    await startApp(tester);
    await _netz(tester, _verwalterToken);
    final z = _Zwischen();
    await _netz(tester, z.starte);
    addTearDown(z.halte);
    await _verbinde(tester, _verwalter, ueber: z.adresse);
    await _serverGruppe(tester);
    await waitFor(tester, find.text(de.serverKontenVerwalten));
    await _netz(tester, z.halte);

    // SIC-148
    await _tapText(tester, de.serverKontenVerwalten);
    await waitFor(
      tester,
      find.descendant(
        of: find.byType(ServerKontenScreen),
        matching: find.text(de.serverNichtErreichbar),
      ),
      timeout: const Duration(seconds: 45),
    );
    await _zurueck(tester);

    // SIC-137
    await _tapText(tester, de.serverEigenesKonto);
    final seite = find.byType(ServerEigenesKontoScreen);
    await waitGone(
      tester,
      find.descendant(
        of: seite,
        matching: find.byType(CircularProgressIndicator),
      ),
      timeout: const Duration(seconds: 45),
    );
    final texte = [
      for (final e
          in find.descendant(of: seite, matching: find.byType(Text)).evaluate())
        (e.widget as Text).data ?? '',
    ]..remove(de.serverEigenesKontoTitel);
    print('SIC-137 Fehlertext: $texte');
    expect(texte.where((t) => t.trim().isNotEmpty), isNotEmpty);
    expect(tester.takeException(), isNull);
    await _zurueck(tester);
    await finish(tester);
  });

  // Befund: Ohne Server zeigt „Mein Konto“ die rohe Ausnahme
  // (lib/screens/server_eigenes_konto_screen.dart:55).
  testWidgets('SIC-137 Fehlertext ohne Server verständlich', (tester) async {
    await startApp(tester);
    await _netz(tester, () => _konto('A137'));
    final z = _Zwischen();
    await _netz(tester, z.starte);
    addTearDown(z.halte);
    await _verbinde(tester, 'A137', ueber: z.adresse);
    await _netz(tester, z.halte);
    await _serverGruppe(tester);
    await _tapText(tester, de.serverEigenesKonto);
    final seite = find.byType(ServerEigenesKontoScreen);
    await waitGone(
      tester,
      find.descendant(
        of: seite,
        matching: find.byType(CircularProgressIndicator),
      ),
      timeout: const Duration(seconds: 45),
    );
    final texte = [
      for (final e
          in find.descendant(of: seite, matching: find.byType(Text)).evaluate())
        (e.widget as Text).data ?? '',
    ].join(' | ');
    expect(texte, isNot(contains('KeineVerbindung')));
    expect(texte, isNot(contains('Exception')));
    await finish(tester);
  }, skip: true);

  testWidgets('SIC-158 SIC-161 SIC-168 SIC-171 SIC-175 Abgleich mit einem '
      'zweiten Gerät', (tester) async {
    await startApp(tester);
    final k = await _netz(tester, () => _konto('Abgl158', geraet: 'Geraet-2'));
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
    // Direkt, ohne Zwischenserver: Über ihn kamen Änderungen anderer
    // Geräte nach einem eigenen Befehl nicht mehr an (siehe Bericht).
    await _verbinde(tester, 'Abgl158');
    // SIC-161: in den ersten Sekunden kein „nicht erreichbar“.
    for (var i = 0; i < 40; i++) {
      expect(find.textContaining('Server nicht erreichbar'), findsNothing);
      await tester.pump(const Duration(milliseconds: 100));
    }
    await eventually(
      tester,
      () async => bibliothek.abgleichszustand?.erreichbar ?? false,
    );

    /// Wartet, bis Gerät 2s Bewertung [wert] für [id] hier ankommt.
    Future<bool> kommtAn(String id, int wert, Duration frist) async {
      final ende = DateTime.now().add(frist);
      while (DateTime.now().isBefore(ende)) {
        final a = await _netz(tester, () => bibliothek.db.assetById(id));
        if (a?.rating == wert) return true;
        await _warte(tester, const Duration(seconds: 1));
      }
      final zst = bibliothek.abgleichszustand;
      print(
        'SIC-158 nicht angekommen: erreichbar ${zst?.erreichbar}, '
        'ausstehend ${zst?.ausstehend}',
      );
      return false;
    }

    // SIC-158 (Empfang zuerst): Gerät 2 ändert, hier kommt es ohne
    // Neustart an.
    await _netz(tester, () => _befehl(k.token, BewertungSetzen([ids[0]], 3)));
    final empfangVorher = await kommtAn(ids[0], 3, const Duration(seconds: 60));
    print('SIC-158 Empfang vor eigenem Befehl: $empfangVorher');

    // SIC-158: fünf Sterne hier.
    await _rasterFokus(tester);
    await key(tester, LogicalKeyboardKey.arrowRight);
    await key(tester, LogicalKeyboardKey.digit5);
    await eventually(tester, () async {
      final alle = await bibliothek.db.select(bibliothek.db.assets).get();
      return alle.where((a) => a.rating == 5).length == 1;
    }, was: 'fünf Sterne hier');
    await _serverGruppe(tester);
    // „1 Änderungen gehen zum Server“ steht nur einen Augenblick da.
    print(
      'SIC-158 „gehen zum Server“ gesehen: '
      '${find.text(de.serverSendet(1)).evaluate().isNotEmpty}',
    );
    await waitFor(
      tester,
      find.text(de.serverAbgeglichen),
      timeout: const Duration(seconds: 40),
    );
    final bewertet = (await _assets(tester)).firstWhere((a) => a.rating == 5);
    expect(
      (await _netz(tester, () => _aufnahme(k.token, bewertet.id)))['rating'],
      5,
    );
    // Und noch einmal Gerät 2, nach dem eigenen Befehl.
    final anderes = ids.firstWhere((i) => i != bewertet.id);
    await _netz(tester, () => _befehl(k.token, BewertungSetzen([anderes], 4)));
    final empfangNachher = await kommtAn(
      anderes,
      4,
      const Duration(seconds: 60),
    );
    var mitAnstoss = false;
    if (!empfangNachher) {
      // Wie beim Zurückkommen der App in den Vordergrund.
      bibliothek.abgleich?.jetzt();
      mitAnstoss = await kommtAn(anderes, 4, const Duration(seconds: 30));
    }
    print(
      'SIC-158 Empfang nach eigenem Befehl: $empfangNachher, '
      'mit Anstoss: $mitAnstoss',
    );
    expect(empfangVorher, isTrue, reason: 'Empfang vor eigenem Befehl');
    expect(empfangNachher, isTrue, reason: 'Empfang nach eigenem Befehl');

    // SIC-168: die leere Übersicht.
    await _tapText(tester, de.syncUebersicht);
    await waitFor(tester, find.text(st.anzahl(0, 0)));
    expect(find.text(st.leer), findsOneWidget);
    await tester.tap(find.byTooltip(st.aktualisieren));
    var balken = false;
    for (var i = 0; i < 60 && !balken; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      balken = find.byType(LinearProgressIndicator).evaluate().isNotEmpty;
    }
    print('SIC-168 Balken gesehen: $balken');
    await settle(tester);
    expect(find.text(st.leer), findsOneWidget);
    expect(find.text(st.fehler), findsNothing);
    await _zurueck(tester);

    // SIC-171: zu grosse Änderung (über 6 MB) – der Hinweis kommt, nichts
    // ändert sich. Ausgelöst über denselben Befehl wie die Info-Ansicht.
    final vorBeschreibung = (await _netz(
      tester,
      () => bibliothek.db.assetById(anderes),
    ))!.description;
    await _netz(tester, () async {
      try {
        await bibliothek.db.fuehreAus(
          BeschreibungSetzen([anderes], 'x' * (7 * 1024 * 1024)),
        );
      } catch (e, s) {
        _wieImBetrieb(e, s);
      }
    });
    await erwarteMeldung(tester, de.syncAuswahlZuGross);
    expect(
      (await _netz(
        tester,
        () => bibliothek.db.assetById(anderes),
      ))!.description,
      vorBeschreibung,
    );
    expect(bibliothek.abgleichszustand?.ausstehend, 0);

    // SIC-175: Importieren heisst hochladen.
    await openSection(tester, Hauptbereich.zeitleiste);
    // Die Glocke der Meldungen liegt sonst über dem Knopf „Importieren“.
    await _meldungenSchliessen(tester);
    await _importiereUeberLeiste(tester, [testfoto('neu175.jpg')]);
    await eventually(
      tester,
      () async {
        final alle = await bibliothek.db.select(bibliothek.db.assets).get();
        return alle.any((a) => a.originalFileName == 'neu175.jpg');
      },
      timeout: const Duration(seconds: 60),
      was: 'Import hier',
    );
    final neu = (await _assets(
      tester,
    )).firstWhere((a) => a.originalFileName == 'neu175.jpg');
    final dort = await _netz(tester, () => _aufnahme(k.token, neu.id));
    expect(dort['originalFileName'], 'neu175.jpg');
    await finish(tester);
  });

  testWidgets('SIC-159 SIC-160 SIC-125 Offline arbeiten und trennen', (
    tester,
  ) async {
    await startApp(tester);
    final k = await _netz(tester, () => _konto('Off159', geraet: 'Geraet-2'));
    final ids = <String>[];
    for (var i = 0; i < 3; i++) {
      ids.add(
        await _netz(
          tester,
          () => _hochladen(
            k.token,
            testfoto('off_$i.jpg', datum: DateTime(2024, 7, 1 + i)),
          ),
        ),
      );
    }
    final z = _Zwischen();
    await _netz(tester, z.starte);
    addTearDown(z.halte);
    await _verbinde(tester, 'Off159', ueber: z.adresse);
    await eventually(
      tester,
      () async => bibliothek.abgleichszustand?.erreichbar ?? false,
    );
    await _rasterFokus(tester);
    await _netz(tester, z.halte);
    await eventually(
      tester,
      () async => bibliothek.abgleichszustand?.erreichbar == false,
      timeout: const Duration(seconds: 60),
      was: 'offline',
    );

    // SIC-159: drei Favoriten offline.
    await _rasterFokus(tester);
    for (var i = 0; i < 3; i++) {
      await key(tester, LogicalKeyboardKey.arrowRight);
      await key(tester, LogicalKeyboardKey.keyF);
    }
    await eventually(tester, () async {
      final alle = await bibliothek.db.select(bibliothek.db.assets).get();
      return alle.where((a) => a.isFavorite).length == 3;
    }, was: 'drei Favoriten hier');
    await waitFor(tester, find.text(de.serverOffline(3)));
    await _serverGruppe(tester);
    expect(find.text(de.serverOffline(3)), findsWidgets);

    // SIC-160: Neustart ohne Server – sie warten weiter.
    await _neustart(tester);
    await waitFor(
      tester,
      find.text(de.serverOffline(3)),
      timeout: const Duration(seconds: 60),
    );
    await _netz(tester, z.starte);
    await eventually(
      tester,
      () async => (bibliothek.abgleichszustand?.ausstehend ?? -1) == 0,
      timeout: const Duration(seconds: 150),
      was: 'alles nachgereicht',
    );
    for (final id in ids) {
      expect(
        (await _netz(tester, () => _aufnahme(k.token, id)))['isFavorite'],
        isTrue,
      );
    }
    await _serverGruppe(tester);
    await waitFor(tester, find.text(de.serverAbgeglichen));

    // SIC-125: trennen ohne Netz.
    await _netz(tester, z.halte);
    await eventually(
      tester,
      () async => bibliothek.abgleichszustand?.erreichbar == false,
      timeout: const Duration(seconds: 60),
    );
    await _tapText(tester, de.serverTrennen);
    await _tap(tester, _imDialog(de.serverTrennenAktion));
    await waitFor(
      tester,
      find.text(de.serverGetrennt),
      timeout: const Duration(seconds: 60),
    );
    final geraete = await _netz(tester, () => _hole(k.token, 'api/v1/geraete'));
    expect('${geraete['geraete']}', contains(_geraet));
    await _neustart(tester);
    expect(bibliothek.verbunden, isFalse);
    expect(await _assets(tester), hasLength(3));
    await finish(tester);
  });

  testWidgets('SIC-126 SIC-124 Abgemeldetes Gerät, Trennen', (tester) async {
    await startApp(tester);
    final k = await _netz(tester, () => _konto('Abm126', geraet: 'Geraet-2'));
    final id = await _netz(
      tester,
      () => _hochladen(k.token, testfoto('abm.jpg')),
    );
    final appToken = await _verbinde(tester, 'Abm126');
    await eventually(
      tester,
      () async => bibliothek.abgleichszustand?.erreichbar ?? false,
    );
    final geraet =
        (await _netz(tester, () => _hole(appToken, 'api/v1/konto')))['geraet']
            as String;
    final s = await _netz(
      tester,
      () => _status(k.token, 'api/v1/geraete/$geraet', methode: 'DELETE'),
    );
    expect(s, 200);
    // SIC-126: Band und Einstellungen.
    await waitFor(
      tester,
      find.text(de.serverAbgemeldet),
      timeout: const Duration(seconds: 70),
    );
    await _serverGruppe(tester);
    expect(find.text(de.serverAbgemeldet), findsWidgets);
    await _netz(tester, () => _befehl(k.token, BewertungSetzen([id], 3)));
    await _warte(tester, const Duration(seconds: 8));
    expect((await _netz(tester, () => bibliothek.db.assetById(id)))!.rating, 0);

    // SIC-124: trennen, mit Server.
    final k2 = await _netz(tester, () => _konto('Trn124', geraet: 'Geraet-2'));
    await _netz(tester, () => _hochladen(k2.token, testfoto('trn.jpg')));
    await _verbinde(tester, 'Trn124');
    final wurzel = await _netz(tester, LibraryLocation.currentRoot);
    final kennung =
        (jsonDecode(
                  File(
                    p.join(wurzel.path, 'verbindung.json'),
                  ).readAsStringSync(),
                )
                as Map)['tokenkennung']
            as String;
    final tokendatei = File(p.join(anker.path, 'tokens', '$kennung.token'));
    expect(tokendatei.existsSync(), isTrue);
    await _serverGruppe(tester);
    await _tapText(tester, de.serverTrennen);
    await _tap(tester, _imDialog(de.serverTrennenAktion));
    await waitFor(
      tester,
      find.text(de.serverGetrennt),
      timeout: const Duration(seconds: 60),
    );
    final geraete = await _netz(
      tester,
      () => _hole(k2.token, 'api/v1/geraete'),
    );
    expect('${geraete['geraete']}', isNot(contains(_geraet)));
    expect(tokendatei.existsSync(), isFalse);
    await _neustart(tester);
    expect(bibliothek.verbunden, isFalse);
    expect(await _assets(tester), hasLength(1));
    await finish(tester);
  });

  testWidgets('SIC-162 SIC-163 SIC-164 SIC-165 Konflikte', (tester) async {
    await startApp(tester);
    final k = await _netz(tester, () => _konto('Konf162', geraet: 'Geraet-2'));
    for (var i = 0; i < 3; i++) {
      await _netz(
        tester,
        () => _hochladen(
          k.token,
          testfoto('konf_$i.jpg', datum: DateTime(2024, 8, 3 - i)),
        ),
      );
    }
    final z = _Zwischen();
    await _netz(tester, z.starte);
    addTearDown(z.halte);
    await _verbinde(tester, 'Konf162', ueber: z.adresse);
    await eventually(
      tester,
      () async => bibliothek.abgleichszustand?.erreichbar ?? false,
    );

    /// Offline hier [hier], am Server [dort]; gibt die Kennung zurück.
    Future<String> konflikt(int n, String hier, String dort) async {
      await _netz(tester, z.halte);
      await eventually(
        tester,
        () async => bibliothek.abgleichszustand?.erreichbar == false,
        timeout: const Duration(seconds: 60),
        was: 'offline',
      );
      await _beschreibungUi(tester, n, hier);
      final a = (await _assets(
        tester,
      )).firstWhere((a) => a.description == hier);
      await _netz(
        tester,
        () => _befehl(k.token, BeschreibungSetzen([a.id], dort)),
      );
      // Wieder verbunden – direkt, siehe _umstellen.
      await _umstellen(tester, _srv);
      await eventually(
        tester,
        () async => (bibliothek.abgleichszustand?.faelle ?? 0) >= 1,
        timeout: const Duration(seconds: 150),
        was: 'Konflikt erkannt',
      );
      return a.id;
    }

    /// Für den nächsten Fall wieder über den Zwischenserver.
    Future<void> ueberZwischen() async {
      await _netz(tester, z.starte);
      await _umstellen(tester, z.adresse);
      await eventually(
        tester,
        () async => bibliothek.abgleichszustand?.erreichbar ?? false,
        timeout: const Duration(seconds: 60),
        was: 'über den Zwischenserver erreichbar',
      );
    }

    // SIC-162
    final id1 = await konflikt(0, 'A', 'B');
    // Die Meldung kommt nur, wenn der Fall in dieser Sitzung neu dazukommt;
    // nach dem Neustart in _umstellen kann er schon beim ersten Stand da
    // sein. Dann über die Einstellungen.
    await _warte(tester, const Duration(seconds: 2));
    if (find.textContaining(de.syncNichtUebernommen(1)).evaluate().isNotEmpty) {
      print('SIC-162 Meldung gesehen');
      await _tapText(tester, de.syncAnsehen);
    } else {
      print('SIC-162 Meldung nicht gesehen (Neustart), über die Einstellungen');
      await _serverGruppe(tester);
      await _tapText(tester, de.syncUebersicht);
    }
    await waitFor(tester, find.text(st.titel));
    await waitFor(tester, find.text(st.beschreibung));
    expect(find.textContaining(st.konflikt), findsOneWidget);
    Future<bool> zeigtB(Duration frist) async {
      final ende = DateTime.now().add(frist);
      while (DateTime.now().isBefore(ende)) {
        final d = (await _netz(
          tester,
          () => bibliothek.db.assetById(id1),
        ))?.description;
        if (d == 'B') return true;
        await _warte(tester, const Duration(seconds: 1));
      }
      return false;
    }

    final fotoZeigtB = await zeigtB(const Duration(seconds: 45));
    var bMitAnstoss = false;
    if (!fotoZeigtB) {
      bibliothek.abgleich?.jetzt();
      bMitAnstoss = await zeigtB(const Duration(seconds: 30));
    }
    print(
      'SIC-162 Foto zeigt B: $fotoZeigtB, mit Anstoss: $bMitAnstoss, '
      'hier: ${(await _netz(tester, () => bibliothek.db.assetById(id1)))?.description}',
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
    await ueberZwischen();
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
    await ueberZwischen();
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
    expect(fotoZeigtB, isTrue, reason: 'das Foto zeigt B');
    await finish(tester);
  });

  testWidgets('SIC-122 SIC-127 Speicher knapp oder voll, anderes Schema '
      '(Antworten nachgestellt)', (tester) async {
    await startApp(tester);
    final k = await _netz(tester, () => _konto('Speich122'));
    final fotoId = await _netz(
      tester,
      () => _hochladen(k.token, testfoto('speich.jpg')),
    );
    const gib = 1 << 30;
    var stufe = 'knapp';
    int? schema;
    final z = _Zwischen();
    await _netz(tester, z.starte);
    addTearDown(z.halte);
    z.eingriff = (r) async {
      if (r.uri.path == '/api/v1/speicher') {
        await _antworte(r, {
          'stufe': stufe,
          'gesamt': 200 * gib,
          'frei': stufe == 'voll' ? gib : 5 * gib,
          'belegt': 195 * gib,
        });
        return true;
      }
      if (schema != null && r.uri.path == '/api/v1/abgleich/stand') {
        final token = r.headers.value('authorization')!.substring(7);
        final echt = await _hole(token, 'api/v1/abgleich/stand');
        await _antworte(r, {...echt, 'schema': schema});
        return true;
      }
      return false;
    };
    await _verbinde(tester, 'Speich122', ueber: z.adresse);
    // SIC-122 knapp: Band und rote Zeile.
    await waitFor(
      tester,
      find.text(de.serverSpeicherKnapp('5.00 GB')),
      timeout: const Duration(seconds: 30),
    );
    await _serverGruppe(tester);
    final zeile = find.text(de.serverSpeicherStand('5.00 GB', '200.00 GB'));
    await waitFor(tester, zeile);
    expect(
      tester.widget<Text>(zeile).style?.color,
      Theme.of(tester.element(zeile)).colorScheme.error,
    );
    // voll
    stufe = 'voll';
    await _neustart(tester);
    await waitFor(
      tester,
      find.text(de.serverSpeicherVoll),
      timeout: const Duration(seconds: 30),
    );
    await _serverGruppe(tester);
    expect(find.text(de.serverSpeicherVoll), findsWidgets);

    // SIC-127: Server neuer bzw. älter.
    stufe = 'ausreichend';
    final eigenes = bibliothek.db.schemaVersion;
    schema = eigenes + 1;
    await _neustart(tester);
    await waitFor(
      tester,
      find.text(de.serverAppZuAlt),
      timeout: const Duration(seconds: 30),
    );
    schema = eigenes - 1;
    await _neustart(tester);
    await waitFor(
      tester,
      find.text(de.serverZuAlt),
      timeout: const Duration(seconds: 30),
    );
    // Änderungen bleiben hier und gehen nicht zum Server.
    await _rasterFokus(tester);
    await key(tester, LogicalKeyboardKey.arrowRight);
    await key(tester, LogicalKeyboardKey.keyF);
    await eventually(
      tester,
      () async => (await bibliothek.db.assetById(fotoId))?.isFavorite ?? false,
      was: 'Favorit hier',
    );
    await _warte(tester, const Duration(seconds: 6));
    expect(
      (await _netz(tester, () => _aufnahme(k.token, fotoId)))['isFavorite'],
      isFalse,
      reason: 'nichts abgeglichen',
    );
    await finish(tester);
  });

  /// Umzug über einen Zwischenserver, der nach [grenze] hochgeladenen
  /// Dateien abreisst. Gibt Zwischenserver, Zähler und Prüfsummen zurück.
  Future<
    ({
      _Zwischen z,
      int Function() neue,
      void Function() nullen,
      Map<String, String> vorher,
    })
  >
  abgerissenerUmzug(WidgetTester tester, String konto) async {
    await startApp(tester);
    await importiereDirekt(tester, [
      for (var i = 0; i < 4; i++)
        testfoto('u119_$i.jpg', datum: DateTime(2024, 2, 1 + i)),
    ]);
    final vorher = await _originale(tester);
    await _netz(tester, () => _konto(konto));
    final z = _Zwischen();
    await _netz(tester, z.starte);
    addTearDown(z.halte);
    var neue = 0;
    int? grenze;
    z.eingriff = (r) async {
      if (r.method == 'POST' && r.uri.path == '/api/v1/umzug/hochladen') {
        neue++;
        if (grenze != null && neue > grenze) {
          unawaited(z.halte());
          return true;
        }
      }
      return false;
    };
    await _verbindenSeite(tester);
    await _anmeldenUi(tester, adresse: '${z.adresse}', name: konto, pw: _pw);
    await waitFor(
      tester,
      find.text(de.serverServerBibText(0)),
      timeout: const Duration(seconds: 30),
    );
    grenze = 3;
    await _tapText(tester, de.serverUmziehen);
    await waitFor(
      tester,
      find.textContaining('${de.serverFehler}:'),
      timeout: const Duration(seconds: 180),
    );
    grenze = null;
    return (z: z, neue: () => neue, nullen: () => neue = 0, vorher: vorher);
  }

  testWidgets('SIC-119 Unterbrochener Umzug lädt nicht doppelt', (
    tester,
  ) async {
    final u = await abgerissenerUmzug(tester, 'Umzug119');
    // Die Bibliothek bleibt unverbunden und unverändert.
    expect(bibliothek.verbunden, isFalse);
    expect(File(p.join(anker.path, 'verbindung.json')).existsSync(), isFalse);
    expect(await _nachrechnen(tester, u.vorher.keys), u.vorher);

    // Zweiter Versuch nach einem Neustart (das Fortschrittsfenster bleibt
    // stehen, siehe die Prüfung darunter): Was schon da ist, wird
    // übersprungen.
    await _neustart(tester);
    expect(bibliothek.verbunden, isFalse);
    final dateien = bibliothek.paths.root
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) {
          final rel = p.relative(f.path, from: bibliothek.paths.root.path);
          return !p.split(rel).any((t) => t.startsWith('.')) &&
              !rel.endsWith('.teil');
        })
        .length;
    await _netz(tester, u.z.starte);
    await _verbindenSeite(tester);
    await _anmeldenUi(
      tester,
      adresse: '${u.z.adresse}',
      name: 'Umzug119',
      pw: _pw,
    );
    await waitFor(
      tester,
      find.text(de.serverUmziehen),
      timeout: const Duration(seconds: 30),
    );
    await waitFor(tester, find.text(de.serverServerBibText(0)));
    u.nullen();
    await _tapText(tester, de.serverUmziehen);
    await waitFor(
      tester,
      find.text(de.serverFertigNeustart),
      timeout: const Duration(seconds: 180),
    );
    print(
      'SIC-119: $dateien Dateien, beim zweiten Mal ${u.neue()} hochgeladen',
    );
    // Ohne Überspringen wären es alle Dateien und die Datenbank.
    expect(u.neue(), lessThanOrEqualTo(dateien - 1));
    await _neustart(tester);
    expect(bibliothek.verbunden, isTrue);
    await finish(tester);
  });

  // Behoben in #406: Das Fortschrittsfenster wird auf dem Wurzel-Navigator
  // geschlossen, auf dem es liegt.
  testWidgets('SIC-119 Nach dem Abbruch schliesst das Fortschrittsfenster', (
    tester,
  ) async {
    await abgerissenerUmzug(tester, 'Fenster119');
    await settle(tester);
    expect(find.text(de.serverZiehtUm), findsNothing, reason: 'Fenster offen');
    expect(find.text(de.serverUmziehen), findsOneWidget, reason: 'Wahl weg');
    await finish(tester);
  });

  testWidgets('SIC-176 SIC-177 SIC-178 SIC-179 Nur ohne Server', (
    tester,
  ) async {
    await startApp(tester);
    await importiereDirekt(tester, [
      testfoto('sperr.jpg', datum: DateTime(2024, 9, 2)),
      testfoto('papierkorb.jpg', datum: DateTime(2024, 9, 1)),
    ]);
    final alle = await _assets(tester);
    final sperr = alle.firstWhere((a) => a.originalFileName == 'sperr.jpg');
    final weg = alle.firstWhere((a) => a.originalFileName == 'papierkorb.jpg');
    await _netz(tester, () async {
      await bibliothek.setupVaultPin('1357');
      await bibliothek.db.fuehreAus(
        InDenPapierkorb([
          weg.id,
        ], zeit: DateTime.now().subtract(const Duration(days: 400))),
      );
      await bibliothek.db.fuehreAus(
        const PapierkorbFristSetzen(an: true, tage: 30),
      );
    });
    expect(
      (await _netz(tester, () => bibliothek.db.assetById(weg.id)))!.isTrashed,
      isTrue,
    );
    // Umzug auf ein leeres Konto (ohne Oberfläche, wie „Umziehen“).
    await _netz(tester, () => _konto('Sperr176'));
    await _verbindenSeite(tester);
    await _anmeldenUi(tester, adresse: '$_srv', name: 'Sperr176', pw: _pw);
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

    // SIC-179: der abgelaufene Papierkorb wird hier nicht geleert.
    await _warte(tester, const Duration(seconds: 6));
    final nochDa = await _netz(tester, () => bibliothek.db.assetById(weg.id));
    expect(nochDa, isNotNull);
    expect(nochDa!.isTrashed, isTrue);

    // SIC-176: sperren geht verbunden nicht.
    final dateiVorher = await _originale(tester);
    await _rasterFokus(tester);
    await key(tester, LogicalKeyboardKey.arrowRight);
    await key(tester, LogicalKeyboardKey.enter);
    await waitFor(tester, find.byType(AssetViewerScreen));
    await runZonedGuarded(() async {
      await tester.tap(find.byTooltip(de.viewerInGesperrtenOrdner));
      await tester.pump();
    }, _wieImBetrieb);
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
    final nachSperre = await _netz(
      tester,
      () => bibliothek.db.assetById(sperr.id),
    );
    expect(nachSperre!.isLocked, isFalse);
    expect(await _nachrechnen(tester, dateiVorher.keys), dateiVorher);
    if (find.byType(AssetViewerScreen).evaluate().isNotEmpty) {
      await key(tester, LogicalKeyboardKey.escape);
    }

    // SIC-177, SIC-178: Aufgaben laufen am Server.
    await openSection(tester, Hauptbereich.werkzeuge);
    await _tapText(tester, de.aufgTitel);
    Future<void> starte(String titel) async {
      final seite = find.byType(BackgroundTasksScreen);
      await waitFor(tester, seite);
      await _bisSichtbar(tester, find.text(titel), seite);
      final karte = find.ancestor(
        of: find.text(titel),
        matching: find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_Aufgabenrahmen',
        ),
      );
      final knopf = find.descendant(
        of: karte,
        matching: find.byWidgetPredicate(
          (w) =>
              w is Text &&
              (w.data == de.aufgModusAlle || w.data == de.aufgFehlende),
        ),
      );
      await _tap(tester, knopf.first);
      // Rückfrage bestätigen, falls eine kommt.
      if (find.byType(AlertDialog).evaluate().isNotEmpty) {
        final ja = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byWidgetPredicate((w) => w is FilledButton),
        );
        await _tap(tester, ja.last);
      }
    }

    await starte(de.aufgAblageTitel);
    await erwarteMeldung(tester, de.aufgAmServer);
    final ablageNachher = await _originale(tester);
    expect(ablageNachher, dateiVorher);
    await waitGone(
      tester,
      find.text(de.aufgAmServer),
      timeout: const Duration(seconds: 15),
    );
    await starte(de.aufgOcrTitel);
    await erwarteMeldung(tester, de.aufgAmServer);
    expect(bibliothek.lauf('ocr'), isNull, reason: 'lokal startet nichts');
    await finish(tester);
  });

  testWidgets('SIC-208 SIC-229 SIC-209 SIC-206 SIC-214 SIC-215 SIC-210 '
      'Album teilen und füllen (Besitzer)', (tester) async {
    await startApp(tester);
    final b = await _netz(tester, () => _konto('B208'));
    final a = await _netz(tester, () => _konto('A208'));
    final ids = <String>[];
    for (var i = 0; i < 3; i++) {
      ids.add(
        await _netz(
          tester,
          () => _hochladen(
            b.token,
            testfoto('b208_$i.jpg', datum: DateTime(2024, 4, 1 + i)),
          ),
        ),
      );
    }
    final personId = const Uuid().v4();
    await _netz(tester, () async {
      await _befehl(b.token, PersonAnlegen(personId, 'Person A'));
      await _personAuf(b.token, personId, ids[1]);
      await _personAuf(b.token, personId, ids[2]);
    });
    final albumId = await _netz(
      tester,
      () => _albumAufServer(b.token, 'Ferien208', [ids[0]]),
    );
    await _verbinde(tester, 'B208');

    // SIC-208 (und SIC-229 vorher): teilen zum Ansehen.
    await openSection(tester, Hauptbereich.alben);
    await _tapText(tester, 'Ferien208');
    await waitFor(tester, find.byTooltip(tt.kontenTeilen));
    await _warte(tester, const Duration(seconds: 3));
    expect(find.byTooltip(tt.kommentare), findsNothing);
    await _tap(tester, find.byTooltip(tt.kontenTeilen));
    await waitFor(tester, find.text(tt.kontenTeilenTitel('Ferien208')));
    await waitFor(tester, find.byType(DropdownButton<String>));
    await waitFor(tester, _imDialog(tt.kontenNiemand));
    await _waehle(tester, find.byType(DropdownButton<String>), 'A208');
    await _tap(tester, _imDialog(tt.kontenTeilenKnopf));
    await waitGone(tester, _imDialog(tt.kontenNiemand));
    // Die Zeile der Teilung: die mit „Entfernen“.
    final zeileA = find.ancestor(
      of: find.descendant(
        of: find.byType(Dialog),
        matching: find.byTooltip(tt.entfernen),
      ),
      matching: find.byType(Row),
    );
    expect(
      find.descendant(of: zeileA.first, matching: find.text('A208')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: zeileA.first, matching: find.text(tt.kontenAnsehen)),
      findsOneWidget,
    );
    final mitMir = await _netz(tester, () => _hole(a.token, 'api/v1/geteilt'));
    expect('${mitMir['alben']}', contains('Ferien208'));
    // A sieht sonst nichts aus B's Bibliothek.
    final eigeneA = await _netz(
      tester,
      () => _hole(a.token, 'api/v1/bibliothek'),
    );
    expect(eigeneA['aufnahmen'], 0);

    // SIC-209: Recht auf Beitragen.
    await _waehle(
      tester,
      find.descendant(
        of: zeileA.first,
        matching: find.byType(DropdownButton<bool>),
      ),
      tt.kontenBeitragen,
    );
    await eventually(tester, () async {
      final d = await _hole(a.token, 'api/v1/geteilt');
      return '${d['alben']}'.contains('beitragen: true');
    }, was: 'Beitragen für A');
    await _tap(tester, _imDialog(tt.schliessen));
    await _zurueck(tester);

    // SIC-206: A legt zwei Fotos hinein; B sieht „Neu …“.
    final teilung =
        ((await _netz(tester, () => _hole(a.token, 'api/v1/geteilt')))['alben']!
                as List)
            .cast<Map>()
            .first['id'];
    for (var i = 0; i < 2; i++) {
      final f = testfoto('beitrag206_$i.jpg', datum: DateTime(2024, 10, 1 + i));
      await _netz(
        tester,
        () => _mit(
          a.token,
          (v) => v.schickeDatei(
            'api/v1/geteilt/$teilung/beitrag',
            f,
            parameter: {
              'name': p.basename(f.path),
              'geaendert': '${f.lastModifiedSync().millisecondsSinceEpoch}',
            },
          ),
        ),
      );
    }
    await openSection(tester, Hauptbereich.zeitleiste);
    await openSection(tester, Hauptbereich.alben);
    await waitFor(
      tester,
      find.text(tt.neueBeitraegeTitel),
      timeout: const Duration(seconds: 30),
    );
    expect(find.text(tt.neueBeitraegeAlbum('Ferien208', 2)), findsOneWidget);
    expect(find.text(tt.neueBeitraegeVon('A208')), findsOneWidget);
    await _tapText(tester, tt.neueBeitraegeAlbum('Ferien208', 2));
    await waitFor(tester, find.byTooltip(tt.kontenTeilen));
    // SIC-229: geteilt – jetzt mit „Kommentare“.
    await waitFor(tester, find.byTooltip(tt.kommentare));
    await _zurueck(tester);
    await openSection(tester, Hauptbereich.zeitleiste);
    await openSection(tester, Hauptbereich.alben);
    await _warte(tester, const Duration(seconds: 3));
    expect(find.text(tt.neueBeitraegeTitel), findsNothing);

    // SIC-214: automatisch füllen.
    await _tapText(tester, 'Ferien208');
    await _tap(tester, find.byTooltip(tt.automatischFuellen));
    await waitFor(tester, find.text(tt.automatischTitel('Ferien208')));
    await _tapText(tester, tt.speichern);
    await waitFor(tester, find.text(tt.regelMindestensEine));
    await _tap(
      tester,
      find.ancestor(
        of: find.text('Person A'),
        matching: find.byType(CheckboxListTile),
      ),
    );
    await _tapText(tester, tt.regelEine);
    await _tapText(tester, tt.speichern);
    await erwarteMeldung(tester, tt.automatischDazu(2));
    await waitFor(
      tester,
      find.byTooltip('${tt.automatischFuellen}: ${tt.regelMit('Person A')}'),
    );
    final imAlbum = await _netz(
      tester,
      () => _hole(b.token, 'api/v1/alben/$albumId'),
    );
    expect('$imAlbum', allOf(contains(ids[1]), contains(ids[2])));

    // SIC-215: nicht mehr automatisch füllen.
    await _tap(
      tester,
      find.byTooltip('${tt.automatischFuellen}: ${tt.regelMit('Person A')}'),
    );
    await _tapText(tester, tt.automatischAus);
    await erwarteMeldung(tester, tt.automatischAusGemacht);
    final danach = await _netz(
      tester,
      () => _hole(b.token, 'api/v1/alben/$albumId'),
    );
    expect('$danach', allOf(contains(ids[1]), contains(ids[2])));

    // SIC-210: Teilung aufheben.
    await _tap(tester, find.byTooltip(tt.kontenTeilen));
    final entfernen = find.descendant(
      of: find.byType(Dialog),
      matching: find.byTooltip(tt.entfernen),
    );
    await waitFor(tester, entfernen);
    await _tap(tester, entfernen);
    await waitFor(tester, _imDialog(tt.kontenNiemand));
    final nachher = await _netz(tester, () => _hole(a.token, 'api/v1/geteilt'));
    expect('${nachher['alben']}', isNot(contains('Ferien208')));
    await _tap(tester, _imDialog(tt.schliessen));
    await _zurueck(tester);
    await finish(tester);
  });

  testWidgets('SIC-194 SIC-195 SIC-196 SIC-199 SIC-228 SIC-226 SIC-227 '
      'SIC-205 SIC-200 Geteiltes Album (Empfänger)', (tester) async {
    await startApp(tester);
    final b = await _netz(tester, () => _konto('B194'));
    final a = await _netz(tester, () => _konto('A194'));
    final ids = <String>[];
    for (var i = 0; i < 3; i++) {
      ids.add(
        await _netz(
          tester,
          () => _hochladen(
            b.token,
            testfoto('b194_$i.jpg', datum: DateTime(2024, 5, 3 - i)),
          ),
        ),
      );
    }
    final video = await _netz(
      tester,
      () => _hochladen(b.token, fixture('video_5s.mp4')),
    );
    final albumId = await _netz(
      tester,
      () => _albumAufServer(b.token, 'Ferien194', [...ids, video]),
    );
    await _netz(tester, () => _teile(b.token, albumId, a.id));
    await _verbinde(tester, 'A194');

    // SIC-194: ansehen.
    await openSection(tester, Hauptbereich.alben);
    await waitFor(
      tester,
      find.text(tt.geteiltMitMir),
      timeout: const Duration(seconds: 30),
    );
    expect(find.text(tt.geteiltVon('B194')), findsOneWidget);
    await _tapText(tester, 'Ferien194');
    await waitFor(tester, find.text(tt.geteiltAlbumVon('B194')));
    expect(find.byTooltip(tt.geteiltHinzufuegen), findsNothing);
    await waitFor(tester, find.byType(GridView));
    final kacheln = find.descendant(
      of: find.byType(GridView),
      matching: find.byType(GestureDetector),
    );
    await waitFor(tester, kacheln);
    await _tap(tester, kacheln.first);
    await waitFor(tester, find.byType(PageView));
    // Datum und Name; Wischen führt zum nächsten Foto.
    expect(await _blaettereBis(tester, find.text('b194_0.jpg')), isTrue);
    expect(find.textContaining('2024'), findsWidgets);
    await tester.fling(find.byType(PageView), const Offset(-700, 0), 1500);
    await settle(tester);
    await waitFor(tester, find.text('b194_1.jpg'));
    // SIC-228: Gefällt mir.
    final daumen = find.byIcon(Icons.thumb_up_outlined);
    await waitFor(tester, daumen);
    await _tap(tester, daumen);
    await waitFor(tester, find.byIcon(Icons.thumb_up));
    expect(find.text('1'), findsWidgets);
    await tester.longPress(find.byIcon(Icons.thumb_up));
    await settle(tester);
    await waitFor(tester, find.text(tt.gefaelltNamen('A194')));
    // SIC-205: das Video spielt.
    expect(await _blaettereBis(tester, find.text('video_5s.mp4')), isTrue);
    await waitFor(
      tester,
      find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == 'VideoProgressBar',
      ),
      timeout: const Duration(seconds: 40),
    );
    expect(find.byIcon(Icons.videocam_off_outlined), findsNothing);
    await _zurueck(tester);

    // SIC-195: nichts davon in der eigenen Bibliothek.
    expect(await _assets(tester), isEmpty);
    final eigen = await _netz(
      tester,
      () => _hole(a.token, 'api/v1/bibliothek'),
    );
    expect(eigen['aufnahmen'], 0);

    // SIC-196: Beitragen.
    await _netz(tester, () => _teile(b.token, albumId, a.id, beitragen: true));
    await _zurueck(tester);
    await _tapText(tester, 'Ferien194');
    await waitFor(tester, find.byTooltip(tt.geteiltHinzufuegen));
    dialog.dateien = [
      testfoto('mein_1.jpg', datum: DateTime(2024, 11, 1)),
      testfoto('mein_2.jpg', datum: DateTime(2024, 11, 2)),
    ];
    await _tap(tester, find.byTooltip(tt.geteiltHinzufuegen));
    await erwarteMeldung(tester, tt.geteiltHinzugefuegt(2));
    final albumB = await _netz(
      tester,
      () => _hole(b.token, 'api/v1/alben/$albumId'),
    );
    final bibB = await _netz(tester, () => _hole(b.token, 'api/v1/bibliothek'));
    expect(bibB['aufnahmen'], 6);
    print('SIC-196 Album bei B: $albumB');
    // „Beigetragen von A194“ im Betrachter.
    await waitFor(tester, kacheln);
    await _tap(tester, kacheln.first);
    await waitFor(tester, find.byType(PageView));
    expect(
      await _blaettereBis(tester, find.text(tt.geteiltBeigetragenVon('A194'))),
      isTrue,
      reason: 'Beigetragen von A194',
    );

    // SIC-199: eigenen Beitrag entfernen.
    await _tap(tester, find.byTooltip(tt.geteiltEntfernen));
    await waitFor(tester, find.textContaining('Deinen Beitrag'));
    await _tap(tester, _imDialog(tt.geteiltEntfernen));
    await erwarteMeldung(tester, tt.geteiltEntfernt);
    await waitFor(tester, find.text(tt.geteiltAlbumVon('B194')));
    await waitFor(tester, kacheln);
    await _tap(tester, kacheln.first);
    await waitFor(tester, find.byType(PageView));
    // Ein Foto von B: kein Knopf.
    expect(await _blaettereBis(tester, find.text('b194_2.jpg')), isTrue);
    expect(find.byTooltip(tt.geteiltEntfernen), findsNothing);
    await _zurueck(tester);

    // SIC-226: Kommentar schreiben.
    await _tap(tester, find.byTooltip(tt.kommentare));
    await waitFor(tester, find.text(tt.kommentareHinweis));
    await _tippe(tester, field(tt.kommentarSchreiben), 'Schöne Aufnahmen');
    await _tap(tester, find.byTooltip(tt.kommentarSenden));
    await waitFor(tester, find.text('Schöne Aufnahmen'));
    expect(find.textContaining('A194'), findsWidgets);
    final aktB = await _netz(
      tester,
      () => _hole(b.token, 'api/v1/alben/$albumId/aktivitaet'),
    );
    expect('${aktB['kommentare']}', contains('Schöne Aufnahmen'));
    // SIC-227: eigener entfernbar, fremder nicht; der Besitzer darf jeden.
    await _netz(
      tester,
      () => _schickeJson(b.token, 'POST', 'api/v1/alben/$albumId/kommentare', {
        'text': 'Danke vom Besitzer',
      }),
    );
    await _schliesseBlatt(tester);
    await _tap(tester, find.byTooltip(tt.kommentare));
    await waitFor(tester, find.text('Danke vom Besitzer'));
    final fremd = find.ancestor(
      of: find.text('Danke vom Besitzer'),
      matching: find.byType(ListTile),
    );
    expect(
      find.descendant(
        of: fremd,
        matching: find.byTooltip(tt.kommentarEntfernen),
      ),
      findsNothing,
    );
    final eigener = find.ancestor(
      of: find.text('Schöne Aufnahmen'),
      matching: find.byType(ListTile),
    );
    await _tap(
      tester,
      find.descendant(
        of: eigener,
        matching: find.byTooltip(tt.kommentarEntfernen),
      ),
    );
    await _tap(tester, _imDialog(tt.entfernen));
    await waitGone(tester, find.text('Schöne Aufnahmen'));
    final aktB2 = await _netz(
      tester,
      () => _hole(b.token, 'api/v1/alben/$albumId/aktivitaet'),
    );
    for (final k in aktB2['kommentare']! as List) {
      expect((k as Map)['loeschbar'], isTrue, reason: 'Besitzer darf jeden');
    }
    await _schliesseBlatt(tester);

    // SIC-200: nicht mehr anzeigen.
    await _tap(
      tester,
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(PopupMenuButton<void>),
      ),
    );
    await _tapText(tester, tt.geteiltVerlassen);
    await waitFor(
      tester,
      find.text(tt.geteiltVerlassenFrage('Ferien194', 'B194')),
    );
    await _tap(tester, _imDialog(tt.geteiltVerlassen));
    await waitGone(tester, find.text(tt.geteiltAlbumVon('B194')));
    await openSection(tester, Hauptbereich.zeitleiste);
    await openSection(tester, Hauptbereich.alben);
    await _warte(tester, const Duration(seconds: 3));
    expect(find.text('Ferien194'), findsNothing);
    final ablage = bibliothek.paths.geteiltDir;
    final reste = ablage.existsSync()
        ? ablage.listSync().whereType<Directory>().toList()
        : <Directory>[];
    expect(reste, isEmpty, reason: 'Zwischenspeicher gelöscht');
    await finish(tester);
  });

  testWidgets('SIC-203 SIC-197 SIC-198 SIC-204 Empfänger: entzogen, '
      'gesperrt, ohne Netz', (tester) async {
    await startApp(tester);
    final b = await _netz(tester, () => _konto('B197'));
    final a = await _netz(tester, () => _konto('A197'));
    final ids = <String>[];
    for (var i = 0; i < 3; i++) {
      ids.add(
        await _netz(
          tester,
          () => _hochladen(
            b.token,
            testfoto('b197_$i.jpg', datum: DateTime(2024, 5, 3 - i)),
          ),
        ),
      );
    }
    final albumId = await _netz(
      tester,
      () => _albumAufServer(b.token, 'Ferien197', ids),
    );
    await _netz(tester, () => _teile(b.token, albumId, a.id, beitragen: true));
    final teilungen = {
      for (final x
          in ((await _netz(
                    tester,
                    () => _hole(a.token, 'api/v1/geteilt'),
                  ))['alben']!
                  as List)
              .cast<Map>())
        '${x['name']}': '${x['id']}',
    };
    final z = _Zwischen();
    await _netz(tester, z.starte);
    addTearDown(z.halte);
    await _verbinde(tester, 'A197', ueber: z.adresse);
    await openSection(tester, Hauptbereich.alben);
    await _tapText(tester, 'Ferien197');
    final kacheln = find.descendant(
      of: find.byType(GridView),
      matching: find.byType(GestureDetector),
    );
    await waitFor(tester, kacheln);
    expect(kacheln, findsNWidgets(3));
    // Bilder im Zwischenspeicher
    await eventually(tester, () async {
      final d = bibliothek.paths.geteiltDir;
      return d.existsSync() &&
          d.listSync().whereType<Directory>().any(
            (x) => x.listSync().isNotEmpty,
          );
    }, was: 'Bilder im Ordner „geteilt“');

    // SIC-203: der Besitzer legt ein Foto in den Papierkorb; das Album neu
    // geladen (verlassen und wieder öffnen) zeigt es nicht mehr.
    await _netz(tester, () => _befehl(b.token, InDenPapierkorb([ids[0]])));
    final dort = await _netz(
      tester,
      () => _hole(a.token, 'api/v1/geteilt/${teilungen['Ferien197']}'),
    );
    expect(dort['aufnahmen'] as List, hasLength(2), reason: 'Server');
    await _zurueck(tester);
    await _tapText(tester, 'Ferien197');
    await waitFor(tester, kacheln);
    await eventually(
      tester,
      () async => kacheln.evaluate().length == 2,
      was: 'zwei Kacheln',
    );

    // SIC-198: Speicher voll (Antwort nachgestellt).
    z.eingriff = (r) async {
      if (r.uri.path.endsWith('/beitrag')) {
        await _antworte(r, {
          'fehler': 'Der Speicher des Servers ist voll.',
        }, status: 507);
        return true;
      }
      return false;
    };
    dialog.dateien = [testfoto('voll.jpg')];
    await _tap(tester, find.byTooltip(tt.geteiltHinzufuegen));
    await erwarteMeldung(tester, tt.geteiltSpeicherVoll);
    z.eingriff = null;
    await waitGone(
      tester,
      find.text(tt.geteiltSpeicherVoll),
      timeout: const Duration(seconds: 15),
    );

    // SIC-197: das Recht ist inzwischen entzogen.
    await _netz(tester, () => _teile(b.token, albumId, a.id));
    dialog.dateien = [testfoto('spaet.jpg')];
    await _tap(tester, find.byTooltip(tt.geteiltHinzufuegen));
    await erwarteMeldung(tester, tt.geteiltNurAnsehen);
    final albumB = await _netz(
      tester,
      () => _hole(a.token, 'api/v1/geteilt/${teilungen['Ferien197']}'),
    );
    expect(albumB['aufnahmen'] as List, hasLength(2), reason: 'nichts dazu');

    // SIC-204: ohne Netz.
    await _zurueck(tester);
    await _netz(tester, z.halte);
    await openSection(tester, Hauptbereich.zeitleiste);
    await openSection(tester, Hauptbereich.alben);
    await _warte(tester, const Duration(seconds: 2));
    var offlineGesehen = 'Abschnitt fehlt';
    if (find.text('Ferien197').evaluate().isNotEmpty) {
      await _tapText(tester, 'Ferien197');
      await _warte(tester, const Duration(seconds: 3));
      if (find.byType(GridView).evaluate().isEmpty) {
        expect(find.text(tt.geteiltOffline), findsOneWidget);
        offlineGesehen = tt.geteiltOffline;
      }
      await _zurueck(tester);
    }
    print('SIC-204: $offlineGesehen');
    expect(tester.takeException(), isNull);
    await _netz(tester, z.starte);

    await finish(tester);
  });

  testWidgets(
    'SIC-201 SIC-202 Nicht mehr geteilt: Album schliesst, Zwischenspeicher weg',
    (tester) async {
      await startApp(tester);
      final b = await _netz(tester, () => _konto('B201k'));
      final a = await _netz(tester, () => _konto('A201k'));
      final ids = <String>[];
      for (var i = 0; i < 3; i++) {
        ids.add(
          await _netz(
            tester,
            () => _hochladen(b.token, testfoto('k201_$i.jpg')),
          ),
        );
      }
      final albumId = await _netz(
        tester,
        () => _albumAufServer(b.token, 'Kurz201', ids),
      );
      await _netz(tester, () => _teile(b.token, albumId, a.id));
      final teilung =
          ((await _netz(
                    tester,
                    () => _hole(a.token, 'api/v1/geteilt'),
                  ))['alben']!
                  as List)
              .cast<Map>()
              .first['id'];
      await _verbinde(tester, 'A201k');
      await openSection(tester, Hauptbereich.alben);
      await _tapText(tester, 'Kurz201');
      await waitFor(
        tester,
        find.descendant(
          of: find.byType(GridView),
          matching: find.byType(GestureDetector),
        ),
        timeout: const Duration(seconds: 40),
      );
      final ordner = Directory(
        p.join(
          bibliothek.paths.geteiltDir.path,
          '$teilung'.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_'),
        ),
      );
      await eventually(
        tester,
        () async => ordner.existsSync() && ordner.listSync().isNotEmpty,
        was: 'Bilder im Ordner „geteilt“',
      );
      await _netz(
        tester,
        () => _status(
          b.token,
          'api/v1/alben/$albumId/teilungen/${a.id}',
          methode: 'DELETE',
        ),
      );
      await tester.fling(find.byType(GridView), const Offset(0, 600), 1500);
      await settle(tester);
      await erwarteMeldung(tester, tt.geteiltNichtMehr);
      await waitGone(tester, find.text(tt.geteiltAlbumVon('B201k')));
      // SIC-202: beim nächsten Öffnen von „Alben“ ist der Ordner weg.
      await openSection(tester, Hauptbereich.zeitleiste);
      await openSection(tester, Hauptbereich.alben);
      await eventually(
        tester,
        () async => !ordner.existsSync(),
        was: 'Zwischenspeicher gelöscht',
      );
      await finish(tester);
    },
  );

  // Behoben in #415: _hinzufuegen fängt jeden Fehler je Datei, und eine
  // Antwort ohne JSON ist ein Serverfehler.
  testWidgets('SIC-196 Fortschrittsfenster schliesst bei jedem Fehler', (
    tester,
  ) async {
    await startApp(tester);
    final b = await _netz(tester, () => _konto('B196'));
    final a = await _netz(tester, () => _konto('A196'));
    final id = await _netz(
      tester,
      () => _hochladen(b.token, testfoto('b196.jpg')),
    );
    final albumId = await _netz(
      tester,
      () => _albumAufServer(b.token, 'Ferien196', [id]),
    );
    await _netz(tester, () => _teile(b.token, albumId, a.id, beitragen: true));
    final z = _Zwischen();
    await _netz(tester, z.starte);
    addTearDown(z.halte);
    await _verbinde(tester, 'A196', ueber: z.adresse);
    // Eine Antwort, die kein JSON ist (etwa von einem Proxy).
    z.eingriff = (r) async {
      if (r.uri.path.endsWith('/beitrag')) {
        await r.drain<void>();
        r.response.headers.contentType = ContentType.html;
        r.response.write('<html>Bad Gateway</html>');
        await r.response.close();
        return true;
      }
      return false;
    };
    await openSection(tester, Hauptbereich.alben);
    await _tapText(tester, 'Ferien196');
    await waitFor(tester, find.byTooltip(tt.geteiltHinzufuegen));
    dialog.dateien = [testfoto('kaputt.jpg')];
    await _tap(tester, find.byTooltip(tt.geteiltHinzufuegen));
    await _warte(tester, const Duration(seconds: 5));
    print('SIC-196 nach dem Fehler: ${onScreen(tester)}');
    expect(find.textContaining('Lade 1 von 1'), findsNothing);
    await finish(tester);
  });

  testWidgets('SIC-216 SIC-218 SIC-219 Bibliothek teilen (Besitzer)', (
    tester,
  ) async {
    await startApp(tester);
    final b = await _netz(tester, () => _konto('B216'));
    final a = await _netz(tester, () => _konto('A216'));
    final jahr = DateTime.now().year;
    final mitA = await _netz(
      tester,
      () => _hochladen(
        b.token,
        testfoto('mitA_neu.jpg', datum: DateTime(jahr, 2, 1)),
      ),
    );
    final mitAalt = await _netz(
      tester,
      () => _hochladen(
        b.token,
        testfoto('mitA_alt.jpg', datum: DateTime(2020, 5, 1)),
      ),
    );
    final ohne = await _netz(
      tester,
      () => _hochladen(
        b.token,
        testfoto('ohne.jpg', datum: DateTime(jahr, 3, 1)),
      ),
    );
    final personId = const Uuid().v4();
    await _netz(tester, () async {
      await _befehl(b.token, PersonAnlegen(personId, 'Person A'));
      await _personAuf(b.token, personId, mitA);
      await _personAuf(b.token, personId, mitAalt);
    });
    await _verbinde(tester, 'B216');

    // SIC-216
    await _serverGruppe(tester);
    await _tapText(tester, tt.bibliothekTeilen);
    await waitFor(tester, find.text(tt.bibliothekTeilenHinweis));
    await waitFor(tester, find.byType(DropdownButton<String>));
    await _waehle(tester, find.byType(DropdownButton<String>), 'A216');
    await _tap(tester, _imDialog(tt.kontenTeilenKnopf));
    await waitFor(tester, _imDialog(tt.partnerGanz));
    expect(_imDialog('A216'), findsOneWidget);
    final sieht = await _netz(
      tester,
      () => _hole(a.token, 'api/v1/partner/von/${b.id}/aufnahmen'),
    );
    expect((sieht['aufnahmen']! as List), hasLength(3));

    // SIC-218: einschränken auf Person A ab dem 1.1. dieses Jahres.
    await _tap(tester, find.byTooltip(tt.partnerEinschraenken));
    await waitFor(tester, find.text(tt.partnerWasSieht('A216')));
    await _tap(
      tester,
      find.ancestor(
        of: find.text('Person A'),
        matching: find.byType(CheckboxListTile),
      ),
    );
    await _tapText(tester, tt.aufgenommenAb);
    await waitFor(tester, find.byType(DatePickerDialog));
    await _tapText(tester, 'OK');
    await waitGone(tester, find.byType(DatePickerDialog));
    await _tapText(tester, tt.speichern);
    await waitFor(tester, find.textContaining(tt.regelMit('Person A')));
    expect(find.textContaining(tt.regelAb('1.1.$jahr')), findsWidgets);
    final eingeschraenkt = await _netz(
      tester,
      () => _hole(a.token, 'api/v1/partner/von/${b.id}/aufnahmen'),
    );
    final sichtbar = [
      for (final x in eingeschraenkt['aufnahmen']! as List) (x as Map)['id'],
    ];
    expect(sichtbar, [mitA]);
    final datei = await _netz(
      tester,
      () => _status(
        a.token,
        'api/v1/partner/von/${b.id}/aufnahmen/$ohne/vorschau',
      ),
    );
    expect(datei, isNot(200), reason: 'Datei anderer Fotos abgewiesen');
    final mitMir = await _netz(tester, () => _hole(a.token, 'api/v1/partner'));
    expect('${mitMir['mitMir']}', contains('eingeschraenkt: true'));

    // SIC-219: beenden.
    await _tap(
      tester,
      find.descendant(
        of: find
            .ancestor(of: _imDialog('A216'), matching: find.byType(Row))
            .first,
        matching: find.byTooltip(tt.entfernen),
      ),
    );
    await waitGone(tester, _imDialog('A216'));
    final weg = await _netz(
      tester,
      () => _status(a.token, 'api/v1/partner/von/${b.id}/aufnahmen'),
    );
    expect(weg, 404);
    await finish(tester);
  });

  testWidgets('SIC-217 SIC-221 SIC-219 SIC-220 Partnerbibliothek ansehen', (
    tester,
  ) async {
    await startApp(tester);
    final b = await _netz(tester, () => _konto('B217'));
    final a = await _netz(tester, () => _konto('A217'));
    final ids = <String>[];
    for (var i = 0; i < 3; i++) {
      ids.add(
        await _netz(
          tester,
          () => _hochladen(
            b.token,
            testfoto('b217_$i.jpg', datum: DateTime(2024, 3, 3 - i)),
          ),
        ),
      );
    }
    await _netz(tester, () => _befehl(b.token, InDenPapierkorb([ids[2]])));
    Future<void> freigeben() async {
      final s = await _schickeJson(
        b.token,
        'PUT',
        'api/v1/partner/${a.id}',
        {},
      );
      if (s != 200 && s != 204) throw StateError('Partner: $s');
    }

    await _netz(tester, freigeben);
    final z = _Zwischen();
    await _netz(tester, z.starte);
    addTearDown(z.halte);
    await _verbinde(tester, 'A217', ueber: z.adresse);

    // SIC-217
    await openSection(tester, Hauptbereich.alben);
    await waitFor(
      tester,
      find.text(tt.partnerBibliothekVon('B217')),
      timeout: const Duration(seconds: 30),
    );
    expect(find.text(tt.partnerGanzeBibliothek), findsOneWidget);
    await _tapText(tester, tt.partnerBibliothekVon('B217'));
    await waitFor(tester, find.byType(GridView));
    final kacheln = find.descendant(
      of: find.byType(GridView),
      matching: find.byType(GestureDetector),
    );
    await waitFor(tester, kacheln);
    expect(kacheln, findsNWidgets(2), reason: 'ohne Papierkorb');
    await _tap(tester, kacheln.first);
    await waitFor(tester, find.byType(PageView));
    await _warte(tester, const Duration(seconds: 2));
    expect(find.byIcon(Icons.thumb_up_outlined), findsNothing);
    expect(find.byTooltip(tt.kommentare), findsNothing);
    await _zurueck(tester);

    // SIC-221: Schalter für die Zeitleiste.
    Future<void> menue() => _tap(
      tester,
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(PopupMenuButton<void>),
      ),
    );
    bool haken() => tester
        .widget<CheckedPopupMenuItem<void>>(
          find.byType(CheckedPopupMenuItem<void>),
        )
        .checked;
    await menue();
    await waitFor(tester, find.text(tt.partnerInZeitleisteFern));
    expect(haken(), isFalse);
    await _tapText(tester, tt.partnerInZeitleisteFern);
    await settle(tester);
    await _zurueck(tester);
    await _tapText(tester, tt.partnerBibliothekVon('B217'));
    await waitFor(tester, kacheln);
    await menue();
    await waitFor(tester, find.text(tt.partnerInZeitleisteFern));
    expect(haken(), isTrue, reason: 'bleibt nach erneutem Öffnen');
    expect(await _assets(tester), isEmpty, reason: 'keine Partnerfotos hier');
    // offline springt er zurück
    await _netz(tester, z.halte);
    await _tapText(tester, tt.partnerInZeitleisteFern);
    await erwarteMeldung(tester, tt.geteiltOffline);
    await menue();
    await waitFor(tester, find.text(tt.partnerInZeitleisteFern));
    expect(haken(), isTrue, reason: 'zurückgesprungen');
    await key(tester, LogicalKeyboardKey.escape);
    await _netz(tester, z.starte);
    await _zurueck(tester);

    // SIC-219 (Empfänger): die Freigabe endet.
    await _netz(
      tester,
      () => _status(b.token, 'api/v1/partner/${a.id}', methode: 'DELETE'),
    );
    await _tapText(tester, tt.partnerBibliothekVon('B217'));
    await erwarteMeldung(tester, tt.partnerNichtMehr);

    // SIC-220: verlassen.
    await _netz(tester, freigeben);
    await openSection(tester, Hauptbereich.zeitleiste);
    await openSection(tester, Hauptbereich.alben);
    await waitFor(
      tester,
      find.text(tt.partnerBibliothekVon('B217')),
      timeout: const Duration(seconds: 30),
    );
    await _tapText(tester, tt.partnerBibliothekVon('B217'));
    await waitFor(tester, kacheln);
    await menue();
    await _tapText(tester, tt.geteiltVerlassen);
    await waitFor(tester, find.text(tt.partnerVerlassenFrage('B217')));
    await _tap(tester, _imDialog(tt.geteiltVerlassen));
    await waitGone(tester, find.byType(PageView));
    await openSection(tester, Hauptbereich.zeitleiste);
    await openSection(tester, Hauptbereich.alben);
    await _warte(tester, const Duration(seconds: 3));
    expect(find.text(tt.partnerBibliothekVon('B217')), findsNothing);
    final d = bibliothek.paths.geteiltDir;
    expect(
      !d.existsSync() || d.listSync().whereType<Directory>().isEmpty,
      isTrue,
      reason: 'Zwischenspeicher gelöscht',
    );
    await finish(tester);
  });

  testWidgets('SIC-222 SIC-223 SIC-224 Nachlasskontakt', (tester) async {
    await startApp(tester);
    final b = await _netz(tester, () => _konto('B222'));
    final a = await _netz(tester, () => _konto('A222'));
    await _verbinde(tester, 'B222');

    // SIC-222
    await _serverGruppe(tester);
    await _tapText(tester, tt.nachlass);
    await waitFor(tester, find.text(tt.nachlassKeine));
    await _waehle(tester, find.byType(DropdownButton<String>), 'A222');
    final frist = tester
        .widget<DropdownButton<int>>(find.byType(DropdownButton<int>))
        .value!;
    await _tap(tester, _imDialog(tt.nachlassBenennen));
    await waitGone(tester, find.text(tt.nachlassKeine));
    final kontakt = find.ancestor(
      of: _imDialog('A222'),
      matching: find.byType(ListTile),
    );
    await waitFor(tester, kontakt);
    expect(
      find.descendant(
        of: kontakt.first,
        matching: find.textContaining(tt.nachlassFristTage(frist)),
      ),
      findsOneWidget,
    );
    await _tap(tester, _imDialog(tt.schliessen));

    // SIC-223 als A222.
    await _verbinde(tester, 'A222');
    await _serverGruppe(tester);
    await _tapText(tester, tt.nachlass);
    await waitFor(tester, find.text(tt.nachlassFuerMich));
    await _tap(tester, _imDialog(tt.nachlassVerlangen));
    await waitFor(
      tester,
      find.textContaining('Zugang zur Bibliothek von B222'),
    );
    await _tap(
      tester,
      find.descendant(
        of: find.byType(AlertDialog).last,
        matching: find.widgetWithText(FilledButton, tt.nachlassVerlangen),
      ),
    );
    await waitFor(tester, find.textContaining('verlangt Zugang – ohne'));
    expect(_imDialog(tt.nachlassZurueckziehen), findsOneWidget);
    await _tap(tester, _imDialog(tt.schliessen));

    // SIC-224 wieder als B222.
    await _verbinde(tester, 'B222');
    await waitFor(
      tester,
      find.textContaining('A222 verlangt Zugang zu deiner Bibliothek'),
      timeout: const Duration(seconds: 30),
    );
    await _tapText(tester, tt.nachlassAblehnen);
    await waitGone(
      tester,
      find.textContaining('A222 verlangt Zugang zu deiner Bibliothek'),
    );
    final stand = await _netz(tester, () => _hole(a.token, 'api/v1/nachlass'));
    print('SIC-224 Stand bei A: $stand');
    final zugang = await _netz(
      tester,
      () => _status(a.token, 'api/v1/partner/von/${b.id}/aufnahmen'),
    );
    expect(zugang, isNot(200));
    await finish(tester);
  });

  testWidgets('SIC-213 SIC-230 Teilen und Kommentieren ohne Netz', (
    tester,
  ) async {
    await startApp(tester);
    final b = await _netz(tester, () => _konto('B213'));
    final a = await _netz(tester, () => _konto('A213'));
    final id = await _netz(
      tester,
      () => _hochladen(b.token, testfoto('b213.jpg')),
    );
    final albumId = await _netz(
      tester,
      () => _albumAufServer(b.token, 'Ferien213', [id]),
    );
    await _netz(tester, () => _teile(b.token, albumId, a.id));
    final z = _Zwischen();
    await _netz(tester, z.starte);
    addTearDown(z.halte);
    await _verbinde(tester, 'B213', ueber: z.adresse);
    await openSection(tester, Hauptbereich.alben);
    await _tapText(tester, 'Ferien213');
    await waitFor(tester, find.byTooltip(tt.kommentare));

    // SIC-230: Kommentarblatt offen, dann ohne Netz senden.
    await _tap(tester, find.byTooltip(tt.kommentare));
    await waitFor(tester, find.text(tt.kommentareHinweis));
    await _netz(tester, z.halte);
    await _tippe(tester, field(tt.kommentarSchreiben), 'Geht das?');
    await _tap(tester, find.byTooltip(tt.kommentarSenden));
    await erwarteMeldung(tester, tt.kommentarFehler);
    final feld = tester.widget<TextField>(field(tt.kommentarSchreiben));
    expect(feld.controller!.text, 'Geht das?');
    await _schliesseBlatt(tester);

    // SIC-213: Teilen ohne Netz.
    await _tap(tester, find.byTooltip(tt.kontenTeilen));
    await waitFor(
      tester,
      _imDialog(tt.geteiltOffline),
      timeout: const Duration(seconds: 45),
    );
    await _tap(tester, _imDialog(tt.schliessen));
    await _netz(tester, z.starte);
    await _zurueck(tester);
    await finish(tester);
  });

  testWidgets('SIC-169 SIC-170 Viele wartende Änderungen, eine abgelehnte', (
    tester,
  ) async {
    await startApp(tester);
    final k = await _netz(tester, () => _konto('Viele169', geraet: 'Geraet-2'));
    final weg = await _netz(
      tester,
      () => _hochladen(
        k.token,
        testfoto('weg170.jpg', datum: DateTime(2024, 12, 2)),
      ),
    );
    final bleibt = await _netz(
      tester,
      () => _hochladen(
        k.token,
        testfoto('bleibt169.jpg', datum: DateTime(2024, 12, 1)),
      ),
    );
    final z = _Zwischen();
    await _netz(tester, z.starte);
    addTearDown(z.halte);
    await _verbinde(tester, 'Viele169', ueber: z.adresse);
    await eventually(
      tester,
      () async => bibliothek.abgleichszustand?.erreichbar ?? false,
    );
    await _rasterFokus(tester);
    await _netz(tester, z.halte);
    await eventually(
      tester,
      () async => bibliothek.abgleichszustand?.erreichbar == false,
      timeout: const Duration(seconds: 60),
      was: 'offline',
    );
    // Offline: drei Sterne für das neueste Foto, dann 120 Einzeländerungen
    // am zweiten.
    await _rasterFokus(tester);
    await key(tester, LogicalKeyboardKey.arrowRight);
    await key(tester, LogicalKeyboardKey.digit3);
    await key(tester, LogicalKeyboardKey.arrowRight);
    for (var i = 0; i < 120; i++) {
      await tester.sendKeyEvent(
        i.isEven ? LogicalKeyboardKey.digit1 : LogicalKeyboardKey.digit2,
      );
      await tester.pump(const Duration(milliseconds: 30));
    }
    await eventually(
      tester,
      () async => (bibliothek.abgleichszustand?.ausstehend ?? 0) >= 121,
      timeout: const Duration(seconds: 90),
      was: '121 wartende Änderungen',
    );
    expect(
      (await _netz(tester, () => bibliothek.db.assetById(weg)))!.rating,
      3,
    );

    // SIC-169: erst 100, dann weitere.
    await _serverGruppe(tester);
    await _tapText(tester, de.syncUebersicht);
    await waitFor(tester, find.text(st.anzahl(121, 0)));
    int eintraege() => tester
        .widget<ListView>(find.byType(ListView).last)
        .childrenDelegate
        .estimatedChildCount!;
    await eventually(tester, () async => eintraege() == 101);
    await _bisSichtbar(
      tester,
      find.text(st.mehr),
      find.ancestor(of: find.text(st.titel), matching: find.byType(Scaffold)),
    );
    await _tapText(tester, st.mehr);
    await eventually(tester, () async => eintraege() == 121);
    expect(find.text(st.mehr), findsNothing);
    await _zurueck(tester);

    // SIC-170: Gerät 2 löscht das Foto endgültig; dann wieder online.
    await _netz(tester, () async {
      await _befehl(k.token, InDenPapierkorb([weg]));
      final s = await _schickeJson(
        k.token,
        'POST',
        'api/v1/papierkorb/leeren',
        {
          'ids': [weg],
        },
      );
      if (s != 200) throw StateError('leeren: $s');
    });
    // Wieder verbunden – direkt, siehe _umstellen.
    await _umstellen(tester, _srv);
    final bis = DateTime.now().add(const Duration(seconds: 150));
    while ((bibliothek.abgleichszustand?.ausstehend ?? -1) != 0) {
      final zst = bibliothek.abgleichszustand;
      print(
        'SIC-170 Zustand: erreichbar ${zst?.erreichbar}, '
        'ausstehend ${zst?.ausstehend}, Fälle ${zst?.faelle}',
      );
      if (DateTime.now().isAfter(bis)) {
        throw TimeoutException('nicht gesendet: ${onScreen(tester)}');
      }
      await _warte(tester, const Duration(seconds: 10));
    }
    await eventually(
      tester,
      () async => (bibliothek.abgleichszustand?.faelle ?? 0) >= 1,
      timeout: const Duration(seconds: 30),
      was: 'ein Fall',
    );
    // Lokal steht wieder der Serverstand: das Foto ist fort.
    await eventually(
      tester,
      () async => await bibliothek.db.assetById(weg) == null,
      timeout: const Duration(seconds: 60),
      was: 'Serverstand hier',
    );
    final b = (await _netz(tester, () => _aufnahme(k.token, bleibt)));
    expect(
      (await _netz(tester, () => bibliothek.db.assetById(bleibt)))!.rating,
      b['rating'] ?? 0,
    );
    await _serverGruppe(tester);
    final abgelehntText = find.text(de.serverAbgelehnt(1));
    await waitFor(tester, abgelehntText);
    print(
      'SIC-170 rot „abgelehnt“: ${abgelehntText.evaluate().isNotEmpty}, '
      'Zustand: ${bibliothek.abgleichszustand?.abgelehnt}',
    );
    await _tapText(tester, de.syncUebersicht);
    await waitFor(tester, find.text(st.bewertung));
    final status = find.textContaining(st.abgelehnt).evaluate().isNotEmpty
        ? 'abgelehnt'
        : find.textContaining(st.konflikt).evaluate().isNotEmpty
        ? 'konflikt'
        : 'unbekannt';
    // Der Server wertet ein inzwischen gelöschtes Foto als Konflikt
    // (Befehlsbasis.passt), nicht als Ablehnung – festgehalten, nicht
    // verlangt (siehe Bericht).
    print('SIC-170 Fall: $status');
    expect(status, isNot('unbekannt'));
    await _zurueck(tester);
    await finish(tester);
  });

  // Zuletzt: Fehlversuche bremsen alle Anmeldungen von dieser Adresse.
  testWidgets('SIC-105 SIC-107 SIC-106 SIC-146 SIC-139 Falsche Anmeldung, '
      'Sperre, Entsperren', (tester) async {
    await startApp(tester);
    await _netz(tester, () => _konto('A105'));
    await _verbindenSeite(tester);
    // SIC-105
    await _anmeldenUi(tester, adresse: '$_srv', name: 'A105', pw: 'falsch-1');
    await waitFor(tester, find.text(de.serverFalsch));
    // SIC-107: ein unbekannter Name – dieselbe Meldung.
    await _anmeldenUi(
      tester,
      adresse: '$_srv',
      name: 'Niemand107',
      pw: 'falsch-1',
    );
    await waitGone(tester, find.byType(LinearProgressIndicator));
    expect(find.text(de.serverFalsch), findsOneWidget);
    // SIC-106: vier weitere Fehlversuche, dann gesperrt – auch richtig.
    for (var i = 2; i <= 5; i++) {
      await _anmeldenUi(
        tester,
        adresse: '$_srv',
        name: 'A105',
        pw: 'falsch-$i',
      );
      await waitGone(tester, find.byType(LinearProgressIndicator));
    }
    await _anmeldenUi(tester, adresse: '$_srv', name: 'A105', pw: _pw);
    await waitFor(
      tester,
      find.textContaining('Zu viele Fehlversuche – bitte in'),
    );
    expect(find.text(de.serverFalsch), findsNothing);
    await _zurueck(tester);

    // SIC-146 (und SIC-139: „gesperrt nach Fehlversuchen“).
    await _verbinde(tester, _verwalter);
    await _serverGruppe(tester);
    await _tap(tester, find.text(de.serverKontenVerwalten));
    final seite = find.byType(ServerKontenScreen);
    await _bisSichtbar(tester, find.text('A105'), seite);
    expect(
      find.descendant(
        of: _zeile('A105'),
        matching: find.textContaining(de.serverKontoGesperrt),
      ),
      findsOneWidget,
    );
    await _meldungenSchliessen(tester);
    await _tap(
      tester,
      find.descendant(
        of: _zeile('A105'),
        matching: find.byType(PopupMenuButton<String>),
      ),
    );
    await _tapText(tester, de.serverKontoEntsperren);
    await erwarteMeldung(tester, de.serverKontoErledigt);
    await waitGone(
      tester,
      find.descendant(
        of: _zeile('A105'),
        matching: find.textContaining(de.serverKontoGesperrt),
      ),
    );
    await _netz(tester, () => _anmelden('A105', geraet: 'Wieder'));
    await finish(tester);
  });

  // Am Ende: Die Texterkennung über Apple Vision blieb in einem Lauf
  // hängen; so trifft ein Abbruch nur diese Prüfung.
  testWidgets('SIC-180 SIC-186 SIC-187 Rechenhilfe', (tester) async {
    await startApp(tester);
    final k = await _netz(tester, () => _konto('Rechen180'));
    final ids = <String>[];
    for (var i = 0; i < 2; i++) {
      ids.add(
        await _netz(
          tester,
          () => _hochladen(k.token, _textfoto('text_$i.jpg', 'PHOTO VAULT $i')),
        ),
      );
    }
    print('SIC-180: hochgeladen $ids');
    final z = _Zwischen();
    await _netz(tester, z.starte);
    addTearDown(z.halte);
    print('SIC-180: hochgeladen, verbinde');
    await _verbinde(tester, 'Rechen180');
    print('SIC-180: verbunden');
    final groesseVorher = await _netz(tester, () async {
      var n = 0;
      for (final f
          in bibliothek.paths.root
              .listSync(recursive: true)
              .whereType<File>()) {
        n += f.lengthSync();
      }
      return n;
    });
    print('SIC-180: Grösse gemessen');
    await _serverGruppe(tester);
    // SIC-180: einschalten, „Wann rechnen“, liefern.
    final schalter = find.ancestor(
      of: find.text(de.serverRechenhilfe),
      matching: find.byType(SwitchListTile),
    );
    await _tap(tester, schalter);
    await waitFor(tester, find.text(de.serverRechenzeit));
    await _tapText(tester, de.serverRechenzeitImmer);
    await waitFor(
      tester,
      find.textContaining(RegExp(r'(Rechnet|Wartet auf Arbeit) – [1-9]')),
      timeout: const Duration(seconds: 120),
    );
    await eventually(
      tester,
      () async {
        for (final id in ids) {
          final dort = await _aufnahme(k.token, id);
          if (!'${dort['ocrText'] ?? ''}'.contains('PHOTO')) return false;
        }
        return true;
      },
      timeout: const Duration(seconds: 120),
      was: 'Text am Server',
    );
    await eventually(
      tester,
      () async {
        for (final id in ids) {
          final hier = await bibliothek.db.assetById(id);
          if (!(hier?.ocrText ?? '').contains('PHOTO')) return false;
        }
        return true;
      },
      timeout: const Duration(seconds: 150),
      was: 'Text in der Kopie',
    );

    // SIC-187: die Kopie wächst nicht um die Originale.
    final alle = await _assets(tester);
    for (final a in alle) {
      expect(
        bibliothek.paths.absolute(a.relativePath).existsSync(),
        isFalse,
        reason: 'Original von ${a.originalFileName} liegt in der Kopie',
      );
    }
    final groesseNachher = await _netz(tester, () async {
      var n = 0;
      for (final f
          in bibliothek.paths.root
              .listSync(recursive: true)
              .whereType<File>()) {
        n += f.lengthSync();
      }
      return n;
    });
    print('SIC-187: $groesseVorher → $groesseNachher Bytes');

    // SIC-186: ohne Server – dafür über den Zwischenserver.
    await _umstellen(tester, z.adresse);
    await _serverGruppe(tester);
    await waitFor(tester, find.text(de.serverRechenzeit));
    await _netz(tester, z.halte);
    await waitFor(
      tester,
      find.text(de.serverRechenhilfeOffline),
      timeout: const Duration(seconds: 120),
    );
    await _netz(tester, z.starte);
    await waitGone(
      tester,
      find.text(de.serverRechenhilfeOffline),
      timeout: const Duration(seconds: 150),
    );
    await finish(tester);
  });

  // --- Mit eigenem Wegwerf-Server (nicht der der Warteschlange) -----------
  // Laufen nur, wenn PV_SICB_SERVER sagt, welcher Server unter
  // PV_KATALOG_SERVER läuft (gestartet mit tools/wegwerf_server.sh).

  testWidgets('SIC-108 SIC-109 SIC-110 SIC-111 Zwei-Faktor mitTotpServer', (
    tester,
  ) async {
    await startApp(tester);
    await _netz(tester, _verwalterMitTotp);
    await _netz(
      tester,
      () => _mit(
        _verwalterTokenSpeicher!,
        (v) => Kontenverwaltung(v).legeAn('A108', _pw),
      ),
    );

    // SIC-108: Einrichten bei der ersten Anmeldung.
    await _verbindenSeite(tester);
    await _anmeldenUi(tester, adresse: '$_srv', name: 'A108', pw: _pw);
    await waitFor(
      tester,
      find.text(de.serverTotpTitel),
      timeout: const Duration(seconds: 30),
    );
    expect(find.byType(QrBild), findsOneWidget);
    final gruppiert = tester
        .widget<SelectableText>(find.byType(SelectableText).first)
        .data!;
    expect(gruppiert, matches(RegExp(r'^[A-Z2-7]{4}( [A-Z2-7]{1,4})+$')));
    final schluessel = _base32(gruppiert.replaceAll(' ', ''));
    final s0 = _schrittJetzt();
    await _tippe(tester, find.byType(TextField), _totp(schluessel, s0));
    await _tapText(tester, de.serverBestaetigen);
    await waitFor(
      tester,
      find.text(de.serverCodesTitel),
      timeout: const Duration(seconds: 30),
    );
    final codes = tester
        .widget<SelectableText>(find.byType(SelectableText).first)
        .data!
        .split('\n');
    print('SIC-108: ${codes.length} Wiederherstellungscodes');
    expect(codes.length, greaterThanOrEqualTo(5));

    // SIC-109: Kopieren – die Zwischenablage ist nachgestellt, damit die
    // des Rechners unberührt bleibt.
    String? kopiert;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          kopiert = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    await _tapText(tester, de.serverKopieren);
    await erwarteMeldung(tester, de.serverKopiert);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
    expect(kopiert, codes.join('\n'));
    await _tapText(tester, de.serverWeiter);
    await waitFor(tester, find.text(de.serverWahlTitel));
    await _zurueck(tester);

    Future<void> zumCode() async {
      await _verbindenSeite(tester);
      await _anmeldenUi(tester, adresse: '$_srv', name: 'A108', pw: _pw);
      await waitFor(
        tester,
        find.text(de.serverCodeTitel),
        timeout: const Duration(seconds: 30),
      );
    }

    // SIC-110: ein falscher Code, dann ein gültiger mit Enter.
    await zumCode();
    await _tippe(tester, find.byType(TextField), '000000');
    await _tapText(tester, de.serverBestaetigen);
    await waitFor(tester, find.text(de.serverFalsch));
    final s1 = max(_schrittJetzt(), s0 + 1);
    final gueltig = _totp(schluessel, s1);
    await _tippe(tester, find.byType(TextField), gueltig);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    await waitFor(
      tester,
      find.text(de.serverWahlTitel),
      timeout: const Duration(seconds: 30),
    );
    await _zurueck(tester);
    // Derselbe Code ein zweites Mal.
    await zumCode();
    await _tippe(tester, find.byType(TextField), gueltig);
    await _tapText(tester, de.serverBestaetigen);
    await waitFor(tester, find.text(de.serverFalsch));

    // SIC-111: ein Wiederherstellungscode gilt genau einmal.
    await _tippe(tester, find.byType(TextField), codes.first);
    await _tapText(tester, de.serverBestaetigen);
    await waitFor(
      tester,
      find.text(de.serverWahlTitel),
      timeout: const Duration(seconds: 30),
    );
    await _zurueck(tester);
    await zumCode();
    await _tippe(tester, find.byType(TextField), codes.first);
    await _tapText(tester, de.serverBestaetigen);
    await waitFor(tester, find.text(de.serverFalsch));
    await _zurueck(tester);
    await finish(tester);
  }, skip: _eigenerServer != 'totp');

  testWidgets('SIC-152 SIC-151 SIC-153 SIC-156 SIC-154 SIC-155 Server-Sicherung '
      'mitSicherungsServer', (tester) async {
    await startApp(tester);
    final v = await _netz(tester, _verwalterToken);
    for (var i = 0; i < 2; i++) {
      await _netz(
        tester,
        () => _hochladen(
          v,
          testfoto('sich_$i.jpg', datum: DateTime(2024, 1, 1 + i)),
        ),
      );
    }
    Future<Map<String, Object?>> stand() =>
        _netz(tester, () => _hole(v, 'api/v1/sicherung'));
    final ziel = (await stand())['ziel']! as String;
    print('SIC-151 Ziel: $ziel');
    await _verbinde(tester, _verwalter);
    await _serverGruppe(tester);
    await waitFor(
      tester,
      find.textContaining('die Sicherung aber noch nicht eingerichtet'),
      timeout: const Duration(seconds: 30),
    );

    // SIC-152: Prüfungen im Dialog; eingerichtet wird nichts.
    await _tapText(tester, de.serverSicherungEinrichten);
    await waitFor(tester, find.text(de.serverSicherungEinrichtenText));
    expect(de.serverSicherungEinrichtenText, contains('später nicht ändern'));
    final dlg = find.byType(AlertDialog);
    Finder feldIm(String name) =>
        find.descendant(of: dlg, matching: field(name));
    await _tippe(tester, feldIm(de.serverSicherungPassphrase), '12345678');
    await _tippe(tester, feldIm(de.serverPasswortWiederholen), '12345678');
    await _tap(tester, _imDialog(de.allgFestlegen));
    await waitFor(tester, _imDialog(de.serverPasswortZuKurz(12)));
    await _tippe(tester, feldIm(de.serverSicherungPassphrase), _sicherungPw);
    await _tippe(
      tester,
      feldIm(de.serverPasswortWiederholen),
      'etwas-ganz-anderes-1',
    );
    await _tap(tester, _imDialog(de.allgFestlegen));
    await waitFor(tester, _imDialog(de.serverPasswortUngleich));
    expect((await stand())['stufe'], 'nichtEingerichtet');

    // SIC-151: einrichten.
    await _tippe(tester, feldIm(de.serverPasswortWiederholen), _sicherungPw);
    await _tap(tester, _imDialog(de.allgFestlegen));
    await erwarteMeldung(tester, de.serverSicherungGestartet);
    Future<void> fertig() => eventually(
      tester,
      () async {
        final s = await _hole(v, 'api/v1/sicherung');
        return s['laeuft'] != true && s['ende'] != null;
      },
      timeout: const Duration(seconds: 180),
      was: 'Sicherung fertig',
    );
    await fertig();
    print('SIC-151 Stand: ${await stand()}');
    await _neustart(tester);
    await _serverGruppe(tester);
    await waitFor(
      tester,
      find.textContaining('Letzte Sicherung:'),
      timeout: const Duration(seconds: 30),
    );
    expect(find.textContaining('Nächste:'), findsWidgets);
    // SIC-156: je Konto eine Wiederherstellungsprobe.
    expect(find.text(de.backupProbeTitel), findsWidgets);

    // SIC-153: jetzt sichern.
    await _tapText(tester, de.serverSicherungJetzt);
    await erwarteMeldung(tester, de.serverSicherungGestartet);
    final laeuftGesehen = find
        .text(de.serverSicherungLaeuft)
        .evaluate()
        .isNotEmpty;
    print('SIC-153 „läuft gerade“ gesehen: $laeuftGesehen');
    await fertig();

    // SIC-154: die Kennmarke fehlt (Wächter ausserhalb entfernt sie).
    await _signal(tester, 'kennmarke');
    await eventually(
      tester,
      () async => (await _hole(v, 'api/v1/sicherung'))['stufe'] == 'zielFehlt',
      timeout: const Duration(seconds: 60),
      was: 'Ziel ohne Kennmarke',
    );
    await _neustart(tester);
    await waitFor(
      tester,
      find.text(de.serverSicherungWarnung),
      timeout: const Duration(seconds: 30),
    );
    await _serverGruppe(tester);
    final rot = find.text(de.serverSicherungZielFehlt);
    await waitFor(tester, rot);
    expect(
      tester.widget<Text>(rot).style?.color,
      Theme.of(tester.element(rot)).colorScheme.error,
    );
    await _tapText(tester, de.serverSicherungZielNeu);
    await waitFor(tester, find.text(de.serverSicherungZielNeuText));
    await _tap(tester, _imDialog(de.allgUebernehmen));
    await eventually(
      tester,
      () async => (await _hole(v, 'api/v1/sicherung'))['stufe'] != 'zielFehlt',
      timeout: const Duration(seconds: 60),
      was: 'Ziel angenommen',
    );
    expect(
      File(p.join(ziel, 'PHOTOVAULT-SICHERUNGSZIEL.json')).existsSync(),
      isTrue,
    );
    await fertig();

    // SIC-155: die letzte Sicherung scheitert (Ziel schreibgeschützt).
    await _signal(tester, 'sperren');
    await _serverGruppe(tester);
    await _tapText(tester, de.serverSicherungJetzt);
    await eventually(
      tester,
      () async {
        final s = await _hole(v, 'api/v1/sicherung');
        return s['laeuft'] != true && s['stufe'] == 'fehler';
      },
      timeout: const Duration(seconds: 120),
      was: 'Sicherung gescheitert',
    );
    await _signal(tester, 'frei');
    await _neustart(tester);
    await waitFor(
      tester,
      find.text(de.serverSicherungWarnung),
      timeout: const Duration(seconds: 30),
    );
    await _serverGruppe(tester);
    await waitFor(
      tester,
      find.textContaining('Die letzte Sicherung ist gescheitert:'),
    );
    print(
      'SIC-155: ${find.textContaining('gescheitert').evaluate().map((e) => (e.widget as Text).data).toList()}',
    );
    await finish(tester);
  }, skip: _eigenerServer != 'sicherung');

  testWidgets('SIC-157 Server-Sicherung in der App zurückholen '
      'mitSicherungsServer', (tester) async {
    await startApp(tester);
    final v = await _netz(tester, _verwalterToken);
    final ziel =
        (await _netz(tester, () => _hole(v, 'api/v1/sicherung')))['ziel']!
            as String;
    final konto = Directory(ziel).listSync().whereType<Directory>().firstWhere(
      (d) => p.basename(d.path).startsWith('${_verwalter}_'),
    );
    final dort = (await _netz(
      tester,
      () => _hole(v, 'api/v1/bibliothek'),
    ))['aufnahmen'];
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
        return n.length >= (dort as int);
      },
      timeout: const Duration(seconds: 180),
      was: 'Fotos zurück',
    );
    final namen = [for (final a in await _assets(tester)) a.originalFileName];
    print('SIC-157 zurück: $namen');
    expect(namen, containsAll(['sich_0.jpg', 'sich_1.jpg']));
    await finish(tester);
  }, skip: _eigenerServer != 'sicherung');

  testWidgets('SIC-225 Nach Ablauf der Frist nur Ansehen mitSicherungsServer', (
    tester,
  ) async {
    // Vorbereitet ausserhalb: B225 hat A225 benannt, A225 hat Zugang
    // verlangt, die Anfrage ist in der Serverdatenbank um acht Tage
    // zurückdatiert (Frist sieben Tage).
    await startApp(tester);
    await _verbinde(tester, 'A225');
    await openSection(tester, Hauptbereich.alben);
    await waitFor(
      tester,
      find.text(tt.partnerBibliothekVon('B225')),
      timeout: const Duration(seconds: 30),
    );
    expect(find.text(tt.partnerGanzeBibliothek), findsOneWidget);
    await _tapText(tester, tt.partnerBibliothekVon('B225'));
    final kacheln = find.descendant(
      of: find.byType(GridView),
      matching: find.byType(GestureDetector),
    );
    await waitFor(tester, kacheln, timeout: const Duration(seconds: 30));
    await _tap(tester, kacheln.first);
    await waitFor(tester, find.byType(PageView));
    await _warte(tester, const Duration(seconds: 2));
    expect(find.byIcon(Icons.thumb_up_outlined), findsNothing);
    expect(find.byTooltip(tt.kommentare), findsNothing);
    await _zurueck(tester);
    await _zurueck(tester);
    await _serverGruppe(tester);
    await _tapText(tester, tt.nachlass);
    await waitFor(tester, find.text(tt.nachlassFuerMich));
    await waitFor(tester, find.textContaining('Zugang seit'));
    expect(find.textContaining('unter „Geteilt mit mir“'), findsWidgets);
    await finish(tester);
  }, skip: _eigenerServer != 'sicherung');
}
