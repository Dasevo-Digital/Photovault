import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/ortsvorschlag.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/l10n/app_localizations_de.dart';
import 'package:photo_vault/screens/ortsvorschlaege_screen.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/theme/app_theme.dart';

/// Zwei Bündel, ohne dass erst Fotos verortet werden müssen.
class _ZweiBuendel extends LibraryState {
  @override
  Future<List<Ortsbuendel>> ortsvorschlagsbuendel() async => [
    for (final (tag, id) in [
      (DateTime(2024, 5, 4), 'a'),
      (DateTime(2024, 6, 8), 'b'),
    ])
      Ortsbuendel(tag, [
        Ortsvorschlag(
          assetId: id,
          breite: 53.55,
          laenge: 9.99,
          nachbarn: 2,
          spanneKm: 0.1,
          abstand: const Duration(minutes: 5),
        ),
      ]),
  ];
}

/// **„Alle Vorschläge übernehmen?“ – bestätigt mit „Löschen“.**
///
/// Die Rückfrage rief confirmDialog ohne eigene Beschriftung; dessen
/// Vorgabe ist „Löschen“, obwohl hier nichts gelöscht wird.
void main() {
  late AppDatabase db;
  final de = AppTexteDe();

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  testWidgets('der Bestätigungsknopf heisst „Übernehmen“', (tester) async {
    final library = _ZweiBuendel()..db = db;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        theme: buildDarkTheme(),
        home: OrtsvorschlaegeScreen(library: library),
      ),
    );
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.tap(find.text(de.ortVorschlagAlleUebernehmen(2)));
    await tester.pumpAndSettle();
    final knopf = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(FilledButton),
    );
    expect(
      find.descendant(of: knopf, matching: find.text(de.allgUebernehmen)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: knopf, matching: find.text(de.allgLoeschen)),
      findsNothing,
    );
  });
}
