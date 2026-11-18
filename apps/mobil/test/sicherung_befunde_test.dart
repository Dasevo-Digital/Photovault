// Sicherung: behobene Befunde aus dem Prüfkatalog der Handy-App (MOB,
// Issue #418): je Befund ein Test, der ohne die Korrektur scheitert.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_manager/photo_manager.dart' show PermissionState;
import 'package:photo_vault_mobil/l10n/app_localizations.dart';
import 'package:photo_vault_mobil/seiten/sicherung.dart';
import 'package:photo_vault_mobil/sicherung/dienst.dart';
import 'package:photo_vault_mobil/sicherung/kamerarolle.dart';
import 'package:photo_vault_mobil/sicherung/stand.dart';

Widget _app(Widget home) => MaterialApp(
  locale: const Locale('de'),
  localizationsDelegates: AppTexte.localizationsDelegates,
  supportedLocales: AppTexte.supportedLocales,
  home: home,
);

/// Eine Kamerarolle mit festen Einträgen, ohne Dateien.
class _Rolle implements Kamerarolle {
  _Rolle(this.ids);

  final List<String> ids;

  @override
  Future<List<Rolleneintrag>> eintraege({required bool videos}) async => [
    for (final id in ids)
      Rolleneintrag(
        id: id,
        geaendert: DateTime(2026, 6, 1),
        aufgenommen: DateTime(2026, 6, 1, 12),
        video: false,
        dateien: () async => null,
      ),
  ];

  @override
  Future<void> aufraeumen() async {}

  @override
  Future<int> loesche(List<String> ids) async => 0;

  @override
  Future<List<String>> vorhanden(List<String> ids) async => ids;
}

Sicherungsdienst _dienst(
  Sicherungseinstellungen e, {
  Kamerarolle Function(List<String> alben)? rolle,
}) {
  final ordner = Directory.systemTemp.createTempSync('pv_sicherung_befund_');
  addTearDown(() => ordner.deleteSync(recursive: true));
  Sicherungsstand.oeffne(ordner)
    ..einstellungen = e
    ..schliesse();
  final d = Sicherungsdienst(
    ordner: ordner,
    server: Uri.parse('http://localhost:1/'),
    token: 'pv1_test',
    rolle: rolle,
  );
  addTearDown(d.dispose);
  return d;
}

void main() {
  testWidgets('MOB-021 abgemeldet: die Sicherungsseite sagt es auch bei '
      'ausgeschalteter Sicherung', (tester) async {
    final d = _dienst(const Sicherungseinstellungen());
    await tester.pumpWidget(_app(Sicherungsseite(dienst: d)));
    await tester.pumpAndSettle();
    final t = AppTexte.of(tester.element(find.byType(Sicherungsseite)));
    expect(find.text(t.abgemeldetHinweis), findsNothing);

    d.meldeAbgemeldet(true);
    await tester.pumpAndSettle();
    expect(find.text(t.abgemeldetHinweis), findsOneWidget);
  });

  testWidgets('MOB-171 Zugriff in den Einstellungen erteilt: zurück in der '
      'App verschwindet „Kein Zugriff“ ohne Neustart', (tester) async {
    const kanal = MethodChannel('com.fluttercandies/photo_manager');
    final bote = tester.binding.defaultBinaryMessenger;
    var erlaubt = false;
    bote.setMockMethodCallHandler(kanal, (aufruf) async {
      if (aufruf.method == 'getPermissionState') {
        return (erlaubt ? PermissionState.authorized : PermissionState.denied)
            .index;
      }
      return null;
    });
    addTearDown(() => bote.setMockMethodCallHandler(kanal, null));

    // Eingeschaltet scheiterte am verweigerten Zugriff: Schalter aus.
    final d = _dienst(const Sicherungseinstellungen())
      ..zugriff = Zugriff.verweigert;
    await tester.pumpWidget(_app(Sicherungsseite(dienst: d)));
    await tester.pumpAndSettle();
    final t = AppTexte.of(tester.element(find.byType(Sicherungsseite)));
    expect(find.text(t.sicherungKeinZugriff), findsOneWidget);

    erlaubt = true;
    await tester.runAsync(d.zurueckInDerApp);
    await tester.pumpAndSettle();
    expect(d.zugriff, Zugriff.erlaubt);
    expect(find.text(t.sicherungKeinZugriff), findsNothing);
  });

  test('MOB-180 nur gewählte Alben: „nur auf dem Telefon“ zählt nur, was '
      'ein Lauf sichern würde', () async {
    final alle = _Rolle(['a1', 'a2', 'a3', 'b1', 'b2']);
    final urlaub = _Rolle(['a1', 'a2', 'a3']);
    final d = _dienst(
      const Sicherungseinstellungen(an: true, alben: ['urlaub']),
      rolle: (alben) => alben.isEmpty ? alle : urlaub,
    )..zugriff = Zugriff.erlaubt;
    await d.zaehleUngesicherte();
    expect([for (final l in d.ungesichert!) l.id], ['a1', 'a2', 'a3']);
  });
}
