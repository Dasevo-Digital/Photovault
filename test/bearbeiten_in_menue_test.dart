import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kern/db/database.dart';
import 'package:kern/services/import_service.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/asset_viewer_screen.dart';
import 'package:photo_vault/screens/einstellungen/bearbeiten_in.dart';
import 'package:photo_vault/services/backup_service.dart';
import 'package:photo_vault/services/bearbeitungsprogramme.dart';
import 'package:photo_vault/services/fremdprogramme.dart';
import 'package:photo_vault/services/meldungsdienst.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/theme/app_theme.dart';
import 'package:provider/provider.dart';

/// „Bearbeiten in ▸“ im Vollbild und der Abschnitt in den Einstellungen
/// (#499). Kein Programm wird wirklich gestartet: Erkennung und Start
/// sind nachgestellt, der Dateimanager geht nicht auf.
void main() {
  final de = lookupAppTexte(const Locale('de'));
  late Directory wurzel;
  late AppDatabase db;
  late StoragePaths pfade;
  late LibraryState bibliothek;
  late Bearbeitungsprogramme programme;
  late List<String> gestartet;
  late List<String> programmpfade;
  late List<String> gezeigt;
  late AssetData foto;
  String? waehlbar;

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_bearbeiten_in_');
    db = AppDatabase(NativeDatabase.memory());
    pfade = await StoragePaths.forTesting(
      Directory(p.join(wurzel.path, 'lib')),
    );
    bibliothek = LibraryState()
      ..db = db
      ..paths = pfade
      ..backupService = BackupService(db, pfade)
      ..importService = ImportService(db, pfade);
    gestartet = [];
    programmpfade = [];
    gezeigt = [];
    waehlbar = null;
    programme = Bearbeitungsprogramme(
      basis: Directory(p.join(wurzel.path, 'Bilder')),
      einstellungen: () async => File(p.join(wurzel.path, 'programme.json')),
      system: 'macos',
      erkenne: () async => {
        Bekannt.gimp: '/Applications/GIMP.app',
        Bekannt.photoshop:
            '/Applications/Adobe Photoshop 2026/Adobe Photoshop 2026.app',
      },
      starter: Programmstarter(
        system: 'macos',
        umgebung: const {},
        ausfuehren: (programm, argumente, {required warten}) async {
          // open -a <Programm> <Datei>
          gestartet.add(argumente.last);
          programmpfade.add(argumente[1]);
          return true;
        },
      ),
      waehle: (_) async => waehlbar,
      zeigeOrdner: (ordner) async {
        gezeigt.add(ordner);
        return true;
      },
      // Die Ergebnisse hier sind fertig, sobald sie geschrieben sind.
      ruhe: Duration.zero,
    );
    final original = pfade.absolute('originals/a.jpg');
    await original.parent.create(recursive: true);
    await original.writeAsBytes(img.encodeJpg(img.Image(width: 8, height: 8)));
    await db
        .into(db.assets)
        .insert(
          AssetsCompanion.insert(
            id: 'a',
            originalFileName: 'a.jpg',
            relativePath: 'originals/a.jpg',
            checksum: 'pruef-a',
            type: 'IMAGE',
            fileCreatedAt: DateTime(2026, 6, 14),
            importedAt: DateTime(2026),
          ),
        );
    foto = (await db.assetById('a'))!;
    melde.verlaufLeeren();
  });

  tearDown(() async {
    await db.close();
    wurzel.deleteSync(recursive: true);
  });

  Future<void> warte(WidgetTester tester, {int runden = 20}) async {
    for (var i = 0; i < runden; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 30));
    }
  }

  /// Wartet, bis [fertig] gilt – Übernehmen sind viele Schritte auf der
  /// Platte, und jeder braucht hier eine Runde.
  Future<void> warteBis(
    WidgetTester tester,
    bool Function() fertig, {
    int hoechstens = 400,
  }) async {
    for (var i = 0; i < hoechstens && !fertig(); i++) {
      await warte(tester, runden: 1);
    }
  }

  Future<void> zeige(WidgetTester tester, {bool mitBibliothek = true}) async {
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: bibliothek,
        child: MaterialApp(
          locale: const Locale('de'),
          localizationsDelegates: AppTexte.localizationsDelegates,
          supportedLocales: AppTexte.supportedLocales,
          theme: buildDarkTheme(),
          home: AssetViewerScreen(
            assets: [foto],
            initialIndex: 0,
            paths: pfade,
            db: db,
            library: mitBibliothek ? bibliothek : null,
            programme: programme,
          ),
        ),
      ),
    );
    await warte(tester);
  }

  Future<void> menue(WidgetTester tester) async {
    await tester.tap(find.byType(PageView), buttons: kSecondaryMouseButton);
    await warte(tester);
  }

  Future<void> untermenue(WidgetTester tester) async {
    await menue(tester);
    await tester.tap(find.text(de.viewerBearbeitenIn));
    await warte(tester);
  }

  Future<void> waehle(
    WidgetTester tester,
    String text, {
    int runden = 40,
  }) async {
    await tester.tap(find.text(text));
    await warte(tester, runden: runden);
  }

  String meldung() => melde.verlauf.first.text;
  Directory arbeitsordner(String programm) =>
      Directory(p.join(wurzel.path, 'Bilder', 'PhotoVault-$programm', 'a'));

  testWidgets('das Untermenü zeigt die eingeschalteten Programme', (
    tester,
  ) async {
    await zeige(tester);
    await untermenue(tester);
    for (final text in [
      'darktable',
      'GIMP',
      'Adobe Photoshop',
      de.viewerAnderesProgramm,
    ]) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
    // Gegenprobe: nicht gefunden, also nicht eingeschaltet.
    expect(find.text('ON1 Photo RAW'), findsNothing);
    expect(find.text('Affinity Photo'), findsNothing);
    expect(find.textContaining('Ergebnis aus'), findsNothing);
  });

  testWidgets('In GIMP: Kopie, Start, Hinweise, Übernehmen eines TIFF', (
    tester,
  ) async {
    await zeige(tester);
    await untermenue(tester);
    await waehle(tester, 'GIMP');
    final kopie = p.join(arbeitsordner('GIMP').path, 'a.jpg');
    expect(File(kopie).existsSync(), isTrue);
    expect(gestartet, [kopie]);
    expect(programmpfade, ['/Applications/GIMP.app']);
    expect(meldung(), de.fremdGeoeffnet('GIMP'));
    expect(
      File('$kopie.xmp').existsSync(),
      isFalse,
      reason: 'die Beilage gibt es nur für darktable',
    );

    // Noch nichts gespeichert.
    await menue(tester);
    expect(find.text(de.viewerErgebnisAus('GIMP')), findsOneWidget);
    expect(find.text(de.viewerErgebnisAus('darktable')), findsNothing);
    await waehle(tester, de.viewerErgebnisAus('GIMP'));
    expect(meldung(), de.fremdKeinErgebnis('GIMP'));
    expect(gezeigt, [arbeitsordner('GIMP').path]);

    // Nur im eigenen Format gespeichert.
    File(p.join(arbeitsordner('GIMP').path, 'a.xcf')).writeAsStringSync('xcf');
    await menue(tester);
    await waehle(tester, de.viewerErgebnisAus('GIMP'));
    expect(meldung(), de.fremdNurUnlesbar('a.xcf'));

    // Als TIFF exportiert.
    File(
      p.join(arbeitsordner('GIMP').path, 'a-bearbeitet.tif'),
    ).writeAsBytesSync(img.encodeTiff(img.Image(width: 16, height: 12)));
    await menue(tester);
    await waehle(tester, de.viewerErgebnisAus('GIMP'));
    await warteBis(
      tester,
      () => meldung() == de.fremdUebernommenArbeitsdateien('GIMP'),
    );
    final neu = (await tester.runAsync(() => db.assetById('a')))!;
    expect(neu.relativePath, isNot('originals/a.jpg'));
    final bytes = await tester.runAsync(
      () => pfade.absolute(neu.relativePath).readAsBytes(),
    );
    final bild = img.decodeJpg(bytes!)!;
    expect((bild.width, bild.height), (16, 12), reason: 'das Ergebnis');

    // Die XCF ist die Arbeit mit Ebenen und bleibt; Kopie und TIFF gehen.
    expect(meldung(), de.fremdUebernommenArbeitsdateien('GIMP'));
    await warte(tester);
    expect(
      [
        for (final e in arbeitsordner('GIMP').listSync())
          if (!p.basename(e.path).startsWith('.')) p.basename(e.path),
      ],
      ['a.xcf'],
    );
    await menue(tester);
    expect(find.text(de.viewerErgebnisAus('GIMP')), findsNothing);
    gezeigt.clear();
    await waehle(tester, de.viewerArbeitsdateienAus('GIMP'));
    expect(gezeigt, [arbeitsordner('GIMP').path]);
  });

  testWidgets('ein neueres PSD neben dem JPEG: erst fragen, nicht still den '
      'älteren Stand übernehmen', (tester) async {
    await zeige(tester);
    await untermenue(tester);
    await waehle(tester, 'Adobe Photoshop');
    final ordner = arbeitsordner('Photoshop').path;
    final jetzt = DateTime.now();
    File(p.join(ordner, 'a-export.jpg'))
      ..writeAsBytesSync(img.encodeJpg(img.Image(width: 10, height: 10)))
      ..setLastModifiedSync(jetzt.subtract(const Duration(seconds: 20)));
    File(p.join(ordner, 'a.psd'))
      ..writeAsStringSync('ebenen')
      ..setLastModifiedSync(jetzt.subtract(const Duration(seconds: 10)));

    await menue(tester);
    await waehle(tester, de.viewerErgebnisAus('Adobe Photoshop'));
    expect(find.text(de.fremdNeuereArbeitsdateiTitel), findsOneWidget);
    expect(
      find.text(de.fremdNeuereArbeitsdatei('a.psd', 'a-export.jpg')),
      findsOneWidget,
    );
    await tester.tap(find.text(de.allgAbbrechen));
    await warte(tester);
    expect(
      (await tester.runAsync(() => db.assetById('a')))!.relativePath,
      'originals/a.jpg',
      reason: 'abgebrochen: nichts übernommen',
    );
    expect(gezeigt.last, ordner);

    await menue(tester);
    await waehle(tester, de.viewerErgebnisAus('Adobe Photoshop'));
    await tester.tap(find.text(de.fremdAelterenUebernehmen));
    await warteBis(
      tester,
      () => meldung() == de.fremdUebernommenArbeitsdateien('Adobe Photoshop'),
    );
    expect(meldung(), de.fremdUebernommenArbeitsdateien('Adobe Photoshop'));
    await warte(tester);
    expect(
      (await tester.runAsync(() => db.assetById('a')))!.relativePath,
      isNot('originals/a.jpg'),
    );
    expect(File(p.join(ordner, 'a.psd')).existsSync(), isTrue);
  });

  testWidgets('nach einer früheren Bearbeitung trägt die Kopie die Endung der '
      'Datei, nicht die des RAW', (tester) async {
    await tester.runAsync(() => db.setOriginalFileName('a', 'IMG_1.CR3'));
    foto = (await tester.runAsync<AssetData?>(() => db.assetById('a')))!;
    await zeige(tester);
    await untermenue(tester);
    await waehle(tester, 'GIMP');
    expect(gestartet, [p.join(arbeitsordner('GIMP').path, 'IMG_1.jpg')]);
    expect(
      File(p.join(arbeitsordner('GIMP').path, 'IMG_1.CR3')).existsSync(),
      isFalse,
    );
  });

  testWidgets('ein externes Original: der Hinweis vor dem Öffnen, nicht am '
      'Ende', (tester) async {
    await tester.runAsync(
      () => (db.update(db.assets)..where((t) => t.id.equals('a'))).write(
        const AssetsCompanion(
          relativePath: Value('referenzen/q1/a.jpg'),
          previewRelativePath: Value('originals/a.jpg'),
        ),
      ),
    );
    foto = (await tester.runAsync<AssetData?>(() => db.assetById('a')))!;
    await zeige(tester);
    await untermenue(tester);
    await waehle(tester, 'GIMP');
    expect(meldung(), de.katalogGrenzen);
    expect(gestartet, isEmpty);
    expect(arbeitsordner('GIMP').existsSync(), isFalse);
    await untermenue(tester);
    await waehle(tester, de.viewerAnderesProgramm);
    expect(meldung(), de.katalogGrenzen);
  });

  testWidgets('ON1 bekommt den Hinweis auf den Export', (tester) async {
    await tester.runAsync(() async {
      await programme.laden();
      await programme.schalte('on1', true);
    });
    await zeige(tester);
    await untermenue(tester);
    await waehle(tester, 'ON1 Photo RAW');
    expect(meldung(), de.fremdGeoeffnetOn1);
    File(p.join(arbeitsordner('ON1').path, 'a.jpg.on1')).writeAsStringSync('');
    await menue(tester);
    await waehle(tester, de.viewerErgebnisAus('ON1 Photo RAW'));
    expect(meldung(), de.fremdKeinErgebnisOn1);
  });

  testWidgets('„Anderes Programm …“ merkt sich das Programm und öffnet damit', (
    tester,
  ) async {
    waehlbar = '/Applications/Pixelmator Pro.app';
    await zeige(tester);
    await untermenue(tester);
    // Wählen, merken und öffnen sind viele Schritte auf der Platte.
    await waehle(tester, de.viewerAnderesProgramm, runden: 60);
    final kopie = p.join(arbeitsordner('Pixelmator Pro').path, 'a.jpg');
    expect(gestartet, [kopie]);
    expect(programmpfade, ['/Applications/Pixelmator Pro.app']);
    expect(meldung(), de.fremdGeoeffnet('Pixelmator Pro'));
    await untermenue(tester);
    expect(find.text('Pixelmator Pro'), findsOneWidget);
  });

  testWidgets('Gegenprobe: ohne Bibliothek kein „Bearbeiten in“', (
    tester,
  ) async {
    await zeige(tester, mitBibliothek: false);
    await menue(tester);
    expect(find.text(de.viewerInTimelineZeigen), findsOneWidget);
    expect(find.text(de.viewerBearbeitenIn), findsNothing);
  });

  testWidgets('Einstellungen: gefunden, nicht gefunden, umschalten, eigenes '
      'Programm hinzufügen und entfernen', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        theme: buildDarkTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: BearbeitenInGruppe(programme: programme),
          ),
        ),
      ),
    );
    await warte(tester);
    expect(find.text('/Applications/GIMP.app'), findsOneWidget);
    expect(find.text(de.einstBearbeitenInNichtGefunden), findsNWidgets(3));

    Finder schalterVon(String name) => find.descendant(
      of: find.widgetWithText(ListTile, name),
      matching: find.byType(Switch),
    );
    bool an(String name) => tester.widget<Switch>(schalterVon(name)).value;
    expect(an('darktable'), isTrue);
    expect(an('ON1 Photo RAW'), isFalse);
    await tester.tap(schalterVon('GIMP'));
    await warte(tester);
    expect(an('GIMP'), isFalse);
    expect(programme.aktive.map((x) => x.name), [
      'darktable',
      'Adobe Photoshop',
    ]);

    waehlbar = '/Applications/Pixelmator Pro.app';
    await tester.tap(find.text(de.einstBearbeitenInHinzufuegen));
    await warte(tester);
    expect(find.text('Pixelmator Pro'), findsOneWidget);
    expect(find.byTooltip(de.einstBearbeitenInEntfernen), findsOneWidget);
    await tester.tap(find.byTooltip(de.einstBearbeitenInEntfernen));
    await warte(tester);
    expect(find.text('Pixelmator Pro'), findsNothing);
    expect(
      find.text(de.einstBearbeitenInMitKopien),
      findsNothing,
      reason: 'ohne Arbeitskopien keine Rückfrage',
    );

    // Mit einer offenen Arbeitskopie wird gefragt.
    await tester.tap(find.text(de.einstBearbeitenInHinzufuegen));
    await warte(tester);
    final pixelmator = programme.alle.singleWhere((x) => x.eigenes);
    final kopie = File(
      p.join(programme.bruecke(pixelmator).ordner('a').path, 'a.jpg'),
    );
    await tester.runAsync(
      () => programme
          .bruecke(pixelmator)
          .oeffne(
            id: 'a',
            name: 'a.jpg',
            original: pfade.absolute('originals/a.jpg'),
          ),
    );
    await tester.tap(find.byTooltip(de.einstBearbeitenInEntfernen));
    await warte(tester);
    expect(
      find.text(de.einstBearbeitenInEntfernenTitel('Pixelmator Pro')),
      findsOneWidget,
    );
    await tester.tap(find.text(de.allgAbbrechen));
    await warte(tester);
    expect(find.text('Pixelmator Pro'), findsOneWidget, reason: 'abgebrochen');
    await tester.tap(find.byTooltip(de.einstBearbeitenInEntfernen));
    await warte(tester);
    await tester.tap(find.text(de.einstBearbeitenInMitKopien));
    await warteBis(
      tester,
      () => find.text('Pixelmator Pro').evaluate().isEmpty,
    );
    expect(find.text('Pixelmator Pro'), findsNothing);
    expect(kopie.existsSync(), isFalse);

    // Was hier umgeschaltet wurde, steht in der Datei.
    final danach = Bearbeitungsprogramme(
      basis: programme.basis,
      einstellungen: () async => File(p.join(wurzel.path, 'programme.json')),
      system: 'macos',
      erkenne: () async => const {},
    );
    await tester.runAsync(danach.laden);
    expect(
      danach.alle.singleWhere((x) => x.art == Bekannt.gimp).aktiv,
      isFalse,
    );
  });
}
