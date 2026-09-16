
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';

/// **Ein Schwall von Änderungen darf die Ansicht nicht tausendmal neu
/// rechnen lassen.**
///
/// Drift lässt eine `watch`-Abfrage bei jeder Änderung an einer beteiligten
/// Tabelle neu laufen. Das ist richtig, solange Änderungen einzeln kommen –
/// die Hintergrundaufgaben schreiben aber Zeile für Zeile, tausendfach
/// hintereinander. An der gewachsenen Bibliothek (7341 Aufnahmen)
/// gemessen, 200 einzelne Schreibvorgänge:
///
/// ```
///                                        vorher    nachher
/// ohne offene Zeitleiste                   0,5 s      0,3 s
/// Zeitleiste offen, Ladefenster 600        3,7 s      0,3 s
/// Zeitleiste offen, ganze Bibliothek      41,9 s      0,5 s
/// ```
///
/// Aus 101 Neudurchläufen wurde einer. Über 8000 Aufnahmen wären das sonst
/// aus einer halben Minute Schreibarbeit fast eine halbe Stunde – im
/// selben Faden, in dem gezeichnet wird.
///
/// Das Heikle daran ist nicht das Sparen, sondern die **erste** Antwort:
/// Ein einzelner Handgriff muss unverändert augenblicklich wirken.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> aufnahme(String id, {int minute = 0}) =>
      db.into(db.assets).insert(AssetsCompanion.insert(
            id: id,
            originalFileName: '$id.jpg',
            relativePath: 'originals/$id.jpg',
            checksum: 'pruef-$id',
            type: 'IMAGE',
            fileCreatedAt: DateTime(2026, 5, 1).add(Duration(minutes: minute)),
            importedAt: DateTime(2026),
          ));

  test('die erste Antwort kommt ohne Warten', () async {
    await aufnahme('a');
    final uhr = Stopwatch()..start();
    final erste = await db.watchTimeline().first;
    uhr.stop();
    expect(erste, hasLength(1));
    expect(uhr.elapsed, lessThan(AppDatabase.drosselfenster),
        reason: 'ein Anwender, der die Zeitleiste öffnet, wartet auf nichts');
  });

  test('ein einzelner Handgriff wirkt sofort', () async {
    // Der Fall, den eine Drosselung kaputtmachen würde: ein Herz gesetzt,
    // ein Foto in den Papierkorb. Zwischen zwei Handgriffen liegt immer
    // mehr Zeit als das Fenster, also darf keiner davon warten.
    await aufnahme('a');
    final gesehen = <int>[];
    final abo = db.watchTimeline().listen((l) => gesehen.add(l.length));
    await pumpeBis(() => gesehen.isNotEmpty);
    expect(gesehen, [1]);

    // **Die Ruhepause muss wirklich stattfinden.** Der Satz oben stand
    // bis hierher nur im Kommentar: Der zweite Schreibvorgang folgte
    // unmittelbar auf den ersten und lag damit selbst im Drosselfenster.
    // Ob er wartete, entschied dann die Tagesform der Maschine – und
    // unter Last fiel der Test (gemessen 400,7 ms gegen eine Grenze von
    // 400).
    await Future<void>.delayed(AppDatabase.drosselfenster);

    final uhr = Stopwatch()..start();
    await aufnahme('b', minute: 1);
    await pumpeBis(() => gesehen.length >= 2);
    uhr.stop();
    expect(gesehen.last, 2);
    expect(uhr.elapsed, lessThan(AppDatabase.drosselfenster),
        reason: 'nach einer Ruhepause wird nicht gedrosselt');
    await abo.cancel();
  });

  test('ein Schwall wird zusammengefasst, das Ergebnis stimmt trotzdem',
      () async {
    // Der Hintergrundlauf: fünfzig Schreibvorgänge dicht hintereinander.
    await aufnahme('a');
    final gesehen = <int>[];
    final abo = db.watchTimeline().listen((l) => gesehen.add(l.length));
    await pumpeBis(() => gesehen.isNotEmpty);
    gesehen.clear();

    for (var i = 0; i < 50; i++) {
      await aufnahme('f$i', minute: i + 1);
    }
    // Warten, bis der Nachzügler durch ist.
    await pumpeBis(() => gesehen.isNotEmpty && gesehen.last == 51,
        laenge: AppDatabase.drosselfenster * 4);

    expect(gesehen.last, 51,
        reason: 'der letzte Stand muss ankommen, sonst zeigte die Ansicht '
            'für immer die Lage von vorhin');
    expect(gesehen.length, lessThan(10),
        reason: 'ohne Drosselung wären es fünfzig');
    await abo.cancel();
  });

  test('auch der Papierkorb wird gedrosselt', () async {
    // Zweiter Strom auf derselben Tabelle – der Papierkorb steht offen,
    // während im Hintergrund geschrieben wird.
    for (var i = 0; i < 20; i++) {
      await aufnahme('f$i', minute: i);
    }
    final gesehen = <int>[];
    final abo = db.watchTrash().listen((l) => gesehen.add(l.length));
    await pumpeBis(() => gesehen.isNotEmpty);
    gesehen.clear();

    for (var i = 0; i < 20; i++) {
      await db.moveToTrash(['f$i']);
    }
    await pumpeBis(() => gesehen.isNotEmpty && gesehen.last == 20,
        laenge: AppDatabase.drosselfenster * 4);
    expect(gesehen.last, 20);
    expect(gesehen.length, lessThan(10));
    await abo.cancel();
  });

  test('nach dem Abmelden bleibt nichts stehen', () async {
    // Die Drosselung arbeitet mit einem Zeitgeber. Bliebe er nach dem
    // Abmelden liegen, hinge an jedem geschlossenen Bildschirm ein Rest –
    // dieselbe Falle wie bei den Fristen der Meldungszentrale.
    await aufnahme('a');
    final abo = db.watchTimeline().listen((_) {});
    await pumpeBis(() => true);
    await aufnahme('b', minute: 1);
    await aufnahme('c', minute: 2);
    await abo.cancel();
    // Wäre der Zeitgeber noch da, liefe er hier in eine geschlossene
    // Leitung und die Ausnahme schlüge hier auf.
    await Future<void>.delayed(AppDatabase.drosselfenster * 2);
  });
}

/// Wartet in kleinen Schritten, bis [fertig] zutrifft (oder die Zeit um ist).
Future<void> pumpeBis(bool Function() fertig,
    {Duration laenge = const Duration(seconds: 2)}) async {
  final uhr = Stopwatch()..start();
  while (uhr.elapsed < laenge) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    if (fertig()) return;
  }
}
