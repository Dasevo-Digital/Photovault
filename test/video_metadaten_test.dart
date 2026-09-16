import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/video_metadaten.dart';

/// **Aufnahmezeit und Kamera aus einem Video.**
///
/// An gebauten Bytes und nicht an echten Aufnahmen: Die drei Ablagen
/// unterscheiden sich in wenigen Bytes, und eine 1,7-GB-Datei in den
/// Prüfstand zu legen hiesse, genau diese Bytes nicht zu sehen.
///
/// Die Gegenprobe an echten Dateien läuft getrennt
/// (`tool/video_zeit_abgleich.dart` gegen `exiftool`): 440 Videos,
/// **309 von 309 gelesenen Zeitpunkten richtig**, kein falscher.
void main() {
  /// Ein Kasten: vier Byte Länge, vier Byte Art, dann der Inhalt.
  Uint8List kasten(String art, List<int> inhalt) {
    final b = BytesBuilder();
    final laenge = 8 + inhalt.length;
    b.add([
      (laenge >> 24) & 0xff,
      (laenge >> 16) & 0xff,
      (laenge >> 8) & 0xff,
      laenge & 0xff,
    ]);
    b.add(art.codeUnits.length == 4
        ? art.codeUnits
        // „©day" ist ein Zeichen U+00A9 und drei ASCII – als Bytes vier.
        : [0xA9, ...art.substring(1).codeUnits]);
    b.add(inhalt);
    return b.toBytes();
  }

  List<int> u32(int v) =>
      [(v >> 24) & 0xff, (v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff];

  /// `moov/mvhd` in Fassung 0 mit [sekunden] seit 1904-01-01.
  Uint8List mitMvhd(int sekunden, {List<int>? weitere}) => kasten('moov', [
        ...kasten('mvhd', [
          0, 0, 0, 0, // Fassung 0 + Flaggen
          ...u32(sekunden),
          ...u32(sekunden),
          ...u32(1000),
          ...u32(5000),
        ]),
        ...?weitere,
      ]);

  /// `moov/meta/keys+ilst` mit genau einem Schlüssel und seinem Wert.
  Uint8List mitAppleSchluessel(Map<String, String> paare) {
    final namen = paare.keys.toList();
    final keys = kasten('keys', [
      0, 0, 0, 0,
      ...u32(namen.length),
      for (final n in namen) ...[
        ...u32(8 + n.codeUnits.length),
        ...'mdta'.codeUnits,
        ...n.codeUnits,
      ],
    ]);
    final ilst = kasten('ilst', [
      for (var i = 0; i < namen.length; i++)
        ...() {
          final wert = paare[namen[i]]!;
          final data = kasten('data', [
            ...u32(1), // Art: UTF-8
            ...u32(0), // Sprache
            ...wert.codeUnits,
          ]);
          return [...u32(8 + data.length), ...u32(i + 1), ...data];
        }(),
    ]);
    // `meta` ohne Fassungsbytes (QuickTime-Fassung) – [kinderVon]
    // entscheidet das an den Bytes.
    return kasten('moov', [
      ...kasten('meta', [...keys, ...ilst]),
    ]);
  }

  group('Aufnahmezeit', () {
    test('Apples Schlüssel gilt und bringt seine Zeitzone mit', () {
      final moov = mitAppleSchluessel(
          {'com.apple.quicktime.creationdate': '2025-09-20T11:50:21+0200'});
      final zeit = zeitAusMoov(moov)!;
      expect(zeit.herkunft, Zeitherkunft.mitZone);
      expect(zeit.zeitpunkt.toUtc(), DateTime.utc(2025, 9, 20, 9, 50, 21));
    });

    test('vierstellige Zone ohne Doppelpunkt wird angenommen', () {
      // `DateTime.parse` lehnt „+0200" ab und nimmt nur „+02:00" – Apple
      // schreibt aber die erste Form. Ohne das Einsetzen des Doppelpunkts
      // fiele jedes iPhone-Video still auf `mvhd` zurück.
      final ohne = zeitAusMoov(mitAppleSchluessel(
          {'com.apple.quicktime.creationdate': '2025-09-20T11:50:21+02:00'}))!;
      final mit = zeitAusMoov(mitAppleSchluessel(
          {'com.apple.quicktime.creationdate': '2025-09-20T11:50:21+0200'}))!;
      expect(mit.zeitpunkt, ohne.zeitpunkt);
    });

    test('ein Zeitpunkt ohne Zonenangabe zählt nicht als „mit Zone"', () {
      // Sonst würde eine Ortszeit als Zeitpunkt genommen, und niemand
      // wüsste hinterher, dass die Zone geraten war.
      final moov = mitAppleSchluessel(
          {'com.apple.quicktime.creationdate': '2025-09-20T11:50:21'});
      expect(zeitAusMoov(moov), isNull);
    });

    test('mvhd wird als Ortszeit gelesen', () {
      // 1904-01-01 plus diese Sekunden ist 2013-06-02 16:40:17.
      final sekunden = DateTime.utc(2013, 6, 2, 16, 40, 17)
              .difference(DateTime.utc(1904))
              .inSeconds;
      final zeit = zeitAusMoov(mitMvhd(sekunden))!;
      expect(zeit.herkunft, Zeitherkunft.ohneZone);
      expect(zeit.zeitpunkt, DateTime(2013, 6, 2, 16, 40, 17));
    });

    test('die Zeitrechnung beginnt 1904, nicht 1970', () {
      // Die Gegenprobe zur naheliegendsten Verwechslung: Mit der
      // Unix-Epoche käme ein Video von 2013 im Jahr 1947 heraus – eine
      // Zahl, die plausibel genug aussieht, um durchzugehen.
      final sekunden = DateTime.utc(2013, 6, 2)
              .difference(DateTime.utc(1904))
              .inSeconds;
      expect(zeitAusMoov(mitMvhd(sekunden))!.zeitpunkt.year, 2013);
    });

    test('Apples Schlüssel schlägt mvhd', () {
      final sekunden =
          DateTime.utc(2000).difference(DateTime.utc(1904)).inSeconds;
      final moov = kasten('moov', [
        ...kasten('mvhd',
            [0, 0, 0, 0, ...u32(sekunden), ...u32(sekunden), ...u32(1000), ...u32(1)]),
        ...kasten('meta', [
          ...mitAppleSchluessel(
                  {'com.apple.quicktime.creationdate': '2025-09-20T11:50:21+0200'})
              .sublist(16),
        ]),
      ]);
      expect(zeitAusMoov(moov)!.zeitpunkt.year, 2025);
    });

    test('eine ungestellte Kamerauhr ergibt nichts', () {
      expect(zeitAusMoov(mitMvhd(0)), isNull);
      final sekunden =
          DateTime.utc(1980).difference(DateTime.utc(1904)).inSeconds;
      expect(zeitAusMoov(mitMvhd(sekunden)), isNull,
          reason: 'vor 1990 ist keine Aufnahme, sondern eine leere Uhr');
    });

    test('ohne jeden Zeitkasten kommt nichts heraus', () {
      expect(zeitAusMoov(kasten('moov', kasten('udta', []))), isNull);
    });
  });

  group('Kamera', () {
    test('aus Apples Schlüsselliste', () {
      final moov = mitAppleSchluessel({
        'com.apple.quicktime.make': 'Apple',
        'com.apple.quicktime.model': 'iPhone 13 Pro',
      });
      expect(kameraAusMoov(moov), (hersteller: 'Apple', geraet: 'iPhone 13 Pro'));
    });

    test('Leerzeichen im Gerätenamen bleiben stehen', () {
      // Sonst stünde „CanonPowerShotA3350IS" als zweites, unbekanntes
      // Gerät neben demselben aus den Fotos derselben Kamera.
      final moov = mitAppleSchluessel(
          {'com.apple.quicktime.model': 'Canon PowerShot A3350 IS'});
      expect(kameraAusMoov(moov).geraet, 'Canon PowerShot A3350 IS');
    });

    test('aus den klassischen Atomen ©mak/©mod', () {
      final moov = kasten('moov', [
        ...kasten('udta', [
          ...kasten('©mak', [0, 5, 0, 0, ...'Canon'.codeUnits]),
          ...kasten('©mod', [0, 8, 0, 0, ...'EOS R10'.codeUnits, 0x20]),
        ]),
      ]);
      expect(kameraAusMoov(moov).hersteller, 'Canon');
      expect(kameraAusMoov(moov).geraet, 'EOS R10',
          reason: 'aussen wird gekürzt');
    });

    test('ohne Angaben bleibt beides leer', () {
      expect(kameraAusMoov(mitMvhd(3000000000)),
          (hersteller: null, geraet: null));
    });
  });
}
