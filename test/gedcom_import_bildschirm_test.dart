import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/stammbaum_screen.dart';
import 'package:photo_vault/services/backup_service.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/theme/app_theme.dart';

/// Der Weg vom Menüpunkt bis in die Datenbank.
///
/// Der Anlass steht in der Fassung 1.9.6: Dort wurde ein Knopf
/// ausgeliefert, den niemand drücken konnte. Tests, die die Rechnung
/// unmittelbar aufrufen, sehen den Weg dorthin nicht – und der Weg ist
/// hier lang: Menü, Dateidialog, Rückfrage, Übernahme, Bericht.
///
/// Der Dateidialog ist ein Fenster des Betriebssystems und in einem Test
/// nicht zu öffnen. Er wird deshalb nachgestellt; was er zurückgibt, ist
/// eine echte Datei auf der Platte, und alles danach läuft unverändert.
///
/// Nachgestellt wird die **Schnittstelle** des Pakets und nicht sein
/// Kanal zum Betriebssystem: In einem Test wird kein Erweiterungspaket
/// angemeldet, `FilePicker.platform` ist dann nicht belegt, und ein
/// nachgestellter Kanal käme nie zum Zuge.
class _NachgestellterDateidialog extends FilePicker {
  _NachgestellterDateidialog(this.datei);

  /// Was der Dialog zurückgibt – `null` heißt „abgebrochen".
  File? datei;

  /// Welche Wege durch diesen Dialog gegangen wurden.
  final gerufen = <String>[];

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    gerufen.add('pickFiles');
    final d = datei;
    if (d == null) return null;
    return FilePickerResult([
      PlatformFile(name: p.basename(d.path), path: d.path, size: d.lengthSync()),
    ]);
  }

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    gerufen.add('saveFile');
    return null;
  }
}

void main() {
  late Directory tempRoot;
  late AppDatabase db;
  late LibraryState library;
  late File gedcom;
  late _NachgestellterDateidialog dialog;

  setUp(() async {
    tempRoot = Directory.systemTemp.createTempSync('pv_gedcom_bs_');
    db = AppDatabase(NativeDatabase.memory());
    final paths =
        await StoragePaths.forTesting(Directory(p.join(tempRoot.path, 'lib')));
    library = LibraryState()
      ..db = db
      ..paths = paths
      ..backupService = BackupService(db, paths);

    gedcom = File(p.join(tempRoot.path, 'ahnen.ged'));
    await gedcom.writeAsString([
      '0 HEAD',
      '1 CHAR UTF-8',
      '0 @I1@ INDI',
      '1 NAME Hans /Meier/',
      '1 SEX M',
      '1 BIRT',
      '2 DATE 2 APR 1931',
      '2 PLAC Hamburg',
      '0 @I2@ INDI',
      '1 NAME Grete /Meier/',
      '1 SEX F',
      '0 @I3@ INDI',
      '1 NAME Karl /Meier/',
      '0 @F1@ FAM',
      '1 HUSB @I1@',
      '1 WIFE @I2@',
      '1 CHIL @I3@',
      '0 TRLR',
    ].map((z) => '$z\r\n').join());

    dialog = _NachgestellterDateidialog(gedcom);
    FilePicker.platform = dialog;
  });

  tearDown(() async {
    await db.close();
    tempRoot.deleteSync(recursive: true);
  });

  Future<void> zeige(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      theme: buildDarkTheme(),
      home: StammbaumScreen(library: library),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> menueOeffnen(WidgetTester tester) async {
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
  }

  /// Tippt auf etwas, das die Platte anfasst.
  ///
  /// Ein Widget-Test läuft an einer gestellten Uhr; echte Ein- und
  /// Ausgabe läuft daran vorbei und käme nie zurück. [WidgetTester.runAsync]
  /// gibt für die Dauer des Aufrufs den wirklichen Ereignisstrom frei –
  /// ohne das bleibt der Ablauf beim Lesen der Datei stehen, und im Test
  /// sieht das aus, als sei der Menüpunkt wirkungslos.
  Future<void> tippeMitPlatte(WidgetTester tester, Finder was) async {
    await tester.tap(was);
    await tester.pump();
    // [WidgetTester.runAsync] gibt für die Dauer des Aufrufs den
    // wirklichen Ereignisstrom frei. Ohne das bliebe der Ablauf beim
    // Lesen der Datei stehen, und im Test sähe es aus, als sei der
    // Menüpunkt wirkungslos.
    for (var runde = 0; runde < 5; runde++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 50),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );
    }
  }

  testWidgets('der Menuepunkt ist auch ohne eine einzige Person da',
      (tester) async {
    // Genau dann ist er gefragt. Der Ausgabe-Punkt daneben bleibt aus
    // gutem Grund gesperrt – es gäbe nichts auszugeben.
    await zeige(tester);
    await menueOeffnen(tester);

    final punkt = find.text('GEDCOM einlesen …');
    expect(punkt, findsOneWidget);
    expect(
        tester
            .widget<PopupMenuItem<String>>(find.ancestor(
                of: punkt, matching: find.byType(PopupMenuItem<String>)))
            .enabled,
        isTrue);
  });

  testWidgets('vom Menuepunkt bis in die Datenbank', (tester) async {
    await zeige(tester);
    await menueOeffnen(tester);
    await tippeMitPlatte(tester, find.text('GEDCOM einlesen …'));

    // Der Dialog zum **Auswählen** wurde geöffnet, nicht der zum
    // Speichern. Ohne diese Zeile fiele ein vertauschter Menüpunkt nicht
    // auf: Beide Wege enden still, wenn niemand eine Datei wählt.
    expect(dialog.gerufen, ['pickFiles']);

    // Die Rückfrage nennt, was in der Datei steht, und sagt zu, nichts
    // Bestehendes anzufassen.
    expect(find.textContaining('3 Personen'), findsOneWidget);
    expect(find.textContaining('Nichts Bestehendes'), findsOneWidget);
    expect(await db.select(db.people).get(), isEmpty,
        reason: 'vor der Zusage darf nichts geschrieben sein');

    await tippeMitPlatte(tester, find.text('Einlesen'));

    final personen = await db.select(db.people).get();
    expect(personen.map((x) => x.name).toSet(),
        {'Hans Meier', 'Grete Meier', 'Karl Meier'});
    expect(await db.alleBeziehungen(), hasLength(3));
    expect((await db.select(db.lebensereignisse).get()).single.ort, 'Hamburg');

    // Der Bericht erscheint auch dann, wenn nichts auffiel.
    expect(find.text('Nichts zu beanstanden.'), findsOneWidget);
    await tester.tap(find.text('Schließen'));
    await tester.pumpAndSettle();

    // Und der Baum zeigt die eingelesenen Personen sofort.
    expect(find.text('Hans Meier'), findsWidgets);
  });

  testWidgets('Abbrechen schreibt nichts', (tester) async {
    await zeige(tester);
    await menueOeffnen(tester);
    await tippeMitPlatte(tester, find.text('GEDCOM einlesen …'));
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();

    expect(await db.select(db.people).get(), isEmpty);
    expect(await db.alleBeziehungen(), isEmpty);
  });

  testWidgets('zweimal dieselbe Datei meldet die Doppelten', (tester) async {
    // Der Kern der Entscheidung „immer neu anlegen": Beim zweiten Mal
    // stehen sechs Personen da, nicht drei. Das ist gewollt – ein
    // Programm, das selbsttätig zusammenführt, liegt irgendwann falsch,
    // und eine falsch verschmolzene Person ist nicht mehr zu trennen.
    // Ungewollt wäre nur, es zu verschweigen.
    for (var lauf = 0; lauf < 2; lauf++) {
      await zeige(tester);
      await menueOeffnen(tester);
      await tippeMitPlatte(tester, find.text('GEDCOM einlesen …'));
      await tippeMitPlatte(tester, find.text('Einlesen'));
      if (lauf == 0) {
        expect(find.text('Nichts zu beanstanden.'), findsOneWidget);
      } else {
        expect(find.textContaining('könnte es schon geben'), findsOneWidget);
        expect(find.text('Grete Meier, Hans Meier, Karl Meier'), findsOneWidget,
            reason: 'die Namen stehen dabei, sonst müsste man suchen');
        expect(find.textContaining('entscheidest du'), findsOneWidget);
      }
      await tester.tap(find.text('Schließen'));
      await tester.pumpAndSettle();
    }
    expect(await db.select(db.people).get(), hasLength(6));
  });

  testWidgets('eine unlesbare Datei sagt, was ihr fehlt', (tester) async {
    // Absichtlich die synchrone Fassung: Ein Widget-Test läuft an einer
    // gestellten Uhr, und ein `await` auf echte Ein-/Ausgabe käme darin
    // nie zurück – der Test bliebe wortlos stehen.
    gedcom.writeAsStringSync('Das ist ein Brief, keine GEDCOM-Datei.\n');
    await zeige(tester);
    await menueOeffnen(tester);
    await tippeMitPlatte(tester, find.text('GEDCOM einlesen …'));

    expect(find.text('Datei nicht lesbar'), findsOneWidget);
    expect(find.textContaining('GEDCOM-Kopf'), findsOneWidget);
    await tester.tap(find.text('Schließen'));
    await tester.pumpAndSettle();
    expect(await db.select(db.people).get(), isEmpty);
  });
}
