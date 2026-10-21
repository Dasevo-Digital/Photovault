import 'package:flutter_test/flutter_test.dart';
import 'package:kern/services/namensdatum.dart';

void main() {
  final jetzt = DateTime(2026, 10, 21, 12);
  Namensdatum? lies(String name) => namensdatumAus(name, jetzt: jetzt);

  group('mit Uhrzeit', () {
    for (final (name, erwartet) in [
      ('24-11-13 10-48-28 1234.jpg', DateTime(2024, 11, 13, 10, 48, 28)),
      ('23-07-14 09-12-33 a1b2 (1).jpg', DateTime(2023, 7, 14, 9, 12, 33)),
      ('IMG_20190312_081502.jpg', DateTime(2019, 3, 12, 8, 15, 2)),
      ('20190815_173045.jpg', DateTime(2019, 8, 15, 17, 30, 45)),
      ('PXL_20231105_123456789.jpg', DateTime(2023, 11, 5, 12, 34, 56)),
      ('PHOTO-2026-03-14-17-05-09.jpg', DateTime(2026, 3, 14, 17, 5, 9)),
      (
        'Bildschirmfoto vom 2026-01-20 09-30-15.png',
        DateTime(2026, 1, 20, 9, 30, 15),
      ),
      (
        'Screenshot 2024-01-02 at 12.34.56.png',
        DateTime(2024, 1, 2, 12, 34, 56),
      ),
      (
        'WhatsApp Image 2024-01-02 um 08.09.10.jpeg',
        DateTime(2024, 1, 2, 8, 9, 10),
      ),
      ('VID20190101120000.mp4', DateTime(2019, 1, 1, 12, 0, 0)),
    ]) {
      test(name, () {
        final d = lies(name)!;
        expect(d.zeitpunkt, erwartet);
        expect(d.mitUhrzeit, isTrue);
      });
    }
  });

  group('nur der Tag', () {
    for (final (name, erwartet) in [
      ('IMG-20180517-WA0003.jpg', DateTime(2018, 5, 17, 12)),
      ('IMG-20180613-WA0001-0a1b2c3d.jpg', DateTime(2018, 6, 13, 12)),
      ('2019-05-01 Urlaub.jpg', DateTime(2019, 5, 1, 12)),
    ]) {
      test(name, () {
        final d = lies(name)!;
        expect(d.zeitpunkt, erwartet);
        expect(d.mitUhrzeit, isFalse);
      });
    }
  });

  group('kein Datum', () {
    for (final name in [
      // Zählnummern der Kameras.
      'IMG_0042.JPG', 'P8170001-0f1e2d3c.JPG', 'DSC_0000123.JPG',
      'P1010001.JPG', 'IMG00001.JPG',
      // Zweistelliges Jahr ohne Uhrzeit: 13.11.2024 oder 24.11.2013?
      '24-11-13 Geburtstag.jpg',
      // Kennungen und Prüfsummen.
      '3f2a9c1e-7b4d-4e8a-9c2f-1a2b3c4d5e6f.mp4',
      '12345678901__0A1B2C3D-E4F5-4A6B-8C7D-9E0F1A2B3C4D.heic',
      'a20130517bcdef0123.jpg',
      // Unmögliche Tage und die Zukunft.
      'IMG_20230230_101010.jpg', 'IMG_20301224_101010.jpg',
    ]) {
      test(name, () => expect(lies(name), isNull));
    }
  });

  test('passtZu: eine Minute mit Uhrzeit, sonst der Tag', () {
    final mit = lies('25-05-01 12-00-44 1001.MOV')!;
    expect(mit.passtZu(DateTime(2025, 5, 1, 12, 0, 41)), isTrue);
    expect(mit.passtZu(DateTime(2025, 5, 1, 12, 2)), isFalse);
    final ohne = lies('IMG-20180517-WA0003.jpg')!;
    expect(ohne.passtZu(DateTime(2018, 5, 17, 23, 59)), isTrue);
    expect(ohne.passtZu(DateTime(2018, 5, 18, 0, 1)), isFalse);
  });
}
