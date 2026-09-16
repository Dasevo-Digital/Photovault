import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/integrity_check_screen.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/theme/app_theme.dart';

/// **Sichtung vor dem Löschen.**
///
/// Die Integritätsprüfung bietet zwei unwiderrufliche Schritte an: eine
/// verwaiste Datei von der Platte löschen und eine Zeile ohne Datei aus
/// der Datenbank austragen. Angezeigt wurde bis hierher nur der Pfad –
/// und ein Pfad wie `thumbnails/3f2a….jpg` sagt nichts darüber, was
/// darin steckt.
///
/// Die beiden Fälle liegen verschieden herum: Bei der verwaisten Datei
/// gibt es die Datei und keine Zeile, bei der fehlenden die Zeile und
/// keine Datei. Zu sehen gibt es einmal die Datei selbst, einmal das
/// Vorschaubild der Aufnahme.
void main() {
  late Directory wurzel;
  late AppDatabase db;
  late LibraryState library;
  late StoragePaths paths;

  /// Ein 1×1-PNG – gross genug, dass Flutter es dekodiert, und klein
  /// genug, dass es hier hineinpasst.
  final einPixel = <int>[
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
    0x00,
    0x00,
    0x00,
    0x0D,
    0x49,
    0x48,
    0x44,
    0x52,
    0x00,
    0x00,
    0x00,
    0x01,
    0x00,
    0x00,
    0x00,
    0x01,
    0x08,
    0x06,
    0x00,
    0x00,
    0x00,
    0x1F,
    0x15,
    0xC4,
    0x89,
    0x00,
    0x00,
    0x00,
    0x0D,
    0x49,
    0x44,
    0x41,
    0x54,
    0x78,
    0x9C,
    0x63,
    0xF8,
    0xCF,
    0xC0,
    0x00,
    0x00,
    0x03,
    0x01,
    0x01,
    0x00,
    0x18,
    0xDD,
    0x8D,
    0xB0,
    0x00,
    0x00,
    0x00,
    0x00,
    0x49,
    0x45,
    0x4E,
    0x44,
    0xAE,
    0x42,
    0x60,
    0x82,
  ];

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_integ_');
    db = AppDatabase(NativeDatabase.memory());
    paths =
        await StoragePaths.forTesting(Directory(p.join(wurzel.path, 'lib')));
    library = LibraryState()
      ..db = db
      ..paths = paths;
  });

  tearDown(() async {
    await db.close();
    wurzel.deleteSync(recursive: true);
  });

  /// Legt eine Datei an und datiert sie zurueck.
  ///
  /// Die Pruefung laesst Dateien juenger als eine Minute in Ruhe – sonst
  /// meldete sie jede Datei eines gerade laufenden Imports als verwaist.
  /// Ohne das Zurueckdatieren faende der Pruefstand hier also nichts.
  void lege(String relativ) {
    final datei = paths.absolute(relativ);
    datei.parent.createSync(recursive: true);
    datei.writeAsBytesSync(einPixel);
    datei
        .setLastModifiedSync(DateTime.now().subtract(const Duration(hours: 2)));
  }

  Future<void> zeige(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      theme: buildDarkTheme(),
      home: IntegrityCheckScreen(library: library),
    ));
    // Die Pruefung laeuft in einem **eigenen Isolate**. Dessen Antwort
    // kommt in echter Zeit; die Uhr des Pruefstands ist gestellt. Ohne
    // runAsync wartet man mit einer angehaltenen Uhr auf etwas, das nur
    // die laufende kennt. pumpAndSettle ginge ohnehin nicht, solange
    // sich der Ladering dreht.
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 800)));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> aufnahme(String id,
          {required String original,
          String? vorschau,
          bool gesperrt = false}) =>
      db.into(db.assets).insert(AssetsCompanion.insert(
            id: id,
            originalFileName: '$id.jpg',
            relativePath: original,
            checksum: 'c$id',
            type: 'IMAGE',
            fileCreatedAt: DateTime(2026, 3, 5),
            importedAt: DateTime(2026),
            thumbnailRelativePath: Value(vorschau),
            isLocked: Value(gesperrt),
          ));

  testWidgets('eine verwaiste Datei zeigt sich selbst', (tester) async {
    lege('thumbnails/verwaist.png');
    await zeige(tester);

    expect(find.text(p.join('thumbnails', 'verwaist.png')), findsOneWidget);
    expect(find.text('Ansehen'), findsOneWidget);

    await tester.tap(find.text('Ansehen'));
    await tester.pumpAndSettle();
    expect(find.text('Vorschau'), findsOneWidget);
    // Nicht nur ein Rahmen: Im Blatt steht wirklich das Bild.
    expect(find.byType(Image), findsWidgets);
  });

  testWidgets('eine fehlende Datei zeigt das Vorschaubild ihrer Aufnahme',
      (tester) async {
    // Die Datei fehlt, die Zeile steht - und mit ihr das Vorschaubild.
    lege('thumbnails/da.png');
    await aufnahme('a1',
        original: 'originals/weg.jpg', vorschau: 'thumbnails/da.png');
    await zeige(tester);

    expect(find.text('originals/weg.jpg'), findsOneWidget);
    expect(find.text('Ansehen'), findsOneWidget);
  });

  testWidgets('ohne Vorschaubild bleibt es beim Zeichen', (tester) async {
    await aufnahme('a1', original: 'originals/weg.jpg');
    await zeige(tester);
    expect(find.text('originals/weg.jpg'), findsOneWidget);
    expect(find.text('Ansehen'), findsNothing);
  });

  testWidgets('bei einer gesperrten Aufnahme gibt es nichts zu sehen',
      (tester) async {
    // Das Vorschaubild ist mitverschluesselt; ein Bild, das sich nicht
    // dekodieren laesst, waere ein leeres Feld - und das sagt weniger
    // als kein Feld.
    lege('thumbnails/gesperrt.png');
    await aufnahme('a1',
        original: 'originals/weg.jpg',
        vorschau: 'thumbnails/gesperrt.png',
        gesperrt: true);
    await zeige(tester);
    expect(find.text('originals/weg.jpg'), findsOneWidget);
    expect(find.text('Ansehen'), findsNothing);
  });

  testWidgets('ein Format, das Flutter nicht dekodiert, bekommt keinen Knopf',
      (tester) async {
    // HEIC und RAW kann Flutter nicht - dort bliebe ein leeres Feld.
    lege('originals/verwaist.heic');
    await zeige(tester);
    expect(find.text(p.join('originals', 'verwaist.heic')), findsOneWidget);
    expect(find.text('Ansehen'), findsNothing);
  });

  testWidgets('die Rueckfrage vor dem Loeschen zeigt das Bild', (tester) async {
    // Der eigentliche Punkt: nicht irgendwo nachsehen koennen, sondern
    // es genau dann sehen, wenn man entscheidet.
    lege('thumbnails/verwaist.png');
    await zeige(tester);
    await tester.tap(find.text('Datei löschen'));
    await tester.pumpAndSettle();
    expect(find.text('Datei löschen?'), findsWidgets);
    final bilder = tester.widgetList<Image>(find.descendant(
        of: find.byType(AlertDialog), matching: find.byType(Image)));
    expect(bilder, isNotEmpty);
  });
}
