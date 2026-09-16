import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/explore_screen.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';

/// **Der Erkunden-Bildschirm sprang von allein wieder nach oben.**
///
/// Wer bis zum Papierkorb ganz unten scrollte und dann ein Stueck
/// zurueckwollte, stand nach zwei kleinen Zuegen wieder am Anfang.
///
/// **Woran es lag.** Die Seite war ein `ListView`, also eine faule Liste,
/// und ihre Abschnitte sind sehr unterschiedlich hoch: ein Personenstreifen
/// 96 Punkte, die Kartenvorschau 200, die Papierkorbzeile 72. Eine faule
/// Liste kennt die Hoehe der abgebauten Abschnitte nicht mehr, sondern
/// schaetzt die Gesamthoehe aus dem Durchschnitt dessen, was gerade
/// ausgelegt ist. Ganz unten sind das nur die kurzen. Gemessen, bei einem
/// Fenster von 1830x1000 und zwoelf Zuegen zu je 120 Punkten:
///
/// ```
/// unten angekommen   1288 von max 1288
/// ein Zug zurueck    1201 von max 1288
/// noch ein Zug        250 von max  352   <- 950 Punkte auf einmal
/// noch ein Zug        145 von max 2491
/// zwei Zuege spaeter    0 von max 2810   <- ganz oben
/// ```
///
/// Die Schaetzung bricht auf 352 ein, die Rollposition wird darauf
/// gekappt – und wenn die echte Hoehe (2810) zurueckkommt, ist sie weg.
///
/// Geprueft wird deshalb die Rueckfahrt, nicht die Hinfahrt: Nach unten
/// faellt es nicht auf, weil dort ohnehin nach unten gekappt wird.
void main() {
  late Directory wurzel;
  late AppDatabase db;
  late LibraryState library;

  setUp(() async {
    wurzel = Directory.systemTemp.createTempSync('pv_erk_');
    db = AppDatabase(NativeDatabase.memory());
    library = LibraryState()
      ..db = db
      ..paths =
          await StoragePaths.forTesting(Directory(p.join(wurzel.path, 'lib')));
  });

  tearDown(() async {
    await db.close();
    wurzel.deleteSync(recursive: true);
  });

  Future<void> abbauen(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 1));
  }

  Future<void> aufnahme(String id, DateTime wann,
          {double? breite, double? laenge, bool papierkorb = false}) =>
      db.into(db.assets).insert(AssetsCompanion.insert(
            id: id,
            originalFileName: '$id.jpg',
            relativePath: 'originals/$id.jpg',
            checksum: 'pruef-$id',
            type: 'IMAGE',
            fileCreatedAt: wann,
            importedAt: wann,
            latitude: Value(breite),
            longitude: Value(laenge),
            isTrashed: Value(papierkorb),
          ));

  /// Eine Bibliothek, in der jeder Abschnitt etwas zu zeigen hat – sonst
  /// sind alle Streifen gleich flach, und genau die Hoehenunterschiede
  /// sind hier die Frage.
  Future<void> gefuellteBibliothek() async {
    for (var i = 0; i < 40; i++) {
      await aufnahme('a$i', DateTime(2026, 5, 1).add(Duration(days: i)),
          breite: 52.2 + i * 0.01, laenge: 9.8 + i * 0.01);
    }
    // „An diesem Tag" braucht Aufnahmen von heute in frueheren Jahren –
    // und eine krumme Uhrzeit: Volle Stunden gelten seit 3.13.0 als
    // erfunden und fallen aus den Erinnerungen (siehe
    // [AppDatabase.assetsOnThisDay]).
    final heute = DateTime.now();
    for (var j = 1; j <= 5; j++) {
      await aufnahme(
          'e$j', DateTime(heute.year - j, heute.month, heute.day, 12, 17),
          breite: 52.3, laenge: 9.7);
    }
    for (var i = 0; i < 6; i++) {
      await aufnahme('p$i', DateTime(2026, 4, 1 + i), papierkorb: true);
    }
    for (var i = 0; i < 12; i++) {
      await db.createPerson(PeopleCompanion.insert(id: 'per$i', name: 'Person $i'));
    }
    for (var i = 0; i < 10; i++) {
      await db.createAlbum(AlbumsCompanion.insert(
          id: 'alb$i', name: 'Album $i', createdAt: DateTime(2026, 3, 1 + i)));
    }
  }

  Widget rahmen(Widget kind) => MaterialApp(
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        locale: const Locale('de'),
        home: Scaffold(body: kind),
      );

  /// Die senkrechte Rollflaeche der Seite – unabhaengig davon, welches
  /// Widget sie gerade herstellt. Die waagerechten Streifen darin haben
  /// ihre eigenen und sind hier nicht gemeint.
  ScrollPosition senkrechte(WidgetTester tester) => tester
      .stateList<ScrollableState>(find.byType(Scrollable))
      .firstWhere((s) => s.position.axis == Axis.vertical)
      .position;

  testWidgets('nach dem Papierkorb bleibt die Rueckfahrt an ihrem Platz',
      (tester) async {
    tester.view.physicalSize = const Size(1830, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await gefuellteBibliothek();
    await tester.pumpWidget(rahmen(ExploreScreen(library: library)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final pos = senkrechte(tester);
    // Der Zug beginnt in der Mitte des Fensters. Die waagerechten
    // Streifen dort nehmen keinen senkrechten Zug an, er landet also
    // zuverlaessig bei der Seite selbst.
    const mitte = Offset(900, 500);

    // Ganz nach unten, bis zum Papierkorb.
    for (var i = 0; i < 12; i++) {
      await tester.dragFrom(mitte, const Offset(0, -300));
      await tester.pump();
    }
    final unten = pos.pixels;
    expect(unten, greaterThan(1000), reason: 'erst einmal wirklich unten sein');

    // Und ein Stueck zurueck. Zwoelf Zuege zu 120 Punkten sind 1440 –
    // mehr als der Weg nach unten, die Seite darf also oben ankommen,
    // aber nicht schneller als gezogen wird.
    var gezogen = 0.0;
    for (var i = 0; i < 12; i++) {
      final vorher = pos.pixels;
      await tester.dragFrom(mitte, const Offset(0, 120));
      await tester.pump();
      gezogen += vorher - pos.pixels;
      expect(vorher - pos.pixels, lessThan(200),
          reason: 'ein Zug von 120 Punkten darf die Seite nicht weiter '
              'bewegen als 120 Punkte – gesprungen bei Zug ${i + 1}');
    }
    expect(gezogen, greaterThan(600), reason: 'es muss sich ueberhaupt bewegen');

    await abbauen(tester);
  });

  testWidgets('die Gesamthoehe bleibt stabil, egal wo man steht',
      (tester) async {
    // Die Ursache selbst, ohne den Umweg ueber die Rollposition: Eine
    // faule Liste schaetzte hier je nach Standort zwischen 352 und 2810.
    tester.view.physicalSize = const Size(1830, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await gefuellteBibliothek();
    await tester.pumpWidget(rahmen(ExploreScreen(library: library)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final pos = senkrechte(tester);
    const mitte = Offset(900, 500);
    final gesehen = <double>[pos.maxScrollExtent];
    for (var i = 0; i < 12; i++) {
      await tester.dragFrom(mitte, const Offset(0, -300));
      await tester.pump();
      gesehen.add(pos.maxScrollExtent);
    }

    final kleinste = gesehen.reduce((a, b) => a < b ? a : b);
    final groesste = gesehen.reduce((a, b) => a > b ? a : b);
    expect(groesste - kleinste, lessThan(1.0),
        reason: 'die Seite kennt ihre Hoehe, sie schaetzt sie nicht: '
            'gesehen $gesehen');

    await abbauen(tester);
  });
}
