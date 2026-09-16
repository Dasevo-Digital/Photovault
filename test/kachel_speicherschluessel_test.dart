import 'dart:typed_data';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/widgets/mini_location_map.dart';

/// Merkt sich, welche Adressen unten ankommen.
class _Merker implements MapCachingProvider {
  final gelesen = <String>[];
  final geschrieben = <String>[];

  @override
  bool get isSupported => true;

  @override
  Future<CachedMapTile?> getTile(String url) async {
    gelesen.add(url);
    return null;
  }

  @override
  Future<void> putTile({
    required String url,
    required CachedMapTileMetadata metadata,
    Uint8List? bytes,
  }) async {
    geschrieben.add(url);
  }
}

void main() {
  const blank = 'https://tile.openstreetmap.org/12/2148/1370.png';

  group('der Nachfass-Anhang und der Speicherschluessel', () {
    test('ohne Abschneiden waere es eine andere Datei', () {
      // Der Grund fuer [FragmentloserSpeicher]: Der Schluessel ist eine
      // UUID Fassung 5 ueber der vollen Adresse.
      final ohne = BuiltInMapCachingProvider.uuidTileKeyGenerator(blank);
      final eins = BuiltInMapCachingProvider.uuidTileKeyGenerator('$blank#1');
      final zwei = BuiltInMapCachingProvider.uuidTileKeyGenerator('$blank#2');
      expect(ohne, isNot(eins));
      expect(eins, isNot(zwei));
    });

    test('mit Abschneiden ist es dieselbe', () {
      expect(
        BuiltInMapCachingProvider.uuidTileKeyGenerator(
            FragmentloserSpeicher.ohneAnhang('$blank#3')),
        BuiltInMapCachingProvider.uuidTileKeyGenerator(
            FragmentloserSpeicher.ohneAnhang(blank)),
      );
    });

    test('der Anhang kommt unten nicht mehr an', () async {
      final merker = _Merker();
      final speicher = FragmentloserSpeicher(merker);
      await speicher.getTile('$blank#1');
      await speicher.getTile(blank);
      await speicher.putTile(
        url: '$blank#2',
        metadata: CachedMapTileMetadata(
            staleAt: DateTime.timestamp(), lastModified: null, etag: null),
        bytes: Uint8List(4),
      );
      expect(merker.gelesen, [blank, blank]);
      expect(merker.geschrieben, [blank]);
    });

    test('eine Adresse ohne Anhang bleibt unangetastet', () {
      expect(FragmentloserSpeicher.ohneAnhang(blank), blank);
      expect(FragmentloserSpeicher.ohneAnhang(''), '');
    });

    test('isSupported wird durchgereicht', () {
      expect(FragmentloserSpeicher(_Merker()).isSupported, isTrue);
    });

    test('der spaete Speicher wird erst beim Zugriff gebaut', () {
      // Sonst verlangt schon das Bauen des Anbieters eine fertige
      // Flutter-Bindung – siehe den Kommentar an [FragmentloserSpeicher].
      var gebaut = 0;
      final speicher = FragmentloserSpeicher.spaet(() {
        gebaut++;
        return _Merker();
      });
      expect(gebaut, 0);
      expect(speicher.isSupported, isTrue);
      expect(gebaut, 1);
      expect(speicher.isSupported, isTrue);
      expect(gebaut, 1, reason: 'und danach nur noch einmal');
    });

    test('der Kachelanbieter benutzt ihn auch wirklich', () {
      // **Frueher ein Blick in den Quelltext**, weil der Speicher eines
      // `NetworkTileProvider` von aussen nicht abzufragen schien. Er ist
      // es doch – `cachingProvider` ist ein oeffentliches Feld –, und
      // seit der Anbieter sich den Speicher mit dem Offlinerueckfall
      // teilt, stand in der Zeile ohnehin etwas anderes als der Text, auf
      // den diese Pruefung wartete. Jetzt wird das Ergebnis geprueft und
      // nicht die Schreibweise.
      //
      // Ohne den fragmentlosen Speicher faellt flutter_map auf den
      // blanken zurueck, und der Fehler waere still wieder da.
      expect(Nachfassanbieter().cachingProvider, isA<FragmentloserSpeicher>(),
          reason: 'Nachfassanbieter muss den fragmentlosen Speicher mitgeben');
    });
  });
}
