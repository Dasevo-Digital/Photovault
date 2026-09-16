import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/screens/familienstatistik_screen.dart';
import 'package:photo_vault/screens/stammbaum_screen.dart';
import 'package:photo_vault/widgets/faecher_ansicht.dart';
import 'package:photo_vault/widgets/familien_zeitleiste.dart';
import 'package:photo_vault/services/backup_service.dart';
import 'package:photo_vault/services/stammbaum.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/state/library_state.dart';
import 'package:photo_vault/theme/app_theme.dart';

import 'goldbilder.dart';

/// Der Stammbaum-Bildschirm.
///
/// Geprüft wird, was man an einem Bildschirmfoto nicht sieht: dass die
/// richtigen Personen in den richtigen Reihen stehen, dass ein Klick den
/// Ausschnitt verschiebt statt den Bildschirm zu verlassen, und dass die
/// Hinweise auf weitere Verwandtschaft nur dort erscheinen, wo tatsächlich
/// etwas außerhalb des Bildes liegt.
void main() {
  late Directory tempRoot;
  late AppDatabase db;
  late LibraryState library;

  setUp(() async {
    tempRoot = Directory.systemTemp.createTempSync('pv_stammbaum_');
    db = AppDatabase(NativeDatabase.memory());
    final paths = await StoragePaths.forTesting(Directory(p.join(tempRoot.path, 'lib')));
    library = LibraryState()
      ..db = db
      ..paths = paths
      ..backupService = BackupService(db, paths);

    // opa + oma -> vater; vater + mutter -> kind, schwester
    for (final (id, name, jahr, geschlecht) in [
      ('opa', 'Opa', 1901, 'm'),
      ('oma', 'Oma', 1903, 'w'),
      ('vater', 'Vater', 1931, 'm'),
      ('mutter', 'Mutter', 1934, 'w'),
      ('kind', 'Kind', 1962, 'm'),
      ('schwester', 'Schwester', 1965, 'w'),
      ('uropa', 'Uropa', 1874, 'm'),
    ]) {
      await db.createPerson(PeopleCompanion.insert(
        id: id,
        name: name,
        geburtsdatum: Value(DateTime(jahr)),
        geschlecht: Value(geschlecht),
      ));
    }
    await db.fuegeBeziehungHinzu('vater', 'opa', Verwandtschaft.elternteil);
    await db.fuegeBeziehungHinzu('vater', 'oma', Verwandtschaft.elternteil);
    await db.fuegeBeziehungHinzu('vater', 'mutter', Verwandtschaft.partner);
    await db.fuegeBeziehungHinzu('kind', 'vater', Verwandtschaft.elternteil);
    await db.fuegeBeziehungHinzu('kind', 'mutter', Verwandtschaft.elternteil);
    await db.fuegeBeziehungHinzu('schwester', 'vater', Verwandtschaft.elternteil);
    await db.fuegeBeziehungHinzu('schwester', 'mutter', Verwandtschaft.elternteil);
    await db.fuegeBeziehungHinzu('opa', 'uropa', Verwandtschaft.elternteil);
  });

  tearDown(() async {
    await db.close();
    tempRoot.deleteSync(recursive: true);
  });

  /// Derselbe Bildschirm im hellen Erscheinungsbild.
  ///
  /// Der Zierbaum hat zwei Farbsätze, und der zweite ist der, den man
  /// vergisst. Ein Goldbild je Fassung ist das Gegenmittel.
  Future<void> zeigeHell(WidgetTester tester, String start) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      theme: buildLightTheme(),
      home: StammbaumScreen(library: library, startPersonId: start),
    ));
    await tester.pumpAndSettle();
  }

  /// Der Bildschirm wird auf eine Route geschoben statt als `home` gesetzt:
  /// Nur dann gibt es einen Zurück-Pfeil, und nur dann lässt sich prüfen,
  /// dass er erst dem Weg durch den Baum folgt.
  Future<void> zeige(WidgetTester tester, String start,
      {double schriftfaktor = 1.0}) async {
    await tester.pumpWidget(MaterialApp(
      // Eigener Schlüssel je Durchgang: Ohne ihn behält ein zweiter
      // Aufruf im selben Prüfstand den Navigator des ersten, und der
      // Knopf „auf" ist dann gar nicht mehr da.
      key: ValueKey('$start-$schriftfaktor'),
      locale: const Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      theme: buildDarkTheme(),
      builder: schriftfaktor == 1.0
          ? null
          : (context, kind) => MediaQuery.withClampedTextScaling(
              minScaleFactor: schriftfaktor,
              maxScaleFactor: schriftfaktor,
              child: kind!),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    StammbaumScreen(library: library, startPersonId: start),
              )),
              child: const Text('auf'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('auf'));
    await tester.pumpAndSettle();
  }

  testWidgets('jedes Schild nennt Name und Verhältnis', (tester) async {
    await zeige(tester, 'kind');

    // **Keine Reihenüberschriften mehr.** Der Reihenbaum schrieb
    // „Eltern" über eine Zeile; der Zierbaum stellt die Leute dorthin,
    // wo sie hingehören, und schreibt an jedes Schild, wie es zur Mitte
    // steht. Eine Überschrift kann nicht sagen, zu wem jemand gehört –
    // genau daran ist der alte Baum gescheitert.
    expect(find.text('Eltern'), findsNothing);
    expect(find.text('Geschwister'), findsNothing);

    // Je zwei Treffer: der Name auf dem Schild und das Verhältnis
    // darunter, das hier zufällig gleich lautet.
    expect(find.text('Vater'), findsNWidgets(2));
    expect(find.text('Mutter'), findsNWidgets(2));
    expect(find.text('Schwester'), findsNWidgets(2));
  });

  testWidgets('zeigt Partner und Kinder der Person in der Mitte',
      (tester) async {
    await zeige(tester, 'vater');

    // Die Mutter wohnt jetzt IM Haushalt des Vaters – sie steht neben
    // ihm, nicht in einer eigenen Reihe „Partner".
    expect(find.text('Partnerin'), findsOneWidget);
    // Die beiden Kinder heißen „Kind" und „Schwester", ihre Verhältnisse
    // lauten „Sohn" und „Tochter".
    expect(find.text('Kind'), findsOneWidget);
    expect(find.text('Sohn'), findsOneWidget);
    expect(find.text('Schwester'), findsOneWidget);
    expect(find.text('Tochter'), findsOneWidget);
  });

  testWidgets('ein Klick rückt die angetippte Person in die Mitte',
      (tester) async {
    await zeige(tester, 'kind');
    // Der Zierbaum reicht weiter als der Reihenbaum: Großeltern und
    // Urgroßvater stehen von Anfang an im Bild.
    expect(find.text('Opa'), findsOneWidget);
    expect(find.text('Kind'), findsOneWidget, reason: 'die Mitte');

    // Der Name auf dem Schild, nicht das gleichlautende Verhältnis
    // darunter – beide führen zum selben Ziel, aber der Test soll sagen,
    // worauf er tippt.
    await tester.tap(find.text('Vater').first);
    await tester.pumpAndSettle();

    // Jetzt steht der Vater in der Mitte: Das Kind heisst von dort aus
    // „Sohn", und die Großeltern sind zu Eltern geworden.
    expect(find.text('Sohn'), findsOneWidget);
    expect(find.text('Urgroßvater'), findsNothing,
        reason: 'von hier aus ist Uropa der Großvater');
  });

  testWidgets('der Zurück-Pfeil folgt dem eigenen Weg durch den Baum',
      (tester) async {
    await zeige(tester, 'kind');
    expect(find.text('Urgroßvater'), findsOneWidget);
    await tester.tap(find.text('Vater').first);
    await tester.pumpAndSettle();
    expect(find.text('Urgroßvater'), findsNothing,
        reason: 'von hier aus ist Uropa der Großvater');

    // Nicht tester.pageBack(): das sucht nach der Beschriftung "Back",
    // und die Oberfläche läuft hier auf Deutsch.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    // Zurück beim Kind – und nicht aus dem Stammbaum heraus.
    expect(find.byType(StammbaumScreen), findsOneWidget);
    expect(find.text('Urgroßvater'), findsOneWidget);
    expect(find.text('Schwester'), findsNWidgets(2),
        reason: 'Name und Verhältnis, beide auf ihrem Schild');
  });

  testWidgets('weist auf Verwandtschaft hin, die außerhalb des Bildes liegt',
      (tester) async {
    // Der Zierbaum reicht bis zu den Urgroßeltern. Erst eine Generation
    // darüber liegt draussen – und dann trägt der Urgroßvater das
    // Zeichen, sonst niemand.
    await db.createPerson(
        PeopleCompanion.insert(id: 'ururopa', name: 'Ururopa'));
    await db.fuegeBeziehungHinzu('uropa', 'ururopa', Verwandtschaft.elternteil);

    await zeige(tester, 'kind');

    expect(find.text('Uropa'), findsOneWidget);
    expect(find.text('Ururopa'), findsNothing, reason: 'zu weit draussen');
    expect(find.byIcon(Icons.more_horiz), findsOneWidget,
        reason: 'genau am Urgroßvater, über dem es weitergeht');
  });

  testWidgets('eine Verbindung lässt sich lösen', (tester) async {
    await zeige(tester, 'kind');

    final maus = await tester.createGesture(
        kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
    await maus.down(tester.getCenter(find.text('Mutter').first));
    await maus.up();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Verbindung entfernen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entfernen'));
    await tester.pumpAndSettle();

    // Die Mutter verschwindet NICHT aus dem Bild – sie wohnt im Haushalt
    // des Vaters und steht weiter neben ihm. Was sich ändert, ist ihr
    // Verhältnis zur Mitte: Sie ist jetzt die Partnerin eines
    // Elternteils, ohne selbst Elternteil zu sein. Dafür gibt es ein
    // Wort, und es steht auf ihrem Schild.
    expect(find.text('Mutter'), findsOneWidget, reason: 'nur noch der Name');
    expect(find.text('Stiefmutter'), findsOneWidget);
    // Die Schwester bleibt über den Vater im Bild – aber ihr Verhältnis
    // ändert sich mit: Sie hat noch beide Eltern eingetragen, das Kind in
    // der Mitte nur noch einen gemeinsamen. Das sind Halbgeschwister, und
    // genau das soll dort dann auch stehen.
    expect(find.text('Schwester'), findsOneWidget, reason: 'nur noch der Name');
    expect(find.text('Halbschwester'), findsOneWidget);
    expect((await db.alleBeziehungen()).length, 7);
  });

  testWidgets('die Karten nennen die Verwandtschaft', (tester) async {
    await zeige(tester, 'kind');
    // Die Bezeichnung, nicht der Name: Beide heißen hier gleich, deshalb
    // je zwei Treffer – einer als Name, einer als Bezeichnung.
    expect(find.text('Vater'), findsNWidgets(2));
    expect(find.text('Mutter'), findsNWidgets(2));
    // Die Schwester heißt „Schwester" und ist eine – auch zwei Treffer.
    expect(find.text('Schwester'), findsNWidgets(2));
    expect(find.text('Großvater'), findsOneWidget,
        reason: 'der Zierbaum reicht bis zu den Urgroßeltern');
    // Auf der Karte in der Mitte steht keine Bezeichnung.
    expect(find.text('diese Person'), findsNothing);
  });

  testWidgets('die Eltern des Schwagers heissen nach dem Weg zu ihnen',
      (tester) async {
    // Der Anlass der ganzen Runde: Bis hierher stand bei diesen Personen
    // „angeheiratet" – dieselbe Auskunft, die auch ein wildfremder
    // Vetter bekäme. Und die Rechnung allein beweist nichts: Der Baum
    // muss sie auch abrufen.
    await db.createPerson(PeopleCompanion.insert(
        id: 'schwager', name: 'Michael', geschlecht: const Value('m')));
    await db.createPerson(PeopleCompanion.insert(
        id: 'schwiegermutterDerSchwester',
        name: 'Petra',
        geschlecht: const Value('w')));
    await db.fuegeBeziehungHinzu('schwester', 'schwager', Verwandtschaft.partner);
    await db.fuegeBeziehungHinzu(
        'schwager', 'schwiegermutterDerSchwester', Verwandtschaft.elternteil);

    // Angeheiratetes steht am Ende der Liste – ein hohes Fenster, sonst
    // ist die Zeile schlicht noch nicht gebaut und der Sucher findet
    // nichts, obwohl alles stimmt.
    await tester.binding.setSurfaceSize(const Size(1000, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await zeige(tester, 'kind');
    await tester.tap(find.text('Verwandte'));
    await tester.pumpAndSettle();

    expect(find.text('Mutter von Schwager Michael'), findsOneWidget);
    expect(find.text('angeheiratet'), findsNothing,
        reason: 'für diese Person gibt es jetzt eine Auskunft');
  });

  testWidgets('das Geschlecht entscheidet über die Bezeichnung',
      (tester) async {
    await db.setzeGeschlecht('schwester', null);
    await zeige(tester, 'kind');
    // Ohne Angabe lautet die Bezeichnung „Geschwister" – zusammen mit der
    // Überschrift also zwei Treffer. Mit Angabe stand dort „Schwester".
    expect(find.text('Geschwister'), findsOneWidget,
        reason: 'ohne Angabe die neutrale Form');
    expect(find.text('Schwester'), findsOneWidget, reason: 'nur noch der Name');
  });

  testWidgets('die Verwandtenliste nennt auch die Entfernten', (tester) async {
    await zeige(tester, 'kind');
    await tester.tap(find.text('Verwandte'));
    await tester.pumpAndSettle();

    // Im Baum stehen die Großeltern nicht – in der Liste schon, mit
    // ihrer Bezeichnung.
    expect(find.text('Großvater'), findsOneWidget);
    expect(find.text('Großmutter'), findsOneWidget);
    expect(find.text('Opa'), findsOneWidget);
  });

  testWidgets('die Liste stellt die nächsten Angehörigen voran',
      (tester) async {
    await zeige(tester, 'kind');
    await tester.tap(find.text('Verwandte'));
    await tester.pumpAndSettle();

    final namen = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((k) => (k.title! as Text).data)
        .toList();
    expect(namen.first, 'Schwester', reason: 'Geschwister vor Eltern');
    expect(namen.take(3), containsAll(['Vater', 'Mutter']));
    // Der Urgroßvater steht am Ende – er ist der entfernteste Verwandte.
    expect(namen.last, 'Uropa');
  });

  testWidgets('ohne Vorgabe wählt der Bildschirm selbst eine Person',
      (tester) async {
    // Über den Menüpunkt geöffnet gibt es keine Startperson. Genommen wird
    // die mit den meisten Verwandten – hier der Vater (zwei Eltern, zwei
    // Kinder, eine Partnerin).
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      theme: buildDarkTheme(),
      home: StammbaumScreen(library: library),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Stammbaum: Vater'), findsOneWidget);
  });

  testWidgets('der Fächer zeigt Generationen, die der Baum nicht zeigt',
      (tester) async {
    await zeige(tester, 'kind');
    await tester.tap(find.text('Fächer'));
    await tester.pumpAndSettle();

    // Im Baum stehen die Großeltern nicht – im Fächer schon, als äußerer
    // Ring. Gezeichnet wird auf Leinwand, also prüft der Test die Daten
    // dahinter statt der Pixel.
    final maler = tester.widget<CustomPaint>(find.descendant(
      of: find.byType(FaecherAnsicht),
      matching: find.byType(CustomPaint),
    ));
    expect(maler.painter, isNotNull);
    // Und das Abbild weiter unten zeigt, dass daraus auch etwas wird.
    expect(find.byType(FaecherAnsicht), findsOneWidget);
  });

  testWidgets('die Nachfahrengliederung rückt jede Generation ein',
      (tester) async {
    await zeige(tester, 'opa');
    await tester.tap(find.text('Nachfahren'));
    await tester.pumpAndSettle();

    // Opa -> Vater -> Kind und Schwester.
    for (final name in ['Opa', 'Vater', 'Kind', 'Schwester']) {
      expect(find.text(name), findsOneWidget, reason: name);
    }
    // Die Einrückung wächst mit der Generation.
    final x = {
      for (final name in ['Opa', 'Vater', 'Kind'])
        name: tester.getTopLeft(find.text(name)).dx,
    };
    expect(x['Vater']!, greaterThan(x['Opa']!));
    expect(x['Kind']!, greaterThan(x['Vater']!));
  });

  testWidgets('ohne Vorfahren erklärt der Fächer, was er zeigen würde',
      (tester) async {
    // Der Urgroßvater ist die einzige Person ohne eingetragene Eltern.
    await zeige(tester, 'uropa');
    await tester.tap(find.text('Fächer'));
    await tester.pumpAndSettle();
    expect(find.textContaining('noch keine Vorfahren eingetragen'),
        findsOneWidget);
  });

  group('grössere Systemschrift', () {
    /// **Der Fund der 18. Prüfrunde.** In die Tafel eines Schildes
    /// passen genau drei Zeilen: 56,6 von 67 Punkten. Bei 120 Prozent
    /// Systemschrift braucht dieselbe Tafel 67,9 – und dann malt der
    /// Text über seinen Rand, genau wie beim gemeldeten Fehler mit den
    /// zwei Mehrzeichen. Ein Schild lässt sich nicht dehnen, also wächst
    /// der ganze Baum mit.
    testWidgets('das Schild wächst mit', (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await zeige(tester, 'kind');
      final normal = tester.getSize(find.text('Kind'));
      final schildNormal = tester.getSize(
          find.ancestor(of: find.text('Kind'), matching: find.byType(Stack)).first);

      await zeige(tester, 'kind', schriftfaktor: 1.5);
      final gross = tester.getSize(find.text('Kind'));
      final schildGross = tester.getSize(
          find.ancestor(of: find.text('Kind'), matching: find.byType(Stack)).first);

      expect(gross.height / normal.height, closeTo(1.5, 0.15),
          reason: 'die Schrift wird wirklich grösser');
      expect(schildGross.width / schildNormal.width, closeTo(1.5, 0.05),
          reason: 'und das Schild im selben Mass – sonst läuft es über');
    });

  });

  group('den Baum bewegen', () {
    /// Ein Fenster, in das dieser Baum NICHT hineinpasst – sonst gäbe es
    /// nichts zu verschieben, und die Prüfung wäre eine Behauptung.
    Future<void> zeigeGross(WidgetTester tester) async {
      tester.view.physicalSize = const Size(900, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await zeige(tester, 'kind');
    }

    testWidgets('ziehen verschiebt die Ansicht', (tester) async {
      // Vorher lag der Baum in zwei Rollbereichen: An einer Tastfläche
      // oder einer Magic Mouse kam man damit nicht an seinen Rand.
      await zeigeGross(tester);
      final vorher = tester.getRect(find.text('Kind'));
      await tester.drag(find.byType(InteractiveViewer), const Offset(-120, -60));
      await tester.pumpAndSettle();
      final nachher = tester.getRect(find.text('Kind'));
      // Nicht auf den Punkt: Die Gestenerkennung schluckt die ersten
      // Punkte einer Bewegung, damit ein Klick mit zittriger Hand kein
      // Ziehen wird. Es geht um die Richtung und darum, dass überhaupt
      // etwas passiert.
      expect(nachher.left, lessThan(vorher.left - 80));
      expect(nachher.top, lessThan(vorher.top - 20));
    });

    testWidgets('die Zoomknöpfe machen den Baum grösser und wieder kleiner',
        (tester) async {
      await zeigeGross(tester);
      final vorher = tester.getRect(find.text('Kind'));
      await tester.tap(find.byTooltip('Näher heran'));
      await tester.pumpAndSettle();
      final nah = tester.getRect(find.text('Kind'));
      expect(nah.width, greaterThan(vorher.width),
          reason: 'ein Zoomschritt muss zu sehen sein');
      await tester.tap(find.byTooltip('Weiter weg'));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.text('Kind')).width,
          closeTo(vorher.width, 0.5));
    });

    testWidgets('„Ganz zeigen" holt den ganzen Baum ins Bild', (tester) async {
      // Der Knopf ist die Antwort auf die eigentliche Klage: Ein Baum mit
      // angeheirateter Verwandtschaft ist breiter als jedes Fenster.
      await zeigeGross(tester);
      // Erst hineinzoomen, damit das Einpassen etwas zu tun hat.
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byTooltip('Näher heran'));
      }
      await tester.pumpAndSettle();
      expect(tester.getRect(find.text('Opa')).height, greaterThan(20));

      await tester.tap(find.byTooltip('Ganz zeigen'));
      await tester.pumpAndSettle();
      // Oberste und unterste Person stehen beide im Fenster.
      final fenster = tester.getRect(find.byType(InteractiveViewer));
      for (final name in ['Opa', 'Kind']) {
        final kasten = tester.getRect(find.text(name));
        expect(fenster.contains(kasten.topLeft), isTrue, reason: name);
        expect(fenster.contains(kasten.bottomRight), isTrue, reason: name);
      }
    });

    testWidgets('ein Klick auf eine Person rückt sie ins Bild',
        (tester) async {
      // Vorher begann der Ausschnitt in der linken oberen Ecke des
      // Baumes. Wer eine Person in die Mitte setzte, musste sie danach
      // erst suchen.
      await zeigeGross(tester);
      // Erst alles ins Bild holen – anklicken lässt sich nur, was man
      // sieht, und der Urgrossvater steht ausserhalb.
      await tester.tap(find.byTooltip('Ganz zeigen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Opa'));
      await tester.pumpAndSettle();
      final fenster = tester.getRect(find.byType(InteractiveViewer));
      final kasten = tester.getRect(find.text('Opa'));
      expect(fenster.contains(kasten.center), isTrue,
          reason: 'die neue Mitte muss zu sehen sein');
    });
  });

  testWidgets('so sieht der Baum aus', (tester) async {
    // Ein Abbild statt einer Behauptung. An das echte Fenster kommt man in
    // dieser Umgebung nicht heran; das gerenderte Bild ist die einzige
    // Möglichkeit, die Anordnung und die Verbindungslinien tatsächlich
    // anzusehen statt sie aus dem Quelltext zu erschliessen. Die Schrift
    // ist im Test ein Platzhalter – es geht um Kästen und Linien.
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await zeige(tester, 'kind');
    await expectLater(
      find.byType(StammbaumScreen),
      matchesGoldenFile('golden/stammbaum.png'),
    );
  }, skip: nurAufReferenzplattform);

  testWidgets('so sieht der Baum mit Partner und Kindern aus', (tester) async {
    // Der zweite Fall: eine Person mit Eltern darüber, Partner daneben und
    // zwei Kindern darunter. Das erste Abbild zeigt weder die kurze Linie
    // zum Partner noch den Verbinder nach unten.
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await zeige(tester, 'vater');
    await expectLater(
      find.byType(StammbaumScreen),
      matchesGoldenFile('golden/stammbaum_voll.png'),
    );
  }, skip: nurAufReferenzplattform);

  testWidgets('so sieht die Verwandtenliste aus', (tester) async {
    // Die Sicht, in der die entfernteren Bezeichnungen überhaupt erst
    // auftauchen – im Baum stehen die Großeltern nicht.
    tester.view.physicalSize = const Size(760, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await zeige(tester, 'kind');
    await tester.tap(find.text('Verwandte'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(StammbaumScreen),
      matchesGoldenFile('golden/stammbaum_verwandte.png'),
    );
  }, skip: nurAufReferenzplattform);

  testWidgets('der Fächer lässt sich vorlesen', (tester) async {
    // Ein CustomPaint ist für die Sprachausgabe eine leere Fläche. Ohne
    // eigene Beschriftungen wäre der Fächer dort überhaupt nicht
    // vorhanden – geprüft wird deshalb der Semantik-Baum, nicht das Bild.
    final semantik = tester.ensureSemantics();
    await zeige(tester, 'kind');
    await tester.tap(find.text('Fächer'));
    await tester.pumpAndSettle();

    for (final name in ['Kind', 'Vater', 'Mutter', 'Opa', 'Oma']) {
      expect(find.bySemanticsLabel(name), findsOneWidget, reason: name);
    }
    semantik.dispose();
  });

  testWidgets('so sieht die Sanduhr aus', (tester) async {
    tester.view.physicalSize = const Size(860, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await zeige(tester, 'kind');
    await tester.tap(find.text('Sanduhr'));
    await tester.pumpAndSettle();
    await expectLater(find.byType(StammbaumScreen),
        matchesGoldenFile('golden/stammbaum_sanduhr.png'));
  }, skip: nurAufReferenzplattform);

  testWidgets('die Sanduhr zeigt mehrere Generationen auf einmal',
      (tester) async {
    await zeige(tester, 'kind');
    await tester.tap(find.text('Sanduhr'));
    await tester.pumpAndSettle();
    // Im Baum stehen weder Großeltern noch Urgroßvater – hier alle drei
    // Generationen zugleich.
    for (final name in ['Kind', 'Vater', 'Mutter', 'Opa', 'Oma', 'Uropa']) {
      expect(find.text(name), findsOneWidget, reason: name);
    }
  });

  testWidgets('so sieht der Fächer aus', (tester) async {
    // Der eigentliche Beleg für die gewählte Baumoptik: vier Ringe, jeder
    // Platz mit genau einem Nachfolger nach innen.
    tester.view.physicalSize = const Size(760, 560);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await zeige(tester, 'kind');
    await tester.tap(find.text('Fächer'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(StammbaumScreen),
      matchesGoldenFile('golden/stammbaum_faecher.png'),
    );
  }, skip: nurAufReferenzplattform);

  /// Ein paar Daten mehr, damit auf der Zeitleiste etwas zu sehen ist:
  /// ein abgeschlossenes Leben, eine Hochzeit, ein Umzug.
  Future<void> lebenslaeufe() async {
    await (db.update(db.people)..where((t) => t.id.equals('opa')))
        .write(PeopleCompanion(sterbedatum: Value(DateTime(1980, 3, 4))));
    await (db.update(db.people)..where((t) => t.id.equals('uropa')))
        .write(PeopleCompanion(sterbedatum: Value(DateTime(1941, 8, 1))));
    await db.fuegeEreignisHinzu(LebensereignisseCompanion.insert(
      id: 'hochzeit',
      personId: 'vater',
      art: 'hochzeit',
      datum: Value(DateTime(1958, 6, 21)),
    ));
    await db.fuegeEreignisHinzu(LebensereignisseCompanion.insert(
      id: 'umzug',
      personId: 'vater',
      art: 'umzug',
      datum: Value(DateTime(1970, 9, 1)),
    ));
  }

  /// Öffnet die Zeitleiste.
  ///
  /// Mit breiterem Fenster: Die Ansichtsauswahl hat sechs Abschnitte und
  /// liegt in einer waagerecht schiebbaren Zeile – bei 800 Pixeln steht
  /// der letzte außerhalb des Bildes und lässt sich nicht antippen.
  Future<void> zeigeZeitleiste(WidgetTester tester, String start,
      {Size groesse = const Size(1040, 620)}) async {
    tester.view.physicalSize = groesse;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await zeige(tester, start);
    await tester.tap(find.text('Zeitleiste'));
    await tester.pumpAndSettle();
  }

  testWidgets('die Zeitleiste ordnet die Zeilen nach der Zeit',
      (tester) async {
    // Das, was keine der anderen vier Ansichten zeigt: Gleichzeitigkeit.
    // Geprüft wird die Reihenfolge von oben nach unten, nicht das Bild.
    await lebenslaeufe();
    await zeigeZeitleiste(tester, 'kind');

    double y(String name) => tester.getTopLeft(find.text(name)).dy;
    final reihenfolge = ['Uropa', 'Opa', 'Oma', 'Vater', 'Mutter', 'Kind'];
    for (var i = 1; i < reihenfolge.length; i++) {
      expect(y(reihenfolge[i - 1]), lessThan(y(reihenfolge[i])),
          reason: '${reihenfolge[i - 1]} vor ${reihenfolge[i]}');
    }
  });

  testWidgets('ein Tipp auf eine Zeile rueckt die Person in die Mitte',
      (tester) async {
    await lebenslaeufe();
    await zeigeZeitleiste(tester, 'kind');
    await tester.tap(find.text('Uropa'));
    await tester.pumpAndSettle();

    // Nachgewiesen im Baum, nicht auf der Leiste selbst: Dort ist die
    // Hervorhebung eine Farbe, und eine Farbe ist kein Beleg.
    await tester.tap(find.text('Baum'));
    await tester.pumpAndSettle();
    expect(find.text('Sohn'), findsWidgets,
        reason: 'Opa ist der Sohn des Uropas – und das steht auf seinem Schild');
    expect(find.text('Opa'), findsWidgets);
  });

  testWidgets('die Zeitleiste laesst sich vorlesen', (tester) async {
    // Ein gezeichneter Balken ist für die Sprachausgabe nichts. Ohne die
    // Beschriftung je Zeile wäre diese Ansicht dort leer.
    final semantik = tester.ensureSemantics();
    await lebenslaeufe();
    await zeigeZeitleiste(tester, 'kind');

    // Geprüft wird der Durchgang, den eine Sprachausgabe tatsächlich
    // nimmt – nicht ein einzelnes Widget. Die Beschriftung entsteht aus
    // mehreren Teilen und wird zu einem Knoten zusammengefasst; nur so
    // ist zu sehen, was am Ende wirklich vorgelesen wird.
    final gelesen = [
      for (final knoten in tester.semantics.simulatedAccessibilityTraversal())
        if (knoten.label.isNotEmpty) knoten.label,
    ];
    expect(gelesen, containsAll([
      'Uropa, 1874–1941',
      'Opa, 1901–1980',
      'Oma, Geboren 1903',
      'Vater, Geboren 1931, 2 Ereignisse',
    ]));
    // Auch die Reihenfolge stimmt: Wer sich die Leiste vorlesen lässt,
    // bekommt sie chronologisch und nicht in der Reihenfolge der
    // Datenbank.
    expect(gelesen.indexOf('Uropa, 1874–1941'),
        lessThan(gelesen.indexOf('Kind, Geboren 1962')));
    semantik.dispose();
  });

  testWidgets('ohne ein einziges Datum sagt die Zeitleiste, was ihr fehlt',
      (tester) async {
    // Nicht „keine Verwandten": Die Personen sind da, nur ihre Zeit ist
    // es nicht. Es gäbe keine Achse, auf der etwas läge.
    for (final id in ['opa', 'oma', 'vater', 'mutter', 'kind', 'schwester',
      'uropa']) {
      await (db.update(db.people)..where((t) => t.id.equals(id)))
          .write(const PeopleCompanion(geburtsdatum: Value(null)));
    }
    await zeigeZeitleiste(tester, 'kind');
    expect(find.textContaining('Auf der Zeitleiste steht noch nichts'),
        findsOneWidget);
  });

  testWidgets('so sieht die Zeitleiste aus', (tester) async {
    await lebenslaeufe();
    await zeigeZeitleiste(tester, 'kind');
    await expectLater(find.byType(StammbaumScreen),
        matchesGoldenFile('golden/stammbaum_zeitleiste.png'));
  }, skip: nurAufReferenzplattform);

  testWidgets('die Familienstatistik rechnet die Lebenden nicht als null',
      (tester) async {
    // Der Fall, vor dem der Plan ausdrücklich warnte, und der einzige
    // Weg, ihn zu sehen: Die Zahl selbst ist plausibel, gleich welche
    // von beiden dasteht.
    //
    // Sieben Personen in dieser Familie, zwei davon verstorben: Opa mit
    // 79, Uropa mit 67. Richtig sind 73 Jahre. Zählte man die fünf
    // Übrigen als „null Jahre" mit, kämen 20,9 heraus.
    tester.view.physicalSize = const Size(1040, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await lebenslaeufe();
    await zeige(tester, 'kind');
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Familienstatistik'));
    await tester.pumpAndSettle();

    expect(find.byType(FamilienstatistikScreen), findsOneWidget);
    expect(find.text('73 Jahre'), findsOneWidget);
    expect(find.textContaining('20,9'), findsNothing,
        reason: 'das waere der Durchschnitt mit den Lebenden als null');

    // Und die Zahl der Ausgeschlossenen steht daneben – ohne sie waere
    // das Ergebnis wieder nur eine halbe Auskunft.
    expect(find.textContaining('5 Personen ohne Sterbedatum'),
        findsOneWidget);
    expect(find.textContaining('Wer noch lebt'), findsOneWidget);

    // Das Heiratsalter kommt aus dem Ereignis, nicht aus einer Spalte.
    expect(find.text('27 Jahre'), findsOneWidget);

    // Die Namensliste steht weiter unten – nachgesehen wird sie durch
    // Blättern, sonst behauptet der Test etwas über einen Teil der Seite,
    // der gar nicht gebaut wurde.
    await tester.scrollUntilVisible(find.text('Opa'), 200);
    expect(find.text('Vornamen'), findsOneWidget);
    // Und keine Nachnamen: In dieser Familie hat niemand einen zweiten
    // Namensteil. Eine Liste mit sieben leeren Zeilen wäre schlechter als
    // keine.
    expect(find.text('Nachnamen'), findsNothing);
  });

  testWidgets('so sieht die Familienstatistik aus', (tester) async {
    tester.view.physicalSize = const Size(1040, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await lebenslaeufe();
    await zeige(tester, 'kind');
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Familienstatistik'));
    await tester.pumpAndSettle();
    await expectLater(find.byType(FamilienstatistikScreen),
        matchesGoldenFile('golden/familienstatistik.png'));
  }, skip: nurAufReferenzplattform);

  testWidgets('ohne Lebensdaten steht ein Satz statt leerer Kacheln',
      (tester) async {
    // Frueher standen hier zwei Kacheln „keine Angabe" nebeneinander. Das
    // sah aus wie ein Fehler des Programms, dabei fehlten schlicht die
    // Eintraege. Jetzt steht ein Satz da, der sagt, was fehlt – und die
    // Kinderverteilung bleibt, weil sie ohne jedes Datum auskommt.
    tester.view.physicalSize = const Size(1040, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    for (final id in ['opa', 'oma', 'vater', 'mutter', 'kind', 'schwester',
      'uropa']) {
      await (db.update(db.people)..where((t) => t.id.equals(id)))
          .write(const PeopleCompanion(geburtsdatum: Value(null)));
    }
    await zeige(tester, 'kind');
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Familienstatistik'));
    await tester.pumpAndSettle();

    expect(find.text('keine Angabe'), findsNothing);
    expect(find.text('Lebensalter'), findsNothing);
    expect(find.text('Heiratsalter'), findsNothing);
    expect(find.textContaining('Photo Vault schätzt sie nicht'),
        findsOneWidget);
    await tester.scrollUntilVisible(find.text('Kinder je Person'), 200);
    expect(find.text('Kinder je Person'), findsOneWidget,
        reason: 'die Verteilung braucht keine Daten und steht weiter da');
  });

  testWidgets('eine Person ohne Verwandtschaft bekommt eine Erklärung',
      (tester) async {
    await db.createPerson(PeopleCompanion.insert(id: 'allein', name: 'Allein'));
    await zeige(tester, 'allein');
    expect(find.textContaining('noch keine Verwandtschaft eingetragen'),
        findsOneWidget);
  });

  testWidgets('der Schwager steht bei seiner Frau, seine Eltern ueber ihm',
      (tester) async {
    // **Der Kernbeleg der ganzen Runde.** Vorher stand der Schwager in
    // einer eigenen Reihe „Schwager und Schwägerin", und welche der
    // Schwestern ihn geheiratet hatte, war nicht zu sehen. Seine Eltern
    // standen ueberhaupt nicht im Bild und hiessen „angeheiratet".
    //
    // Auch der Schalter „Seitenäste" ist weg: Es gibt nur noch einen
    // Baum, und der zeigt sie immer.
    tester.view.physicalSize = const Size(2000, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await db.createPerson(PeopleCompanion.insert(
        id: 'schwager', name: 'Michael', geschlecht: const Value('m')));
    await db.createPerson(PeopleCompanion.insert(
        id: 'schwagersVater', name: 'Kurt', geschlecht: const Value('m')));
    await db.fuegeBeziehungHinzu(
        'schwester', 'schwager', Verwandtschaft.partner);
    await db.fuegeBeziehungHinzu(
        'schwager', 'schwagersVater', Verwandtschaft.elternteil);

    await zeige(tester, 'kind');

    // Alle drei sind da – ohne dass jemand einen Schalter umlegen muss.
    expect(find.text('Michael'), findsOneWidget);
    expect(find.text('Schwager'), findsOneWidget);
    expect(find.text('Kurt'), findsOneWidget);
    expect(find.text('Vater von Schwager Michael'), findsOneWidget);

    // Und die Anordnung sagt dasselbe: Michael steht unmittelbar neben
    // seiner Frau, sein Vater darueber. Eine Reihe nach Rolle konnte das
    // nicht ausdruecken.
    final schwester = tester.getCenter(find.text('Schwester').first);
    final michael = tester.getCenter(find.text('Michael'));
    final kurt = tester.getCenter(find.text('Kurt'));
    final mitte = tester.getCenter(find.text('Kind'));

    expect((michael.dy - schwester.dy).abs(), lessThan(20),
        reason: 'dieselbe Generation, dieselbe Hoehe');
    expect((michael.dx - schwester.dx).abs(), lessThan(200),
        reason: 'Seite an Seite, nicht in getrennten Gruppen');
    expect(kurt.dy, lessThan(michael.dy), reason: 'die Eltern stehen darueber');
    expect((kurt.dx - michael.dx).abs(), lessThan((kurt.dx - mitte.dx).abs()),
        reason: 'Kurt steht ueber seinem Sohn, nicht ueber mir');
  });

  testWidgets('so sieht der Baum mit Seitenaesten aus', (tester) async {
    // Der Blick, um den es ging: Grosseltern oben, Neffen unter den
    // Geschwistern, der Schwager NEBEN seiner Frau und seine Eltern
    // ueber ihm. Es gibt keinen Schalter mehr - der Baum zeigt die
    // Seitenaeste immer.
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await db.createPerson(
        PeopleCompanion.insert(id: 'schwager', name: 'Schwager'));
    await db.fuegeBeziehungHinzu(
        'schwester', 'schwager', Verwandtschaft.partner);
    await zeige(tester, 'kind');
    await expectLater(find.byType(StammbaumScreen),
        matchesGoldenFile('golden/stammbaum_seitenaeste.png'));
  }, skip: nurAufReferenzplattform);

  testWidgets('so sieht der Baum im hellen Erscheinungsbild aus',
      (tester) async {
    // Bronze auf Pergament statt Gold auf Dunkel. Nicht die dunkle
    // Fassung mit vertauschten Werten: Dieselben Goldtöne auf hellem
    // Grund verlieren jeden Halt.
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await zeigeHell(tester, 'kind');
    await expectLater(
      find.byType(StammbaumScreen),
      matchesGoldenFile('golden/stammbaum_hell.png'),
    );
  }, skip: nurAufReferenzplattform);

  testWidgets('ein Schild mit beiden Mehrzeichen laeuft nicht ueber',
      (tester) async {
    // Der gemeldete Fehler, am Bildschirmfoto zu sehen: Auf einer Karte
    // lag "Sohn" halb ueber "Martin". Ursache waren fuenf Zeilen in einem
    // Schild, das fuer drei gebaut ist - Name, Verhaeltnis, Lebensdaten
    // plus zwei Mehrzeichen. Sie liegen jetzt als Marke am Rand.
    tester.view.physicalSize = const Size(1800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Vier Generationen nach unten, damit die unterste draussen bleibt
    // und die darueber ein Mehrzeichen traegt.
    for (final (id, name) in [
      ('enkel', 'Enkelin'),
      ('urenkel', 'Urenkel'),
      ('ururenkel', 'Ururenkel'),
      ('urururenkel', 'Urururenkel'),
    ]) {
      await db.createPerson(PeopleCompanion.insert(id: id, name: name));
    }
    await db.fuegeBeziehungHinzu('enkel', 'kind', Verwandtschaft.elternteil);
    await db.fuegeBeziehungHinzu('urenkel', 'enkel', Verwandtschaft.elternteil);
    await db.fuegeBeziehungHinzu(
        'ururenkel', 'urenkel', Verwandtschaft.elternteil);
    await db.fuegeBeziehungHinzu(
        'urururenkel', 'ururenkel', Verwandtschaft.elternteil);
    // Ein zweiter Elternteil, der zur Mitte in keiner Beziehung steht -
    // genau die Lage aus der Meldung, wo Martin einen Vater hatte, der
    // von Berta aus niemand ist. Damit traegt Ururenkel BEIDE Zeichen:
    // oben ein unbekannter Elternteil, unten ein Kind ausserhalb.
    await db.createPerson(
        PeopleCompanion.insert(id: 'fremd', name: 'Fremde'));
    await db.fuegeBeziehungHinzu(
        'ururenkel', 'fremd', Verwandtschaft.elternteil);

    await zeige(tester, 'kind');
    expect(tester.takeException(), isNull);

    // Der eigentliche Fund: Der Baum reicht jetzt drei Generationen
    // hinab, nicht mehr eine.
    expect(find.text('Enkelin'), findsOneWidget);
    expect(find.text('Urenkel'), findsOneWidget);
    expect(find.text('Ururenkel'), findsOneWidget);
    expect(find.text('Urururenkel'), findsNothing, reason: 'eine Stufe zu weit');
    expect(find.text('Fremde'), findsNothing, reason: 'mit der Mitte nicht verwandt');
    // Genau ein Schild traegt beide Zeichen - und das ist das, an dem
    // es kaputt war.
    expect(find.byIcon(Icons.more_horiz), findsNWidgets(2));

    // Und nichts wird gequetscht. Das ist die Eigenschaft, die wirklich
    // kaputt war: Ein `Flexible` laesst seine Zeilen nicht ueberlappen -
    // es DRUECKT sie zusammen, und der Text malt dann ueber seinen
    // eigenen Kasten hinaus. Auf dem Bildschirmfoto lag "Sohn" deshalb
    // halb ueber "Martin", obwohl die Kaesten sauber untereinander lagen.
    //
    // Messbar ist es an der Kastenhoehe: Sie muss mindestens die
    // Zeilenhoehe hergeben.
    for (final name in ['Enkelin', 'Urenkel', 'Ururenkel', 'Kind']) {
      final treffer = find.text(name);
      if (treffer.evaluate().isEmpty) continue;
      final kasten = tester.getSize(treffer.first);
      final stil = tester.widget<Text>(treffer.first).style!;
      final zeilenhoehe = stil.fontSize! * (stil.height ?? 1.2);
      expect(kasten.height, greaterThanOrEqualTo(zeilenhoehe - 0.5),
          reason: '"$name" ist auf ${kasten.height.toStringAsFixed(1)} '
              'gequetscht, braucht aber ${zeilenhoehe.toStringAsFixed(1)}');
    }
  });
  group('der Baum merkt sich, wo man war', () {
    /// Sechs Ansichten und je nach Familie hunderte Personen: Wer den
    /// Stammbaum schliesst und wieder aufschlaegt, fing bis hierher
    /// jedes Mal beim Baum an – und bei der Person mit den meisten
    /// Verwandten, nicht bei der, die man zuletzt ansah.
    Future<void> ohneVorgabe(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        key: UniqueKey(),
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        theme: buildDarkTheme(),
        home: StammbaumScreen(library: library),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('die gewaehlte Ansicht steht beim naechsten Mal wieder da',
        (tester) async {
      // Breit genug, dass die Ansichtsleiste ganz hineinpasst - sie
      // liegt sonst in einer waagerechten Rolle und ist nicht antippbar.
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await zeige(tester, 'kind');
      await tester.tap(find.text('Zeitleiste'));
      await tester.pumpAndSettle();
      expect(find.byType(FamilienZeitleiste), findsOneWidget);

      await ohneVorgabe(tester);
      expect(find.byType(FamilienZeitleiste), findsOneWidget,
          reason: 'die Zeitleiste war zuletzt offen');
    });

    testWidgets('und die Person, die zuletzt in der Mitte stand',
        (tester) async {
      await zeige(tester, 'kind');
      // Ueber ein Schild in eine andere Person ruecken.
      await tester.tap(find.text('Schwester').first);
      await tester.pumpAndSettle();
      expect(await db.stammbaumZuletzt(),
          (ansicht: 'baum', person: 'schwester'));

      await ohneVorgabe(tester);
      expect(find.text('Stammbaum: Schwester'), findsOneWidget);
    });

    testWidgets('eine geloeschte Person faellt still zurueck',
        (tester) async {
      await db.setzeStammbaumZuletzt(ansicht: 'baum', person: 'gibtsnicht');
      await ohneVorgabe(tester);
      // Kein leerer Bildschirm, sondern die Person mit den meisten
      // Verwandten – genau das bisherige Verhalten.
      expect(find.textContaining('Stammbaum: '), findsOneWidget);
      expect(find.text('Stammbaum: '), findsNothing);
    });
  });

}
