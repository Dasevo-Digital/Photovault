import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/services/storage_paths.dart';
import 'package:photo_vault/screens/people_screen.dart';
import 'package:photo_vault/widgets/person_picker_dialog.dart';

/// Der Zuordnungs-Dialog.
///
/// Drei Dinge sind hier leicht zu übersehen: dass die bestehenden Personen
/// ihr Profilbild zeigen, dass „Ignorieren" nur dort erscheint, wo der
/// Aufrufer es angeboten hat (ein Ignorieren-Knopf an der falschen Stelle
/// würde ein bereits benanntes Gesicht still aus seiner Person entfernen),
/// und dass **dasselbe Feld sucht und anlegt**.
///
/// Das letzte ist der heikle Teil: Wer sich vertippt, legt sonst eine
/// zweite „Martin" an, statt die erste zu finden. Deshalb sagt die
/// Beschriftung des Knopfes, was er tut, und ein Name, den es schon gibt,
/// führt zur bestehenden Person statt zu einer neuen.
void main() {
  late Directory tempRoot;
  late StoragePaths paths;

  setUp(() async {
    tempRoot = Directory.systemTemp.createTempSync('pv_person_picker_');
    paths = await StoragePaths.forTesting(Directory(p.join(tempRoot.path, 'library')));
  });

  tearDown(() => tempRoot.deleteSync(recursive: true));

  PersonData person(String id, String name, {String? bild}) => PersonData(
        id: id,
        name: name,
        coverFaceCropPath: bild,
      );

  /// Legt eine echte Bilddatei an – FileImage schlägt sonst beim Laden fehl,
  /// und der Test prüfte nur, dass ein Widget existiert, nicht dass es ein
  /// benutzbares Bild bekommt.
  String bilddatei(String faceId) {
    final relativ = paths.faceRelativePath(faceId);
    final datei = paths.absolute(relativ);
    datei.parent.createSync(recursive: true);
    // Kleinstes gültiges PNG (1×1, transparent).
    datei.writeAsBytesSync([
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
      0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
      0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
      0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
      0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
      0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
      0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
      0x42, 0x60, 0x82,
    ]);
    return relativ;
  }

  Future<PersonChoice?> zeige(
    WidgetTester tester,
    List<PersonData> leute, {
    bool erlaubtIgnorieren = false,
    String? currentName,
  }) async {
    PersonChoice? ergebnis;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () async {
              ergebnis = await showPersonPickerDialog(
                context,
                leute,
                paths: paths,
                erlaubtIgnorieren: erlaubtIgnorieren,
                currentName: currentName,
              );
            },
            child: const Text('los'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('los'));
    await tester.pumpAndSettle();
    return ergebnis;
  }

  testWidgets('bestehende Personen erscheinen mit ihrem Profilbild', (tester) async {
    final leute = [
      person('p1', 'Anna', bild: bilddatei('f1')),
      person('p2', 'Bernd', bild: bilddatei('f2')),
    ];
    await zeige(tester, leute);

    // Die Liste steht sofort da – kein Aufklappen mehr nötig. Genau das
    // war der Mangel: In einer gewachsenen Bibliothek sind es 39 Bilder
    // hinter einem zugeklappten Feld.
    expect(find.text('Anna'), findsWidgets);
    expect(find.byType(CircleAvatar), findsWidgets);

    final avatare = tester.widgetList<CircleAvatar>(find.byType(CircleAvatar));
    final bilder = avatare
        .map((a) => a.backgroundImage)
        .whereType<ResizeImage>()
        .toList();
    expect(bilder, isNotEmpty,
        reason: 'ohne backgroundImage bliebe nur der graue Platzhalter');
    // Seit der 17. Prüfrunde geht das Bild durch [begrenztesBild]: Ein
    // roher FileImage dekodierte die Datei in voller Grösse, und das an
    // neun gleichlautenden Stellen.
    expect(bilder.first.imageProvider, isA<FileImage>());
    expect(bilder.first.policy, ResizeImagePolicy.fit);
  });

  testWidgets('eine Person ohne Profilbild bekommt ein Platzhaltersymbol', (tester) async {
    // Der Fall tritt auf, bevor das erste Gesicht zugeordnet ist. Ein
    // FileImage auf einen nicht vorhandenen Pfad brächte eine rote
    // Fehlerbox mitten in die Liste.
    await zeige(tester, [person('p1', 'Ohne Bild')]);

    expect(find.byIcon(Icons.person_outline), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ohne bestehende Personen bleibt nur das Namensfeld', (tester) async {
    await zeige(tester, []);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byType(ListTile), findsNothing);
    expect(find.textContaining('noch keine Person'), findsOneWidget,
        reason: 'ein leerer Kasten sähe aus, als lade er noch');
  });

  testWidgets('die Eingabe filtert die Liste', (tester) async {
    await zeige(tester, [
      person('p1', 'Anna'),
      person('p2', 'Bernd'),
      person('p3', 'Annemarie'),
    ]);
    await tester.enterText(find.byType(TextField), 'ann');
    await tester.pumpAndSettle();

    expect(find.text('Anna'), findsOneWidget);
    expect(find.text('Annemarie'), findsOneWidget);
    expect(find.text('Bernd'), findsNothing);
  });

  testWidgets('wer vorn anfängt, steht oben', (tester) async {
    // „Ma" meint eher Martin als Thomas – sonst muss man in einer nach
    // Alphabet sortierten Liste an den Treffern vorbeisuchen.
    await zeige(tester, [person('p1', 'Thomas'), person('p2', 'Martin')]);
    await tester.enterText(find.byType(TextField), 'ma');
    await tester.pumpAndSettle();

    final zeilen = tester.widgetList<ListTile>(find.byType(ListTile)).toList();
    expect((zeilen.first.title! as Text).data, 'Martin');
  });

  testWidgets('ein neuer Name legt an, und der Knopf sagt es', (tester) async {
    PersonChoice? ergebnis;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () async {
              ergebnis = await showPersonPickerDialog(
                  context, [person('p1', 'Anna')],
                  paths: paths);
            },
            child: const Text('los'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('los'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Zoe');
    await tester.pumpAndSettle();

    // Genau der Knopftext, nicht „irgendwo steht anlegen": Die
    // Beschriftung des Suchfeldes enthält das Wort auch.
    expect(find.text('\u201eZoe\u201c anlegen'), findsOneWidget,
        reason: 'der Knopf muss sagen, dass er eine NEUE Person anlegt');
    await tester.tap(find.text('\u201eZoe\u201c anlegen'));
    await tester.pumpAndSettle();

    expect(ergebnis!.newName, 'Zoe');
    expect(ergebnis!.existingPersonId, isNull);
  });

  testWidgets('ein vorhandener Name legt NICHT doppelt an', (tester) async {
    // Der teuerste Fehler dieses Dialogs: eine zweite „Anna" neben der
    // ersten. Gross-/Kleinschreibung zählt dabei nicht.
    PersonChoice? ergebnis;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () async {
              ergebnis = await showPersonPickerDialog(
                  context, [person('p1', 'Anna')],
                  paths: paths);
            },
            child: const Text('los'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('los'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'anna');
    await tester.pumpAndSettle();

    expect(find.text('\u201eanna\u201c anlegen'), findsNothing,
        reason: 'sonst entstünde eine zweite Anna neben der ersten');
    await tester.tap(find.text('Zuordnen'));
    await tester.pumpAndSettle();

    expect(ergebnis!.existingPersonId, 'p1');
    expect(ergebnis!.newName, isNull);
  });

  testWidgets('der Vorschlag steht oben und ist vorausgewählt', (tester) async {
    PersonChoice? ergebnis;
    final anna = person('p1', 'Anna');
    final zoe = person('p9', 'Zoe');
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () async {
              ergebnis = await showPersonPickerDialog(context, [anna, zoe],
                  paths: paths, suggestedPerson: zoe);
            },
            child: const Text('los'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('los'));
    await tester.pumpAndSettle();

    final zeilen = tester.widgetList<ListTile>(find.byType(ListTile)).toList();
    expect((zeilen.first.title! as Text).data, 'Zoe',
        reason: 'der Vorschlag steht vor dem Alphabet');
    expect(zeilen.first.selected, isTrue);

    // Vorausgewählt, aber NICHT bestätigt: Ein Vorschlag, der sich selbst
    // bestätigt, ordnet falsch zu, sobald jemand nur schnell wegklickt.
    expect(ergebnis, isNull);
    await tester.tap(find.text('Zuordnen'));
    await tester.pumpAndSettle();
    expect(ergebnis!.existingPersonId, 'p9');
  });

  testWidgets('„Ignorieren" erscheint nur, wenn es angeboten wird', (tester) async {
    await zeige(tester, [person('p1', 'Anna')]);
    expect(find.text('Ignorieren'), findsNothing);
  });

  testWidgets('„Ignorieren" liefert die entsprechende Entscheidung', (tester) async {
    PersonChoice? ergebnis;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppTexte.localizationsDelegates,
      supportedLocales: AppTexte.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () async {
              ergebnis = await showPersonPickerDialog(
                context,
                [person('p1', 'Anna')],
                paths: paths,
                erlaubtIgnorieren: true,
              );
            },
            child: const Text('los'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('los'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ignorieren'));
    await tester.pumpAndSettle();

    expect(ergebnis, isNotNull);
    expect(ergebnis!.ignorieren, isTrue);
    expect(ergebnis!.newName, isNull);
    expect(ergebnis!.existingPersonId, isNull);
  });

  group('Die Reihe für die Pfeiltasten', () {
    FaceData g(String id, String assetId) => FaceData(
          id: id,
          assetId: assetId,
          boxX: 0,
          boxY: 0,
          boxW: 0.1,
          boxH: 0.1,
          isIgnored: false,
        );

    test('behält die Reihenfolge des Rasters bei', () {
      // Sonst spränge die Pfeiltaste scheinbar wahllos durch die Bibliothek,
      // obwohl im Raster eine klare Ordnung zu sehen ist.
      expect(
        assetReiheFuerGesichter([g('f1', 'c'), g('f2', 'a'), g('f3', 'b')]),
        ['c', 'a', 'b'],
      );
    });

    test('ein Gruppenfoto steht nur einmal in der Reihe', () {
      // Drei unbenannte Gesichter auf einem Foto sind drei Rasterkacheln,
      // aber ein einziges Foto zum Durchblättern.
      expect(
        assetReiheFuerGesichter([g('f1', 'a'), g('f2', 'a'), g('f3', 'b'), g('f4', 'a')]),
        ['a', 'b'],
      );
    });

    test('ein leeres Raster ergibt eine leere Reihe', () {
      expect(assetReiheFuerGesichter([]), isEmpty);
    });
  });
}
