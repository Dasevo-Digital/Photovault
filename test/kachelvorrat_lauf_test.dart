import 'dart:convert';
import 'dart:io' show HttpDate;
import 'dart:typed_data';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:photo_vault/services/kachelvorrat.dart';
import 'package:photo_vault/widgets/mini_location_map.dart';

/// Der Lauf selbst: Was wird geholt, was übersprungen, was passiert bei
/// einem Fehlschlag?

/// Ein Speicher, der nur im Arbeitsspeicher lebt.
class _Merkspeicher implements MapCachingProvider {
  final Map<String, CachedMapTile> inhalt = {};

  @override
  bool get isSupported => true;

  @override
  Future<CachedMapTile?> getTile(String url) async => inhalt[url];

  @override
  Future<void> putTile({
    required String url,
    required CachedMapTileMetadata metadata,
    Uint8List? bytes,
  }) async {
    if (bytes != null) inhalt[url] = (bytes: bytes, metadata: metadata);
  }
}

/// Die Kopfzeilen einer eben angekommenen Kachel: sieben Tage haltbar.
///
/// **Und das Datum wird gerechnet, nicht eingetragen.** flutter_map
/// bestimmt die Frist als `max-age` minus dem Alter, das sich aus `date`
/// ergibt. Ein festes Datum altert also mit der Wanduhr: Sieben Tage
/// nachdem dieser Test geschrieben war, galt seine Kachel beim zweiten
/// Lauf als abgelaufen, wurde erwartungsgemäss neu geholt – und der Test
/// fiel, ohne dass sich am Programm etwas geändert hätte. Ein Test, der
/// vom Kalender abhängt, prüft nicht das Programm.
///
/// [alter] macht die Kachel absichtlich alt, um den anderen Fall zu
/// prüfen.
Map<String, String> _kopfzeilen({Duration alter = Duration.zero}) => {
      'cache-control': 'max-age=604800',
      'date': HttpDate.format(DateTime.now().toUtc().subtract(alter)),
    };

void main() {
  final gebiet = [(sued: 51.9, west: 10.4, nord: 51.95, ost: 10.45)];

  test('holt jede Kachel genau einmal und legt sie ab', () async {
    var abrufe = 0;
    final netz = MockClient((_) async {
      abrufe++;
      return Response.bytes(utf8.encode('kachel'), 200, headers: _kopfzeilen());
    });
    final speicher = _Merkspeicher();
    final staende = await ladeVorrat(gebiet, Kartenstil.topo,
            speicher: speicher, netz: netz, von: 5, bis: 7)
        .toList();

    final letzter = staende.last;
    expect(letzter.fertig, letzter.gesamt);
    expect(letzter.geladen, letzter.gesamt);
    expect(letzter.fehler, 0);
    expect(abrufe, letzter.gesamt);
    expect(speicher.inhalt.length, letzter.gesamt);
  });

  test('überspringt, was schon frisch im Speicher liegt', () async {
    var abrufe = 0;
    final netz = MockClient((_) async {
      abrufe++;
      return Response.bytes(utf8.encode('kachel'), 200, headers: _kopfzeilen());
    });
    final speicher = _Merkspeicher();
    await ladeVorrat(gebiet, Kartenstil.topo,
            speicher: speicher, netz: netz, von: 5, bis: 6)
        .drain<void>();
    final ersteRunde = abrufe;
    expect(ersteRunde, greaterThan(0));

    // Zweiter Lauf: nichts mehr zu tun.
    final zweiter = await ladeVorrat(gebiet, Kartenstil.topo,
            speicher: speicher, netz: netz, von: 5, bis: 6)
        .last;
    expect(abrufe, ersteRunde, reason: 'der zweite Lauf darf nichts kosten');
    expect(zweiter.geladen, 0);
    expect(zweiter.fertig, zweiter.gesamt);
  });

  test('eine abgelaufene Kachel wird sehr wohl neu geholt', () async {
    // Die Kehrseite, und sie stand bisher nur zufällig unter Beobachtung:
    // Übersprungen wird die *frische* Kachel, nicht jede vorhandene. Acht
    // Tage sind älter als die sieben, die `max-age` zugesteht.
    var abrufe = 0;
    var alter = Duration.zero;
    final netz = MockClient((_) async {
      abrufe++;
      return Response.bytes(utf8.encode('kachel'), 200,
          headers: _kopfzeilen(alter: alter));
    });
    final speicher = _Merkspeicher();
    alter = const Duration(days: 8);
    await ladeVorrat(gebiet, Kartenstil.topo,
            speicher: speicher, netz: netz, von: 5, bis: 6)
        .drain<void>();
    final ersteRunde = abrufe;
    expect(ersteRunde, greaterThan(0));
    expect(speicher.inhalt, isNotEmpty, reason: 'abgelegt wurde sie trotzdem');

    final zweiter = await ladeVorrat(gebiet, Kartenstil.topo,
            speicher: speicher, netz: netz, von: 5, bis: 6)
        .last;
    expect(abrufe, ersteRunde * 2, reason: 'alles noch einmal');
    expect(zweiter.geladen, zweiter.gesamt);
  });

  test('ein Fehlschlag bricht den Lauf nicht ab', () async {
    var nummer = 0;
    final netz = MockClient((_) async {
      nummer++;
      // Jede zweite Kachel scheitert.
      if (nummer.isEven) return Response('weg', 404);
      return Response.bytes(utf8.encode('kachel'), 200, headers: _kopfzeilen());
    });
    final speicher = _Merkspeicher();
    final letzter = await ladeVorrat(gebiet, Kartenstil.topo,
            speicher: speicher, netz: netz, von: 5, bis: 6)
        .last;
    expect(letzter.fertig, letzter.gesamt, reason: 'zu Ende gelaufen');
    expect(letzter.fehler, greaterThan(0));
    expect(letzter.geladen, greaterThan(0));
  });

  test('eine geworfene Ausnahme ebenso wenig', () async {
    final netz = MockClient((_) async => throw const FormatException('kaputt'));
    final letzter = await ladeVorrat(gebiet, Kartenstil.topo,
            speicher: _Merkspeicher(), netz: netz, von: 5, bis: 5)
        .last;
    expect(letzter.fertig, letzter.gesamt);
    expect(letzter.geladen, 0);
    expect(letzter.fehler, letzter.gesamt);
  });

  test('eine Kachel ohne brauchbare Kopfzeilen zählt trotzdem als geholt',
      () async {
    // Die Frischerechnung von flutter_map wirft, wenn `max-age` da ist,
    // aber weder `age` noch `date`. Ohne Auffang zählte die Kachel als
    // unerreichbar, obwohl sie längst angekommen war.
    final netz = MockClient((_) async => Response.bytes(
        utf8.encode('kachel'), 200,
        headers: {'cache-control': 'max-age=604800'}));
    final speicher = _Merkspeicher();
    final letzter = await ladeVorrat(gebiet, Kartenstil.topo,
            speicher: speicher, netz: netz, von: 5, bis: 5)
        .last;
    expect(letzter.geladen, letzter.gesamt);
    expect(letzter.fehler, 0);
    expect(speicher.inhalt, isNotEmpty);
  });
}
