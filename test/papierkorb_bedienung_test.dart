import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/trash_screen.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:path/path.dart' as p;

/// **Der Ausgang muss zu sehen sein.**
///
/// Die 16. Prüfrunde fand den Papierkorb ohne jede Tür; seit 2.2.1 führt
/// ein Weg hinein. Der Weg *heraus* lag danach immer noch hinter einem
/// langen Druck – einer Geste, die nirgends steht. Dieser Test besteht
/// darauf, dass Wiederherstellen ohne Vorwissen erreichbar ist.
void main() {
  late Directory wurzel;
  late AppDatabase db;
  late LibraryState library;

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_papierkorb_');
    db = AppDatabase(NativeDatabase.memory());
    library = LibraryState()
      ..db = db
      ..paths =
          await StoragePaths.forTesting(Directory(p.join(wurzel.path, 'lib')));
  });

  tearDown(() async {
    await db.close();
    wurzel.deleteSync(recursive: true);
  });

  Future<void> imPapierkorb(String id, {int bytes = 0}) async {
    await db.into(db.assets).insert(AssetsCompanion.insert(
          id: id,
          originalFileName: '$id.jpg',
          relativePath: 'originals/$id.jpg',
          checksum: 'pruef-$id',
          type: 'IMAGE',
          fileCreatedAt: DateTime(2026),
          importedAt: DateTime(2026),
          isTrashed: const Value(true),
          trashedAt: Value(DateTime(2026, 8, 1)),
          fileSizeBytes: Value(bytes),
        ));
  }

  /// Baut den Baum ab und lässt den Aufräum-Timer von drift auslaufen.
  ///
  /// Ohne das meldet flutter_test „A Timer is still pending even after the
  /// widget tree was disposed": Die Abmeldung eines `watch`-Stroms läuft
  /// über einen Timer mit Dauer null, und der fällt sonst hinter das Ende
  /// des Prüflaufs.
  Future<void> abbauen(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    // Zweimal und mit Dauer: Der Abmelde-Timer von drift entsteht ERST
    // beim Abbau des Baums, den der erste Durchlauf auslöst.
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 1));
  }

  Widget bildschirm() => MaterialApp(
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: TrashScreen(library: library),
      );

  testWidgets('jede Kachel trägt einen Wiederherstellen-Knopf',
      (tester) async {
    await imPapierkorb('a');
    await imPapierkorb('b');
    await tester.pumpWidget(bildschirm());
    await tester.pump();
    await tester.pump();

    expect(find.byIcon(Icons.restore_from_trash_outlined), findsNWidgets(2),
        reason: 'einer je Foto, ohne dass jemand lange drücken muss');

    await abbauen(tester);
  });

  testWidgets('der Knopf holt das Foto zurück', (tester) async {
    await imPapierkorb('a');
    await tester.pumpWidget(bildschirm());
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byIcon(Icons.restore_from_trash_outlined).first);
    await tester.pump();
    await tester.pump();

    final a = await (db.select(db.assets)..where((t) => t.id.equals('a')))
        .getSingle();
    expect(a.isTrashed, isFalse);

    await abbauen(tester);
  });

  testWidgets('und die Bedienung steht als Hinweis dabei', (tester) async {
    await imPapierkorb('a');
    await tester.pumpWidget(bildschirm());
    await tester.pump();
    await tester.pump();
    final t = AppTexte.of(tester.element(find.byType(TrashScreen)));
    expect(find.text(t.papierkorbHinweis), findsOneWidget);

    await abbauen(tester);
  });

  testWidgets('bei ausgewählten Fotos weicht der Kachelknopf der Leiste',
      (tester) async {
    await imPapierkorb('a');
    await imPapierkorb('b');
    await tester.pumpWidget(bildschirm());
    await tester.pump();
    await tester.pump();

    await tester.longPress(find.byType(GestureDetector).first);
    await tester.pump();
    await tester.pump();

    // Genau einer: der in der Leiste. Die Kachelknöpfe verschwinden,
    // sonst stünde neben der Auswahl eine zweite, widersprüchliche
    // Bedienung.
    expect(find.byIcon(Icons.restore_from_trash_outlined), findsOneWidget);

    await abbauen(tester);
  });

  /// **Wieviel hier liegt, muss dastehen.**
  ///
  /// An einer gewachsenen Bibliothek lagen 619 Aufnahmen und 6,01 GB im
  /// Papierkorb – sieben Prozent des Bestands. Weder dieser Bildschirm
  /// noch die Einstellungen nannten den Platz mit einem Wort, und die
  /// Zahl der Fotos allein sagt darüber nichts: 619 Bildschirmfotos wären
  /// ein Bruchteil davon.
  testWidgets('der Umfang steht über der Liste', (tester) async {
    await imPapierkorb('a', bytes: 3 * 1024 * 1024);
    await imPapierkorb('b', bytes: 5 * 1024 * 1024);
    await tester.pumpWidget(bildschirm());
    await tester.pump();
    await tester.pump();

    final t = AppTexte.of(tester.element(find.byType(TrashScreen)));
    expect(find.text(t.papierkorbUmfang(2, '8.0 MB')), findsOneWidget,
        reason: 'Zahl und Platz, sonst bleibt der Verbrauch unsichtbar');

    await abbauen(tester);
  });

  testWidgets('ein leerer Papierkorb nennt keinen Umfang', (tester) async {
    await tester.pumpWidget(bildschirm());
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('KB'), findsNothing);
    expect(find.textContaining('MB'), findsNothing);
    await abbauen(tester);
  });
}
