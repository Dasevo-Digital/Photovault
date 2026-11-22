// Auswahl: behobene Befunde aus dem Prüfkatalog der Handy-App (MOB,
// Issue #418): je Befund ein Test, der ohne die Korrektur scheitert.
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:kern/abgleich/abgleich.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:kern/db/database.dart';
import 'package:kern/db/rasterzeile.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:photo_vault_mobil/l10n/app_localizations.dart';
import 'package:photo_vault_mobil/seiten/auswahl.dart';
import 'package:photo_vault_mobil/seiten/gesichtsebene.dart';
import 'package:photo_vault_mobil/sitzung.dart';
import 'package:teilen_ui/collage.dart';

/// Eine Sitzung, deren erster Abgleich scheitert; der zweite bringt, was
/// [danach] in die Kopie legt.
class _ErstBeimZweiten extends Sitzung {
  _ErstBeimZweiten(this.danach);

  final Future<void> Function() danach;
  var versuche = 0;

  @override
  Future<void> gleicheAb() async {
    if (versuche++ == 0) throw KeineVerbindung('kurz weg');
    await danach();
  }
}

/// Eine Sitzung, deren Abgleich gerade nicht geht – etwa weil der Server
/// schon ein neueres Schema hat.
class _OhneAbgleich extends Sitzung {
  @override
  Future<void> gleicheAb() async => throw StateError('anderes Schema');
}

Rasterzeile _zeile(String id) => Rasterzeile(
  id: id,
  type: 'IMAGE',
  originalFileName: '$id.jpg',
  relativePath: 'originals/$id.jpg',
  thumbnailRelativePath: null,
  fileCreatedAt: DateTime(2025),
  durationSeconds: null,
  isFavorite: false,
  isStackCover: false,
  stackId: null,
  stackSize: null,
  linkedAssetId: null,
  rating: 0,
  colorLabel: null,
  widthPx: null,
  heightPx: null,
  latitude: null,
  longitude: null,
  cameraMake: null,
  isLocked: false,
);

void main() {
  testWidgets('MOB-043 gemischte Auswahl archivieren: „Rückgängig“ stellt '
      'nur die geänderte zurück, die Meldung geht von selbst', (tester) async {
    final ordner = Directory.systemTemp.createTempSync('pv_archiv_');
    addTearDown(() => ordner.deleteSync(recursive: true));
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    for (final id in ['alt', 'neu']) {
      await db.insertAsset(
        AssetsCompanion.insert(
          id: id,
          originalFileName: '$id.jpg',
          relativePath: 'originals/$id.jpg',
          checksum: 'pruef-$id',
          type: 'IMAGE',
          fileCreatedAt: DateTime(2025),
          importedAt: DateTime(2026),
        ),
      );
    }
    await db.fuehreAus(const ArchivSetzen(['alt'], true));
    final pfade = (await tester.runAsync(
      () => StoragePaths.forTesting(ordner),
    ))!;
    final sitzung = Sitzung()
      ..db = db
      ..paths = pfade;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Scaffold(
          body: const SizedBox.expand(),
          bottomSheet: Auswahlleiste(
            sitzung: sitzung,
            zeilen: [_zeile('alt'), _zeile('neu')],
            aufheben: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final t = AppTexte.of(tester.element(find.byType(Auswahlleiste)));
    Future<bool> archiviert(String id) async =>
        (await db.assetById(id))!.isArchived;

    await tester.tap(find.text(t.auswahlArchiv));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(t.auswahlArchiviert(2)), findsOneWidget);
    expect(await archiviert('alt'), isTrue);
    expect(await archiviert('neu'), isTrue);

    await tester.tap(find.text(t.variantenRueckgaengig));
    await tester.pumpAndSettle();
    expect(await archiviert('neu'), isFalse);
    expect(
      await archiviert('alt'),
      isTrue,
      reason: 'lag schon vorher im Archiv',
    );

    // Ohne Tipp verschwindet die Meldung nach ihrer Zeit.
    await tester.tap(find.text(t.auswahlArchiv));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(t.auswahlArchiviert(2)), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.text(t.auswahlArchiviert(2)), findsNothing);
  });

  testWidgets('#454 Collage gespeichert, nur der Abgleich danach scheitert: '
      'die Seite schliesst, und es entsteht keine zweite', (tester) async {
    final ordner = Directory.systemTemp.createTempSync('pv_collage_');
    addTearDown(() => ordner.deleteSync(recursive: true));
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final pfade = (await tester.runAsync(
      () => StoragePaths.forTesting(ordner),
    ))!;
    final bild = img.Image(width: 30, height: 30);
    img.fill(bild, color: img.ColorRgb8(200, 30, 30));
    final jpeg = img.encodeJpg(bild);
    var angelegt = 0;
    final v = Serververbindung(
      Uri.parse('https://fotos.example/'),
      't',
      client: MockClient((r) async {
        if (r.url.path.endsWith('/miniatur')) {
          return http.Response.bytes(
            jpeg,
            200,
            headers: {'content-type': 'image/jpeg'},
          );
        }
        if (r.url.path != '/api/v1/collage') return http.Response('', 404);
        if ((jsonDecode(r.body) as Map)['vorschau'] == true) {
          return http.Response.bytes(
            jpeg,
            200,
            headers: {'content-type': 'image/jpeg'},
          );
        }
        angelegt++;
        return http.Response(
          jsonEncode({'aufnahme': 'neu', 'ausgang': 'imported'}),
          201,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    final sitzung = _OhneAbgleich()
      ..db = db
      ..paths = pfade
      ..abgleich = Abgleich(db, v);
    var aufgehoben = false;
    await tester.binding.setSurfaceSize(const Size(1000, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Scaffold(
          body: const SizedBox.expand(),
          bottomSheet: Auswahlleiste(
            sitzung: sitzung,
            zeilen: [_zeile('a'), _zeile('b')],
            aufheben: () => aufgehoben = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> warte() async {
      await tester.pump(const Duration(milliseconds: 300));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
    }

    await tester.tap(find.text('Collage'));
    await warte();
    expect(find.byType(Collageseite), findsOneWidget);
    await tester.tap(find.text('Speichern'));
    await warte();
    expect(angelegt, 1);
    expect(find.byType(Collageseite), findsNothing);
    expect(aufgehoben, isTrue);
  });

  test('#454 ein aufgezogenes Gesicht ist angelegt, auch wenn ein Abgleich '
      'danach scheitert', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.insertAsset(
      AssetsCompanion.insert(
        id: 'x',
        originalFileName: 'x.jpg',
        relativePath: 'originals/x.jpg',
        checksum: 'pruef-x',
        type: 'IMAGE',
        fileCreatedAt: DateTime(2025),
        importedAt: DateTime(2026),
      ),
    );
    var angelegt = 0;
    final v = Serververbindung(
      Uri.parse('https://fotos.example/'),
      't',
      client: MockClient((r) async {
        angelegt++;
        return http.Response(
          jsonEncode({
            'gesicht': {'id': 'neu'},
          }),
          201,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    final sitzung =
        _ErstBeimZweiten(
            () => db
                .into(db.faces)
                .insert(
                  FacesCompanion.insert(
                    id: 'neu',
                    assetId: 'x',
                    boxX: 0.1,
                    boxY: 0.1,
                    boxW: 0.2,
                    boxH: 0.2,
                  ),
                ),
          )
          ..db = db
          ..abgleich = Abgleich(db, v);
    final f = await gesichtAmServerAnlegen(
      sitzung,
      'x',
      const Rect.fromLTWH(0.1, 0.1, 0.2, 0.2),
    );
    expect(f?.id, 'neu');
    expect(angelegt, 1);
    expect(sitzung.versuche, 2);
  });
}
