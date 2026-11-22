import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kern/abgleich/kachelumleitung.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:photo_vault_mobil/kachelnetz.dart';
import 'package:photo_vault_mobil/sitzung.dart';

/// Das Telefon holt Kartenkacheln nie selbst beim Anbieter (#469): nur
/// über den eigenen Server, und was der nicht weiterreicht, gar nicht.
void main() {
  final server = Serververbindung(
    Uri.parse('http://heimserver.test/fotos'),
    'pv1_geheim',
  );

  late List<http.Request> abgerufen;
  late Serververbindung? ziel;
  late http.Client netz;

  setUp(() {
    abgerufen = [];
    ziel = null;
    netz = handyKachelnetz(
      server: () => ziel,
      innen: MockClient((r) async {
        abgerufen.add(r);
        return http.Response('', 200);
      }),
    );
  });

  const osm = 'https://tile.openstreetmap.org/3/4/2.png';
  const topo = 'https://tile.opentopomap.org/12/2170/1381.png';

  test('liefert der Server keine Kacheln, wird nichts abgerufen', () async {
    for (final adresse in [osm, topo]) {
      await expectLater(
        netz.get(Uri.parse(adresse)),
        throwsA(isA<KachelNurUeberServer>()),
      );
    }
    expect(abgerufen, isEmpty);
  });

  test('liefert er welche, gehen OSM und OpenTopoMap zu ihm', () async {
    ziel = server;
    await netz.get(Uri.parse(osm));
    await netz.get(Uri.parse(topo));
    expect(
      [for (final r in abgerufen) '${r.url}'],
      [
        'http://heimserver.test/fotos/api/v1/karte/osm/3/4/2.png',
        'http://heimserver.test/fotos/api/v1/karte/topo/12/2170/1381.png',
      ],
    );
    expect(abgerufen.first.headers['authorization'], 'Bearer pv1_geheim');
  });

  test('was der Server nicht weiterreicht, holt das Telefon nie selbst', () async {
    ziel = server;
    for (final adresse in [
      // Höhendaten der Landschaft.
      'https://s3.amazonaws.com/elevation-tiles-prod/terrarium/12/2170/1381.png',
      // Luftbild.
      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/12/1381/2170',
      // CARTO, mit eigenem Schlüssel.
      'https://a.basemaps.cartocdn.com/dark_all/3/4/2.png?key=abc',
      // Eine eigene Kartenquelle.
      'https://kacheln.beispiel.test/3/4/2.png',
      // Wanderwege.
      'https://tile.waymarkedtrails.org/hiking/12/2170/1381.png',
    ]) {
      await expectLater(
        netz.get(Uri.parse(adresse)),
        throwsA(isA<KachelNurUeberServer>()),
        reason: adresse,
      );
    }
    await expectLater(
      netz.post(Uri.parse(osm)),
      throwsA(isA<KachelNurUeberServer>()),
    );
    expect(abgerufen, isEmpty);
  });

  // Ein Widget-Test, weil dort kein Abruf das echte Netz erreicht: Ohne die
  // Sperre käme hier eine Antwort statt des Fehlers.
  testWidgets('die Sitzung ohne Server fragt OpenStreetMap nicht', (
    tester,
  ) async {
    final sitzung = Sitzung();
    addTearDown(sitzung.dispose);
    await tester.runAsync(() async {
      await expectLater(
        sitzung.kachelnetz.get(Uri.parse(osm)),
        throwsA(isA<KachelNurUeberServer>()),
      );
      sitzung.kartenUeberServer = true;
      await expectLater(
        sitzung.kachelnetz.get(Uri.parse(osm)),
        throwsA(isA<KachelNurUeberServer>()),
        reason: 'fähig gemeldet, aber nicht angemeldet',
      );
    });
  });
}
