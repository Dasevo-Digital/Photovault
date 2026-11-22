import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/xmp_import_screen.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/theme/app_theme.dart';

/// Hält jeden Befehl an, bis [weiter] erfüllt ist – damit sich der
/// Bildschirm mitten in einer Übernahme verlassen lässt.
class _AnhaltendeDatenbank extends AppDatabase {
  _AnhaltendeDatenbank() : super(NativeDatabase.memory());
  Completer<void>? weiter;

  @override
  Future<T> fuehreAus<T>(Befehl<T> befehl) async {
    await weiter?.future;
    return super.fuehreAus(befehl);
  }
}

/// „Alle übernehmen“ stand fest weiss in der Kopfleiste – im hellen
/// Erscheinungsbild weiss auf fast weiss (IMP-107).
void main() {
  late Directory wurzel;
  late _AnhaltendeDatenbank db;
  late LibraryState library;

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_xmp_knopf_');
    db = _AnhaltendeDatenbank();
    library = LibraryState()
      ..db = db
      ..paths = await StoragePaths.forTesting(
        Directory(p.join(wurzel.path, 'l')),
      );
    await db
        .into(db.assets)
        .insert(
          AssetsCompanion.insert(
            id: 'a',
            originalFileName: 'k.jpg',
            relativePath: 'originals/k.jpg',
            checksum: 'c',
            type: 'IMAGE',
            fileCreatedAt: DateTime(2024),
            importedAt: DateTime(2024),
            rating: const Value(0),
          ),
        );
    final beilage = library.paths.absolute(
      library.paths.xmpSidecarPath('originals/k.jpg'),
    );
    beilage.parent.createSync(recursive: true);
    beilage.writeAsStringSync(
      '<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF '
      'xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">'
      '<rdf:Description rdf:about="" '
      'xmlns:xmp="http://ns.adobe.com/xap/1.0/" xmp:Rating="4"/>'
      '</rdf:RDF></x:xmpmeta>',
    );
  });

  tearDown(() async {
    await db.close();
    wurzel.deleteSync(recursive: true);
  });

  double kontrast(Color a, Color b) {
    final la = a.computeLuminance(), lb = b.computeLuminance();
    return la > lb ? (la + 0.05) / (lb + 0.05) : (lb + 0.05) / (la + 0.05);
  }

  for (final (name, thema) in [
    ('hell', buildLightTheme()),
    ('dunkel', buildDarkTheme()),
  ]) {
    testWidgets('„Alle übernehmen“ ist $name lesbar', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('de'),
          localizationsDelegates: AppTexte.localizationsDelegates,
          supportedLocales: AppTexte.supportedLocales,
          theme: thema,
          home: XmpImportScreen(library: library),
        ),
      );
      await tester.runAsync(() async {
        for (var i = 0; i < 50; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
          if (find.byType(TextButton).evaluate().isNotEmpty) break;
        }
      });
      final de = AppTexte.of(tester.element(find.byType(XmpImportScreen)));
      final schrift = tester.widget<RichText>(
        find.descendant(
          of: find.widgetWithText(TextButton, de.xmpAlleUebernehmen),
          matching: find.byType(RichText),
        ),
      );
      // Die Fläche der Kopfleiste: ihr erstes Material, nicht das des
      // Knopfs (das ist durchsichtig).
      final leiste = tester
          .widget<Material>(
            find
                .descendant(
                  of: find.byType(AppBar),
                  matching: find.byType(Material),
                )
                .first,
          )
          .color!;
      final vorne = schrift.text.style!.color!;
      expect(
        kontrast(vorne, leiste),
        greaterThanOrEqualTo(3.0),
        reason: 'Schrift $vorne auf $leiste',
      );
    });
  }

  Future<void> zeige(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: XmpImportScreen(library: library),
      ),
    );
  }

  /// Wartet, bis der Lauf durch ist: Das Lesen geht in ein eigenes
  /// Isolate, und das kommt nur unter `runAsync` zu Ende.
  Future<void> bisGeladen(WidgetTester tester) async {
    for (var i = 0; i < 100; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await tester.pump();
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) return;
    }
  }

  // Mit Server ist die Bibliothek hier eine Kopie, und `bereit` holt jedes
  // fehlende Original. Der Bildschirm tat das gleich beim Öffnen für die
  // ganze Bibliothek samt Videos.
  testWidgets('verbunden holt das Einlesen keine Originale vom Server', (
    tester,
  ) async {
    final geholt = <String>[];
    library.paths.beschaffe = (pfad) async => geholt.add(pfad);
    await db
        .into(db.assets)
        .insert(
          AssetsCompanion.insert(
            id: 'fern',
            originalFileName: 'fern.mov',
            relativePath: 'originals/fern.mov',
            checksum: 'f',
            type: 'VIDEO',
            fileCreatedAt: DateTime(2024),
            importedAt: DateTime(2024),
          ),
        );
    await tester.runAsync(() async {
      await zeige(tester);
      await bisGeladen(tester);
    });
    expect(geholt, isEmpty);
    // Die Beilage, die hier liegt, kommt trotzdem an.
    expect(find.textContaining('k.jpg'), findsOneWidget);
  });

  // Wer den Bildschirm verliess, während „Alle übernehmen“ lief, bekam eine
  // Ausnahme aus dem nächsten setState, und der Rest blieb liegen.
  testWidgets('Verlassen während „Alle übernehmen“ übernimmt trotzdem alles', (
    tester,
  ) async {
    await db.insertFace(
      FacesCompanion.insert(
        id: 'g',
        assetId: 'a',
        boxX: 0.4,
        boxY: 0.4,
        boxW: 0.2,
        boxH: 0.2,
      ),
    );
    library.paths
        .absolute(library.paths.xmpSidecarPath('originals/k.jpg'))
        .writeAsStringSync('''
<x:xmpmeta xmlns:x="adobe:ns:meta/">
 <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
  <rdf:Description rdf:about="" xmlns:xmp="http://ns.adobe.com/xap/1.0/" xmp:Rating="4"/>
  <rdf:Description rdf:about=""
    xmlns:mwg-rs="http://www.metadataworkinggroup.com/schemas/regions/"
    xmlns:stArea="http://ns.adobe.com/xmp/sType/Area#">
   <mwg-rs:Regions rdf:parseType="Resource">
    <mwg-rs:RegionList>
     <rdf:Bag>
      <rdf:li rdf:parseType="Resource">
       <mwg-rs:Name>Anna</mwg-rs:Name>
       <mwg-rs:Type>Face</mwg-rs:Type>
       <mwg-rs:Area stArea:x="0.5" stArea:y="0.5" stArea:w="0.2" stArea:h="0.2" stArea:unit="normalized"/>
      </rdf:li>
     </rdf:Bag>
    </mwg-rs:RegionList>
   </mwg-rs:Regions>
  </rdf:Description>
 </rdf:RDF>
</x:xmpmeta>''');
    await tester.runAsync(() async {
      await zeige(tester);
      await bisGeladen(tester);
    });
    final de = AppTexte.of(tester.element(find.byType(XmpImportScreen)));
    final knopf = find.widgetWithText(TextButton, de.xmpAlleUebernehmen);
    expect(knopf, findsOneWidget);
    db.weiter = Completer<void>();
    await tester.tap(knopf);
    await tester.pumpWidget(const SizedBox());
    db.weiter!.complete();
    await tester.runAsync(() async {
      for (var i = 0; i < 50; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
    });
    final personen = await db.allePersonen();
    expect(personen.single.name, 'Anna');
    expect((await db.facesForAsset('a')).single.personId, personen.single.id);
    expect((await db.assetById('a'))!.rating, 4);
  });
}
