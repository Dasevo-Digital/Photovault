import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/raw_praezision.dart';

Uint8List tiff(int bits) {
  final b = Uint8List(110), d = ByteData.sublistView(b);
  b[0] = b[1] = 73;
  d.setUint16(2, 42, Endian.little);
  d.setUint32(4, 8, Endian.little);
  d.setUint16(8, 6, Endian.little);
  final tags = [
    [256, 4, 1, 3],
    [257, 4, 1, 1],
    [258, 3, 3, 100],
    [262, 3, 1, 2],
    [277, 3, 1, 3],
    [339, 3, 1, 1],
  ];
  for (var i = 0; i < tags.length; i++) {
    final a = 10 + i * 12, t = tags[i];
    d.setUint16(a, t[0], Endian.little);
    d.setUint16(a + 2, t[1], Endian.little);
    d.setUint32(a + 4, t[2], Endian.little);
    d.setUint32(a + 8, t[3], Endian.little);
  }
  for (var i = 0; i < 3; i++) {
    d.setUint16(100 + i * 2, bits, Endian.little);
  }
  return b;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('TIFF16 verlangt alle Kanäle, richtige Typen und gültige Offsets', () {
    expect(RawPraezision.istTiff16(tiff(16)), isTrue);
    expect(RawPraezision.istTiff16(tiff(8)), isFalse);
    expect(
      RawPraezision.istTiff16(Uint8List.fromList([255, 216, 255])),
      isFalse,
    );
    final kaputt = tiff(16);
    ByteData.sublistView(kaputt).setUint32(4, 999999, Endian.little);
    expect(RawPraezision.istTiff16(kaputt), isFalse);
  });
  test('JPEG wird vor jedem nativen Zugriff abgewiesen', () async {
    expect(
      () => RawPraezision.entwickle(File('/tmp/probe.jpg')),
      throwsFormatException,
    );
  });
  test(
    'fehlender oder 8-Bit-Konverter wird niemals als TIFF16 ausgegeben',
    () async {
      if (!Platform.isMacOS) return;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        RawPraezision.kanal,
        (_) async => tiff(8),
      );
      addTearDown(
        () => messenger.setMockMethodCallHandler(RawPraezision.kanal, null),
      );
      expect(
        () => RawPraezision.entwickle(File('/tmp/synthetisch.dng')),
        throwsFormatException,
      );
    },
  );
}
