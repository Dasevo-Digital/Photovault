import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kern/db/database.dart';
import 'package:kern/services/backup_auswahl.dart';
import 'package:kern/services/import_service.dart';
import 'package:kern/services/original_referenzen.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/services/importquittungen.dart';
import 'package:photo_vault/services/platform/folder_access.dart';
import 'package:photo_vault/services/speicherkarte.dart';
import 'package:photo_vault/widgets/speicherkarte_grafik.dart';

void main() {
  late Directory temp, backup;
  late AppDatabase db;
  late StoragePaths paths;
  late SpeicherkarteDienst dienst;
  late AssetData a;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pv_speicherkarte_');
    backup = await Directory('${temp.path}/backup').create();
    paths = await StoragePaths.forTesting(Directory('${temp.path}/bibliothek'));
    db = AppDatabase(NativeDatabase.memory());
    final bytes = img.encodeJpg(
      img.Image(width: 20, height: 16)..clear(img.ColorRgb8(40, 80, 120)),
    );
    final f = await File('${temp.path}/test.jpg').writeAsBytes(bytes);
    final r = await ImportService(db, paths).importFile(f.path);
    a = (await db.assetById(r.assetId!))!;
    dienst = SpeicherkarteDienst(
      db,
      paths,
      File('${temp.path}/nachweise.json'),
    );
    await File('${backup.path}/metadata.json').writeAsString(
      jsonEncode({
        'format': 1,
        'assets': [
          {
            'checksum': a.checksum,
            'backupRelativePath': 'foto.jpg',
            'originalFileName': 'test.jpg',
          },
        ],
      }),
    );
    await File('${backup.path}/foto.jpg').writeAsBytes(bytes);
  });
  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });
  Future<BackupAuswahl> auswahl() =>
      BackupAuswahl.oeffne(backup.path, schemaVersion: db.schemaVersion);
  test(
    'Vorhandensein und alter DB-Sicherungsmerker ersetzen keinen Inhaltsnachweis',
    () async {
      await db.customStatement('UPDATE assets SET backed_up=1 WHERE id=?', [
        a.id,
      ]);
      final s = await dienst.laden();
      expect(s.anzahl(Speichergruppe.bibliothek), 1);
      expect(s.anzahl(Speichergruppe.kopien), 1);
      expect(s.anzahl(Speichergruppe.nachgewiesen), 0);
      expect(s.anzahl(Speichergruppe.unbekannt), 1);
      await paths.absolute(a.relativePath).delete();
      expect((await dienst.laden()).anzahl(Speichergruppe.fehlt), 1);
    },
  );
  test(
    'Serverübersicht lädt keine Originale und behauptet keine lokale Kopie',
    () async {
      await paths.absolute(a.relativePath).delete();
      var heruntergeladen = 0;
      paths.beschaffe = (_) async {
        heruntergeladen++;
      };
      final s = await dienst.laden();
      expect(s.anzahl(Speichergruppe.server), 1);
      expect(s.anzahl(Speichergruppe.kopien), 0);
      expect(heruntergeladen, 0);
    },
  );
  test(
    'SHA-Prüfung bleibt datiert, fehlendes Ziel und geänderter Inhalt werden sichtbar',
    () async {
      final n = await dienst.pruefe(
        await auswahl(),
        PickedFolder(backup.path, ''),
        {a.checksum},
      );
      expect(n.vollstaendig, isTrue);
      expect(n.bestaetigt, 1);
      expect((await dienst.laden()).anzahl(Speichergruppe.nachgewiesen), 1);
      final weg = await backup.rename('${backup.path}-abgezogen');
      var s = await dienst.laden();
      expect(s.nachweise.single.am, n.am.toUtc());
      expect(s.nachweise.single.erreichbar, isFalse);
      expect(s.anzahl(Speichergruppe.nachgewiesen), 0);
      await weg.rename(backup.path);
      final f = File('${backup.path}/foto.jpg');
      final bytes = await f.readAsBytes();
      bytes[bytes.length ~/ 2] ^= 1;
      await f.writeAsBytes(bytes);
      final neu = await dienst.pruefe(
        await auswahl(),
        PickedFolder(backup.path, ''),
        {a.checksum},
      );
      expect(neu.bestaetigt, 0);
      expect(neu.befunde[a.checksum], Kopienbefund.unlesbar);
      s = await dienst.laden();
      expect(s.anzahl(Speichergruppe.unbekannt), 1);
    },
  );
  test(
    'Abbruch und defekter Nachweisspeicher lassen die Originalkarte benutzbar',
    () async {
      final n = await dienst.pruefe(
        await auswahl(),
        PickedFolder(backup.path, ''),
        {a.checksum},
        abgebrochen: () => true,
      );
      expect(n.vollstaendig, isFalse);
      expect(n.bestaetigt, 0);
      await dienst.nachweisdatei.writeAsString('unvollständig');
      final s = await dienst.laden();
      expect(s.nachweiseUnlesbar, isTrue);
      expect(s.anzahl(Speichergruppe.kopien), 1);
      await dienst.pruefe(await auswahl(), PickedFolder(backup.path, ''), {
        a.checksum,
      });
      expect((await dienst.laden()).nachweiseUnlesbar, isFalse);
      expect(
        temp.listSync().whereType<File>().any(
          (f) => f.path.endsWith('.unlesbar'),
        ),
        isTrue,
      );
    },
  );
  test(
    'gesperrte Daten bleiben verborgen, externer Ordner zählt nicht als lokale Kopie',
    () async {
      final refs = OriginalReferenzen(File('${temp.path}/refs.json'));
      paths.referenzen = refs;
      final id = await refs.ordnerHinzufuegen(temp);
      final ref = await refs.aufnehmen(id, File('${temp.path}/test.jpg'));
      await db.customStatement('UPDATE assets SET relative_path=? WHERE id=?', [
        ref,
        a.id,
      ]);
      var s = await dienst.laden();
      expect(s.anzahl(Speichergruppe.extern), 1);
      expect(s.anzahl(Speichergruppe.kopien), 0);
      await (db.update(db.assets)..where((t) => t.id.equals(a.id))).write(
        const AssetsCompanion(isLocked: Value(true)),
      );
      s = await dienst.laden();
      expect(s.gesperrt, 1);
      expect(s.fotos, isEmpty);
      expect(s.originalorte, isEmpty);
    },
  );
  testWidgets(
    'Grafik zeigt Zahlen und öffnet Gruppen auch auf schmalen Ansichten',
    (tester) async {
      final s = (await tester.runAsync(dienst.laden))!;
      Speichergruppe? geklickt;
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final schrift = Platform.environment['PV_VISUAL_FONT'];
      if (schrift != null) {
        await tester.runAsync(() async {
          final font = FontLoader('Vorschau')
            ..addFont(
              File(schrift).readAsBytes().then((b) => ByteData.sublistView(b)),
            );
          await font.load();
          await (FontLoader('MaterialIcons')
                ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
              .load();
        });
      }
      const bildKey = Key('speicherkarte-bild');
      await tester.pumpWidget(
        RepaintBoundary(
          key: bildKey,
          child: MaterialApp(
            theme: schrift == null ? null : ThemeData(fontFamily: 'Vorschau'),
            locale: const Locale('de'),
            localizationsDelegates: AppTexte.localizationsDelegates,
            supportedLocales: AppTexte.supportedLocales,
            home: Scaffold(
              body: SingleChildScrollView(
                child: SpeicherkarteGrafik(
                  stand: s,
                  beiAuswahl: (g) => geklickt = g,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('In dieser Bibliothek'), findsOneWidget);
      await tester.tap(find.text('In dieser Bibliothek'));
      expect(geklickt, Speichergruppe.bibliothek);
      expect(tester.takeException(), isNull);
      final ausgabe = Platform.environment['PV_VISUAL_OUT'];
      if (ausgabe != null) {
        tester.view.physicalSize = const Size(1120, 760);
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          final bild = await tester
              .renderObject<RenderRepaintBoundary>(find.byKey(bildKey))
              .toImage();
          try {
            final bytes = await bild.toByteData(format: ui.ImageByteFormat.png);
            await File(ausgabe).writeAsBytes(bytes!.buffer.asUint8List());
          } finally {
            bild.dispose();
          }
        });
      }
    },
  );
}
