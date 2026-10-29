import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/import_plan.dart';
import 'package:kern/services/import_service.dart';
import 'package:kern/services/regelpruefung.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/screens/import_plan_screen.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

void main() {
  late AppDatabase db;
  late Directory temp;
  late StoragePaths pfade;
  late ImportService importe;
  late ImportPlanDienst dienst;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pv_importplan_');
    db = AppDatabase(NativeDatabase.memory());
    pfade = await StoragePaths.forTesting(
      Directory(p.join(temp.path, 'bibliothek')),
    );
    importe = ImportService(db, pfade);
    dienst = ImportPlanDienst(db, importe);
  });
  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });

  Future<String> foto(String name, List<int> bytes) async {
    final f = File(p.join(temp.path, name));
    await f.writeAsBytes(bytes);
    await f.setLastModified(DateTime(2026, 6, 1, 10));
    return f.path;
  }

  test(
    'Vorschau unterscheidet vorhandene und ausgewählte Dubletten ohne Schreibzugriff',
    () async {
      final alt = await foto('alt.jpg', [1, 2]);
      await importe.importFile(alt);
      final neu = await foto('neu.jpg', [3, 4]);
      final doppelt = await foto('kopie.jpg', [3, 4]);
      final fremd = await foto('notiz.txt', [7]);
      final vorher = await db.select(db.assets).get();
      final dateienVorher = await pfade.originalsDir
          .list(recursive: true)
          .toList();
      final plan = await dienst.erstelle([alt, neu, doppelt, fremd]);
      expect(plan.eintraege.map((e) => e.art), [
        ImportPlanArt.vorhanden,
        ImportPlanArt.neu,
        ImportPlanArt.doppelt,
        ImportPlanArt.format,
      ]);
      expect(plan.originalBytes, 2);
      expect(plan.eintraege[1].angaben!.datum, DateTime(2026, 6, 1, 10));
      expect(plan.eintraege[1].angaben!.datumGeschaetzt, isTrue);
      expect(await db.select(db.assets).get(), vorher);
      expect(
        (await pfade.originalsDir.list(recursive: true).toList()).map(
          (f) => f.path,
        ),
        dateienVorher.map((f) => f.path),
      );
    },
  );

  test(
    'Dateiname und Endung verwenden dieselbe Regelauswertung wie der Import',
    () async {
      await db.fuehreAus(AlbumAnlegen('urlaub', 'Urlaub', DateTime(2026)));
      await db.fuehreAus(
        RegelSpeichern(
          AutomationRulesCompanion.insert(
            id: 'r1',
            name: 'Urlaubsbilder',
            triggerType: 'dateiname',
            aiTagTerm: const Value('URLAUB'),
            targetAlbumId: const Value('urlaub'),
            autoFavorite: const Value(true),
          ),
        ),
      );
      await db.fuehreAus(
        RegelSpeichern(
          AutomationRulesCompanion.insert(
            id: 'r2',
            name: 'Foto',
            triggerType: 'dateiendung',
            aiTagTerm: const Value('.jpg, jpeg'),
          ),
        ),
      );
      await db.fuehreAus(
        RegelSpeichern(
          AutomationRulesCompanion.insert(
            id: 'r3',
            name: 'Nach Analyse',
            triggerType: 'aiTag',
            aiTagTerm: const Value('Berge'),
          ),
        ),
      );
      final quelle = await foto('urlaub.JPG', [8, 9]);
      final plan = await dienst.erstelle([quelle]);
      final e = plan.eintraege.single;
      expect(e.alben, ['Urlaub']);
      expect(e.favorit, isTrue);
      expect(e.regeln, ['Urlaubsbilder', 'Foto']);
      expect(plan.spaetereRegeln, 1);
      expect(plan.dateiregeln, isTrue);
      final regeln = await db.allAutomationRules();
      expect(
        regeln
            .where((r) => regelTrifftZu(r, dateiname: 'urlaub.JPG'))
            .map((r) => r.name),
        e.regeln,
      );
      expect((await db.assetsInAlbumOnce('urlaub')), isEmpty);
      expect((await db.select(db.assets).get()), isEmpty);
    },
  );

  test(
    'bestätigter Plan lehnt nachträglich veränderte Dateien ohne Importreste ab',
    () async {
      final quelle = await foto('a.jpg', [3, 6]);
      final plan = await dienst.erstelle([quelle]);
      File(quelle).writeAsBytesSync([9, 9]);
      final r = await importe.importFile(
        quelle,
        erwartetePruefsumme: plan.pruefsummen[quelle],
      );
      expect(r.outcome, ImportOutcome.failed);
      expect(await db.select(db.assets).get(), isEmpty);
      expect(
        await pfade.originalsDir
            .list(recursive: true)
            .where((f) => f is File)
            .toList(),
        isEmpty,
      );
    },
  );

  test(
    'Regelstand erkennt Änderungen, bleibt bei neuen fremden Tags und Favoriten stabil',
    () async {
      final vorher = await dienst.aktuellerRegelstand();
      await db.fuehreAus(
        RegelSpeichern(
          AutomationRulesCompanion.insert(
            id: 'r',
            name: 'Neu',
            triggerType: 'dateiname',
            aiTagTerm: const Value('probe'),
          ),
        ),
      );
      final nachher = await dienst.aktuellerRegelstand();
      expect(nachher, isNot(vorher));
      final r = await importe.importFile(await foto('a.jpg', [6, 7]));
      await db.tagAsset(r.assetId!, 'ohne Regel');
      await db.setFavorite(r.assetId!, true);
      expect(await dienst.aktuellerRegelstand(), nachher);
    },
  );

  test(
    'Abbruch und fehlende Quellen erzeugen weder Dateien noch Metadaten',
    () async {
      final quelle = await foto('a.jpg', [3, 6]);
      await expectLater(
        dienst.erstelle([quelle], abgebrochen: () => true),
        throwsA(isA<ImportPlanAbgebrochen>()),
      );
      final plan = await dienst.erstelle([p.join(temp.path, 'fehlt.jpg')]);
      expect(plan.eintraege.single.art, ImportPlanArt.fehler);
      expect(await db.select(db.assets).get(), isEmpty);
    },
  );

  test(
    'Ordnerscan führt nicht aus versteckten Ordnern oder über Verzeichnisverweise hinaus',
    () async {
      final ordner = await Directory(p.join(temp.path, 'eingang')).create();
      File(p.join(ordner.path, 'sichtbar.jpg')).writeAsBytesSync([3]);
      final versteckt = await Directory(
        p.join(ordner.path, '.versteckt'),
      ).create();
      File(p.join(versteckt.path, 'innen.jpg')).writeAsBytesSync([4]);
      if (!Platform.isWindows) {
        await Link(p.join(ordner.path, 'verweis')).create(temp.path);
      }
      expect(
        (await ImportPlanDienst.dateienImOrdner(ordner.path)).map(p.basename),
        ['sichtbar.jpg'],
      );
    },
  );
  test(
    'bestätigte Vorschau und echter Import erzeugen dieselben Alben, Tags und Favoriten',
    () async {
      await db.fuehreAus(AlbumAnlegen('album', 'Album', DateTime(2026)));
      await db.upsertAutomationRule(
        AutomationRulesCompanion.insert(
          id: 'r',
          name: 'Dateiregel',
          triggerType: 'dateiendung',
          aiTagTerm: const Value('jpg'),
          targetAlbumId: const Value('album'),
          autoFavorite: const Value(true),
        ),
      );
      await db.customStatement(
        "INSERT INTO tags (id, name) VALUES ('t', 'Dateiregel-Tag')",
      );
      await db.setAutomationRuleTags('r', ['t']);
      await db.fuehreAus(const AuswertenNachImportSetzen(false));
      final quelle = await foto('probe.jpg', [7, 5, 3]);
      final plan = await dienst.erstelle([quelle]);
      final library = LibraryState()
        ..db = db
        ..paths = pfade
        ..importService = importe;
      try {
        final ergebnisse = await library.importFiles([
          quelle,
        ], plan: plan).toList();
        final id = ergebnisse.last.assetId!;
        expect(
          (await db.assetById(id))!.isFavorite,
          plan.eintraege.single.favorit,
        );
        expect(
          (await db.tagsForAsset(id)).map((t) => t.name),
          plan.eintraege.single.tags,
        );
        expect((await db.assetsInAlbumOnce('album')).map((a) => a.id), [id]);
      } finally {
        library.dispose();
      }
    },
  );

  test(
    'lokaler Import verwirft einen bestätigten Plan mit inzwischen geänderten Regeln',
    () async {
      final quelle = await foto('probe.jpg', [7, 8, 9]);
      final plan = await dienst.erstelle([quelle]);
      await db.upsertAutomationRule(
        AutomationRulesCompanion.insert(
          id: 'neu',
          name: 'Neu',
          triggerType: 'dateiname',
        ),
      );
      final library = LibraryState()
        ..db = db
        ..paths = pfade
        ..importService = importe;
      try {
        await expectLater(
          library.importFiles([quelle], plan: plan).drain<void>(),
          throwsFormatException,
        );
        expect(await db.select(db.assets).get(), isEmpty);
      } finally {
        library.dispose();
      }
    },
  );

  testWidgets(
    'Importvorschau markiert Dubletten und bleibt beim Verlassen ohne Schreibwirkung',
    (t) async {
      final neu = (await t.runAsync(() => foto('probe.jpg', [5, 10, 15])))!;
      final doppelt = (await t.runAsync(() => foto('kopie.jpg', [5, 10, 15])))!;
      final library = LibraryState()
        ..db = db
        ..paths = pfade
        ..importService = importe;
      await t.pumpWidget(
        MaterialApp(
          locale: const Locale('de'),
          supportedLocales: AppTexte.supportedLocales,
          localizationsDelegates: AppTexte.localizationsDelegates,
          home: ImportPlanScreen(library: library, dateien: [neu, doppelt]),
        ),
      );
      // Dateimetadaten werden vom Betriebssystem gelesen, außerhalb der
      // virtuellen Testuhr. Auf das fertige Ergebnis statt eine feste Zeit warten.
      for (
        var i = 0;
        i < 100 && find.text('1 Datei importieren').evaluate().isEmpty;
        i++
      ) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await t.pump();
      }
      expect(find.text('1 Datei importieren'), findsOneWidget);
      expect(
        find.textContaining('Identischer Inhalt bereits in dieser Auswahl'),
        findsOneWidget,
      );
      await t.pumpWidget(const SizedBox.shrink());
      expect(await db.select(db.assets).get(), isEmpty);
      library.dispose();
    },
  );
}
