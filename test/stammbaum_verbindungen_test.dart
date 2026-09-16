import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/stammbaum_screen.dart';
import 'package:photo_vault/services/backup_service.dart';
import 'package:photo_vault/services/stammbaum.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/theme/app_theme.dart';

/// Verbindungen im Stammbaum: lösen, umwidmen, und die Verwandten, die
/// über eine Zwischenperson eingetragen werden.
///
/// Der erste Block hält einen gemeldeten Fehler fest: Eine Adoptiv- oder
/// Pflegeverbindung ließ sich nicht lösen. Beide Elternreihen übergaben
/// fest „leiblich", und das Löschen traf deshalb keine Zeile – ohne
/// Fehler, ohne Hinweis.
void main() {
  late Directory tempRoot;
  late AppDatabase db;
  late LibraryState library;

  setUp(() async {
    tempRoot = Directory.systemTemp.createTempSync('pv_verbindungen_');
    db = AppDatabase(NativeDatabase.memory());
    final paths = await StoragePaths.forTesting(Directory(p.join(tempRoot.path, 'lib')));
    library = LibraryState()
      ..db = db
      ..paths = paths
      ..backupService = BackupService(db, paths);

    for (final (id, name, jahr, geschlecht) in [
      ('kind', 'Kind', 1960, null),
      ('vater', 'Vater', 1930, 'm'),
      ('ziehvater', 'Ziehvater', 1932, 'm'),
      ('pflegemutter', 'Pflegemutter', 1935, 'w'),
      ('enkel', 'Enkel', 1990, null),
      // Mit Geschlecht, damit die ausgerechnete Bezeichnung
      // geschlechtsgenau ausfällt („Neffe" statt „Geschwisterkind").
      ('fremd', 'Fremd', 1970, 'm'),
    ]) {
      await db.createPerson(PeopleCompanion.insert(
          id: id,
          name: name,
          geburtsdatum: Value(DateTime(jahr)),
          geschlecht: Value(geschlecht)));
    }
  });

  tearDown(() async {
    await db.close();
    tempRoot.deleteSync(recursive: true);
  });

  Future<void> zeige(WidgetTester tester, String start) async {
    // Die Vorgabe des Testfensters (800x600) ist kleiner als jedes echte
    // Fenster; der Gradwähler müsste darin gerollt werden, was den Test
    // über die Rollmechanik statt über die Sache aussagen liesse.
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      theme: buildDarkTheme(),
      home: StammbaumScreen(library: library, startPersonId: start),
    ));
    await tester.pumpAndSettle();
  }

  /// Wählt im Personenwähler eine bestehende Person aus und bestätigt.
  ///
  /// Der Wähler ist seit der Suche eine offene Liste, kein Ausklappfeld:
  /// Der Name steht sofort da und wird angetippt.
  Future<void> waehlePerson(WidgetTester tester, String name) async {
    await tester.tap(find.descendant(
        of: find.byType(ListTile), matching: find.text(name).last));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zuordnen'));
    await tester.pumpAndSettle();
  }

  /// Öffnet das Kartenmenü über den sichtbaren Knopf.
  Future<void> oeffneMenue(WidgetTester tester, String name) async {
    final karte = find.ancestor(
      of: find.text(name).first,
      matching: find.byType(Stack),
    );
    await tester.tap(
      find.descendant(of: karte.first, matching: find.byIcon(Icons.more_vert)).first,
    );
    await tester.pumpAndSettle();
  }

  group('Verbindung lösen', () {
    test('eine Adoptivkante lässt sich auch als "leiblich" adressiert lösen', () async {
      await db.fuegeBeziehungHinzu('kind', 'ziehvater', Verwandtschaft.adoptivelternteil);
      // Genau der Aufruf, den die Oberfläche vorher machte.
      final weg = await db.entferneBeziehung(
          'kind', 'ziehvater', Verwandtschaft.elternteil);
      expect(weg, isTrue);
      expect(await db.alleBeziehungen(), isEmpty);
    });

    test('das Lösen meldet, wenn es gar nichts gab', () async {
      expect(
        await db.entferneBeziehung('kind', 'fremd', Verwandtschaft.elternteil),
        isFalse,
      );
    });

    test('eine Partnerkante bleibt beim Lösen einer Elternkante stehen', () async {
      await db.fuegeBeziehungHinzu('kind', 'vater', Verwandtschaft.elternteil);
      await db.fuegeBeziehungHinzu('kind', 'fremd', Verwandtschaft.partner);
      await db.entferneBeziehung('kind', 'vater', Verwandtschaft.elternteil);
      final rest = await db.alleBeziehungen();
      expect(rest, hasLength(1));
      expect(rest.single.art, 'partner');
    });

    testWidgets('über die Oberfläche: die Adoptivkarte verschwindet', (tester) async {
      await db.fuegeBeziehungHinzu('kind', 'ziehvater', Verwandtschaft.adoptivelternteil);
      await db.fuegeBeziehungHinzu('kind', 'pflegemutter', Verwandtschaft.pflegeelternteil);
      await zeige(tester, 'kind');

      await oeffneMenue(tester, 'Ziehvater');
      await tester.tap(find.text('Verbindung entfernen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Entfernen'));
      await tester.pumpAndSettle();

      expect(find.text('Ziehvater'), findsNothing);
      expect(find.text('Pflegemutter'), findsWidgets, reason: 'die andere bleibt');
      final rest = await db.alleBeziehungen();
      expect(rest, hasLength(1));
      expect(rest.single.andereId, 'pflegemutter');
    });

    testWidgets('das Menü öffnet auch weiterhin per rechter Maustaste', (tester) async {
      await db.fuegeBeziehungHinzu('kind', 'vater', Verwandtschaft.elternteil);
      await zeige(tester, 'kind');

      final maus = await tester.createGesture(
          kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      await maus.down(tester.getCenter(find.text('Vater').first));
      await maus.up();
      await tester.pumpAndSettle();
      expect(find.text('Verbindung entfernen'), findsOneWidget);
    });
  });

  group('Art der Verbindung ändern', () {
    test('aus leiblich wird adoptiv, ohne die Verbindung zu verlieren', () async {
      await db.fuegeBeziehungHinzu('kind', 'vater', Verwandtschaft.elternteil);
      expect(
        await db.aendereElternart('kind', 'vater', Verwandtschaft.adoptivelternteil),
        isTrue,
      );
      final zeilen = await db.alleBeziehungen();
      expect(zeilen, hasLength(1));
      expect(zeilen.single.art, 'adoptiv');
      expect(zeilen.single.personId, 'kind');
      expect(zeilen.single.andereId, 'vater');
    });

    test('ohne bestehende Verbindung wird nichts angelegt', () async {
      expect(
        await db.aendereElternart('kind', 'fremd', Verwandtschaft.adoptivelternteil),
        isFalse,
      );
      expect(await db.alleBeziehungen(), isEmpty);
    });

    test('eine Partnerschaft hat keine Art und lässt sich nicht umwidmen', () async {
      await db.fuegeBeziehungHinzu('kind', 'fremd', Verwandtschaft.partner);
      expect(
        await db.aendereElternart('kind', 'fremd', Verwandtschaft.partner),
        isFalse,
      );
      expect((await db.alleBeziehungen()).single.art, 'partner');
    });

    testWidgets('über die Oberfläche wird aus dem Vater ein Ziehvater', (tester) async {
      await db.fuegeBeziehungHinzu('kind', 'vater', Verwandtschaft.elternteil);
      await zeige(tester, 'kind');

      await oeffneMenue(tester, 'Vater');
      await tester.tap(find.text('Art der Verbindung …'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Adoptiv'));
      await tester.pumpAndSettle();

      expect((await db.alleBeziehungen()).single.art, 'adoptiv');
    });
  });

  group('Kartenhöhe', () {
    testWidgets('ein zweizeiliger Name lässt die Karte nicht überlaufen',
        (tester) async {
      // Der Fall fiel beim Nachstellen des Verbindungsfehlers auf: Ein
      // Name, der in zwei Zeilen umbricht, brauchte zusammen mit
      // Bezeichnung und Lebensspanne 158 Punkte – die Karte war 148 hoch.
      // Nachgemessen, nicht geschätzt.
      await db.createPerson(PeopleCompanion.insert(
        id: 'lang',
        name: 'Marianne Schmidt-Hollmann',
        geburtsdatum: Value(DateTime(1874)),
        sterbedatum: Value(DateTime(1955)),
      ));
      await db.fuegeBeziehungHinzu('kind', 'lang', Verwandtschaft.elternteil);
      await zeige(tester, 'kind');

      expect(find.textContaining('Marianne'), findsWidgets);
      expect(find.text('1874–1955'), findsOneWidget);
      expect(tester.takeException(), isNull,
          reason: 'Ein Überlauf meldet sich hier als Ausnahme.');
    });
  });

  group('Weitere Verwandte über den Gradwähler', () {
    /// Öffnet Mehr -> Verwandten hinzufügen.
    Future<void> oeffneGradwaehler(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Mehr'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Verwandten hinzufügen …'));
      await tester.pumpAndSettle();
    }

    /// Holt einen Grad ins Bild. Die Liste ist länger als der Ausschnitt,
    /// sobald das Fenster klein genug ist – der Test soll an dieser Stelle
    /// nichts über die Fenstergröße behaupten.
    Future<Finder> zeigeGrad(WidgetTester tester, String grad) async {
      final ziel = find.text(grad);
      if (ziel.evaluate().isEmpty) {
        await tester.scrollUntilVisible(ziel, 80,
            scrollable: find.byType(Scrollable).last);
        await tester.pumpAndSettle();
      }
      return ziel;
    }

    Future<void> waehleGrad(WidgetTester tester, String grad) async {
      await oeffneGradwaehler(tester);
      await tester.tap(await zeigeGrad(tester, grad));
      await tester.pumpAndSettle();
    }

    testWidgets('ein Neffe wird Kind des Geschwisterkindes und heißt danach so',
        (tester) async {
      // kind und bruder teilen sich den Vater.
      await db.createPerson(
          PeopleCompanion.insert(id: 'bruder', name: 'Bruder',
              geschlecht: const Value('m')));
      await db.fuegeBeziehungHinzu('kind', 'vater', Verwandtschaft.elternteil);
      await db.fuegeBeziehungHinzu('bruder', 'vater', Verwandtschaft.elternteil);
      await zeige(tester, 'kind');

      await waehleGrad(tester, 'Neffe oder Nichte');
      // Nur ein Geschwisterkind – es wird nicht gefragt.
      await waehlePerson(tester, 'Fremd');

      final neu = (await db.alleBeziehungen())
          .where((k) => k.personId == 'fremd')
          .toList();
      expect(neu.single.andereId, 'bruder');
      // Die Rückmeldung nennt die AUSGERECHNETE Bezeichnung.
      expect(find.textContaining('Neffe'), findsWidgets);
    });

    testWidgets('ein nicht eintragbarer Grad steht grau da und erklärt sich',
        (tester) async {
      await zeige(tester, 'kind');
      await oeffneGradwaehler(tester);

      // Ohne jede Verwandtschaft ist nichts eintragbar – aber alles
      // sichtbar, mit dem Grund darunter.
      expect(find.text('Neffe oder Nichte'), findsOneWidget);
      expect(find.text('Cousin oder Cousine'), findsOneWidget);
      expect(find.textContaining('zuerst ein Geschwisterkind'), findsWidgets);
      expect(find.textContaining('zuerst einen Onkel'), findsWidgets);

      // Ein Tippen auf den grauen Eintrag tut nichts.
      await tester.tap(find.text('Neffe oder Nichte'));
      await tester.pumpAndSettle();
      expect(find.text('Verwandten hinzufügen …'), findsOneWidget,
          reason: 'der Wähler bleibt offen');
    });

    testWidgets('ein Geschwisterkind bekommt beide Eltern', (tester) async {
      await db.fuegeBeziehungHinzu('kind', 'vater', Verwandtschaft.elternteil);
      await db.fuegeBeziehungHinzu('kind', 'pflegemutter', Verwandtschaft.elternteil);
      await zeige(tester, 'kind');

      await waehleGrad(tester, 'Geschwisterkind');
      await waehlePerson(tester, 'Fremd');

      expect(
        (await db.alleBeziehungen())
            .where((k) => k.personId == 'fremd')
            .map((k) => k.andereId)
            .toSet(),
        equals({'vater', 'pflegemutter'}),
        reason: 'mit nur einem wäre es ein Halbgeschwisterkind',
      );
    });

    testWidgets('bei zwei Eltern fragt der Großelternteil, wessen gemeint ist',
        (tester) async {
      await db.fuegeBeziehungHinzu('kind', 'vater', Verwandtschaft.elternteil);
      await db.fuegeBeziehungHinzu('kind', 'pflegemutter', Verwandtschaft.elternteil);
      await zeige(tester, 'kind');

      await waehleGrad(tester, 'Großelternteil');
      expect(find.textContaining('über wen?'), findsOneWidget);
      await tester.tap(find.text('Pflegemutter').last);
      await tester.pumpAndSettle();
      await waehlePerson(tester, 'Fremd');

      final neu = (await db.alleBeziehungen())
          .where((k) => k.andereId == 'fremd')
          .toList();
      expect(neu.single.personId, 'pflegemutter');
    });

    testWidgets('ein Schwiegerkind wird Partner des Kindes', (tester) async {
      await db.fuegeBeziehungHinzu('enkel', 'kind', Verwandtschaft.elternteil);
      await zeige(tester, 'kind');

      await waehleGrad(tester, 'Schwiegerkind');
      await waehlePerson(tester, 'Fremd');

      final neu = (await db.alleBeziehungen())
          .where((k) => k.art == 'partner')
          .toList();
      expect(neu, hasLength(1));
      expect({neu.single.personId, neu.single.andereId}, {'fremd', 'enkel'});
    });
  });
}
