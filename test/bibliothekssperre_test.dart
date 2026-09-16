import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/bibliothek_belegt_screen.dart';
import 'package:photo_vault/services/bibliothekssperre.dart';
import 'package:photo_vault/services/library_location.dart';
import 'package:photo_vault/state/library_state.dart';

/// **Die Instanzsperre – gegen einen echten zweiten Prozess geprüft.**
///
/// Warum ein zweiter Prozess und nicht bloss ein zweites Öffnen derselben
/// Datei: Gemessen, weil es den Prüfstand entscheidet.
///
/// ```
/// derselbe Prozess, zweites open() + lock()  ->  BEKOMMT SIE AUCH
/// ```
///
/// Dart benutzt auf POSIX `fcntl`-Satzsperren, und die gehören dem
/// *Prozess*, nicht der geöffneten Datei. Ein Prüfstand, der die Sperre im
/// selben Prozess ein zweites Mal nähme, bekäme sie klaglos und hätte damit
/// **nichts** geprüft. (Auf Windows wäre er zufällig richtig – dort ist die
/// Sperre an das Handle gebunden. Ein Test, der nur auf einer Plattform das
/// Richtige tut, ist keiner.)
///
/// Der Halter ist deshalb ein eigener Dart-Prozess. Er kommt aus
/// `FLUTTER_ROOT`, weil `Platform.resolvedExecutable` im Testlauf auf
/// `flutter_tester` zeigt und nicht auf `dart`.
void main() {
  late Directory ordner;
  late List<Process> fremdeProzesse;

  setUp(() {
    ordner = Directory.systemTemp.createTempSync('pv_instanz_');
    fremdeProzesse = [];
  });

  // ---------------------------------------------------------------------
  // Der fremde Halter
  // ---------------------------------------------------------------------

  /// Das Programm, das der zweite Prozess ausführt: Sperre nehmen, „da"
  /// melden, warten. Bewusst nur `dart:io` – ohne Paketimporte braucht es
  /// keine Paketauflösung und startet in Bruchteilen einer Sekunde.
  const halterQuelle = '''
import 'dart:io';
void main(List<String> a) async {
  final f = File(a[0]).openSync(mode: FileMode.append);
  f.lockSync(FileLock.exclusive);
  print('gehalten');
  await Future.delayed(const Duration(seconds: 120));
}
''';

  String dartProgramm() {
    final wurzel = Platform.environment['FLUTTER_ROOT'];
    expect(wurzel, isNotNull,
        reason: 'ohne FLUTTER_ROOT lässt sich kein zweiter Prozess starten');
    final name = Platform.isWindows ? 'dart.exe' : 'dart';
    return p.join(wurzel!, 'bin', 'cache', 'dart-sdk', 'bin', name);
  }

  /// Startet den Halter und kehrt erst zurück, wenn er die Sperre wirklich
  /// hat. Ohne dieses Warten wäre der Test ein Wettlauf, den er meistens,
  /// aber nicht immer gewönne.
  Future<Process> halterAuf(Directory wurzel) async {
    final skript = File(p.join(ordner.path, 'halter.dart'))
      ..writeAsStringSync(halterQuelle);
    final ziel = p.join(wurzel.path, Bibliothekssperre.dateiname);
    await wurzel.create(recursive: true);
    final prozess = await Process.start(dartProgramm(), [skript.path, ziel]);
    fremdeProzesse.add(prozess);
    final da = Completer<void>();
    prozess.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((z) {
      if (z.trim() == 'gehalten' && !da.isCompleted) da.complete();
    });
    unawaited(prozess.stderr.drain<void>());
    await da.future.timeout(const Duration(seconds: 60),
        onTimeout: () => fail('der fremde Halter kam nicht zustande'));
    return prozess;
  }

  /// Wartet, bis der Prozess wirklich weg ist. `kill` kehrt sofort zurück;
  /// die Sperre fällt erst, wenn der Kern ihn abgeräumt hat.
  Future<void> halterFort(Process prozess) async {
    prozess.kill(ProcessSignal.sigkill);
    await prozess.exitCode;
    fremdeProzesse.remove(prozess);
  }

  tearDown(() async {
    for (final prozess in List<Process>.of(fremdeProzesse)) {
      await halterFort(prozess);
    }
    await Bibliothekssperre.gib();
    LibraryLocation.zuruecksetzenFuerTests();
    for (var versuch = 0; versuch < 40 && ordner.existsSync(); versuch++) {
      try {
        await ordner.delete(recursive: true);
      } on FileSystemException {
        if (versuch == 39) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
    }
  });

  // ---------------------------------------------------------------------
  // Der Dienst
  // ---------------------------------------------------------------------

  test('eine freie Bibliothek wird genommen', () async {
    final befund = await Bibliothekssperre.nimm(ordner);
    expect(befund.zustand, Sperrzustand.genommen);
    expect(Bibliothekssperre.haeltEtwas, isTrue);
    expect(File(p.join(ordner.path, Bibliothekssperre.dateiname)).existsSync(),
        isTrue);
  });

  test('eine von einem anderen Prozess gehaltene wird abgewiesen', () async {
    final fremd = await halterAuf(ordner);
    addTearDown(() => halterFort(fremd));

    final uhr = Stopwatch()..start();
    final befund = await Bibliothekssperre.nimm(ordner);
    uhr.stop();

    expect(befund.zustand, Sperrzustand.belegt);
    expect(Bibliothekssperre.haeltEtwas, isFalse,
        reason: 'nach einer Abweisung darf nichts halb Gehaltenes bleiben');
    expect(uhr.elapsedMilliseconds, lessThan(2000),
        reason: 'die Abweisung kommt sofort, es wird nicht gewartet');
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('nach einem harten Abschuss ist sie sofort wieder frei', () async {
    // DIE wichtigste Prüfung des ganzen Prüfstands. Eine Sperre, die einen
    // Absturz überlebt, sperrt den Besitzer aus seinen eigenen Daten aus –
    // und das wäre schlimmer als das Problem, das die Sperre löst. Genau
    // deshalb steht hier eine Dateisperre und keine Datei mit einer
    // Prozessnummer darin: Es gibt keine Aufräumroutine, die versagen
    // könnte.
    final fremd = await halterAuf(ordner);
    expect((await Bibliothekssperre.nimm(ordner)).zustand, Sperrzustand.belegt);

    await halterFort(fremd);

    final befund = await Bibliothekssperre.nimm(ordner);
    expect(befund.zustand, Sperrzustand.genommen,
        reason: 'der Kern gibt sie beim Wegfall des Prozesses selbst her');
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('zwei verschiedene Bibliotheken behindern einander nicht', () async {
    // Der Grund, warum die BIBLIOTHEK gesperrt wird und nicht das Programm:
    // Die Testfassung neben der produktiven muss weiter laufen dürfen.
    final zweite = Directory(p.join(ordner.path, 'andere'))..createSync();
    final fremd = await halterAuf(zweite);
    addTearDown(() => halterFort(fremd));

    expect(
        (await Bibliothekssperre.nimm(ordner)).zustand, Sperrzustand.genommen);
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('gib() macht sie für andere wieder frei', () async {
    expect(
        (await Bibliothekssperre.nimm(ordner)).zustand, Sperrzustand.genommen);
    await Bibliothekssperre.gib();
    expect(Bibliothekssperre.haeltEtwas, isFalse);

    // Die Gegenprobe muss von aussen kommen: Im selben Prozess bekäme man
    // sie wegen der fcntl-Semantik ohnehin, gelöst oder nicht.
    final fremd = await halterAuf(ordner);
    addTearDown(() => halterFort(fremd));
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('ein Wechsel gibt die zuvor gehaltene her', () async {
    final zweite = Directory(p.join(ordner.path, 'zweite'))..createSync();
    await Bibliothekssperre.nimm(ordner);
    final ersterOrt = Bibliothekssperre.gehaltenerOrt;

    expect(
        (await Bibliothekssperre.nimm(zweite)).zustand, Sperrzustand.genommen);
    expect(Bibliothekssperre.gehaltenerOrt, isNot(ersterOrt));

    // Und der erste Ort ist wirklich los – von aussen belegt.
    final fremd = await halterAuf(ordner);
    addTearDown(() => halterFort(fremd));
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('zweimal dieselbe zu nehmen ist folgenlos', () async {
    await Bibliothekssperre.nimm(ordner);
    final ort = Bibliothekssperre.gehaltenerOrt;
    expect(
        (await Bibliothekssperre.nimm(ordner)).zustand, Sperrzustand.genommen);
    expect(Bibliothekssperre.gehaltenerOrt, ort);
  });

  test('ein unbeantwortbarer Fall wird durchgelassen, nicht abgewiesen',
      () async {
    // Die Ausnahme, ohne die die Sperre gefährlicher wäre als nützlich:
    // Lässt sie sich aus einem ANDEREN Grund als Belegung nicht nehmen,
    // muss durchgelassen werden. Hier nachgestellt mit einer Wurzel, die
    // gar kein Ordner sein kann, weil an ihrer Stelle eine Datei liegt.
    final block = File(p.join(ordner.path, 'keinOrdner'))
      ..writeAsStringSync('x');
    final befund =
        await Bibliothekssperre.nimm(Directory(p.join(block.path, 'drin')));

    expect(befund.zustand, Sperrzustand.unklar);
    expect(befund.zustand, isNot(Sperrzustand.belegt),
        reason: 'Unwissen darf niemanden aussperren');
    expect(befund.grund, isNotNull, reason: 'für das Protokoll');
    expect(Bibliothekssperre.haeltEtwas, isFalse);
  });

  // ---------------------------------------------------------------------
  // Der Anschluss an den Start
  // ---------------------------------------------------------------------

  test('initialize() bricht ab, BEVOR die Datenbank geöffnet wird', () async {
    LibraryLocation.nutzeFuerTests(anker: ordner);
    final fremd = await halterAuf(ordner);
    addTearDown(() => halterFort(fremd));

    final bib = LibraryState();
    await bib.initialize();

    expect(bib.bibliothekBelegt, isTrue);
    expect(bib.isReady, isFalse);
    expect(bib.belegterOrt, ordner.path);
    // Der eigentliche Punkt: Es wurde nichts geöffnet. Wäre `db` gesetzt,
    // hätten zwei Instanzen dieselbe Datei offen – genau das, was verhindert
    // werden soll.
    expect(() => bib.db, throwsA(isA<Error>()),
        reason: 'die Datenbank darf gar nicht erst aufgemacht worden sein');
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('ein Startfehler wird als Zustand gemeldet statt weitergeworfen',
      () async {
    final block = File(p.join(ordner.path, 'kein_datenordner'))
      ..writeAsStringSync('Datei statt Ordner');
    LibraryLocation.nutzeFuerTests(anker: Directory(block.path));
    final bib = LibraryState();

    await expectLater(bib.initialize(), completes);

    expect(bib.isReady, isFalse);
    expect(bib.bibliothekBelegt, isFalse);
    expect(bib.initialisierungsfehler, isNotNull);
    expect(Bibliothekssperre.haeltEtwas, isFalse);
  });

  testWidgets('der Bildschirm nennt den Ort und bietet drei Wege',
      (tester) async {
    // ALLES echte Ein-/Ausgabe gehört hier in runAsync. Der Rumpf eines
    // Widget-Tests läuft in einer angehaltenen Zeit; ein `await` auf einen
    // fremden Prozess oder auf die Platte kommt darin nie zurück, und der
    // Test hängt wortlos bis zu seiner Frist.
    LibraryLocation.nutzeFuerTests(anker: ordner);
    late Process fremd;
    final bib = LibraryState();
    await tester.runAsync(() async {
      fremd = await halterAuf(ordner);
      await bib.initialize();
    });
    addTearDown(() => halterFort(fremd));

    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      home: BibliothekBelegtScreen(library: bib),
    ));

    final texte = AppTexte.of(tester.element(find.byType(Scaffold)));
    expect(find.text(texte.sperreTitel), findsOneWidget);
    expect(find.text(ordner.path), findsOneWidget,
        reason: 'bei mehreren Bibliotheken muss erkennbar sein, welche klemmt');
    expect(find.text(texte.sperreErneut), findsOneWidget);
    expect(find.text(texte.sperreAndere), findsOneWidget);
    expect(find.text(texte.sperreBeenden), findsOneWidget);
    expect(find.text(texte.sperreNochBelegt), findsNothing,
        reason: 'vor dem ersten Versuch gibt es nichts zu wiederholen');

    // Der Halter lebt weiter – der zweite Anlauf muss das sagen, statt
    // stumm denselben Bildschirm zu zeigen.
    // Auch der DRUCK gehört in runAsync, nicht nur das Warten danach: Der
    // Knopf startet einen neuen Anlauf mit echter Datei-Ein-/Ausgabe. Wird
    // er in der angehaltenen Zeit gedrückt, kommt dieser Anlauf nie zurück,
    // und ein späteres runAsync holt ihn auch nicht mehr ein – die Zusage
    // hing schon in der falschen Zeit.
    //
    // `pumpAndSettle` scheidet ohnehin aus: Der Kringel im Knopf ist eine
    // endlose Animation, und die Ruhe, auf die es wartete, tritt nie ein.
    await tester.runAsync(() async {
      await tester.tap(find.text(texte.sperreErneut));
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pump();

    expect(find.text(texte.sperreNochBelegt), findsOneWidget);
    expect(bib.bibliothekBelegt, isTrue);
  }, timeout: const Timeout(Duration(seconds: 90)));
}
