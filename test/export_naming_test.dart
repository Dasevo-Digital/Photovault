import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/db/database.dart';
import 'package:photo_vault/services/export_naming.dart';

/// Das Namensmuster ist der Teil der Export-Voreinstellungen, der einen
/// Dateinamen erzeugt – und damit der Teil, an dem sich ungültige Zeichen,
/// leere Ergebnisse und Pfadausbrüche zeigen würden.
AssetData _asset({
  String dateiname = 'IMG_1234.CR3',
  DateTime? aufgenommen,
  String? hersteller,
  String? modell,
}) {
  return AssetData(
    id: 'a1',
    relativePath: 'originals/2026/03/a1.cr3',
    originalFileName: dateiname,
    type: 'IMAGE',
    fileSizeBytes: 1000,
    checksum: 'a1',
    fileCreatedAt: aufgenommen ?? DateTime(2026, 3, 7, 14, 5),
    importedAt: DateTime(2026, 3, 8),
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
    cameraMake: hersteller,
    cameraModel: modell,
    rating: 0,
  );
}

void main() {
  test('jeder Baustein setzt ein, was er verspricht', () {
    final a = _asset(hersteller: 'SONY', modell: 'ILCE-6300');
    expect(namenAusMuster('{name}', a, nummer: 1), 'IMG_1234');
    expect(namenAusMuster('{datum}', a, nummer: 1), '2026-03-07');
    expect(namenAusMuster('{zeit}', a, nummer: 1), '1405');
    expect(namenAusMuster('{jahr}-{monat}-{tag}', a, nummer: 1), '2026-03-07');
    expect(namenAusMuster('{kamera}', a, nummer: 1), 'SONY ILCE-6300');
    expect(namenAusMuster('{nr}', a, nummer: 7), '0007',
        reason: 'vierstellig, damit die Reihenfolge im Dateimanager stimmt');
  });

  test('Hersteller und Modell werden nicht doppelt geschrieben', () {
    // Canon steht in beiden EXIF-Feldern.
    final a = _asset(hersteller: 'Canon', modell: 'Canon EOS R10');
    expect(namenAusMuster('{kamera}', a, nummer: 1), 'Canon EOS R10');
  });

  test('fehlende Kameradaten ergeben keinen Rest im Namen', () {
    final a = _asset();
    expect(namenAusMuster('{kamera}', a, nummer: 1), 'IMG_1234',
        reason: 'ein leeres Ergebnis fällt auf den Originalnamen zurück');
    expect(namenAusMuster('{name}_{kamera}', a, nummer: 1), 'IMG_1234_');
  });

  test('ein Muster kann nicht aus dem Zielordner ausbrechen', () {
    final a = _asset();
    final name = namenAusMuster('../../{name}', a, nummer: 1);
    expect(name, isNot(contains('/')));
    expect(name, isNot(contains('\\')));
  });

  test('unter Windows verbotene Zeichen werden ersetzt', () {
    final a = _asset(dateiname: 'a:b*c?.jpg');
    final name = namenAusMuster('{name}', a, nummer: 1);
    for (final zeichen in [':', '*', '?', '"', '<', '>', '|']) {
      expect(name, isNot(contains(zeichen)));
    }
  });

  test('führende Punkte machen die Datei nicht versteckt', () {
    final a = _asset();
    expect(namenAusMuster('.{name}.', a, nummer: 1), 'IMG_1234');
  });

  test('sehr lange Namen werden gekappt', () {
    final a = _asset(dateiname: '${'x' * 400}.jpg');
    expect(namenAusMuster('{name}', a, nummer: 1).length, lessThanOrEqualTo(200));
  });

  test('die Endung kommt nie aus dem Muster', () {
    final a = _asset();
    // Auch wenn im Muster eine Endung steht, hängt der Aufrufer die
    // tatsächliche an – sonst hiesse eine gerenderte JPEG-Datei ".cr3".
    expect(dateiname('{name}.cr3', a, nummer: 1, endung: '.jpg'),
        'IMG_1234.cr3.jpg');
    expect(dateiname('{name}', a, nummer: 1, endung: '.jpg'), 'IMG_1234.jpg');
  });

  test('alle Bausteine der Aufzählung funktionieren auch wirklich', () {
    // Die Aufzählung ist zugleich die Hilfe im Editor – ein Baustein, der
    // dort steht, aber nicht ersetzt wird, landete sonst wörtlich im
    // Dateinamen.
    final a = _asset(hersteller: 'Sony', modell: 'A7');
    for (final baustein in Namensbaustein.values) {
      final ergebnis = namenAusMuster(baustein.muster, a, nummer: 3);
      expect(ergebnis, isNot(contains('{')),
          reason: '${baustein.muster} wurde nicht ersetzt');
    }
  });

  test('gekürzt wird nach Bytes, nicht nach Zeichen', () {
    // 200 Umlaute sind 400 UTF-8-Bytes. APFS zählt Zeichen und nähme das
    // noch an, ext4 und exFAT zählen Bytes und lehnten ab – und wohin
    // exportiert wird, sucht der Nutzer selbst aus.
    final a = _asset(dateiname: '${'ä' * 400}.jpg');
    final name = namenAusMuster('{name}', a, nummer: 1);
    expect(utf8.encode(name).length, lessThanOrEqualTo(200));
    expect(name, isNotEmpty);
  });

  test('beim Kürzen entsteht kein kaputtes Zeichen', () {
    // Schneidet man stumpf nach Bytes, landet man mitten in einer
    // Mehrbyte-Folge und der Dateiname ist ungültig.
    for (final zeichen in ['ä', '€', '😀']) {
      final a = _asset(dateiname: '${zeichen * 300}.jpg');
      final name = namenAusMuster('{name}', a, nummer: 1);
      expect(() => utf8.decode(utf8.encode(name)), returnsNormally);
      expect(name, equals(String.fromCharCodes(name.runes)));
    }
  });
}
