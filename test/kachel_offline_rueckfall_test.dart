// **Ohne Netz bleibt grau, was laengst auf der Platte liegt.**
//
// flutter_map liest die Kachel, sieht die abgelaufene Haltbarkeit, fragt
// den Server – und wirft, wenn keine Antwort kommt. Die Bilddaten hat es
// zu diesem Zeitpunkt bereits in der Hand und sieht sie nicht mehr an.
// Fuer ein vorgeladenes Gebiet heisst das: Am einunddreissigsten Tag ist
// es ohne Netz wertlos (der Vorrat wird mit `kartenKachelFrische`
// geschrieben, also dreissig Tagen).
//
// Geprueft wird der Rueckfall und ebenso seine drei Grenzen – ein
// Rueckfall, der immer zuschlaegt, waere schlimmer als keiner.
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:photo_vault/widgets/mini_location_map.dart';

const _adresse = 'https://kacheln.example/12/2148/1370.png';

/// Ein Speicher, der genau eine Kachel kennt – und mitschreibt, was
/// jemand hineinschreiben will.
class _Platte implements MapCachingProvider {
  _Platte({this.haelt = true, this.wirftBeimLesen = false, this.bild});

  bool haelt;
  bool wirftBeimLesen;

  /// Was auf der Platte liegt; ohne Angabe drei Zaehlbytes.
  Uint8List? bild;
  final geschrieben = <({String url, bool mitBilddaten})>[];

  @override
  bool get isSupported => true;

  @override
  Future<CachedMapTile?> getTile(String url) async {
    if (wirftBeimLesen) throw const FormatException('kaputte Datei');
    if (!haelt || url != _adresse) return null;
    return (
      metadata: CachedMapTileMetadata(
        // Abgelaufen: genau der Fall, in dem flutter_map nachfragt.
        staleAt: DateTime.timestamp().subtract(const Duration(days: 1)),
        lastModified: null,
        etag: null,
      ),
      bytes: bild ?? Uint8List.fromList(const [1, 2, 3]),
    );
  }

  @override
  Future<void> putTile({
    required String url,
    required CachedMapTileMetadata metadata,
    Uint8List? bytes,
  }) async {
    geschrieben.add((url: url, mitBilddaten: bytes != null));
  }
}

/// Ein Client, der auf Ansage scheitert oder antwortet.
class _Netz extends BaseClient {
  _Netz(this.verhalten);

  /// Was beim Abruf passieren soll.
  Object Function() verhalten;
  var abrufe = 0;

  @override
  Future<StreamedResponse> send(BaseRequest anfrage) async {
    abrufe++;
    final was = verhalten();
    if (was is StreamedResponse) return was;
    throw was;
  }
}

StreamedResponse _antwort(int status, BaseRequest? anfrage) => StreamedResponse(
      const Stream<List<int>>.empty(),
      status,
      request: anfrage,
    );

void main() {
  test('ohne Netz antwortet die Platte mit 304', () async {
    final platte = _Platte();
    final lager = FragmentloserSpeicher(platte);
    final netz = _Netz(() => ClientException('Aborted: no response within 15 s',
        Uri.parse(_adresse)));

    final antwort = await Offlinerueckfall(netz, lager)
        .send(Request('GET', Uri.parse(_adresse)));

    expect(antwort.statusCode, 304,
        reason: 'flutter_map nimmt bei 304 die Bilddaten, die es schon hat');
    expect(netz.abrufe, 1);
  });

  test('liegt nichts auf der Platte, fliegt der Fehler weiter', () async {
    final lager = FragmentloserSpeicher(_Platte(haelt: false));
    final netz = _Netz(() => ClientException('kein Netz'));

    await expectLater(
      Offlinerueckfall(netz, lager).send(Request('GET', Uri.parse(_adresse))),
      throwsA(isA<ClientException>()),
    );
  });

  test('ein unlesbarer Eintrag zaehlt wie keiner', () async {
    final lager = FragmentloserSpeicher(_Platte(wirftBeimLesen: true));
    final netz = _Netz(() => ClientException('kein Netz'));

    await expectLater(
      Offlinerueckfall(netz, lager).send(Request('GET', Uri.parse(_adresse))),
      throwsA(isA<ClientException>()),
      reason: 'sonst verschluckte der Rueckfall den eigentlichen Fehler',
    );
  });

  test('ein geplanter Abbruch bekommt keine alte Kachel nachgeschoben',
      () async {
    final lager = FragmentloserSpeicher(_Platte());
    final netz = _Netz(() => RequestAbortedException(Uri.parse(_adresse)));

    await expectLater(
      Offlinerueckfall(netz, lager).send(Request('GET', Uri.parse(_adresse))),
      throwsA(isA<RequestAbortedException>()),
      reason: 'die Kachel ist aus dem Bild gelaufen, niemand will sie noch',
    );
  });

  test('ein Fehlerstatus bleibt ein Fehlerstatus', () async {
    // OpenTopoMap meldet mit 404, dass eine Kachel noch gerendert wird.
    // Wuerde hier die alte Kachel als Erfolg gelten, liefe die
    // Nachfass-Staffel nie an und die fertige Kachel kaeme nie.
    final lager = FragmentloserSpeicher(_Platte());
    final anfrage = Request('GET', Uri.parse(_adresse));
    final netz = _Netz(() => _antwort(404, anfrage));

    final antwort = await Offlinerueckfall(netz, lager).send(anfrage);
    expect(antwort.statusCode, 404);
  });

  test('die Haltbarkeit wird nach einem Rueckfall NICHT aufgefrischt',
      () async {
    // Die 304 kam von uns, nicht vom Server. Niemand hat bestaetigt, dass
    // die Kachel noch gilt – sie bekaeme sonst dreissig weitere Tage,
    // ohne je nachgefragt worden zu sein.
    final platte = _Platte();
    final lager = FragmentloserSpeicher(platte);
    final netz = _Netz(() => ClientException('kein Netz'));

    await Offlinerueckfall(netz, lager).send(Request('GET', Uri.parse(_adresse)));
    await lager.putTile(
      url: _adresse,
      metadata: CachedMapTileMetadata(
          staleAt: DateTime.timestamp().add(const Duration(days: 30)),
          lastModified: null,
          etag: null),
      bytes: null,
    );

    expect(platte.geschrieben, isEmpty);
  });

  test('eine echte 304 vom Server frischt weiterhin auf', () async {
    // Ohne diesen Unterschied waere die Marke ein Holzhammer: Dann
    // schriebe auch der Server nie mehr eine Haltbarkeit fort.
    final platte = _Platte();
    final lager = FragmentloserSpeicher(platte);

    await lager.putTile(
      url: '$_adresse#1',
      metadata: CachedMapTileMetadata(
          staleAt: DateTime.timestamp().add(const Duration(days: 30)),
          lastModified: null,
          etag: null),
      bytes: null,
    );

    expect(platte.geschrieben, hasLength(1));
    expect(platte.geschrieben.single.url, _adresse,
        reason: 'der Nachfass-Anhang gehoert nicht in den Speicherschluessel');
  });

  test('Bilddaten werden auch nach einem Rueckfall geschrieben', () async {
    final platte = _Platte();
    final lager = FragmentloserSpeicher(platte);
    final netz = _Netz(() => ClientException('kein Netz'));

    await Offlinerueckfall(netz, lager).send(Request('GET', Uri.parse(_adresse)));
    await lager.putTile(
      url: _adresse,
      metadata: CachedMapTileMetadata(
          staleAt: DateTime.timestamp().add(const Duration(days: 30)),
          lastModified: null,
          etag: null),
      bytes: Uint8List.fromList(const [9]),
    );

    expect(platte.geschrieben, hasLength(1));
    expect(platte.geschrieben.single.mitBilddaten, isTrue);
  });

  testWidgets('und flutter_map zeigt die Kachel dann wirklich',
      (tester) async {
    // Der eigentliche Nachweis. Die sieben Pruefungen darueber messen den
    // Rueckfall fuer sich; ob flutter_map eine 304 ohne Rumpf auch
    // annimmt und die Bilddaten von der Platte nimmt, steht damit noch
    // nicht fest – und genau daran haengt alles.
    late final Uint8List png;
    await tester.runAsync(() async {
      final aufnahme = ui.PictureRecorder();
      Canvas(aufnahme)
          .drawRect(const Rect.fromLTWH(0, 0, 4, 4), Paint()..color = const Color(0xFF2266AA));
      final bild = await aufnahme.endRecording().toImage(4, 4);
      png = (await bild.toByteData(format: ui.ImageByteFormat.png))!
          .buffer
          .asUint8List();
    });

    final platte = _Platte(bild: png);
    final lager = FragmentloserSpeicher(platte);
    final netz = _Netz(() => ClientException('kein Netz'));
    final anbieter = Nachfassanbieter(
        httpClient: Offlinerueckfall(netz, lager), lager: lager);

    final schicht = TileLayer(
      urlTemplate: 'https://kacheln.example/{z}/{x}/{y}.png',
      tileProvider: anbieter,
    );
    final bildquelle = anbieter.getImageWithCancelLoadingSupport(
        const TileCoordinates(2148, 1370, 12), schicht, Completer<void>().future);

    ui.Image? angekommen;
    Object? gescheitert;
    await tester.runAsync(() async {
      final fertig = Completer<void>();
      bildquelle.resolve(ImageConfiguration.empty).addListener(
            ImageStreamListener(
              (info, _) {
                angekommen = info.image;
                if (!fertig.isCompleted) fertig.complete();
              },
              onError: (fehler, _) {
                gescheitert = fehler;
                if (!fertig.isCompleted) fertig.complete();
              },
            ),
          );
      await fertig.future;
    });

    expect(gescheitert, isNull);
    expect(angekommen, isNotNull);
    expect(angekommen!.width, 4);
    expect(platte.geschrieben, isEmpty,
        reason: 'die Haltbarkeit darf der Rueckfall nicht auffrischen');
  });
}
