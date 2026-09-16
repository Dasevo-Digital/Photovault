import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/model_catalog.dart';
import 'package:photo_vault/services/model_download_service.dart';

/// **Die Prüfsumme darf nicht nur einmal wirken.**
///
/// Der Katalog begründet seine SHA-256-Summen ausdrücklich damit, dass hier
/// „ONNX-Modelldateien direkt in die App-Inferenz geladen werden". Bis zur
/// 21. Prüfrunde wurde genau einmal verglichen: beim Herunterladen. Danach
/// lautete die ganze Frage `existsSync()`.
///
/// Der teure Fall, den allein das Nachrechnen findet, ist die Datei mit
/// **richtiger Länge und falschem Inhalt** – eine Längenprüfung geht daran
/// vorbei, und ein Modell, das etwas anderes rechnet als angenommen, sagt
/// das von selbst nicht.
void main() {
  late Directory ordner;
  late ModelDownloadService dienst;

  setUp(() {
    ordner = Directory.systemTemp.createTempSync('pv_pruefsumme_');
    dienst = ModelDownloadService(ordner.path);
  });
  tearDown(() => ordner.deleteSync(recursive: true));

  /// Ein Eintrag mit einer Datei, deren Prüfsumme und Länge zum Inhalt
  /// passen – so, wie der echte Katalog beides führt.
  ({ModelCatalogEntry eintrag, Uint8List inhalt}) baue(String name, int laenge) {
    final inhalt =
        Uint8List.fromList(List.generate(laenge, (i) => (i * 37 + 11) % 251));
    return (
      eintrag: ModelCatalogEntry(
        id: 'probe',
        sourceUrl: 'http://127.0.0.1',
        files: [
          ModelFile(name, 'http://127.0.0.1/$name',
              sha256.convert(inhalt).toString(), laenge),
        ],
      ),
      inhalt: inhalt,
    );
  }

  test('eine unveränderte Datei stimmt', () async {
    final (:eintrag, :inhalt) = baue('m.onnx', 5000);
    File('${ordner.path}/m.onnx').writeAsBytesSync(inhalt);

    final befunde = await dienst.pruefe(eintrag);
    expect(befunde.single.zustand, Modellzustand.stimmt);
    expect(befunde.single.inOrdnung, isTrue);
  });

  test('richtige Länge, falscher Inhalt fällt auf', () async {
    final (:eintrag, :inhalt) = baue('m.onnx', 5000);
    // Ein einziges Byte kippen – die Länge bleibt, und damit ginge jede
    // billigere Prüfung daran vorbei.
    final verfaelscht = Uint8List.fromList(inhalt);
    verfaelscht[2500] = verfaelscht[2500] ^ 0xFF;
    File('${ordner.path}/m.onnx').writeAsBytesSync(verfaelscht);

    expect(dienst.isEntryInstalled(eintrag), isTrue,
        reason: 'die Längenprüfung sieht hier bewusst nichts');
    final befunde = await dienst.pruefe(eintrag);
    expect(befunde.single.zustand, Modellzustand.weichtAb);
  });

  test('eine abgeschnittene Datei heisst „falsche Länge", nicht „weicht ab"',
      () async {
    final (:eintrag, :inhalt) = baue('m.onnx', 5000);
    File('${ordner.path}/m.onnx').writeAsBytesSync(inhalt.sublist(0, 4000));

    final befunde = await dienst.pruefe(eintrag);
    expect(befunde.single.zustand, Modellzustand.zuKurz,
        reason: 'der Bericht soll sagen, was los ist, nicht nur dass etwas los ist');
  });

  test('eine fehlende Datei heisst „fehlt"', () async {
    final (:eintrag, inhalt: _) = baue('m.onnx', 5000);
    final befunde = await dienst.pruefe(eintrag);
    expect(befunde.single.zustand, Modellzustand.fehlt);
  });

  test('ein gar nicht installierter Eintrag bleibt aus dem Bericht', () async {
    final (:eintrag, inhalt: _) = baue('m.onnx', 5000);
    // „Fehlt" ist kein Befund, wenn niemand das Modell haben wollte –
    // sonst meldete die Prüfung bei jedem Nutzer neun rote Zeilen für
    // Modelle, die er bewusst nie geladen hat.
    expect(await dienst.pruefeAlleInstallierten([eintrag]), isEmpty);
  });

  test('ein halb installierter Eintrag kommt vollständig in den Bericht',
      () async {
    final inhalt =
        Uint8List.fromList(List.generate(3000, (i) => (i * 13 + 5) % 251));
    final eintrag = ModelCatalogEntry(
      id: 'zwei',
      sourceUrl: 'http://127.0.0.1',
      files: [
        ModelFile('a.onnx', 'http://127.0.0.1/a',
            sha256.convert(inhalt).toString(), inhalt.length),
        ModelFile('b.onnx', 'http://127.0.0.1/b',
            sha256.convert(inhalt).toString(), inhalt.length),
      ],
    );
    File('${ordner.path}/a.onnx').writeAsBytesSync(inhalt);

    final befunde = await dienst.pruefeAlleInstallierten([eintrag]);
    expect(befunde.map((b) => b.zustand),
        [Modellzustand.stimmt, Modellzustand.fehlt]);
  });

  test('der Fortschritt nennt jede geprüfte Datei', () async {
    final (:eintrag, :inhalt) = baue('m.onnx', 1000);
    File('${ordner.path}/m.onnx').writeAsBytesSync(inhalt);
    final gesehen = <String>[];
    await dienst.pruefeAlleInstallierten([eintrag],
        fortschritt: gesehen.add);
    expect(gesehen, ['m.onnx']);
  });
}
