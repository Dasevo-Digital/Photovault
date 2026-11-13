import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault_mobil/app_sperre.dart';
import 'package:photo_vault_mobil/l10n/app_localizations.dart';

/// Die App-Sperre (#376): Ohne Face ID oder Gerätecode zeigt die App
/// nichts, und im Hintergrund liegt eine Abdeckung über allem.
void main() {
  late DateTime uhr;
  late List<String> fragen;
  late bool antwort;
  late List<bool> abdeckungen;
  // Die Laufzeit des Geräts (#382): läuft mit der Uhr, lässt sich aber
  // nicht mit ihr zurückstellen.
  late Duration laufzeit;
  late int sperrungen;

  setUp(() {
    uhr = DateTime(2026, 11, 12, 12);
    fragen = [];
    antwort = true;
    abdeckungen = [];
    laufzeit = const Duration(hours: 3);
    sperrungen = 0;
  });

  void vergeht(Duration d) {
    uhr = uhr.add(d);
    laufzeit += d;
  }

  AppSperre sperre({
    bool an = true,
    Duration frist = Duration.zero,
    Future<int?> Function()? lauf,
    bool abdeckenWennInaktiv = true,
    Future<bool> Function()? frage,
    bool android = false,
  }) => AppSperre(
    an: an,
    frist: frist,
    pruefe: (grund) async {
      fragen.add(grund);
      return frage == null ? antwort : await frage();
    },
    verfuegbar: () async => true,
    jetzt: () => uhr,
    laufzeit: lauf ?? () async => laufzeit.inMilliseconds,
    abdecken: (an) async => abdeckungen.add(an),
    beiSperre: () async => sperrungen++,
    abdeckenWennInaktiv: abdeckenWennInaktiv,
    android: android,
  );

  Future<void> zeige(WidgetTester tester, AppSperre s) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        builder: (context, kind) => AppSperrschicht(sperre: s, child: kind!),
        home: const Scaffold(body: Text('Bibliothek')),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> wechsle(WidgetTester tester, List<AppLifecycleState> s) async {
    for (final z in s) {
      tester.binding.handleAppLifecycleStateChanged(z);
    }
    await tester.pumpAndSettle();
  }

  testWidgets('aus: die App zeigt alles, ohne zu fragen', (tester) async {
    await zeige(tester, sperre(an: false));
    expect(find.text('Bibliothek'), findsOneWidget);
    expect(find.text('Photo Vault ist gesperrt'), findsNothing);
    expect(fragen, isEmpty);
  });

  testWidgets('an: beim Start fragt sie und gibt erst danach frei', (
    tester,
  ) async {
    antwort = false;
    final s = sperre();
    await zeige(tester, s);
    expect(fragen, ['Photo Vault entsperren'], reason: 'fragt von selbst');
    expect(find.text('Photo Vault ist gesperrt'), findsOneWidget);
    expect(
      tester.getSemantics(find.text('Bibliothek')),
      isNot(matchesSemantics(label: 'Bibliothek')),
      reason: 'VoiceOver liest nichts dahinter',
    );

    // Abgebrochen: Sie fragt nicht gleich wieder, aber auf Tipp.
    antwort = true;
    await tester.pumpAndSettle();
    expect(fragen, hasLength(1));
    await tester.tap(find.text('Entsperren'));
    await tester.pumpAndSettle();
    expect(fragen, hasLength(2));
    expect(find.text('Photo Vault ist gesperrt'), findsNothing);
    expect(s.gesperrt, isFalse);
  });

  testWidgets('im Hintergrund: Abdeckung, nach der Frist wieder gesperrt', (
    tester,
  ) async {
    final s = sperre(frist: const Duration(minutes: 5));
    await zeige(tester, s);
    expect(s.gesperrt, isFalse);
    fragen.clear();

    await wechsle(tester, [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]);
    expect(s.verdeckt, isTrue);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);

    // Nach drei Minuten zurück: innerhalb der Frist, also frei.
    vergeht(const Duration(minutes: 3));
    await wechsle(tester, [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]);
    expect(s.gesperrt, isFalse);
    expect(find.byIcon(Icons.lock_outline), findsNothing);
    expect(fragen, isEmpty);

    // Nach sechs Minuten: gesperrt, und sie fragt von selbst.
    await wechsle(tester, [
      AppLifecycleState.inactive,
      AppLifecycleState.paused,
    ]);
    vergeht(const Duration(minutes: 6));
    antwort = false;
    await wechsle(tester, [
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]);
    expect(s.gesperrt, isTrue);
    expect(fragen, hasLength(1));
    expect(find.text('Photo Vault ist gesperrt'), findsOneWidget);
    expect(sperrungen, 1, reason: 'iOS schliesst das Teilen-Blatt darüber');
  });

  group('Uhrzeit zurückgestellt (#382)', () {
    Future<AppSperre> weg(
      WidgetTester tester, {
      Duration frist = const Duration(minutes: 15),
      Future<int?> Function()? lauf,
    }) async {
      final s = sperre(frist: frist, lauf: lauf);
      await zeige(tester, s);
      await wechsle(tester, [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]);
      return s;
    }

    // Wer zurückkommt, kann Face ID nicht: Sperrt sie, bleibt sie zu.
    Future<void> zurueck(WidgetTester tester) {
      antwort = false;
      return wechsle(tester, [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]);
    }

    testWidgets('vor das Verlassen: sperrt, auch wenn die Laufzeit passt', (
      tester,
    ) async {
      final s = await weg(tester);
      // Eine Minute weg – nach der Laufzeit frei; die Uhr aber zwei Stunden
      // vor dem Verlassen: Das kann nur Verstellen sein.
      laufzeit += const Duration(minutes: 1);
      uhr = uhr.subtract(const Duration(hours: 2));
      await zurueck(tester);
      expect(s.gesperrt, isTrue);
    });

    testWidgets('Laufzeit wirft oder läuft rückwärts: sperrt', (tester) async {
      var n = 0;
      final s = await weg(
        tester,
        lauf: () async => ++n == 1 ? 5000 : throw PlatformException(code: 'x'),
      );
      vergeht(const Duration(minutes: 1));
      await zurueck(tester);
      expect(s.gesperrt, isTrue);
    });

    testWidgets('Laufzeit kleiner als beim Verlassen: sperrt', (tester) async {
      var n = 0;
      final s = await weg(tester, lauf: () async => ++n == 1 ? 90000 : 1000);
      vergeht(const Duration(minutes: 1));
      await zurueck(tester);
      expect(s.gesperrt, isTrue);
    });

    testWidgets('die Abdeckung bleibt, bis die Laufzeit antwortet', (
      tester,
    ) async {
      final spaeter = Completer<int?>();
      var n = 0;
      final s = await weg(
        tester,
        lauf: () => ++n == 1 ? Future.value(1000) : spaeter.future,
      );
      vergeht(const Duration(minutes: 1));
      await zurueck(tester);
      expect(s.verdeckt, isTrue, reason: 'nichts zeigen, ehe entschieden ist');
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      spaeter.complete(1000 + const Duration(minutes: 1).inMilliseconds);
      await tester.pumpAndSettle();
      expect(s.verdeckt, isFalse);
      expect(s.gesperrt, isFalse);
    });

    testWidgets('kurz zurück und gleich wieder weg: es zählt das erste Gehen', (
      tester,
    ) async {
      // Uhr jeweils zurückgestellt: Erst die Laufzeit verrät es. Kommt die
      // App vor ihrer Antwort wieder weg, darf die erste Abwesenheit nicht
      // vergessen werden.
      final antworten = <Completer<int?>>[];
      final s = await weg(
        tester,
        lauf: () {
          final c = Completer<int?>();
          antworten.add(c);
          return c.future;
        },
      );
      antworten.last.complete(0);
      laufzeit = const Duration(hours: 1);
      uhr = uhr.add(const Duration(minutes: 1));
      await zurueck(tester);
      // Noch ehe die Laufzeit antwortet: wieder weg.
      await wechsle(tester, [
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]);
      antworten[1].complete(const Duration(hours: 1).inMilliseconds);
      await tester.pumpAndSettle();
      uhr = uhr.add(const Duration(minutes: 1));
      await zurueck(tester);
      antworten.last.complete(
        const Duration(hours: 1, minutes: 1).inMilliseconds,
      );
      await tester.pumpAndSettle();
      expect(s.gesperrt, isTrue);
    });

    testWidgets('auf kurz nach dem Verlassen: die Laufzeit zählt', (
      tester,
    ) async {
      final s = await weg(tester);
      // Eine Stunde später, die Uhr aber auf eine Minute danach gestellt.
      laufzeit += const Duration(hours: 1);
      uhr = uhr.add(const Duration(minutes: 1));
      await zurueck(tester);
      expect(s.gesperrt, isTrue);
      expect(find.text('Photo Vault ist gesperrt'), findsOneWidget);
    });

    testWidgets('ohne Laufzeit vom System: sperrt', (tester) async {
      final s = await weg(tester, lauf: () async => null);
      vergeht(const Duration(minutes: 1));
      await zurueck(tester);
      expect(s.gesperrt, isTrue);
    });

    testWidgets('innerhalb der Frist nach beiden: frei', (tester) async {
      final s = await weg(tester);
      vergeht(const Duration(minutes: 1));
      await zurueck(tester);
      expect(s.gesperrt, isFalse);
      expect(s.verdeckt, isFalse);
      expect(sperrungen, 0);
    });
  });

  testWidgets('nach „Abbrechen“ fragt sie nicht in einer Schleife (#382)', (
    tester,
  ) async {
    antwort = false;
    final s = sperre();
    await zeige(tester, s);
    expect(fragen, hasLength(1));
    // Der Dialog von Face ID macht die App inaktiv; nach „Abbrechen“ kommt
    // sie zurück – das ist kein Weg in den Hintergrund.
    await wechsle(tester, [
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]);
    await wechsle(tester, [
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]);
    expect(fragen, hasLength(1));
    expect(s.gesperrt, isTrue);
    // Aus dem Hintergrund zurück: dann wieder von selbst.
    await wechsle(tester, [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]);
    await wechsle(tester, [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]);
    expect(fragen, hasLength(2));
  });

  testWidgets('wer eben bestätigt hat, wird nicht gleich wieder gesperrt', (
    tester,
  ) async {
    // Android 9/10: Die Eingabe des Codes ist eine eigene Activity, die
    // App ist solange „paused“ (#382).
    antwort = false;
    final s = sperre();
    await zeige(tester, s);
    s.lebenslauf(AppLifecycleState.paused);
    antwort = true;
    expect(await s.entsperre('x'), isTrue);
    s.lebenslauf(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(s.gesperrt, isFalse);
  });

  test('nach dem Häkchen gleich nach Hause: diese Abwesenheit zählt', () async {
    final bestaetigt = Completer<bool>();
    final s = sperre(frage: () => bestaetigt.future);
    final entsperrt = s.entsperre('x');
    await Future<void>.delayed(Duration.zero); // die Abfrage läuft
    // Face ID erkennt, die Antwort ist unterwegs – da wischt man weg.
    s.lebenslauf(AppLifecycleState.inactive);
    s.lebenslauf(AppLifecycleState.hidden);
    s.lebenslauf(AppLifecycleState.paused);
    bestaetigt.complete(true);
    expect(await entsperrt, isTrue);
    expect(s.gesperrt, isFalse);
    vergeht(const Duration(hours: 2));
    s.lebenslauf(AppLifecycleState.resumed);
    expect(s.gesperrt, isTrue, reason: 'mit „Sofort“ gesperrt');
  });

  testWidgets(
    'Android 9/10: Code-Eingabe als Activity, „Zurück“ ohne Schleife',
    (tester) async {
      var offen = Completer<bool>();
      final s = sperre(frage: () => (offen = Completer<bool>()).future);
      await zeige(tester, s);
      expect(fragen, hasLength(1));
      // Die Eingabe des Codes ist eine eigene Activity: die App ist „paused“.
      await wechsle(tester, [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]);
      offen.complete(false);
      await wechsle(tester, [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]);
      expect(fragen, hasLength(1), reason: 'nicht gleich wieder');
      expect(s.gesperrt, isTrue);
      expect(find.text('Entsperren'), findsOneWidget);
    },
  );

  test(
    'Android 9/10: PIN bestätigt, während die App noch „paused“ ist',
    () async {
      // Die Antwort kann ankommen, ehe Flutter „resumed“ meldet. Was während
      // der eigenen Abfrage begann, gehört zu ihr – sonst sperrte sie gleich
      // wieder und fragte von vorn (#382).
      final bestaetigt = Completer<bool>();
      final s = sperre(frage: () => bestaetigt.future, android: true);
      final entsperrt = s.entsperre('x');
      await Future<void>.delayed(Duration.zero); // die Abfrage läuft
      s.lebenslauf(AppLifecycleState.inactive);
      s.lebenslauf(AppLifecycleState.hidden);
      s.lebenslauf(AppLifecycleState.paused);
      bestaetigt.complete(true);
      expect(await entsperrt, isTrue);
      s.lebenslauf(AppLifecycleState.hidden);
      s.lebenslauf(AppLifecycleState.inactive);
      s.lebenslauf(AppLifecycleState.resumed);
      expect(s.gesperrt, isFalse);
    },
  );

  test('Abschalten vergisst eine offene Abwesenheit', () async {
    final s = sperre(frist: const Duration(minutes: 15));
    expect(await s.entsperre('x'), isTrue);
    s.lebenslauf(AppLifecycleState.paused);
    await s.setze(an: false);
    vergeht(const Duration(hours: 1));
    await s.setze(an: true);
    s.lebenslauf(AppLifecycleState.paused);
    vergeht(const Duration(minutes: 1));
    s.lebenslauf(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);
    expect(s.gesperrt, isFalse, reason: 'eine Minute weg, nicht eine Stunde');
  });

  testWidgets('schon verdeckt: kein Fokus, die Tastatur schliesst (#382)', (
    tester,
  ) async {
    final s = sperre(frist: const Duration(minutes: 15));
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        builder: (context, kind) => AppSperrschicht(sperre: s, child: kind!),
        home: const Scaffold(body: TextField()),
      ),
    );
    await tester.pumpAndSettle();
    expect(s.gesperrt, isFalse);
    await tester.showKeyboard(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isTrue);
    await wechsle(tester, [AppLifecycleState.inactive]);
    expect(s.verdeckt, isTrue);
    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets('unter Android verdeckt Inaktiv nichts (FLAG_SECURE)', (
    tester,
  ) async {
    final s = sperre(abdeckenWennInaktiv: false);
    await zeige(tester, s);
    await wechsle(tester, [AppLifecycleState.inactive]);
    expect(s.verdeckt, isFalse);
    await wechsle(tester, [AppLifecycleState.hidden]);
    expect(s.verdeckt, isTrue);
  });

  testWidgets('nur inaktiv (Kontrollzentrum): verdeckt, aber nicht gesperrt', (
    tester,
  ) async {
    final s = sperre();
    await zeige(tester, s);
    fragen.clear();
    await wechsle(tester, [AppLifecycleState.inactive]);
    expect(s.verdeckt, isTrue);
    await wechsle(tester, [AppLifecycleState.resumed]);
    expect(s.verdeckt, isFalse);
    expect(s.gesperrt, isFalse);
    expect(fragen, isEmpty);
  });

  testWidgets('ohne Gerätecode sperrt sie nicht aus, sondern schaltet ab', (
    tester,
  ) async {
    final s = AppSperre(
      an: true,
      pruefe: (grund) async {
        fragen.add(grund);
        return false;
      },
      verfuegbar: () async => false,
      jetzt: () => uhr,
      abdecken: (an) async => abdeckungen.add(an),
    );
    await zeige(tester, s);
    expect(find.text('Bibliothek'), findsOneWidget);
    expect(s.gesperrt, isFalse);
    expect(s.an, isFalse);
    expect(fragen, isEmpty, reason: 'gar nicht erst gefragt');
  });

  testWidgets('ein Fehler beim Fragen schaltet die Sperre nicht ab (#382)', (
    tester,
  ) async {
    final s = AppSperre(
      an: true,
      pruefe: (grund) async {
        fragen.add(grund);
        return false;
      },
      verfuegbar: () async => throw PlatformException(code: 'kaputt'),
      jetzt: () => uhr,
      abdecken: (an) async => abdeckungen.add(an),
    );
    await zeige(tester, s);
    expect(s.an, isTrue);
    expect(s.gesperrt, isTrue);
    expect(find.text('Photo Vault ist gesperrt'), findsOneWidget);
    expect(await s.verfuegbar(), isFalse, reason: 'Einschalten nur sicher');
  });

  test(
    'liest die Einstellung; was sich nicht lesen lässt, gilt als an',
    () async {
      final ordner = Directory.systemTemp.createTempSync('pv_appsperre_');
      addTearDown(() => ordner.deleteSync(recursive: true));
      final datei = File('${ordner.path}/app_sperre.json');
      expect(await AppSperre.leseEinstellung(datei), (false, Duration.zero));
      datei.writeAsStringSync('{"an": false, "frist": 60}');
      expect(await AppSperre.leseEinstellung(datei), (
        false,
        const Duration(minutes: 1),
      ));
      datei.writeAsStringSync('{"an": true, "fr');
      expect(await AppSperre.leseEinstellung(datei), (true, Duration.zero));
    },
  );

  test('merkt sich An und Frist und schaltet die Abdeckung', () async {
    final ordner = Directory.systemTemp.createTempSync('pv_appsperre_');
    addTearDown(() => ordner.deleteSync(recursive: true));
    final datei = File('${ordner.path}/app_sperre.json');
    final s = AppSperre(
      datei: datei,
      verfuegbar: () async => true,
      abdecken: (an) async => abdeckungen.add(an),
    );
    await s.setze(an: true, frist: const Duration(minutes: 5));
    expect(jsonDecode(datei.readAsStringSync()), {'an': true, 'frist': 300});
    await s.setze(an: false);
    expect(jsonDecode(datei.readAsStringSync()), {'an': false, 'frist': 300});
    expect(abdeckungen, [true, false]);
    expect(s.gesperrt, isFalse);
    expect(File('${datei.path}.neu').existsSync(), isFalse, reason: 'atomar');
  });
}
