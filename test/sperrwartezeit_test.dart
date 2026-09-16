import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';

/// **Was passiert, wenn zwei auf dieselbe Datenbank schreiben.**
///
/// SQLites Vorgabe für `busy_timeout` ist **null**: Wer auf eine belegte
/// Datei trifft, bekommt sofort „database is locked" und keinen zweiten
/// Versuch. Das ist so lange folgenlos, wie genau ein Prozess die Datei
/// anfasst – und genau das ist nicht zugesichert. Nichts in diesem
/// Programm hindert jemanden daran, es zweimal zu starten; auf dem
/// Windows-Prüfrechner liefen bei der 22. Prüfrunde zwei Fassungen
/// stundenlang nebeneinander, ohne dass eine davon etwas gemerkt hätte.
///
/// An zwei echten Prozessen gemessen (400 Zeilen jeder, gleichzeitig):
///
/// ```
/// ohne Wartezeit    734 von 800 Schreibvorgängen scheitern
/// 5 Sekunden          0 von 800, zusammen 170 ms
/// ```
void main() {
  late Directory ordner;
  late File datei;
  late List<Process> fremdeProzesse;

  setUp(() {
    ordner = Directory.systemTemp.createTempSync('pv_sperre_');
    datei = File('${ordner.path}/library.sqlite');
    fremdeProzesse = [];
  });
  tearDown(() async {
    for (final prozess in fremdeProzesse) {
      prozess.kill(ProcessSignal.sigkill);
      await prozess.exitCode;
    }
    ordner.deleteSync(recursive: true);
  });

  const sperrerQuelle = r'''
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

typedef OpenNative = Int32 Function(
    Pointer<Utf8>, Pointer<Pointer<Void>>, Int32, Pointer<Utf8>);
typedef OpenDart = int Function(
    Pointer<Utf8>, Pointer<Pointer<Void>>, int, Pointer<Utf8>);
typedef ExecNative = Int32 Function(
    Pointer<Void>, Pointer<Utf8>, Pointer<Void>, Pointer<Void>, Pointer<Pointer<Utf8>>);
typedef ExecDart = int Function(
    Pointer<Void>, Pointer<Utf8>, Pointer<Void>, Pointer<Void>, Pointer<Pointer<Utf8>>);
typedef CloseNative = Int32 Function(Pointer<Void>);
typedef CloseDart = int Function(Pointer<Void>);

Future<void> main(List<String> argumente) async {
  final bibliothek = DynamicLibrary.open(argumente[1]);
  final open = bibliothek.lookupFunction<OpenNative, OpenDart>('sqlite3_open_v2');
  final exec = bibliothek.lookupFunction<ExecNative, ExecDart>('sqlite3_exec');
  final close = bibliothek.lookupFunction<CloseNative, CloseDart>('sqlite3_close_v2');
  final dbZeiger = calloc<Pointer<Void>>();
  final fehler = calloc<Pointer<Utf8>>();
  final dateiname = argumente[0].toNativeUtf8();
  if (open(dateiname, dbZeiger, 6, nullptr) != 0) exit(2);

  void ausfuehren(String sql) {
    final text = sql.toNativeUtf8();
    final code = exec(dbZeiger.value, text, nullptr, nullptr, fehler);
    calloc.free(text);
    if (code != 0) exit(3);
  }

  ausfuehren('PRAGMA busy_timeout = 0');
  ausfuehren('BEGIN IMMEDIATE');
  stdout.writeln('gesperrt');
  await Future<void>.delayed(Duration(milliseconds: int.parse(argumente[2])));
  ausfuehren('COMMIT');
  close(dbZeiger.value);
  calloc.free(dateiname);
  calloc.free(fehler);
  calloc.free(dbZeiger);
}
''';

  Future<Process> sperreVonAussen(int dauerMs) async {
    final flutterRoot = Platform.environment['FLUTTER_ROOT'];
    expect(flutterRoot, isNotNull,
        reason: 'ohne FLUTTER_ROOT lässt sich kein zweiter Prozess starten');
    final dartName = Platform.isWindows ? 'dart.exe' : 'dart';
    final dart = '$flutterRoot/bin/cache/dart-sdk/bin/$dartName';
    final skript = File('${ordner.path}/sperrer.dart')
      ..writeAsStringSync(sperrerQuelle);
    final projekt = Directory.current.absolute;
    final pakete =
        File(p.join(projekt.path, '.dart_tool', 'package_config.json'));
    final nativeWurzel = Directory(p.join(projekt.path, '.dart_tool',
        'hooks_runner', 'shared', 'sqlite3', 'build'));
    final endung = Platform.isWindows
        ? 'sqlite3.dll'
        : Platform.isMacOS
            ? 'libsqlite3.dylib'
            : 'libsqlite3.so';
    final nativeBibliothek = nativeWurzel
        .listSync(recursive: true)
        .whereType<File>()
        .firstWhere((datei) => p.basename(datei.path) == endung);
    final prozess = await Process.start(
      dart,
      [
        '--packages=${pakete.path}',
        skript.path,
        datei.path,
        nativeBibliothek.path,
        '$dauerMs',
      ],
      workingDirectory: projekt.path,
    );
    fremdeProzesse.add(prozess);
    final bereit = Completer<void>();
    final fehler = StringBuffer();
    prozess.stdout
        .transform(const SystemEncoding().decoder)
        .transform(const LineSplitter())
        .listen((zeile) {
      if (zeile.trim() == 'gesperrt' && !bereit.isCompleted) bereit.complete();
    });
    prozess.stderr
        .transform(const SystemEncoding().decoder)
        .listen(fehler.write);
    await bereit.future.timeout(const Duration(seconds: 30),
        onTimeout: () =>
            fail('fremde Datenbanksperre fehlgeschlagen: $fehler'));
    return prozess;
  }

  Future<void> gibFremdeSperre(Process prozess) async {
    final code = await prozess.exitCode;
    fremdeProzesse.remove(prozess);
    expect(code, 0, reason: 'der fremde SQLite-Prozess muss sauber enden');
  }

  test('die Vorgabe wird gesetzt und ist nicht null', () async {
    final db = AppDatabase(
        NativeDatabase(datei, setup: AppDatabase.bereiteVerbindungVor));
    addTearDown(db.close);
    final zeile = await db.customSelect('PRAGMA busy_timeout').getSingle();
    expect(zeile.data.values.first, AppDatabase.sperrwartezeitMs);
    expect(AppDatabase.sperrwartezeitMs, greaterThan(0),
        reason: 'null hiesse: sofort aufgeben, und das war der Befund');
  });

  test('eine fremde Sperre lässt den Schreibvorgang nicht scheitern', () async {
    // Der zweite Zugriff ist ein eigener Prozess mit einer offenen
    // Schreibtransaktion. Das bildet auch POSIX-Dateisperren zuverlässig ab;
    // zwei Verbindungen desselben Prozesses tun das auf Linux nicht.
    // **Im Hintergrund-Isolat, wie im Betrieb.** Mit dem einfachen
    // `NativeDatabase` läuft SQLite auf demselben Isolat: Die Wartezeit
    // blockiert dann die Ereignisschleife, und der Timer, der die Sperre
    // gleich wieder löst, käme nie dran – der Test hinge fünf Sekunden an
    // sich selbst und fiele.
    //
    // Dasselbe gilt im Betrieb, und deshalb ist es kein Testkniff,
    // sondern der Grund, warum fünf Sekunden vertretbar sind:
    // [AppDatabase.open] nimmt `createInBackground`, also wartet nicht
    // die Oberfläche, sondern ein Isolat, das ohnehin nichts anderes tut.
    final db = AppDatabase(AppDatabase.mitSperrwartezeit(
        NativeDatabase.createInBackground(datei,
            setup: AppDatabase.bereiteVerbindungVor)));
    addTearDown(db.close);
    // Erst einmal anlegen, damit beide dieselbe Datei meinen.
    await db.customSelect('SELECT 1').get();
    final wartezeit = await db.customSelect('PRAGMA busy_timeout').getSingle();
    expect(wartezeit.data.values.first, AppDatabase.sperrwartezeitMs,
        reason: 'die Einstellung muss auch im Hintergrund-Isolat gelten');

    // Der fremde Prozess löst selbst nach kurzer Zeit. Dadurch hängt die
    // Freigabe nicht an der Ereignisschleife des geprüften Prozesses.
    final fremd = await sperreVonAussen(300);

    final uhr = Stopwatch()..start();
    await db.insertAsset(AssetsCompanion.insert(
      id: 'a',
      relativePath: 'originals/a.jpg',
      originalFileName: 'a.jpg',
      type: 'IMAGE',
      checksum: 'a',
      fileCreatedAt: DateTime(2026),
      importedAt: DateTime(2026),
      isTrashed: const Value(false),
    ));
    await gibFremdeSperre(fremd);
    uhr.stop();

    expect(await db.assetById('a'), isNotNull,
        reason: 'geschrieben werden muss es, nicht abgelehnt');
    expect(uhr.elapsedMilliseconds, greaterThan(100),
        reason: 'es hat wirklich gewartet – sonst prüft dieser Test nichts');
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('ohne Wartezeit scheitert derselbe Schreibvorgang', () async {
    // Die Gegenprobe im selben Test: Mit der Vorgabe von SQLite gibt es
    // keinen zweiten Versuch, und genau das war der Befund.
    final db = AppDatabase(NativeDatabase.createInBackground(datei,
        setup: (d) => d.execute('PRAGMA busy_timeout = 0')));
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get();

    final fremd = await sperreVonAussen(1000);

    await expectLater(
      db.insertAsset(AssetsCompanion.insert(
        id: 'b',
        relativePath: 'originals/b.jpg',
        originalFileName: 'b.jpg',
        type: 'IMAGE',
        checksum: 'b',
        fileCreatedAt: DateTime(2026),
        importedAt: DateTime(2026),
        isTrashed: const Value(false),
      )),
      throwsA(predicate((e) => '$e'.contains('locked'))),
    );
    await gibFremdeSperre(fremd);
  }, timeout: const Timeout(Duration(seconds: 30)));
}
