import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:photo_vault/services/gelaende_laden.dart';
import 'package:photo_vault/services/gelaendekacheln.dart';

/// Wie die Landschaft an ihre Kacheln kommt.
///
/// Der Befund der 15. Prüfrunde: Sie ging am Kachelspeicher vorbei, den
/// die Karten benutzen – also holte sie dieselben Bilder ein zweites Mal
/// und beim nächsten Öffnen ein drittes. Und sie nahm ein 404 für bare
/// Münze, obwohl OpenTopoMap damit „noch nicht gerendert" meint.
///
/// Geprüft wird deshalb nicht, wie die Landschaft aussieht, sondern
/// **wie oft und mit welchem Ergebnis der Server gefragt wird**.
Future<Uint8List> _kachel() async {
  const kante = 256;
  final rgba = Uint8List(kante * kante * 4);
  for (var i = 0; i < kante * kante; i++) {
    final roh = (500 + 32768).round();
    rgba[i * 4] = roh >> 8;
    rgba[i * 4 + 1] = roh & 255;
    rgba[i * 4 + 3] = 255;
  }
  final fertig = Completer<ui.Image>();
  ui.decodeImageFromPixels(
      rgba, kante, kante, ui.PixelFormat.rgba8888, fertig.complete);
  final bild = await fertig.future;
  final daten = await bild.toByteData(format: ui.ImageByteFormat.png);
  bild.dispose();
  return daten!.buffer.asUint8List();
}

/// Ein Kachelspeicher im Arbeitsspeicher – dieselbe Schnittstelle wie der
/// echte, nur nachzählbar.
class _Speicher implements MapCachingProvider {
  final Map<String, ({Uint8List bytes, CachedMapTileMetadata metadata})> inhalt =
      {};
  var gelesen = 0;
  var geschrieben = 0;

  @override
  bool get isSupported => true;

  @override
  Future<CachedMapTile?> getTile(String url) async {
    gelesen++;
    return inhalt[url];
  }

  @override
  Future<void> putTile({
    required String url,
    required CachedMapTileMetadata metadata,
    Uint8List? bytes,
  }) async {
    geschrieben++;
    if (bytes != null) inhalt[url] = (bytes: bytes, metadata: metadata);
  }
}

void main() {
  late Uint8List kachel;
  setUpAll(() async => kachel = await _kachel());

  // Ein winziger Ausschnitt, damit es bei wenigen Kacheln bleibt.
  Future<Hoehengitter?> lade(MockClient netz, MapCachingProvider sp) =>
      ladeHoehengitter(
          sued: 50.610,
          west: 9.860,
          nord: 50.612,
          ost: 9.862,
          netz: netz,
          speicher: sp);

  test('beim zweiten Mal fragt sie den Server nicht mehr', () async {
    final sp = _Speicher();
    var abrufe = 0;
    final netz = MockClient((_) async {
      abrufe++;
      return http.Response.bytes(kachel, 200);
    });

    expect(await lade(netz, sp), isNotNull);
    final ersteRunde = abrufe;
    expect(ersteRunde, greaterThan(0));
    expect(sp.geschrieben, ersteRunde,
        reason: 'jede geholte Kachel landet im Speicher');

    expect(await lade(netz, sp), isNotNull);
    expect(abrufe, ersteRunde,
        reason: 'die zweite Runde kam vollständig aus dem Speicher');
  });

  test('ein 404 von OpenTopoMap ist kein endgueltiges Nein', () async {
    final sp = _Speicher();
    final versuche = <String, int>{};
    final netz = MockClient((anfrage) async {
      final u = anfrage.url.toString();
      versuche[u] = (versuche[u] ?? 0) + 1;
      // Beim ersten Mal noch nicht gerendert, beim zweiten da.
      return versuche[u] == 1
          ? http.Response.bytes(Uint8List(0), 404)
          : http.Response.bytes(kachel, 200);
    });

    expect(await lade(netz, sp), isNotNull,
        reason: 'nach dem zweiten Versuch ist die Kachel da');
    expect(versuche.values.every((n) => n == 2), isTrue,
        reason: 'jede Kachel wurde genau einmal wiederholt');
  });

  test('ein 403 wird nicht wiederholt', () async {
    // Die Gegenprobe: Nicht jeder Fehler verdient einen zweiten Versuch.
    final sp = _Speicher();
    final versuche = <String, int>{};
    final netz = MockClient((anfrage) async {
      final u = anfrage.url.toString();
      versuche[u] = (versuche[u] ?? 0) + 1;
      return http.Response.bytes(Uint8List(0), 403);
    });

    expect(await lade(netz, sp), isNull);
    expect(versuche.values.every((n) => n == 1), isTrue,
        reason: '403 heisst nein, nicht „gleich wieder"');
  });

  test('ohne Netz gilt die abgelaufene Kachel', () async {
    // Wer unterwegs ist, hat die Kacheln auf der Platte, aber keinen
    // Empfang. Bisher hiess das „konnte nicht geladen werden".
    final sp = _Speicher();
    final netz = MockClient((_) async => http.Response.bytes(kachel, 200));
    expect(await lade(netz, sp), isNotNull);

    // Alles auf abgelaufen setzen.
    for (final e in sp.inhalt.entries.toList()) {
      sp.inhalt[e.key] = (
        bytes: e.value.bytes,
        metadata: CachedMapTileMetadata(
            staleAt: DateTime.timestamp().subtract(const Duration(days: 1)),
            lastModified: null,
            etag: null),
      );
    }

    final ohneNetz = MockClient((_) async => throw const _KeinNetz());
    expect(await lade(ohneNetz, sp), isNotNull,
        reason: 'eine alte Kachel ist besser als eine leere Landschaft');
  });
}

class _KeinNetz implements Exception {
  const _KeinNetz();
}
