import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/model_catalog.dart';
import 'package:photo_vault/services/model_download_service.dart';

/// Der Modellordner wächst schnell auf über ein Gigabyte, ohne dass die App
/// das bisher irgendwo auswies. Diese Zahlen speisen die Anzeige in den
/// Einstellungen.
void main() {
  late Directory dir;
  late ModelDownloadService dienst;
  late ModelCatalogEntry eintrag;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('pv_groesse_');
    dienst = ModelDownloadService(dir.path);
    eintrag = ModelCatalog.all.first;
  });
  tearDown(() => dir.deleteSync(recursive: true));

  void lege(String name, int bytes) =>
      File('${dir.path}/$name').writeAsBytesSync(List.filled(bytes, 0));

  test('nicht installiert ergibt null Bytes', () {
    expect(dienst.belegteBytes(eintrag), 0);
    expect(dienst.isEntryInstalled(eintrag), isFalse);
  });

  test('zählt alle Dateien eines Eintrags zusammen', () {
    var erwartet = 0;
    for (var i = 0; i < eintrag.files.length; i++) {
      final groesse = 1000 * (i + 1);
      lege(eintrag.files[i].fileName, groesse);
      erwartet += groesse;
    }
    expect(dienst.belegteBytes(eintrag), erwartet);
  });

  test('eine fehlende Datei zählt als null, der Rest weiterhin mit', () {
    // Nur die erste Datei anlegen – ein halb installierter Eintrag.
    lege(eintrag.files.first.fileName, 4096);
    expect(dienst.belegteBytes(eintrag), 4096);
    // Und selbst wenn der Eintrag nur diese eine Datei hätte, gilt er
    // nicht als installiert: 4096 Bytes sind nicht die Länge, die der
    // Katalog nennt. Genau das ist der Sinn der Längenprüfung.
    expect(dienst.isEntryInstalled(eintrag), isFalse);
  });

  /// **Die Länge entscheidet mit, nicht nur das Dasein.**
  ///
  /// Bis zur 21. Prüfrunde fragte [ModelDownloadService.isEntryInstalled]
  /// allein `existsSync()`. Eine abgebrochene Übertragung galt damit als
  /// fertig, und eine im Katalog geänderte Fassung erreichte niemanden,
  /// der die alte schon hatte – beim Wechsel von CLIP auf fp16 wäre die
  /// 352-MB-Datei stillschweigend liegengeblieben.
  test('eine abgeschnittene Datei gilt nicht als installiert', () {
    for (final f in eintrag.files) {
      lege(f.fileName, f.bytes);
    }
    expect(dienst.isEntryInstalled(eintrag), isTrue);

    lege(eintrag.files.first.fileName, eintrag.files.first.bytes - 1);
    expect(dienst.isEntryInstalled(eintrag), isFalse);
  });

  test('jede Katalogdatei kennt ihre Länge', () {
    // Ein vergessener Eintrag machte die Prüfung oben wirkungslos: Bei
    // `bytes == 0` gälte jede Datei als falsch lang und damit als nie
    // installiert.
    for (final e in ModelCatalog.all) {
      for (final f in e.files) {
        expect(f.bytes, greaterThan(0), reason: '${f.fileName} ohne Länge');
        expect(f.sha256, hasLength(64), reason: '${f.fileName} ohne Prüfsumme');
      }
    }
  });

  test('die Gesamtsumme erfasst auch Dateien ausserhalb des Katalogs', () {
    lege(eintrag.files.first.fileName, 2048);
    lege('uraltes_modell.onnx', 5000);
    expect(dienst.gesamteBytes(), 7048,
        reason: 'sonst unterschlüge die Anzeige gerade die Altlasten, '
            'wegen derer man nachsieht');
  });

  test('ein fehlender Ordner ergibt null statt eines Fehlers', () {
    final weg = ModelDownloadService('${dir.path}/gibtesnicht');
    expect(weg.gesamteBytes(), 0);
    expect(weg.belegteBytes(eintrag), 0);
  });
}
