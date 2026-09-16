import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/face_review_screen.dart';
import 'package:photo_vault/services/backup_service.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/theme/app_theme.dart';

/// Der Rechtsklick in der Gesichts-Vollbildansicht.
///
/// Sie ist der Bildschirm, auf dem man unter „Personen" tatsächlich
/// arbeitet – per Doppelklick auf ein Gesicht oder auf ein Foto einer
/// Person. Gemeldet wurde, dass der Rechtsklick dort nichts tut.
void main() {
  late Directory tempRoot;
  late AppDatabase db;
  late LibraryState library;
  late AssetData asset;

  setUp(() async {
    tempRoot = Directory.systemTemp.createTempSync('pv_gesicht_kontext_');
    db = AppDatabase(NativeDatabase.memory());
    final paths = await StoragePaths.forTesting(Directory(p.join(tempRoot.path, 'lib')));
    library = LibraryState()
      ..db = db
      ..paths = paths
      ..backupService = BackupService(db, paths);

    // Eine echte Bilddatei, sonst meldet Image.file einen Ladefehler und
    // der zählt im Test als Ausnahme.
    final datei = paths.absolute('originals/a1.jpg');
    datei.parent.createSync(recursive: true);
    datei.writeAsBytesSync(Uint8List.fromList([
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
      0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
      0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
      0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
      0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
      0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
      0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
      0x42, 0x60, 0x82,
    ]));

    await db.into(db.assets).insert(AssetsCompanion.insert(
          id: 'a1',
          originalFileName: 'a1.jpg',
          relativePath: 'originals/a1.jpg',
          checksum: 'c1',
          type: 'IMAGE',
          fileCreatedAt: DateTime(2026, 1, 1),
          importedAt: DateTime(2026, 1, 1),
          // Gesetzt, damit nicht die Datei dekodiert werden muss.
          widthPx: const Value(1000),
          heightPx: const Value(800),
        ));
    await db.insertFace(FacesCompanion.insert(
      id: 'f1',
      assetId: 'a1',
      boxX: 0.1,
      boxY: 0.1,
      boxW: 0.3,
      boxH: 0.3,
      cropRelativePath: const Value('faces/f1.jpg'),
    ));
    asset = (await db.assetById('a1'))!;
  });

  tearDown(() async {
    await db.close();
    await _raeumeAuf(tempRoot);
  });

  /// [neuAufbauen] erzwingt einen frischen Zustand. Ohne einen anderen
  /// Schlüssel erkennt Flutter beim zweiten Aufruf dasselbe Widget wieder,
  /// initState läuft nicht erneut – und der Bildschirm zeigt weiter den
  /// alten Datenbankstand.
  Future<void> zeige(WidgetTester tester, {Object? neuAufbauen}) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      theme: buildDarkTheme(),
      home: FaceReviewScreen(
        key: ValueKey(neuAufbauen ?? 'erst'),
        library: library,
        assets: [asset],
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// Wartet, bis [pruefung] zutrifft – für Schritte, die echtes Datei-I/O
  /// auslösen. `pumpAndSettle` pumpt Bilder, keine Dateisystem-Aufrufe;
  /// ohne dieses Warten prüfte der Test, während das Löschen noch läuft.
  Future<void> bisDann(WidgetTester tester, bool Function() pruefung) async {
    await tester.runAsync(() async {
      for (var i = 0; i < 100 && !pruefung(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
  }

  Future<void> rechtsklick(WidgetTester tester, Offset stelle) async {
    final maus = await tester.createGesture(
        kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
    await maus.down(stelle);
    await maus.up();
    await tester.pumpAndSettle();
  }

  testWidgets('Rechtsklick auf ein Gesicht öffnet ein Menü', (tester) async {
    await zeige(tester);
    // Auf den Gesichtsrahmen – er trägt die Beschriftung „Unbenannt".
    await rechtsklick(tester, tester.getCenter(find.text('Unbenannt')));
    expect(find.text('Ignorieren'), findsOneWidget);
  });

  testWidgets('Rechtsklick daneben öffnet ebenfalls ein Menü', (tester) async {
    await zeige(tester);
    await rechtsklick(tester, const Offset(700, 500));
    expect(find.text('Gesicht manuell hinzufügen'), findsOneWidget);
  });

  testWidgets('das Menü unterscheidet Rahmen von freier Fläche',
      (tester) async {
    await zeige(tester);

    // Auf dem Gesicht: die gesichtsbezogenen Einträge.
    await rechtsklick(tester, tester.getCenter(find.text('Unbenannt')));
    expect(find.text('Erkennung löschen'), findsOneWidget);
    expect(find.text('Gesicht benennen'), findsOneWidget);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    // Daneben: nur, was das ganze Foto betrifft.
    await rechtsklick(tester, const Offset(700, 500));
    expect(find.text('Erkennung löschen'), findsNothing,
        reason: 'ohne Gesicht gibt es nichts zu löschen');
    expect(find.text('Gesicht manuell hinzufügen'), findsOneWidget);
  });

  testWidgets('„Ignorieren" wirkt und der Rahmen wechselt die Beschriftung',
      (tester) async {
    await zeige(tester);
    await rechtsklick(tester, tester.getCenter(find.text('Unbenannt')));
    await tester.tap(find.text('Ignorieren'));
    await tester.pumpAndSettle();

    expect((await db.facesForAsset('a1')).single.isIgnored, isTrue);
    expect(find.text('Ignoriert'), findsOneWidget);

    // Und derselbe Weg wieder zurück.
    await rechtsklick(tester, tester.getCenter(find.text('Ignoriert')));
    expect(find.text('Nicht mehr ignorieren'), findsOneWidget);
    expect(find.text('Ignorieren'), findsNothing);
  });

  testWidgets('„Erkennung löschen" entfernt Zeile und Ausschnittdatei',
      (tester) async {
    // Die Datei mitzunehmen ist der Punkt: Bliebe sie liegen, wäre der
    // Platz nicht frei, und das ist der einzige Vorteil des Löschens
    // gegenüber dem Beiseitelegen.
    final ausschnitt = library.paths.absolute('faces/f1.jpg');
    ausschnitt.parent.createSync(recursive: true);
    ausschnitt.writeAsStringSync('x');

    await zeige(tester);
    await rechtsklick(tester, tester.getCenter(find.text('Unbenannt')));
    await tester.tap(find.text('Erkennung löschen'));
    await tester.pumpAndSettle();

    await bisDann(tester, () => !ausschnitt.existsSync());
    expect(await db.facesForAsset('a1'), isEmpty);
    expect(ausschnitt.existsSync(), isFalse);
  });

  testWidgets('„Zuordnung lösen" gibt es nur bei benannten Gesichtern',
      (tester) async {
    await zeige(tester);
    await rechtsklick(tester, tester.getCenter(find.text('Unbenannt')));
    expect(find.text('Zuordnung lösen'), findsNothing);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    await db.createPerson(PeopleCompanion.insert(id: 'p1', name: 'Anna'));
    await db.assignFacesToPerson(['f1'], 'p1');
    await zeige(tester, neuAufbauen: 'mitPerson');

    await rechtsklick(tester, tester.getCenter(find.text('Anna')));
    expect(find.text('Zuordnung lösen'), findsOneWidget);
    await tester.tap(find.text('Zuordnung lösen'));
    await tester.pumpAndSettle();

    final f = (await db.facesForAsset('a1')).single;
    expect(f.personId, isNull, reason: 'die Person ist weg');
    expect(f.isIgnored, isFalse, reason: 'das Gesicht selbst bleibt');
  });

  testWidgets('„Gesicht manuell hinzufügen" schaltet den Modus ein',
      (tester) async {
    // Bisher war das nur über das Symbol oben rechts erreichbar – und der
    // Leertext des Rasters schickt die Leute genau hierher.
    await zeige(tester);
    await rechtsklick(tester, const Offset(700, 500));
    await tester.tap(find.text('Gesicht manuell hinzufügen'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Ziehe ein Rechteck'), findsOneWidget);
  });

  testWidgets('die Rahmen lassen sich aus- und wieder einblenden',
      (tester) async {
    // Bei einem Gruppenfoto liegen schnell ein Dutzend Kästen über dem
    // Bild – dann sieht man die Rahmen und nicht mehr das Foto.
    await zeige(tester);
    expect(find.text('Unbenannt'), findsOneWidget);

    await tester.tap(find.byTooltip('Rahmen ausblenden'));
    await tester.pumpAndSettle();
    expect(find.text('Unbenannt'), findsNothing);

    await tester.tap(find.byTooltip('Rahmen einblenden'));
    await tester.pumpAndSettle();
    expect(find.text('Unbenannt'), findsOneWidget);
  });

  testWidgets('ausgeblendete Rahmen findet man über den Rechtsklick zurück',
      (tester) async {
    // Sind die Rahmen weg, sucht man den Weg zurück dort, wo man gerade
    // hinsieht – nicht in der Titelleiste.
    await zeige(tester);
    await tester.tap(find.byTooltip('Rahmen ausblenden'));
    await tester.pumpAndSettle();

    await rechtsklick(tester, const Offset(700, 500));
    expect(find.text('Rahmen einblenden'), findsOneWidget);
    await tester.tap(find.text('Rahmen einblenden'));
    await tester.pumpAndSettle();

    expect(find.text('Unbenannt'), findsOneWidget);
  });
}

/// Räumt den Testordner ab und erträgt eine kurz gesperrte Datei.
///
/// **Warum das nötig ist.** Unter Windows lässt sich eine geöffnete Datei
/// nicht löschen; POSIX erlaubt es. Nach dem Antippen von „Erkennung
/// löschen" bleibt die angezeigte Originaldatei dort gesperrt – gemessen
/// über acht Sekunden hinweg, 54 Versuche.
///
/// Das ist **kein** Fehler im Löschpfad der App: Die vier übrigen Tests
/// dieser Datei zeigen dasselbe Foto an und löschen es anschliessend ohne
/// jede Verzögerung („frei nach 1 Versuch, 0 ms"). Den Bildzwischenspeicher
/// zu leeren ändert ebenfalls nichts. Es hängt an dieser einen Aktion im
/// Testkontext, und der Gegenstand dieses Tests ist das Kontextmenü, nicht
/// das Aufräumen.
///
/// Deshalb: mehrfach versuchen, und wenn es dabei bleibt, den Ordner dem
/// Betriebssystem überlassen, statt den Test an seinem Abbau scheitern zu
/// lassen. Unter macOS und Linux greift der erste Versuch immer.
Future<void> _raeumeAuf(Directory ordner) async {
  for (var versuch = 0; versuch < 10; versuch++) {
    try {
      ordner.deleteSync(recursive: true);
      return;
    } on FileSystemException {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
  // Ein Rest im Temp-Ordner ist ärgerlich, aber kein Grund, einen grünen
  // Test rot zu färben. Das Betriebssystem räumt ihn beim nächsten Mal weg.
}
