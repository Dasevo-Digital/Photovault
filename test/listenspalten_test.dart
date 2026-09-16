import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/services/asset_grouping.dart';
import 'package:photo_vault/services/listenspalten.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/theme/app_theme.dart';
import 'package:photo_vault/widgets/asset_list_view.dart';

/// **Die Liste bekommt Spalten.**
///
/// Vorher waren es fünf feste Angaben ohne Überschrift, deren
/// Sichtbarkeit allein an der Fensterbreite hing – 620 Punkte für die
/// Kamera, 860 für die Belichtung, 1040 für die Bewertung. Wer nach dem
/// Objektiv suchte, fand es nirgends; wer die Kamera nicht brauchte,
/// wurde sie nicht los.
AssetData _foto(String id) => AssetData(
      id: id,
      relativePath: 'originals/$id.jpg',
      originalFileName: '$id.jpg',
      type: 'IMAGE',
      fileSizeBytes: 2500000,
      checksum: id,
      fileCreatedAt: DateTime(2026, 3, 5, 14, 30),
      importedAt: DateTime(2026, 3, 6),
      isFavorite: false,
      isTrashed: false,
      isLocked: false,
      faceScanExcluded: false,
      gpsGeprueft: false,
      datumGeschaetzt: false,
      datumGeprueft: false,
      ortGeerbt: false,
      videobilderGeprueft: false,
      backedUp: false,
      autoBackedUp: false,
      facesScanned: false,
      ocrScanned: false,
      aiCaptionScanned: false,
      aiCaptionEdited: false,
      aiTagsScanned: false,
      isStackCover: false,
      rating: 3,
      cameraModel: 'Canon EOS R10',
      lensModel: 'RF 24-105mm F4 L',
      widthPx: 6000,
      heightPx: 4000,
      locationCity: 'Lissabon',
      locationCountry: 'Portugal',
      colorLabel: 'red',
    );

void main() {
  group('Die Wahl selbst', () {
    test('die Vorgabe sind genau die fuenf von vorher', () {
      expect(Listenspaltenwahl.vorgabe.spalten, [
        Listenspalte.dateiname,
        Listenspalte.datum,
        Listenspalte.kamera,
        Listenspalte.belichtung,
        Listenspalte.bewertung,
      ]);
    });

    test('eine neue Spalte kommt an ihren Platz, nicht ans Ende', () {
      // Sonst hinge die Anordnung der Liste davon ab, in welcher
      // Reihenfolge man die Haekchen gesetzt hat.
      final wahl =
          Listenspaltenwahl.vorgabe.umgeschaltet(Listenspalte.objektiv);
      expect(wahl.spalten.indexOf(Listenspalte.objektiv),
          wahl.spalten.indexOf(Listenspalte.kamera) + 1);
      expect(wahl.spalten.indexOf(Listenspalte.objektiv),
          lessThan(wahl.spalten.indexOf(Listenspalte.belichtung)));
    });

    test('eine abgeschaltete Spalte behaelt ihre Breite', () {
      final breit = Listenspaltenwahl.vorgabe
          .mitBreite(Listenspalte.kamera, 300)
          .umgeschaltet(Listenspalte.kamera)
          .umgeschaltet(Listenspalte.kamera);
      expect(breit.breiteVon(Listenspalte.kamera), 300);
    });

    test('die letzte Spalte laesst sich nicht auch noch abschalten', () {
      // Eine Liste ohne jede Spalte waere eine leere Flaeche ohne Weg
      // zurueck - das Menue haengt an der Kopfzeile.
      var wahl = Listenspaltenwahl.vorgabe;
      for (final s in Listenspalte.values) {
        wahl = wahl.umgeschaltet(s);
      }
      expect(wahl.spalten, hasLength(greaterThanOrEqualTo(1)));
    });

    test('die Breite bleibt zwischen den Grenzen', () {
      expect(
          Listenspaltenwahl.vorgabe
              .mitBreite(Listenspalte.datum, 5)
              .breiteVon(Listenspalte.datum),
          listenspalteMindestbreite);
      expect(
          Listenspaltenwahl.vorgabe
              .mitBreite(Listenspalte.datum, 9999)
              .breiteVon(Listenspalte.datum),
          listenspalteHoechstbreite);
    });
  });

  group('Aufschreiben und zurueckholen', () {
    test('ein Rundlauf ergibt dasselbe', () {
      final wahl = Listenspaltenwahl.vorgabe
          .umgeschaltet(Listenspalte.ort)
          .mitBreite(Listenspalte.ort, 210);
      final zurueck = Listenspaltenwahl.ausText(wahl.alsText());
      expect(zurueck.spalten, wahl.spalten);
      expect(zurueck.breiteVon(Listenspalte.ort), 210);
    });

    test('Unsinn endet in der Vorgabe statt in einem leeren Bildschirm', () {
      expect(Listenspaltenwahl.ausText('kein json').spalten,
          Listenspaltenwahl.vorgabe.spalten);
      expect(Listenspaltenwahl.ausText('[1,2,3]').spalten,
          Listenspaltenwahl.vorgabe.spalten);
      expect(Listenspaltenwahl.ausText(null).spalten,
          Listenspaltenwahl.vorgabe.spalten);
    });

    test('eine Spalte, die es nicht mehr gibt, faellt still weg', () {
      final wahl = Listenspaltenwahl.ausText(
          '{"spalten":["dateiname","gabsmalnicht","datum"]}');
      expect(wahl.spalten, [Listenspalte.dateiname, Listenspalte.datum]);
    });

    test('sind am Ende gar keine gueltig, gilt die Vorgabe', () {
      expect(Listenspaltenwahl.ausText('{"spalten":["gabsmalnicht"]}').spalten,
          Listenspaltenwahl.vorgabe.spalten);
    });

    test('die Wahl ueberdauert in der Datenbank', () async {
      final db = AppDatabase(NativeDatabase.memory());
      expect((await db.listenspaltenWahl()).spalten,
          Listenspaltenwahl.vorgabe.spalten);
      final wahl = Listenspaltenwahl.vorgabe
          .umgeschaltet(Listenspalte.masse)
          .mitBreite(Listenspalte.masse, 133);
      await db.setzeListenspalten(wahl);
      final zurueck = await db.listenspaltenWahl();
      expect(zurueck.zeigt(Listenspalte.masse), isTrue);
      expect(zurueck.breiteVon(Listenspalte.masse), 133);
      await db.close();
    });
  });

  group('In der Ansicht', () {
    late Directory wurzel;
    late StoragePaths paths;
    late Listenspaltenwahl wahl;

    setUp(() async {
      wurzel = Directory.systemTemp.createTempSync('pv_spalten_');
      paths = await StoragePaths.forTesting(
          Directory(p.join(wurzel.path, 'library')));
      wahl = Listenspaltenwahl.vorgabe;
    });
    tearDown(() => wurzel.deleteSync(recursive: true));

    Future<void> zeige(WidgetTester tester, {double breite = 1600}) async {
      tester.view.physicalSize = Size(breite, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        theme: buildDarkTheme(),
        home: StatefulBuilder(
          builder: (context, setzen) => Scaffold(
            body: AssetListView(
              assets: [_foto('urlaub')],
              paths: paths,
              gruppierung: ListenGruppierung.keine,
              selectedIds: const {},
              onTap: (_) {},
              onLongPress: (_) {},
              spalten: wahl,
              onSpalten: (neu) => setzen(() => wahl = neu),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('ueber jeder Spalte steht ihr Name', (tester) async {
      await zeige(tester);
      expect(find.text('Dateiname'), findsOneWidget);
      expect(find.text('Aufgenommen'), findsOneWidget);
      expect(find.text('Kamera'), findsOneWidget);
      expect(find.text('Belichtung'), findsOneWidget);
      expect(find.text('Bewertung'), findsOneWidget);
      // Und was nicht gewaehlt ist, steht auch nicht da.
      expect(find.text('Objektiv'), findsNothing);
    });

    testWidgets('eine Spalte laesst sich zuschalten', (tester) async {
      await zeige(tester);
      expect(find.text('RF 24-105mm F4 L'), findsNothing);

      await tester.tap(find.byIcon(Icons.view_column_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Objektiv').last);
      await tester.pumpAndSettle();

      expect(find.text('Objektiv'), findsOneWidget);
      expect(find.text('RF 24-105mm F4 L'), findsOneWidget);
      expect(wahl.zeigt(Listenspalte.objektiv), isTrue);
    });

    testWidgets('und wieder abschalten', (tester) async {
      await zeige(tester);
      expect(find.text('Canon EOS R10'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.view_column_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kamera').last);
      await tester.pumpAndSettle();

      expect(find.text('Kamera'), findsNothing);
      expect(find.text('Canon EOS R10'), findsNothing);
    });

    testWidgets('am Griff gezogen wird die Spalte breiter', (tester) async {
      await zeige(tester);
      // Gemessen wird, wo die NAECHSTE Spalte anfaengt: Die Ueberschrift
      // selbst ist so breit wie ihr Wort und waechst nicht mit.
      final vorher = tester.getRect(find.text('Kamera')).left;

      // Der Griff rechts der Datumsspalte – gefunden ueber den Zeiger,
      // den er setzt, nicht ueber eine ausgerechnete Stelle.
      final griffe = find.byWidgetPredicate((w) =>
          w is MouseRegion && w.cursor == SystemMouseCursors.resizeColumn);
      expect(griffe, findsNWidgets(Listenspaltenwahl.vorgabe.spalten.length));
      // Ohne `touchSlopX: 0` schluckt der Pruefstand die ersten zwanzig
      // Punkte als Wackelschwelle, und aus 80 wuerden 60.
      await tester.drag(griffe.at(1), const Offset(80, 0), touchSlopX: 0);
      await tester.pumpAndSettle();

      expect(wahl.breiteVon(Listenspalte.datum),
          Listenspaltenwahl.vorgabe.breiteVon(Listenspalte.datum) + 80);
      expect(tester.getRect(find.text('Kamera')).left,
          closeTo(vorher + 80, 0.5));
      // Und die Zeile darunter geht mit.
      expect(tester.getRect(find.text('Canon EOS R10')).left,
          closeTo(tester.getRect(find.text('Kamera')).left, 0.5));
    });

    testWidgets('die Ueberschrift steht ueber ihrer eigenen Spalte',
        (tester) async {
      // Der Fehler, den man am ehesten baut: Kopfzeile und Zeilen
      // rechnen die Breiten leicht verschieden, und der Versatz
      // summiert sich ueber die Reihe.
      await zeige(tester);
      final kopf = tester.getRect(find.text('Kamera'));
      final wert = tester.getRect(find.text('Canon EOS R10'));
      expect(wert.left, closeTo(kopf.left, 0.5));
    });

    testWidgets('die zusaetzlichen Spalten zeigen, was sie versprechen',
        (tester) async {
      wahl = const Listenspaltenwahl(
        spalten: [
          Listenspalte.masse,
          Listenspalte.groesse,
          Listenspalte.ort,
          Listenspalte.art,
        ],
        breiten: listenspalteBreiteVorgabe,
      );
      await zeige(tester);
      expect(find.text('6000 × 4000'), findsOneWidget);
      expect(find.textContaining('MB'), findsOneWidget);
      expect(find.text('Lissabon, Portugal'), findsOneWidget);
      expect(find.text('Foto'), findsOneWidget);
    });
  });
}
