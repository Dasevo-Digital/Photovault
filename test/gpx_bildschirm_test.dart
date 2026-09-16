import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/gpx_verortung_screen.dart';
import 'package:photo_vault/services/backup_service.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/theme/app_theme.dart';
import 'package:photo_vault/services/meldungsdienst.dart';
import 'package:photo_vault/widgets/meldungsfenster.dart';

/// Der Weg von der GPX-Datei bis zur Koordinate in der Datenbank.
///
/// Die Rechnung ist in gpx_test.dart geprüft. Hier geht es um das, was
/// Tests, die sie unmittelbar aufrufen, nicht sehen: ob der Knopf
/// wirklich zu einer verorteten Aufnahme führt – und ob der
/// vorgeschlagene Zeitversatz auf dem Bildschirm ankommt.
class _NachgestellterDateidialog extends FilePicker {
  _NachgestellterDateidialog(this.datei);
  File? datei;

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
    final d = datei;
    if (d == null) return null;
    return FilePickerResult(
        [PlatformFile(name: p.basename(d.path), path: d.path, size: d.lengthSync())]);
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
  }) async =>
      null;
}

void main() {
  late Directory tempRoot;
  late AppDatabase db;
  late LibraryState library;
  late File spurdatei;

  setUp(() async {
    tempRoot = Directory.systemTemp.createTempSync('pv_gpx_');
    db = AppDatabase(NativeDatabase.memory());
    final paths =
        await StoragePaths.forTesting(Directory(p.join(tempRoot.path, 'lib')));
    library = LibraryState()
      ..db = db
      ..paths = paths
      ..backupService = BackupService(db, paths);

    // Eine Spur von 09:00 bis 10:00 UTC, alle fünf Minuten ein Punkt.
    final punkte = [
      for (var m = 0; m <= 60; m += 5)
        '<trkpt lat="${52.0 + m / 1000}" lon="13.0"><time>'
            '${DateTime.utc(2024, 6, 3, 9).add(Duration(minutes: m)).toIso8601String()}'
            '</time></trkpt>',
    ].join();
    spurdatei = File(p.join(tempRoot.path, 'wanderung.gpx'));
    spurdatei.writeAsStringSync(
        '<?xml version="1.0"?><gpx version="1.1"><trk><trkseg>$punkte'
        '</trkseg></trk></gpx>');

    // Fünf Aufnahmen ohne Koordinate über eine volle Stunde, zwei
    // Stunden versetzt (Kamera auf MESZ), und eine, die längst verortet
    // ist.
    //
    // Über die volle Stunde verteilt, damit der Versatz eindeutig ist:
    // Lägen sie enger beieinander, passten mehrere Versätze gleich gut,
    // und der Test prüfte die Gleichstandsregel statt der Erkennung.
    Future<void> foto(String id, DateTime zeit, {double? breite}) =>
        db.into(db.assets).insert(AssetsCompanion.insert(
              id: id,
              originalFileName: '$id.jpg',
              relativePath: 'originals/$id.jpg',
              checksum: 'pruef-$id',
              type: 'IMAGE',
              fileCreatedAt: zeit,
              importedAt: DateTime(2024),
              latitude: Value(breite),
              longitude: Value(breite == null ? null : 1.0),
            ));
    for (var i = 0; i < 5; i++) {
      await foto('f$i', DateTime.utc(2024, 6, 3, 11, i * 15));
    }
    await foto('schon', DateTime.utc(2024, 6, 3, 11, 5), breite: 9.9);

    FilePicker.platform = _NachgestellterDateidialog(spurdatei);
  });

  tearDown(() async {
    // Der Meldungsdienst ist ein Einzelstueck – was hier stehen
    // bleibt, steht im naechsten Test noch da.
    melde.verlaufLeeren();
    await db.close();
    tempRoot.deleteSync(recursive: true);
  });

  Future<void> zeige(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      theme: buildDarkTheme(),
      // Der Meldungsstapel gehoert dazu: Seit der Meldungszentrale
      // erscheinen Meldungen dort und nicht mehr als SnackBar im
      // Scaffold.
      builder: (context, kind) => mitMeldungen(kind),
      home: GpxVerortungScreen(library: library),
    ));
    await tester.pumpAndSettle();
  }

  /// Waehlt die Datei und laesst den Ablauf durchlaufen.
  ///
  /// Ohne `pumpAndSettle`: Solange gelesen wird, dreht sich ein
  /// Fortschrittsring, und eine endlose Bewegung laesst sich nicht
  /// aussitzen. `runAsync` gibt dazwischen den wirklichen Ereignisstrom
  /// frei – echte Datei-Ein-/Ausgabe laeuft an der Testuhr vorbei.
  Future<void> waehlen(WidgetTester tester) async {
    await tester.tap(find.text('GPX-Datei wählen …'));
    await tester.pump();
    for (var runde = 0; runde < 6; runde++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('der Zeitversatz wird vorgeschlagen, nicht erfragt',
      (tester) async {
    // EXIF schreibt ohne Zeitzone, GPX schreibt UTC. Die Kamera stand auf
    // MESZ – niemand soll das raten muessen.
    await zeige(tester);
    await waehlen(tester);
    // Nur die Punktzahl: Die Zeitangabe steht in Ortszeit, und die haengt
    // an der Zeitzone der Maschine, auf der der Test laeuft.
    expect(find.textContaining('13 Punkte · '), findsOneWidget);
    expect(find.text('−2:00'), findsOneWidget);
    expect(find.text('5 Aufnahmen bekommen einen Ort.'), findsOneWidget);
  });

  testWidgets('vom Knopf bis zur Koordinate', (tester) async {
    await zeige(tester);
    await waehlen(tester);
    await tester.tap(find.text('Verorten'));
    await tester.pumpAndSettle();

    final verortet = await db.aufnahmenFuerReiseerkennung();
    expect(verortet.map((a) => a.id).toSet(),
        {'schon', 'f0', 'f1', 'f2', 'f3', 'f4'});
    // **Nicht auf dem Schirm nachsehen.** `pumpAndSettle` läuft, bis
    // keine Bilder mehr anstehen – und der ablaufende Balken der Meldung
    // ist so ein Bild. Die Karte ist danach also planmässig weg. Im
    // Verlauf steht sie noch; genau dafür gibt es ihn.
    expect(melde.verlauf.first.text, '5 Aufnahmen verortet.');
    expect(melde.verlauf.first.art, Meldungsart.erfolg);

    // Und danach ist nichts mehr zu tun – dieselbe Zahl darf nicht noch
    // einmal dastehen.
    expect(find.text('Im Zeitraum dieser Spur hat jede Aufnahme schon '
        'einen Ort.'), findsOneWidget);
  });

  testWidgets('ein anderer Versatz trifft weniger', (tester) async {
    await zeige(tester);
    await waehlen(tester);
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    expect(find.text('−1:30'), findsOneWidget);
    expect(find.text('5 Aufnahmen bekommen einen Ort.'), findsNothing);
  });

  testWidgets('eine Datei ohne Zeitstempel sagt, was ihr fehlt',
      (tester) async {
    spurdatei.writeAsStringSync('<?xml version="1.0"?><gpx version="1.1">'
        '<trk><trkseg><trkpt lat="52" lon="13"/></trkseg></trk></gpx>');
    await zeige(tester);
    await waehlen(tester);
    expect(find.textContaining('kein Punkt einen Zeitstempel'), findsOneWidget);
    expect(find.text('Verorten'), findsNothing);
  });

  testWidgets('etwas anderes als GPX wird abgelehnt', (tester) async {
    spurdatei.writeAsStringSync('Das ist ein Brief.');
    await zeige(tester);
    await waehlen(tester);
    expect(find.text('Das ist keine GPX-Datei.'), findsOneWidget);
  });
}
