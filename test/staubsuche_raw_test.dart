import 'dart:io';
import 'dart:math' as math;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/staubsuche_screen.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';

/// **Die Staubsuche muss auch bei RAW-Aufnahmen etwas untersuchen.**
///
/// Das `image`-Paket dekodiert weder CR3 noch DNG – es gibt nach wenigen
/// Millisekunden `null` zurück. Der erste Entwurf las deshalb bei einer
/// Canon EOS R10 (939 Aufnahmen, 821 davon CR3) von vierzig gezogenen
/// Aufnahmen ganze fünf und meldete danach „kein Sensorstaub gefunden".
///
/// Die Vorschaudatei liegt für jede dieser Aufnahmen längst daneben, mit
/// 2048 Punkten an der langen Kante – über den 1024, auf die die Suche
/// ohnehin verkleinert. Genau diesen Weg nimmt der Rest der App (siehe
/// `LibraryState._decodeAsset`).
void main() {
  late Directory temp;
  late AppDatabase db;
  late StoragePaths pfade;
  late LibraryState library;

  setUp(() async {
    temp = Directory.systemTemp.createTempSync('pv_staub_raw_');
    db = AppDatabase(NativeDatabase.memory());
    pfade = await StoragePaths.forTesting(Directory(p.join(temp.path, 'lib')));
    library = LibraryState()
      ..db = db
      ..paths = pfade;
  });
  tearDown(() async {
    await db.close();
    temp.deleteSync(recursive: true);
  });

  /// Ein gleichmässiger Himmel mit einem Staubkorn – dieselbe Vorlage wie in
  /// `staubflecken_test.dart`, nur als Datei.
  List<int> himmelMitKorn(int seed) {
    final zufall = math.Random(seed);
    final b = img.Image(width: 800, height: 600);
    for (var y = 0; y < b.height; y++) {
      for (var x = 0; x < b.width; x++) {
        final g = 210 - (y * 30 ~/ b.height) + zufall.nextInt(3);
        b.setPixelRgb(x, y, g, g, g + 12);
      }
    }
    const mx = 240, my = 132, r = 6.0;
    for (var dy = -20; dy <= 20; dy++) {
      for (var dx = -20; dx <= 20; dx++) {
        final d = math.sqrt(dx * dx + dy * dy);
        if (d > r * 1.8) continue;
        final neu = (b.getPixel(mx + dx, my + dy).r - 55 * math.exp(-(d * d) / (r * r)))
            .clamp(0, 255)
            .toInt();
        b.setPixelRgb(mx + dx, my + dy, neu, neu, neu);
      }
    }
    return img.encodeJpg(b, quality: 95);
  }

  /// Eine CR3-Aufnahme: Original nicht dekodierbar, Vorschau daneben.
  Future<void> legeRaw(String id, DateTime wann) async {
    final original = 'originals/$id.cr3';
    final vorschau = pfade.previewRelativePath(id);
    pfade.absolute(original)
      ..createSync(recursive: true)
      // Was in einer CR3 steht, interessiert hier nicht – nur, dass das
      // `image`-Paket damit nichts anfangen kann.
      ..writeAsBytesSync(List.filled(4096, 7));
    pfade.absolute(vorschau)
      ..createSync(recursive: true)
      ..writeAsBytesSync(himmelMitKorn(id.hashCode));
    await db.insertAsset(AssetsCompanion.insert(
      id: id,
      relativePath: original,
      originalFileName: '$id.CR3',
      type: 'IMAGE',
      checksum: id,
      fileCreatedAt: wann,
      importedAt: wann,
      cameraModel: const Value('Canon EOS R10'),
      dateiformat: const Value('cr3'),
      previewRelativePath: Value(vorschau),
      thumbnailRelativePath: Value(vorschau),
    ));
  }

  testWidgets('eine Serie aus RAW-Aufnahmen wird untersucht, nicht übersprungen',
      (tester) async {
    for (var i = 0; i < 8; i++) {
      await legeRaw('r$i', DateTime(2024, 1, 1 + i));
    }

    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      home: StaubsucheScreen(library: library),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Canon EOS R10').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Suchen'));

    // Jede Aufnahme geht durch ein eigenes Isolat (`compute`), und das
    // braucht die **echte** Ereignisschleife: `pump` dreht nur die
    // Testuhr weiter, und der Lauf käme über „0 von 8" nie hinaus.
    for (var i = 0; i < 120; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      // Nach dem Ergebnis suchen, nicht nach einer Wendung, die schon im
      // Erklärungstext oben steht.
      if (find.textContaining('untersuchten Aufnahmen').evaluate().isNotEmpty) {
        break;
      }
    }

    // Der Befund selbst: acht Aufnahmen mit demselben Korn an derselben
    // Stelle. Vor der Umstellung stand hier „Auf 0 untersuchten Aufnahmen
    // wurde kein Sensorstaub gefunden."
    expect(find.textContaining('kein Sensorstaub'), findsNothing);
    expect(find.textContaining('Stelle, die immer wieder'), findsOneWidget);
    // Die Zahl dahinter: alle acht, nicht ein Rest.
    expect(find.textContaining('auf 8 von 8'), findsOneWidget);
  });

  testWidgets('was nicht gelesen werden konnte, steht dabei', (tester) async {
    // „Kein Sensorstaub gefunden" nach fünf von vierzig Aufnahmen ist keine
    // Entwarnung, und der Zahl allein sieht man den Unterschied nicht an.
    for (var i = 0; i < 4; i++) {
      await legeRaw('r$i', DateTime(2024, 1, 1 + i));
    }
    // Zwei, deren Vorschau fehlt – der Fall „Datei nicht lesbar".
    for (var i = 4; i < 6; i++) {
      await legeRaw('r$i', DateTime(2024, 1, 1 + i));
      pfade.absolute(pfade.previewRelativePath('r$i')).deleteSync();
    }

    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      home: StaubsucheScreen(library: library),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Canon EOS R10').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Suchen'));

    for (var i = 0; i < 120; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      if (find.textContaining('übersprungen').evaluate().isNotEmpty) break;
    }

    expect(find.textContaining('2 von 6'), findsOneWidget);
  });
}