import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/bibliothek_unerreichbar_screen.dart';
import 'package:photo_vault/services/library_location.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/theme/app_theme.dart';

/// Der Startbildschirm für eine Bibliothek, die sich nicht öffnen lässt.
///
/// Er ersetzt den stillen Rückfall auf den Standardordner. Geprüft wird,
/// dass er sagt, welche Bibliothek wo fehlt, und alle Wege hinaus anbietet.
class _Zustand extends LibraryState {
  _Zustand(this._eintrag);
  final Bibliothekseintrag _eintrag;
  @override
  Bibliothekseintrag? get unerreichbar => _eintrag;
}

void main() {
  testWidgets('nennt Bibliothek und Ort und bietet alle Wege an',
      (tester) async {
    const eintrag = Bibliothekseintrag(
        path: '/Volumes/Platte/Fotos', token: 'x', name: 'Familie');
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      theme: buildLightTheme(),
      home: BibliothekUnerreichbarScreen(library: _Zustand(eintrag)),
    ));

    expect(find.text('Bibliothek nicht erreichbar'), findsOneWidget);
    expect(find.textContaining('„Familie“'), findsOneWidget);
    expect(find.text('/Volumes/Platte/Fotos'), findsOneWidget);
    expect(find.text('Ordner freigeben …'), findsOneWidget);
    expect(find.text('Erneut versuchen'), findsOneWidget);
    expect(find.text('Standardbibliothek öffnen'), findsOneWidget);
    expect(find.text('Photo Vault beenden'), findsOneWidget);
  });

  test('nur ein Ordner mit Bibliothek wird angenommen', () async {
    // Wer im Ordnerdialog den Ordner darüber erwischt, bekäme sonst eine
    // neue, leere Bibliothek – die er dann für seine hält.
    final tmp = Directory.systemTemp.createTempSync('pv_freigabe');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final bib = Directory('${tmp.path}/Fotos')..createSync();
    expect(await enthaeltBibliothek(bib.path), isFalse);
    File('${bib.path}/library.sqlite').writeAsStringSync('db');
    expect(await enthaeltBibliothek(bib.path), isTrue);
    expect(await enthaeltBibliothek(tmp.path), isFalse,
        reason: 'der Ordner darüber ist keine Bibliothek');
  });
}
