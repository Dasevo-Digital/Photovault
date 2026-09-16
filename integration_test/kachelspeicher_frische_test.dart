// ignore_for_file: avoid_print
// Greift die Frische-Übersteuerung des Kachelspeichers wirklich?
//
// Anlass: OpenTopoMap rendert Kacheln bei Bedarf und gibt ausgerechnet
// den frisch gerenderten – also den teuersten – die kürzeste
// Haltbarkeit. An echten Abrufen gemessen:
//
//   x-cache-status: MISS   max-age=15875   (4,4 h)   Abruf 1,72 s
//   x-cache-status: MISS   max-age=13615   (3,8 h)   Abruf 1,63 s
//   vorgerendert           max-age=604800  (7 Tage)  Abruf 0,09 s
//
// Läuft eine Kachel ab, macht flutter_map VOR der Anzeige einen
// blockierenden Rückfrage-Umlauf. Ohne Übersteuerung wartet man am
// selben Ort einen Tag später also wieder.
//
// Im Unittest lässt sich das nicht prüfen: Der Speicher braucht
// `path_provider` und damit Plattformkanäle. Deshalb steht es hier.
import 'dart:typed_data';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:photo_vault/widgets/mini_location_map.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('eine kurzlebige Kachel bleibt trotzdem lange frisch',
      (tester) async {
    kartenSpeicherEinrichten();
    final speicher = BuiltInMapCachingProvider.getOrCreateInstance();
    expect(speicher.isSupported, isTrue,
        reason: 'ohne Speicher hat die Messung keinen Gegenstand');

    // Genau die Kopfzeilen, die OpenTopoMap einer frisch gerenderten
    // Kachel mitgibt: 3,5 Stunden Haltbarkeit.
    const kurz = 12590;
    final url = 'https://example.invalid/probe/${DateTime.now().microsecondsSinceEpoch}.png';

    await speicher.putTile(
      url: url,
      metadata: CachedMapTileMetadata.fromHttpHeaders(const {
        'cache-control': 'max-age=$kurz',
        // Ohne `age` oder `date` kann flutter_map das Alter nicht
        // ausrechnen und faellt auf sieben Tage zurueck - dann maesse
        // der Test den Rueckfall statt unserer Uebersteuerung. Echte
        // Antworten tragen die Zeile.
        'age': '0',
      }),
      bytes: Uint8List.fromList(const [1, 2, 3, 4]),
    );

    // Das Schreiben laeuft nebenher; ohne kurze Pause laese man
    // gelegentlich, bevor die Datei da ist.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final abgelegt = await speicher.getTile(url);
    expect(abgelegt, isNotNull, reason: 'die Kachel muss abgelegt worden sein');

    final haltbarBis = abgelegt!.metadata.staleAt;
    final rest = haltbarBis.difference(DateTime.now());

    print('Kopfzeile sagt:      ${(kurz / 3600).toStringAsFixed(1)} h');
    print('Tatsaechlich frisch: ${rest.inDays} Tage '
        '(${rest.inHours} h)');
    print('Eingestellt:         ${kartenKachelFrische.inDays} Tage');

    // Der Kern: Die kurze Angabe des Servers darf NICHT gewinnen.
    expect(rest.inHours, greaterThan(kurz ~/ 3600 * 2),
        reason: 'sonst wirkt die Uebersteuerung gar nicht');
    expect(rest.inDays, closeTo(kartenKachelFrische.inDays, 1),
        reason: 'die Frische soll unserer Einstellung folgen, '
            'nicht der Kopfzeile');
    expect(abgelegt.metadata.isStale, isFalse);
  });
}
