// ignore_for_file: avoid_print
// Misst von innen, was ein Modelllauf an Speicher kostet – und vor allem,
// ob wiederholte Läufe weiter wachsen.
//
// Von aussen betrachtet sieht das Verhalten nach einem Leck aus: Nach dem
// ersten Lauf gibt der Prozess nur einen Teil zurück. Das ist keins. Weder
// glibc noch der Zuteiler von ONNX Runtime geben freie Seiten sofort ans
// Betriebssystem zurück; sie behalten sie für den nächsten Lauf. Der
// Unterschied zeigt sich erst in der Wiederholung: Ein Leck wüchse in
// jeder Runde um denselben Betrag, zurückgehaltener Speicher pendelt sich
// ein.
//
// Gemessen auf der Linux-Testmaschine (2026-08-21):
//   Runde 1: 448 MB · 2: 497 · 3: 508 · 4: 512
//   Zuwachs je Runde: +49, +11, +4 – eine konvergierende Reihe.
//   Ein anschliessender fünfter Lauf belegte 0 MB zusätzlich.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:photo_vault/services/ocr_service.dart';
import 'package:photo_vault/services/speicher_rueckgabe.dart';

/// Der belegte Speicher in MB. `/proc` gibt es nur unter Linux – deshalb
/// läuft diese Datei auch nur dort.
int rssMb() {
  final zeile = File('/proc/self/status')
      .readAsLinesSync()
      .firstWhere((z) => z.startsWith('VmRSS'), orElse: () => 'VmRSS: 0 kB');
  return int.parse(zeile.split(RegExp(r'\s+'))[1]) ~/ 1024;
}

/// Wo die OCR-Modelle liegen.
///
/// Frueher stand hier fest `~/ocr_modelle`. Dieser Ordner wurde spaeter
/// fuer die HardSwish-Untersuchung umgewidmet, und die Messung fiel
/// stillschweigend aus - "Modelle fehlen" sieht aus wie ein Umgebungs-
/// problem und wurde als solches uebersehen. Deshalb wird jetzt gesucht,
/// mit der Ablage der installierten App als zweiter Stelle.
String? modellOrdner() {
  final heim = Platform.environment['HOME'];
  for (final kandidat in [
    '$heim/ocr_modelle',
    '$heim/.var/app/com.example.PhotoVault/data/com.example.photo_vault/PhotoVault/models',
  ]) {
    if (OcrService.isAvailable(kandidat)) return kandidat;
  }
  return null;
}

/// Ein Bild fuer den Modelllauf.
///
/// Nimmt die Musterdatei, wenn es sie gibt - sonst ein erzeugtes Bild.
/// Fuer die Speichermessung zaehlt, dass das Modell laeuft, nicht was es
/// liest; der Test darueber prueft den gelesenen Text und braucht deshalb
/// die echte Datei.
img.Image probebild(String ordner) {
  final datei = File('$ordner/probe_de.png');
  if (datei.existsSync()) return img.decodeImage(datei.readAsBytesSync())!;
  // Selbst gezeichnet statt einer Musterdatei: Die lag frueher neben den
  // Modellen und verschwand mit dem Ordner, worauf die Messung ausfiel.
  // Ein Test, dessen Voraussetzung anderswo liegt, faellt irgendwann aus.
  final bild = img.Image(width: 720, height: 120);
  img.fill(bild, color: img.ColorRgb8(255, 255, 255));
  img.drawString(bild, 'PHOTO VAULT',
      font: img.arial48, x: 40, y: 30, color: img.ColorRgb8(0, 0, 0));
  return bild;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('wiederholte Modellläufe wachsen nicht weiter', () async {
    final ordner = modellOrdner();
    expect(ordner, isNotNull, reason: 'OCR-Modelle nirgends gefunden');
    final bild = probebild(ordner!);

    final stand = <int>[];
    for (var runde = 1; runde <= 4; runde++) {
      final dienst = await OcrService.load(ordner);
      final text = await dienst.erkenneText(bild);
      expect(text.isNotEmpty, isTrue, reason: 'Runde $runde las nichts');
      await dienst.dispose();
      // Dem Zuteiler einen Moment lassen, Seiten zurückzugeben.
      await Future<void>.delayed(const Duration(seconds: 2));
      stand.add(rssMb());
      print('nach Runde $runde: ${stand.last} MB');
    }

    final spaeterZuwachs = stand[3] - stand[1];
    print('Zuwachs über die letzten zwei Runden: $spaeterZuwachs MB');

    // Der Kern: Zwei weitere vollständige Runden dürfen zusammen weniger
    // kosten als ein einzelnes Laden der Modelle (rund 50 MB). Liefe je
    // Runde derselbe Betrag weg, wären es hier rund 100 MB – und bei
    // achttausend Fotos das Ende.
    //
    // Nicht geprüft wird, ob der Zuwachs von Runde zu Runde monoton
    // abnimmt: Bei diesen kleinen Beträgen schwankt die Messung zwischen
    // den Läufen stärker als der Effekt (gesehen: 5 MB, dann 15 MB).
    expect(spaeterZuwachs, lessThan(60),
        reason: 'gleichbleibender Zuwachs je Runde wäre ein Leck');
  });

  // Der Gegenpart zum Test darueber: Zurueckgehaltener Speicher ist kein
  // Leck - aber er laesst sich zurueckgeben. Gemessen am 25.08.2026 an
  // einer knapp dreizehn Stunden alten Instanz: 2,4 GB belegt, davon
  // 1,5 GB Heap; ein malloc_trim(0) gab 692 MB ans System zurueck.
  test('malloc_trim gibt nach einem Modelllauf Speicher zurueck', () async {
    expect(SpeicherRueckgabe.moeglich, isTrue,
        reason: 'malloc_trim nicht auffindbar - kein glibc?');

    final ordner = modellOrdner();
    expect(ordner, isNotNull, reason: 'OCR-Modelle nirgends gefunden');
    final bild = probebild(ordner!);

    final dienst = await OcrService.load(ordner);
    await dienst.erkenneText(bild);
    await dienst.dispose();
    await Future<void>.delayed(const Duration(seconds: 2));

    final vorher = rssMb();
    final etwasFrei = SpeicherRueckgabe.jetzt();
    final nachher = rssMb();
    print('vor der Rueckgabe: $vorher MB, danach: $nachher MB '
        '(${vorher - nachher} MB zurueck, etwasFrei=$etwasFrei)');

    // Bewusst keine Zahl als Erwartung: Wie viel zurueckkommt, haengt an
    // der Fragmentierung des Heaps und schwankt. Was zaehlt, ist die
    // Richtung - der Aufruf darf den Speicher nicht VERGROESSERN, und er
    // muss melden, dass er etwas getan hat.
    expect(etwasFrei, isTrue);
    expect(nachher, lessThanOrEqualTo(vorher));
  }, timeout: const Timeout(Duration(minutes: 3)));
}
