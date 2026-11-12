import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
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

  setUp(() {
    uhr = DateTime(2026, 11, 12, 12);
    fragen = [];
    antwort = true;
    abdeckungen = [];
  });

  AppSperre sperre({bool an = true, Duration frist = Duration.zero}) =>
      AppSperre(
        an: an,
        frist: frist,
        pruefe: (grund) async {
          fragen.add(grund);
          return antwort;
        },
        verfuegbar: () async => true,
        jetzt: () => uhr,
        abdecken: (an) async => abdeckungen.add(an),
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
    uhr = uhr.add(const Duration(minutes: 3));
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
    uhr = uhr.add(const Duration(minutes: 6));
    antwort = false;
    await wechsle(tester, [
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]);
    expect(s.gesperrt, isTrue);
    expect(fragen, hasLength(1));
    expect(find.text('Photo Vault ist gesperrt'), findsOneWidget);
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
  });
}
