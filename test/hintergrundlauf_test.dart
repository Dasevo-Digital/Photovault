import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/storage_paths.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/state/hintergrundlauf.dart';
import 'package:photo_vault/state/library_state.dart';

/// Was die Laufverwaltung können muss: weiterlaufen, sich abbrechen lassen,
/// dieselbe Arbeit nicht zweimal gleichzeitig anstossen – und seit Fassung
/// 2.2.4 das, was vorher fehlte: **einreihen statt abweisen**.
void main() {
  late LibraryState library;

  setUp(() => library = LibraryState());

  /// Ein Nachholvorgang, der sich von aussen steuern lässt – so wie die
  /// echten ein `async*`-Generator sind, der zwischen den Fotos wartet.
  ({
    Stream<ImportProgress> Function() strom,
    void Function(int) schritt,
    Future<void> Function() schliessen,
    bool Function() abgeraeumt,
    bool Function() angefasst,
  }) steuerbarerLauf(int gesamt) {
    final regler = StreamController<ImportProgress>();
    var abgeraeumt = false;
    var angefasst = false;
    regler.onCancel = () => abgeraeumt = true;
    return (
      strom: () {
        angefasst = true;
        return regler.stream;
      },
      schritt: (n) =>
          regler.add(ImportProgress(n, gesamt, currentFile: 'foto_$n.jpg')),
      schliessen: () => regler.close(),
      abgeraeumt: () => abgeraeumt,
      angefasst: () => angefasst,
    );
  }

  /// Der Abschluss eines Laufs – seit dem Einreihen gibt die Startfunktion
  /// selbst kein `Future` mehr zurück, und das ist der Punkt: Einreihen und
  /// Fertigwerden sind zwei verschiedene Zeitpunkte.
  Future<void> abschluss(String schluessel) =>
      library.lauf(schluessel)!.abschluss;

  test('ein Lauf meldet seinen Fortschritt und bleibt nach dem Ende stehen',
      () async {
    final quelle = steuerbarerLauf(3);
    library.reiheAufgabeEin(
        schluessel: 'ocr',
        titel: 'Erkenne Text …',
        leermeldung: 'nichts zu tun',
        strom: quelle.strom);
    await pumpEventQueue();

    expect(library.lauf('ocr')!.titel, 'Erkenne Text …');
    expect(library.lauf('ocr')!.laeuft, isTrue);
    expect(library.lauf('ocr')!.wartet, isFalse);
    expect(library.etwasLaeuft, isTrue);

    quelle.schritt(2);
    await pumpEventQueue();
    expect(library.lauf('ocr')!.erledigt, 2);
    expect(library.lauf('ocr')!.gesamt, 3);
    expect(library.lauf('ocr')!.datei, 'foto_2.jpg');
    expect(library.lauf('ocr')!.anteil, closeTo(2 / 3, 1e-9));

    final fertig = abschluss('ocr');
    await quelle.schliessen();
    await fertig;
    await pumpEventQueue();

    // Der Eintrag verschwindet NICHT von selbst: Sonst wäre nach einem Lauf
    // über Stunden nirgends zu sehen, dass er überhaupt fertig wurde.
    expect(library.lauf('ocr')!.beendet, isTrue);
    expect(library.lauf('ocr')!.abgebrochen, isFalse);
    expect(library.etwasLaeuft, isFalse);

    library.verwerfeLauf('ocr');
    expect(library.lauf('ocr'), isNull);
  });

  test('Abbrechen kündigt das Abonnement – der Generator räumt auf', () async {
    final quelle = steuerbarerLauf(100);
    library.reiheAufgabeEin(
        schluessel: 'beschreibungen',
        titel: 'Erzeuge …',
        leermeldung: 'nichts zu tun',
        strom: quelle.strom);
    await pumpEventQueue();
    quelle.schritt(7);
    await pumpEventQueue();

    final fertig = abschluss('beschreibungen');
    library.brichAufgabeAb('beschreibungen');
    await fertig;
    await pumpEventQueue();

    // Das Kündigen ist der Punkt: Nur dadurch laufen die finally-Blöcke der
    // Nachholvorgänge, die dort ihre geliehenen KI-Modelle zurückgeben.
    expect(quelle.abgeraeumt(), isTrue);
    expect(library.lauf('beschreibungen')!.abgebrochen, isTrue);
    expect(library.lauf('beschreibungen')!.erledigt, 7);
    expect(library.etwasLaeuft, isFalse);

    await quelle.schliessen();
  });

  test('dieselbe Aufgabe startet nicht zweimal gleichzeitig', () async {
    final erste = steuerbarerLauf(10);
    final zweite = steuerbarerLauf(10);
    library.reiheAufgabeEin(
        schluessel: 'kitags',
        titel: 'erster Lauf',
        leermeldung: 'nichts zu tun',
        strom: erste.strom);
    await pumpEventQueue();

    expect(
      library.reiheAufgabeEin(
          schluessel: 'kitags',
          titel: 'zweiter Lauf',
          leermeldung: 'nichts zu tun',
          strom: zweite.strom),
      Startabweisung.laeuftBereits,
    );
    expect(zweite.angefasst(), isFalse,
        reason: 'der Strom darf gar nicht erst entstehen');
    expect(library.lauf('kitags')!.titel, 'erster Lauf');

    final fertig = abschluss('kitags');
    await erste.schliessen();
    await fertig;
    await pumpEventQueue();

    // Nach dem Ende ist der Platz wieder frei.
    library.reiheAufgabeEin(
        schluessel: 'kitags',
        titel: 'dritter Lauf',
        leermeldung: 'nichts zu tun',
        strom: () => const Stream<ImportProgress>.empty());
    expect(library.lauf('kitags')!.titel, 'dritter Lauf');
  });

  test('ein Fehler im Strom beendet den Lauf, statt ihn hängen zu lassen',
      () async {
    library.reiheAufgabeEin(
      schluessel: 'xmp',
      titel: 'Schreibe …',
      leermeldung: 'nichts zu tun',
      strom: () => Stream<ImportProgress>.error(StateError('Modell fehlt')),
    );
    await abschluss('xmp');
    await pumpEventQueue();

    expect(library.lauf('xmp')!.beendet, isTrue);
    expect(library.lauf('xmp')!.fehler, isA<StateError>());
    expect(library.etwasLaeuft, isFalse);
  });

  test('ein beendeter Lauf lässt sich wegräumen, ein laufender nicht',
      () async {
    final quelle = steuerbarerLauf(5);
    library.reiheAufgabeEin(
        schluessel: 'orte',
        titel: 'Lese Orte …',
        leermeldung: 'nichts zu tun',
        strom: quelle.strom);
    await pumpEventQueue();

    library.verwerfeLauf('orte');
    expect(library.lauf('orte'), isNotNull,
        reason: 'ein laufender Vorgang bleibt sichtbar');

    final fertig = abschluss('orte');
    await quelle.schliessen();
    await fertig;
    await pumpEventQueue();
    library.verwerfeLauf('orte');
    expect(library.lauf('orte'), isNull);
  });

  group('teure Auswertungen warten aufeinander', () {
    // Der Anlass gilt weiter: Vier Klicks genügten, um Gesichter,
    // Bildbeschreibung, Einbettung und Übersetzung gleichzeitig
    // anzustossen – vier KI-Modelle im Speicher und dieselben Fotos
    // vierfach dekodiert. Die frühere Antwort darauf war, die zweite
    // abzuweisen; jetzt wird sie eingereiht.

    test('eine zweite teure Aufgabe wartet, eine billige läuft sofort',
        () async {
      final erste = steuerbarerLauf(100);
      final zweite = steuerbarerLauf(100);
      library.reiheAufgabeEin(
        schluessel: 'beschreibungen',
        titel: 'Erzeuge …',
        leermeldung: 'nichts zu tun',
        strom: erste.strom,
        rechenintensiv: true,
      );
      await pumpEventQueue();

      expect(
        library.reiheAufgabeEin(
          schluessel: 'embeddings',
          titel: 'Berechne …',
          leermeldung: 'nichts zu tun',
          strom: zweite.strom,
          rechenintensiv: true,
        ),
        isNull,
        reason: 'nicht mehr abgewiesen – eingereiht',
      );
      await pumpEventQueue();
      expect(library.lauf('embeddings')!.wartet, isTrue);
      expect(library.lauf('embeddings')!.laeuft, isFalse);
      expect(zweite.angefasst(), isFalse,
          reason: 'ein wartender Lauf fasst seinen Strom nicht an und '
              'hält damit auch kein Modell im Speicher');
      expect(library.wartendeAufgaben, hasLength(1));

      // Orte einlesen, XMP schreiben und Ähnliches kosten nichts, was sich
      // in die Quere käme – die dürfen nebenher laufen.
      library.reiheAufgabeEin(
        schluessel: 'orte',
        titel: 'Lese Orte …',
        leermeldung: 'nichts zu tun',
        strom: () => const Stream<ImportProgress>.empty(),
      );
      await pumpEventQueue();
      expect(library.lauf('orte')!.wartet, isFalse);

      // Sobald die erste durch ist, rückt die wartende nach – von selbst.
      final fertig = abschluss('beschreibungen');
      await erste.schliessen();
      await fertig;
      await pumpEventQueue();

      expect(library.lauf('embeddings')!.laeuft, isTrue);
      expect(zweite.angefasst(), isTrue);
      await zweite.schliessen();
    });

    test('mit erhöhter Obergrenze laufen zwei nebeneinander', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      library.db = db;

      final erste = steuerbarerLauf(100);
      final zweite = steuerbarerLauf(100);
      library.reiheAufgabeEin(
          schluessel: 'beschreibungen',
          titel: 'a',
          leermeldung: '-',
          strom: erste.strom,
          rechenintensiv: true);
      library.reiheAufgabeEin(
          schluessel: 'embeddings',
          titel: 'b',
          leermeldung: '-',
          strom: zweite.strom,
          rechenintensiv: true);
      await pumpEventQueue();
      expect(library.lauf('embeddings')!.wartet, isTrue);

      // Das Heraufsetzen lässt sofort nachrücken – niemand soll erst noch
      // einmal auf „Starten" drücken müssen.
      await library.setzeMaxGleichzeitig(2);
      await pumpEventQueue();

      expect(library.maxGleichzeitig, 2);
      expect(library.lauf('embeddings')!.laeuft, isTrue);
      expect(library.laufendeSchwerarbeit, hasLength(2));
      expect(await db.maxGleichzeitigeAufgaben(), 2,
          reason: 'die Wahl überlebt den Programmstart');

      await erste.schliessen();
      await zweite.schliessen();
      await pumpEventQueue();
    });

    test('eine Null als Obergrenze wird zu eins – sonst liefe nie etwas',
        () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      library.db = db;
      await library.setzeMaxGleichzeitig(0);
      expect(library.maxGleichzeitig, 1);
    });

    test('ein wartender Lauf lässt sich streichen, ohne den laufenden zu '
        'stören', () async {
      final erste = steuerbarerLauf(100);
      final zweite = steuerbarerLauf(100);
      library.reiheAufgabeEin(
          schluessel: 'beschreibungen',
          titel: 'a',
          leermeldung: '-',
          strom: erste.strom,
          rechenintensiv: true);
      library.reiheAufgabeEin(
          schluessel: 'embeddings',
          titel: 'b',
          leermeldung: '-',
          strom: zweite.strom,
          rechenintensiv: true);
      await pumpEventQueue();

      library.brichAufgabeAb('embeddings');
      await pumpEventQueue();

      // Ganz weg, nicht als beendeter Eintrag: Es gab nichts zu sehen, also
      // gibt es auch kein Ergebnis zu zeigen.
      expect(library.lauf('embeddings'), isNull);
      expect(zweite.angefasst(), isFalse);
      expect(library.lauf('beschreibungen')!.laeuft, isTrue);

      await erste.schliessen();
      await pumpEventQueue();
    });

    test('eine angefragte Analyse wird nachgeholt statt verworfen', () async {
      final quelle = steuerbarerLauf(50);
      library.reiheAufgabeEin(
        schluessel: 'kitags',
        titel: 'Berechne KI-Tags …',
        leermeldung: 'nichts zu tun',
        strom: quelle.strom,
        rechenintensiv: true,
      );
      await pumpEventQueue();

      // So kommt die Anfrage im Betrieb: automatisch nach einem Import.
      await library.starteHintergrundanalyse();
      expect(library.analyseLaeuft, isFalse);
      expect(library.analyseZurueckgestellt, isTrue,
          reason: 'verworfen wäre schlimmer – frisch importierte Fotos '
              'blieben bis zum nächsten Programmstart ohne Auswertung');

      final fertig = abschluss('kitags');
      await quelle.schliessen();
      await fertig;
      await pumpEventQueue();

      // Ohne Modelle im Test läuft die Analyse sofort durch; entscheidend
      // ist, dass sie überhaupt angestossen wurde und die Merkung fällt.
      expect(library.analyseZurueckgestellt, isFalse);
    });

    test('während die Analyse läuft, wartet eine teure Aufgabe – und läuft '
        'danach von selbst los', () async {
      // Die Analyse braucht Arbeit, sonst ist sie durch, bevor man
      // hinsehen kann: eine echte (leere) Datenbank mit Fotos, denen die
      // Texterkennung noch fehlt.
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final tempRoot = Directory.systemTemp.createTempSync('pv_lauf_analyse_');
      addTearDown(() => tempRoot.deleteSync(recursive: true));
      library
        ..db = db
        ..paths =
            await StoragePaths.forTesting(Directory(p.join(tempRoot.path, 'lib')));

      for (var i = 0; i < 40; i++) {
        await db.into(db.assets).insert(AssetsCompanion.insert(
              id: 'a$i',
              originalFileName: 'a$i.jpg',
              relativePath: 'originals/a$i.jpg',
              checksum: 'a$i',
              fileCreatedAt: DateTime(2024, 5, 1),
              importedAt: DateTime(2024, 5, 2),
              type: 'IMAGE',
            ));
      }

      final analyse = library.starteHintergrundanalyse();

      // Warten, bis sie wirklich läuft – ohne Wanduhr, nur über die
      // Ereignisschlange.
      var gesehen = false;
      for (var i = 0; i < 200 && !gesehen; i++) {
        await pumpEventQueue();
        if (library.analyseLaeuft) gesehen = true;
      }
      expect(gesehen, isTrue, reason: 'die Analyse kam gar nicht erst in Gang');

      final teuer = steuerbarerLauf(10);
      library.reiheAufgabeEin(
          schluessel: 'beschreibungen',
          titel: 'Erzeuge …',
          leermeldung: '-',
          strom: teuer.strom,
          rechenintensiv: true);
      await pumpEventQueue();
      expect(library.lauf('beschreibungen')!.wartet, isTrue);
      expect(teuer.angefasst(), isFalse);

      // Billige Aufgaben laufen auch daneben sofort.
      library.reiheAufgabeEin(
          schluessel: 'xmp',
          titel: 'Schreibe …',
          leermeldung: '-',
          strom: () => const Stream<ImportProgress>.empty());
      await pumpEventQueue();
      expect(library.lauf('xmp')!.wartet, isFalse);

      library.brichHintergrundanalyseAb();
      await analyse;
      await pumpEventQueue();

      expect(library.lauf('beschreibungen')!.laeuft, isTrue,
          reason: 'nach dem Ende der Analyse rückt die wartende nach');
      await teuer.schliessen();
      await pumpEventQueue();
    });
  });
}
