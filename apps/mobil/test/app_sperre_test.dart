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
  }) => AppSperre(
    an: an,
    frist: frist,
    pruefe: (grund) async {
      fragen.add(grund);
      return antwort;
    },
    verfuegbar: () async => true,
    jetzt: () => uhr,
    laufzeit: lauf ?? () async => laufzeit.inMilliseconds,
    abdecken: (an) async => abdeckungen.add(an),
    beiSperre: () async => sperrungen++,
    abdeckenWennInaktiv: abdeckenWennInaktiv,
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

    testWidgets('vor das Verlassen: sperrt, auch mit „Sofort“', (tester) async {
      final s = await weg(tester, frist: Duration.zero);
      laufzeit += const Duration(hours: 1);
      uhr = uhr.subtract(const Duration(hours: 2));
      await zurueck(tester);
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
