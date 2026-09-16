// ignore_for_file: avoid_print
// Holt die Landschaft ihre Kacheln wirklich aus demselben Speicher wie
// die Karte?
//
// Befund der 15. Prüfrunde: Sie tat es nicht. Sie holte dieselben
// OpenTopoMap-Bilder mit einem blanken http.Client – also ein zweites
// Mal, obwohl die Routenkarte einen Knopfdruck vorher schon dieselben
// Kacheln geladen und auf die Platte gelegt hatte. Beim nächsten Öffnen
// derselben Wanderung ein drittes Mal. Und ohne Netz: gar nichts,
// während die Karte daneben ihre Kacheln von der Platte nahm.
//
// Im Unittest ist das nicht prüfbar – der Speicher braucht
// `path_provider` und damit Plattformkanäle. Der Unittest
// `test/gelaende_kachelspeicher_test.dart` prüft dieselbe Logik gegen
// einen gestellten Speicher; hier steht die Gegenprobe am echten.
import 'dart:io';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:photo_vault/services/gelaende_laden.dart';
import 'package:photo_vault/widgets/mini_location_map.dart';

/// Zählt mit, wie oft wirklich ein Server gefragt wird.
class _ZaehlenderClient extends http.BaseClient {
  final http.Client _innen = http.Client();
  var abrufe = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest anfrage) {
    abrufe++;
    return _innen.send(anfrage);
  }

  @override
  void close() => _innen.close();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('beim zweiten Oeffnen kommt die Landschaft von der Platte',
      (tester) async {
    kartenSpeicherEinrichten();
    expect(BuiltInMapCachingProvider.getOrCreateInstance().isSupported, isTrue,
        reason: 'ohne Speicher hat die Messung keinen Gegenstand');

    // Ein kleiner Ausschnitt im Harz – wenige Kacheln, echte Höhen.
    const sued = 51.780, west = 10.590, nord = 51.810, ost = 10.640;

    final erste = _ZaehlenderClient();
    final u = Stopwatch()..start();
    final gitter = await ladeHoehengitter(
        sued: sued, west: west, nord: nord, ost: ost, netz: erste);
    final karte = await ladeKartenbild(
        sued: sued, west: west, nord: nord, ost: ost, netz: erste);
    final tErste = u.elapsedMilliseconds;
    erste.close();

    expect(gitter, isNotNull, reason: 'ohne Netz ist nichts zu messen');
    print('1. Oeffnen: ${erste.abrufe} Abrufe, $tErste ms');
    karte?.dispose();

    // Zweites Öffnen – ein frischer Client, wie ihn ein neu geöffneter
    // Bildschirm auch anlegt. Der Speicher ist derselbe.
    final zweite = _ZaehlenderClient();
    u.reset();
    final gitter2 = await ladeHoehengitter(
        sued: sued, west: west, nord: nord, ost: ost, netz: zweite);
    final karte2 = await ladeKartenbild(
        sued: sued, west: west, nord: nord, ost: ost, netz: zweite);
    final tZweite = u.elapsedMilliseconds;
    zweite.close();

    print('2. Oeffnen: ${zweite.abrufe} Abrufe, $tZweite ms');
    expect(gitter2, isNotNull);
    expect(karte2, isNotNull);
    karte2?.dispose();

    expect(zweite.abrufe, 0,
        reason: 'das zweite Oeffnen darf keinen Server mehr fragen');
    expect(tZweite, lessThan(tErste),
        reason: 'von der Platte muss schneller sein als aus dem Netz');
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('ohne Netz gilt, was auf der Platte liegt', (tester) async {
    kartenSpeicherEinrichten();
    // Derselbe Ausschnitt wie oben – die Kacheln liegen jetzt dort.
    const sued = 51.780, west = 10.590, nord = 51.810, ost = 10.640;

    final gitter = await ladeHoehengitter(
        sued: sued,
        west: west,
        nord: nord,
        ost: ost,
        netz: _OhneNetz());
    expect(gitter, isNotNull,
        reason: 'wer unterwegs keinen Empfang hat, soll seine Wanderung '
            'trotzdem im Gelaende sehen');
  }, timeout: const Timeout(Duration(minutes: 2)));
}

/// Ein Client, der sich verhält wie ein Gerät im Funkloch.
class _OhneNetz extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest anfrage) =>
      Future.error(const SocketException('kein Netz (Probe)'));
}
