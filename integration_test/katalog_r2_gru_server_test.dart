// ignore_for_file: avoid_print
// Zweite Prüfrunde, Prüfer r2-gru: Prüfungen mit dem Wegwerf-Server.
//
//   PV_E2E_SERVER=1 PV_E2E_RECHNEN=alles (dazu PV_ONNXRUNTIME, PV_MODELLE)
//
// Jede Prüfung bekommt ein eigenes, leeres Konto (ein Umzug geht nur in
// eine leere Bibliothek). „Server gestoppt“ ist eine [Durchreiche] vor dem
// Server, die abbricht und abweist (GRU-057); ein zweites Gerät ist eine
// zweite verbundene Bibliothek desselben Kontos mit eigener Anmeldung, wie
// „Bibliothek des Servers holen“ sie anlegt (IMP-122, IMP-185). Der zu alte
// Server (IMP-185) ist ein Server der Fassung 3.54.0 aus einem eigenen
// Worktree auf 127.0.0.1:18871 (tools/wegwerf_server.sh, Name r2gru-alt).
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:kern/abgleich/abgleich.dart';
import 'package:kern/abgleich/tus.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:kern/abgleich/verbindungsdatei.dart';
import 'package:kern/db/database.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/screens/asset_viewer_screen.dart';
import 'package:photo_vault/screens/fotokammer_screen.dart';
import 'package:photo_vault/screens/trash_screen.dart';
import 'package:photo_vault/services/library_location.dart';
import 'package:photo_vault/services/meldungsdienst.dart';
import 'package:photo_vault/services/serversperre.dart';
import 'package:photo_vault/widgets/asset_info_sheet.dart';
import 'package:photo_vault/widgets/seitenleiste.dart';
import 'package:teilen_ui/l10n/teilen_texte.dart';

import 'katalog_kit.dart';
import 'katalog_r2_gru_test.dart' hide main;

final TeilenTexte teilenDe = lookupTeilenTexte(const Locale('de'));

/// Der Wegwerf-Server der Fassung 3.54.0 (vor dem endgültigen Löschen).
const alterServer = 'http://127.0.0.1:18871';

/// Deckkraft der Beschriftung eines Leisteneintrags (0 = eingeklappt).
double deckkraft(WidgetTester tester, String text) => tester
    .widget<AnimatedOpacity>(
      find
          .ancestor(
            of: find.descendant(of: zeile(text), matching: find.text(text)),
            matching: find.byType(AnimatedOpacity),
          )
          .first,
    )
    .opacity;

/// Der Bearbeiten-Knopf in der Datumszeile des Info-Blatts.
Finder bearbeitenBeiDatum(String datumTitel) => find
    .descendant(
      of: find
          .ancestor(
            of: find.descendant(
              of: find.byType(AssetInfoSheet),
              matching: find.text(datumTitel),
            ),
            matching: find.byType(Row),
          )
          .first,
      matching: find.byType(IconButton),
    )
    .first;

/// Im Datumswähler auf Eingabe wechseln, [datum] eintippen, Uhrzeit
/// bestätigen.
Future<void> datumWaehlen(WidgetTester tester, DateTime datum) async {
  await waitFor(tester, find.byType(DatePickerDialog));
  final loc = MaterialLocalizations.of(
    tester.element(find.byType(DatePickerDialog)),
  );
  await tippe(tester, find.byTooltip(loc.inputDateModeButtonLabel));
  await enter(
    tester,
    find.descendant(
      of: find.byType(DatePickerDialog),
      matching: find.byType(TextField),
    ),
    loc.formatCompactDate(datum),
  );
  await tippe(
    tester,
    find.descendant(
      of: find.byType(DatePickerDialog),
      matching: find.text(loc.okButtonLabel),
    ),
  );
  await waitFor(tester, find.byType(TimePickerDialog));
  await tippe(
    tester,
    find.descendant(
      of: find.byType(TimePickerDialog),
      matching: find.text(loc.okButtonLabel),
    ),
  );
  await settle(tester);
}

String tag(DateTime d) => DateFormat.yMMMd('de').format(d);

/// Ein Datum aus der Antwort des Servers (drift: Millisekunden oder Text).
DateTime? alsDatum(Object? wert) => switch (wert) {
  final int ms => DateTime.fromMillisecondsSinceEpoch(ms),
  final String s => DateTime.tryParse(s)?.toLocal(),
  _ => null,
};

/// Ohne runAsync: Es wird auch in [eventually] gerufen, das seine
/// Bedingung schon in runAsync prüft (runAsync lässt sich nicht
/// schachteln).
Future<List<String>> albumInhalt(WidgetTester tester, String album) async {
  final db = bibliothek.db;
  final a = (await db.alleAlben()).firstWhere((x) => x.name == album);
  return [for (final x in await db.assetsInAlbumOnce(a.id)) x.originalFileName]
    ..sort();
}

/// Legt auf [name] ein Gesicht an und ordnet es [personId] zu (vor dem
/// Verbinden: Das Gesicht zieht mit um).
Future<void> gesichtFuer(
  WidgetTester tester,
  String name,
  String personId,
) async {
  final a = await aufnahme(tester, name);
  final gesicht = uuid.v4();
  await mitDb(tester, () async {
    await bibliothek.db.insertFace(
      FacesCompanion.insert(
        id: gesicht,
        assetId: a.id,
        personId: const Value.absent(),
        boxX: 0.3,
        boxY: 0.3,
        boxW: 0.2,
        boxH: 0.2,
      ),
    );
    await bibliothek.db.fuehreAus(GesichterZuordnen([gesicht], personId));
  });
}

/// Der Server als erreichbar abwarten (nach einem Neustart).
Future<void> erreichbar(WidgetTester tester) => eventually(
  tester,
  () async => bibliothek.abgleichszustand?.erreichbar ?? false,
  timeout: const Duration(seconds: 90),
  was: 'Server erreichbar',
);

void main() {
  lebenszeichen();

  testWidgets('GRU-045 Zähler der Fotokammer am Symbol', (tester) async {
    filtereSemantik();
    await starte(tester);
    await importiere(tester, fotos(4, stamm: 'kam'));
    final alle = await aufnahmen(tester);
    final inKammer = [alle[0].id, alle[1].id];
    await verbinde(
      tester,
      Uri.parse(serverAdresse),
      vorNeustart: (v) async {
        // In der Fotokammer warten Fotos – hineingelegt, während die App
        // geschlossen war (wie von einem anderen Gerät).
        final j = await v.schicke('api/v1/kammer/aufnehmen', {'ids': inKammer});
        print('GRU-045: aufnehmen $j');
      },
    );
    final dienst = bibliothek.fotokammer!;
    await eventually(
      tester,
      () async => dienst.anzahl.value == 2,
      timeout: const Duration(seconds: 60),
      was: 'Zähler 2',
    );
    await openSection(tester, Hauptbereich.zeitleiste);
    await settle(tester);
    Badge marke() => tester.widget<Badge>(
      find
          .descendant(of: zeile(de.navFotokammer), matching: find.byType(Badge))
          .first,
    );
    String? zahlAmSymbol() =>
        marke().isLabelVisible ? (marke().label as Text?)?.data : null;
    // Eingeklappt.
    expect(
      tester.widget<Seitenleiste>(find.byType(Seitenleiste)).fixiert,
      isFalse,
    );
    expect(deckkraft(tester, de.navFotokammer), 0, reason: 'eingeklappt');
    expect(zahlAmSymbol(), '2', reason: 'eingeklappt');
    // Aufgeklappt (Maus über der Leiste).
    final maus = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await maus.addPointer(location: const Offset(900, 450));
    addTearDown(maus.removePointer);
    await tester.pump();
    await maus.moveTo(const Offset(30, 300));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));
    expect(deckkraft(tester, de.navFotokammer), 1, reason: 'aufgeklappt');
    expect(zahlAmSymbol(), '2', reason: 'aufgeklappt');
    await maus.moveTo(const Offset(900, 450));
    await tester.pump(const Duration(milliseconds: 800));
    // Fotokammer leeren: alle freigeben.
    await leiste(tester, de.navFotokammer);
    await waitFor(tester, find.byType(FotokammerScreen));
    await waitFor(
      tester,
      find.byTooltip(de.kammerAlle),
      timeout: const Duration(seconds: 30),
    );
    await tippe(tester, find.byTooltip(de.kammerAlle));
    await tippe(tester, find.widgetWithText(FilledButton, de.kammerFreigeben));
    await eventually(
      tester,
      () async => dienst.anzahl.value == 0,
      timeout: const Duration(seconds: 90),
      was: 'Kammer leer',
    );
    await settle(tester);
    expect(zahlAmSymbol(), isNull, reason: 'bei 0 keine Zahl');
    expect(marke().isLabelVisible, isFalse);
    await ende(tester);
  }, timeout: frist);

  testWidgets(
    'IMP-122 IMP-185 Zwei verbundene Geräte: Datum ändern, Papierkorb leeren',
    (tester) async {
      filtereSemantik();
      await starte(tester);
      await importiere(tester, [
        testfoto('s_b.jpg', datum: DateTime(2023, 8, 16, 14, 30)),
        testfoto('s_c.jpg', datum: DateTime(2023, 8, 17, 14, 30)),
        testfoto('s_d.jpg', datum: DateTime(2023, 8, 18, 14, 30)),
      ]);
      final b = await aufnahme(tester, 's_b.jpg');
      final c = await aufnahme(tester, 's_c.jpg');
      final server = Uri.parse(serverAdresse);
      final k = await verbinde(tester, server, geraet: 'Rechner A');
      final v = Serververbindung(server, k.token);
      addTearDown(v.schliesse);
      // Gerät A legt c in den Papierkorb.
      await befehl(tester, InDenPapierkorb([c.id]));
      await eventually(
        tester,
        () async => ((await v.hole('api/v1/papierkorb'))['aufnahmen']! as List)
            .isNotEmpty,
        timeout: const Duration(seconds: 60),
        was: 'c im Papierkorb des Servers',
      );
      // Gerät B: eigene Anmeldung, eigene Kopie (wie „Bibliothek des
      // Servers holen“: Abzug, Verbindungsdatei, Eintrag in der Liste).
      final standard = (await mitDb(
        tester,
        LibraryLocation.bekannte,
      )).firstWhere((e) => e.istStandard).eintrag;
      late Bibliothekseintrag eintragB;
      await tester.runAsync(() async {
        final tokenB = await anmelden(server, k.konto, 'Rechner B');
        final daten = await LibraryLocation.datenordner();
        final ordner = Directory(p.join(daten.path, 'verbunden', 'rechner-b'))
          ..createSync(recursive: true);
        final vb = Serververbindung(server, tokenB);
        try {
          await Abgleich.holeAbzug(
            vb,
            File(p.join(ordner.path, 'library.sqlite')),
          );
        } finally {
          vb.schliesse();
        }
        await Verbindungsdatei(
          server: server,
          konto: k.konto,
          geraet: 'Rechner B',
          token: tokenB,
        ).schreibe(ordner);
        eintragB = await LibraryLocation.fuegeEigenenOrdnerHinzu(
          ordner,
          name: 'Rechner B',
        );
      });
      Future<void> wechsle(Bibliothekseintrag e) async {
        await neustart(tester, dazwischen: () => LibraryLocation.wechsleZu(e));
        expect(bibliothek.verbunden, isTrue);
        await erreichbar(tester);
      }

      await wechsle(eintragB);
      print('IMP-122: Gerät B in ${bibliothek.paths.root.path}');
      expect(bibliothek.paths.root.path, contains('rechner-b'));
      await eventually(
        tester,
        () async => (await bibliothek.db.assetById(c.id))?.isTrashed ?? false,
        was: 'B: c im Papierkorb',
      );
      final bVorher = (await mitDb(
        tester,
        () => bibliothek.db.assetById(b.id),
      ))!;
      expect(
        (bVorher.fileCreatedAt.year, bVorher.fileCreatedAt.month),
        (2023, 8),
      );
      await openSection(tester, Hauptbereich.papierkorb);
      await waitFor(tester, find.byType(TrashScreen));
      await eventually(
        tester,
        () async => papierkorbKacheln(tester) == 1,
        was: 'c im Papierkorb',
      );

      // Gerät A: Datum im Info-Blatt ändern, Papierkorb leeren.
      await wechsle(standard);
      expect(bibliothek.paths.root.path, isNot(contains('rechner-b')));
      final bServerVorher = await mitDb(
        tester,
        () => v.hole('api/v1/aufnahmen/${b.id}'),
      );
      await oeffneFoto(tester, b.id);
      await tippe(tester, find.byTooltip(de.viewerInfo));
      await tippe(tester, bearbeitenBeiDatum(tag(DateTime(2023, 8, 16))));
      await datumWaehlen(tester, DateTime(2021, 2, 3));
      await waitFor(
        tester,
        find.descendant(
          of: find.byType(AssetInfoSheet),
          matching: find.text(tag(DateTime(2021, 2, 3))),
        ),
      );
      late Map<String, Object?> bServerNachher;
      await eventually(
        tester,
        () async {
          bServerNachher = await v.hole('api/v1/aufnahmen/${b.id}');
          final d = alsDatum(bServerNachher['fileCreatedAt']);
          return d != null && (d.year, d.month, d.day) == (2021, 2, 3);
        },
        timeout: const Duration(seconds: 60),
        was: 'neues Datum am Server',
      );
      print('IMP-122 Server: $bServerVorher → $bServerNachher');
      expect(bServerNachher['relativePath'], bServerVorher['relativePath']);
      await alleZurueck(tester);
      await openSection(tester, Hauptbereich.papierkorb);
      await waitFor(tester, find.byType(TrashScreen));
      await eventually(
        tester,
        () async => papierkorbKacheln(tester) == 1,
        was: 'c im Papierkorb',
      );
      await tippe(tester, find.byTooltip(de.papierkorbLeeren));
      await waitFor(tester, find.text(de.papierkorbLeerenText(1)));
      await tippe(
        tester,
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(de.allgLoeschen),
        ),
      );
      await eventually(
        tester,
        () async =>
            ((await v.hole('api/v1/papierkorb'))['aufnahmen']! as List).isEmpty,
        timeout: const Duration(seconds: 60),
        was: 'Server-Papierkorb leer',
      );
      await waitFor(tester, find.text(de.papierkorbLeer));

      // Gerät B nach dem Abgleich.
      await wechsle(eintragB);
      await eventually(
        tester,
        () async {
          final x = await bibliothek.db.assetById(b.id);
          return x != null && x.fileCreatedAt.year == 2021;
        },
        timeout: const Duration(seconds: 90),
        was: 'B: neues Datum',
      );
      await eventually(
        tester,
        () async {
          final x = await bibliothek.db.assetById(c.id);
          return x == null || !x.isTrashed;
        },
        timeout: const Duration(seconds: 90),
        was: 'B: Papierkorb leer',
      );
      expect(await mitDb(tester, () => bibliothek.db.assetById(c.id)), isNull);
      await openSection(tester, Hauptbereich.papierkorb);
      await waitFor(tester, find.text(de.papierkorbLeer));
      await oeffneFoto(tester, b.id);
      await tippe(tester, find.byTooltip(de.viewerInfo));
      await waitFor(
        tester,
        find.descendant(
          of: find.byType(AssetInfoSheet),
          matching: find.text(tag(DateTime(2021, 2, 3))),
        ),
      );
      final bB = (await mitDb(tester, () => bibliothek.db.assetById(b.id)))!;
      print('IMP-122: Gerät B ${bB.fileCreatedAt} ${bB.relativePath}');
      await alleZurueck(tester);
      await ende(tester);
    },
    timeout: const Timeout(Duration(minutes: 20)),
  );

  testWidgets('IMP-207 Sperren verbunden: Hinweis über den Fänger der App', (
    tester,
  ) async {
    filtereSemantik();
    // Wie main(): Der Fänger für „geht verbunden noch nicht“ hängt sich vor
    // FlutterError.onError, das der Prüfrahmen je Prüfung neu setzt.
    richteServersperreEin();
    await starte(tester);
    await importiere(tester, [testfoto('sperr.jpg')]);
    await verbinde(tester, Uri.parse(serverAdresse));
    final a = await aufnahme(tester, 'sperr.jpg');
    Object? pinFehler;
    await tester.runAsync(() async {
      try {
        await bibliothek.setupVaultPin('24682468');
      } catch (e) {
        pinFehler = e;
      }
    });
    print('IMP-207: PIN einrichten: ${pinFehler ?? 'ok'}');
    await oeffneFoto(tester, a.id);
    melde.verlaufLeeren();
    final abgefangen = <Object>[];
    var weitergereicht = false;
    final unbehandelt = await mitFehlerfang(
      () async {
        await tester.tap(find.byTooltip(de.viewerInGesperrtenOrdner));
        await tester.pump(const Duration(milliseconds: 300));
        await settle(tester, max: const Duration(seconds: 2));
        if (find.text(de.pinFestlegenTitel).evaluate().isNotEmpty) {
          await enter(tester, field(de.pinNeuFeld), '24682468');
          await enter(tester, field(de.pinWiederholen), '24682468');
          await tester.tap(find.text(de.allgFestlegen));
          await tester.pump(const Duration(milliseconds: 300));
        } else if (find.text(de.pinEingebenTitel).evaluate().isNotEmpty) {
          await enter(tester, find.byType(TextField).last, '24682468');
          await tester.tap(knopf('OK'));
          await tester.pump(const Duration(milliseconds: 300));
        }
        await settle(tester, max: const Duration(seconds: 3));
      },
      beiFehler: (e, s) {
        if (!istServersperre(e)) return false;
        abgefangen.add(e);
        // Was die Wurzelzone der App mit einem ungefangenen Fehler tut: Er
        // geht an PlatformDispatcher.onError (main.dart:68,
        // richteServersperreEin).
        weitergereicht =
            PlatformDispatcher.instance.onError?.call(e, s) ?? false;
        return true;
      },
    );
    print(
      'IMP-207: abgefangen $abgefangen, weitergereicht $weitergereicht, '
      'unbehandelt $unbehandelt, Meldungen ${melde.verlauf.map((m) => m.text)}',
    );
    expect(abgefangen, isNotEmpty, reason: 'Sperren ist verbunden geschützt');
    expect(weitergereicht, isTrue);
    expect(unbehandelt, isEmpty);
    // Der Hinweis steht vier Sekunden; der Verlauf des Meldungsdienstes
    // zeigt, dass er erschien.
    expect(
      melde.verlauf.map((m) => m.text),
      contains(de.nurOhneServer),
      reason: 'Hinweis gezeigt',
    );
    expect(de.nurOhneServer, startsWith('Geht in einer mit dem Server'));
    final nachher = (await mitDb(tester, () => bibliothek.db.assetById(a.id)))!;
    expect(nachher.isLocked, isFalse, reason: 'unverändert');
    expect(nachher.relativePath, a.relativePath);
    expect(find.byType(AssetViewerScreen), findsOneWidget, reason: 'sichtbar');
    await key(tester, LogicalKeyboardKey.escape);
    await waitGone(tester, find.byType(AssetViewerScreen));
    await openSection(tester, Hauptbereich.zeitleiste);
    await waitFor(tester, kachel(a.id));
    await ende(tester);
  }, timeout: frist);

  testWidgets('IMP-185 Papierkorb leeren mit zu altem Server (3.54.0)', (
    tester,
  ) async {
    filtereSemantik();
    final da = await tester.runAsync(() async {
      try {
        final c = HttpClient();
        final r = await (await c.getUrl(
          Uri.parse('$alterServer/api/v1/zustand'),
        )).close();
        c.close(force: true);
        return r.statusCode == 200;
      } catch (_) {
        return false;
      }
    });
    expect(da, isTrue, reason: 'alter Server auf $alterServer');
    // Eine Bibliothek, die vom alten Server stammt: zwei Fotos dort
    // hochgeladen (tus, api/v1/hochladen), dann sein Abzug geholt – wie
    // „Bibliothek des Servers holen“. Eine Bibliothek dieser Fassung auf
    // den alten Server zu ziehen geht nicht: Er öffnet sie nicht
    // („pv_neuere_bibliothek: schema 98 > 95“).
    await starte(tester);
    final server = Uri.parse(alterServer);
    late String token;
    final dateien = [testfoto('alt_a.jpg'), testfoto('alt_b.jpg')];
    await tester.runAsync(() async {
      token = (await neuesKonto(server, nurVerwalter: true)).token;
      final v = Serververbindung(server, token);
      try {
        for (final f in dateien) {
          final kopf = await TusHochladen(
            v,
          ).lade(f, 'api/v1/hochladen', {'filename': p.basename(f.path)});
          print('IMP-185 alt: ${p.basename(f.path)} → ${kopf['pv-ausgang']}');
        }
      } finally {
        v.schliesse();
      }
    });
    await neustart(
      tester,
      dazwischen: () async {
        for (final s in ['', '-wal', '-shm']) {
          final f = File(p.join(anker.path, 'library.sqlite$s'));
          if (f.existsSync()) f.deleteSync();
        }
        final v = Serververbindung(server, token);
        try {
          await Abgleich.holeAbzug(
            v,
            File(p.join(anker.path, 'library.sqlite')),
          );
        } finally {
          v.schliesse();
        }
        await Verbindungsdatei(
          server: server,
          konto: 'verwalter',
          geraet: 'Verwaltung',
          token: token,
        ).schreibe(anker);
      },
    );
    expect(bibliothek.verbunden, isTrue);
    await warte(tester, const Duration(seconds: 5));
    final alle = await aufnahmen(tester);
    print(
      'IMP-185 alt: ${alle.map((x) => x.originalFileName)}, '
      'Zustand ${bibliothek.abgleichszustand}',
    );
    final a = alle.firstWhere((x) => x.originalFileName == 'alt_a.jpg');
    await befehl(tester, InDenPapierkorb([a.id]));
    await openSection(tester, Hauptbereich.papierkorb);
    await waitFor(tester, find.byType(TrashScreen));
    await eventually(
      tester,
      () async => papierkorbKacheln(tester) == 1,
      was: 'alt_a im Papierkorb',
    );
    await tippe(tester, find.byTooltip(de.papierkorbLeeren));
    await waitFor(tester, find.text(de.papierkorbLeerenText(1)));
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(de.allgLoeschen),
      ),
    );
    await waitFor(
      tester,
      find.text(de.papierkorbServerZuAlt),
      timeout: const Duration(seconds: 30),
    );
    expect(
      (await mitDb(tester, () => bibliothek.db.assetById(a.id)))?.isTrashed,
      isTrue,
      reason: 'nichts gelöscht',
    );
    expect(find.byType(TrashScreen), findsOneWidget);
    await ende(tester);
  }, timeout: frist);
}
