import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:photo_vault/services/kachelmitschnitt.dart';
import 'package:photo_vault/widgets/mini_location_map.dart';

/// Fährt im gebauten Programm dieselbe Zoomfahrt, die der Betrieb macht –
/// an den echten Kachelservern, mit dem Mitschnitt mitlaufend.
///
/// **Wozu.** Von aussen standen 5702 TLS-Verbindungen gegen 496
/// angekommene Kacheln. Der Widget-Prüfstand mit untergeschobenem
/// Anbieter macht dieselbe Bewegung mit 1,0 Abrufen je Kachel – er kann
/// die Frage also gar nicht beantworten, weil bei ihm kein Netz im Spiel
/// ist. Hier ist es echt: echter `HttpClient`, echter TLS-Handschlag,
/// echter Server.
///
/// **Zurückhaltung ist Teil des Tests.** Die Kachelserver werden
/// gespendet. Deshalb ein einziger Durchgang über wenige Zoomstufen und
/// nicht die dreissig Sekunden, die von Hand gefahren wurden.
///
/// ```
/// flutter test integration_test/kachelmitschnitt_messung_test.dart -d macos \
///   --dart-define=PV_MESS_KACHELN=1
/// ```
const _an = bool.fromEnvironment('PV_MESS_KACHELN');

/// Ein Fenster in der Grössenordnung, in der von Hand gezoomt wurde –
/// die Zahl der gleichzeitig sichtbaren Kacheln hängt daran.
const _fenster = Size(1400, 900);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Zoomfahrt an echten Kachelservern', (tester) async {
    // **Erst den Kachelspeicher leeren.** Sonst misst der zweite Lauf
    // nichts: Was einmal da ist, kommt aus dem Speicher und nie mehr am
    // Netz an – beim ersten Versuch standen deshalb lauter Nullen da.
    // Das ist genau das dokumentierte Verhalten des Mitschnitts, aber
    // eine Zoomfahrt lässt sich so nicht messen.
    await tester.runAsync(() =>
        BuiltInMapCachingProvider.getOrCreateInstance().destroy(deleteCache: true));
    kartenSpeicherEinrichten();
    await tester.binding.setSurfaceSize(_fenster);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final steuerung = MapController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: FlutterMap(
          mapController: steuerung,
          options: const MapOptions(
            initialCenter: ll.LatLng(51.0, 10.0),
            initialZoom: 5,
          ),
          children: const [Kachelschicht(stil: Kartenstil.topo)],
        ),
      ),
    ));

    Kachelmitschnitt.instanz.starte();
    addTearDown(Kachelmitschnitt.instanz.halteAn);

    // Hinein und wieder heraus, in halben Stufen – so, wie ein Mausrad
    // es tut. Nach jedem Schritt echte Zeit, damit die Abrufe wirklich
    // laufen können; `pump` allein bewegt nur die Uhr des Prüfstands.
    for (final stufe in [
      ...[5.5, 6.0, 6.5, 7.0, 7.5, 8.0],
      ...[7.5, 7.0, 6.5, 6.0, 5.5, 5.0],
    ]) {
      steuerung.move(const ll.LatLng(51.0, 10.0), stufe);
      await tester.pump();
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 900)));
      await tester.pump();
    }
    // Nachlauf: Was noch unterwegs ist, soll ankommen dürfen.
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 4)));
    await tester.pump();

    final b = Kachelmitschnitt.instanz.bilanz;
    // ignore: avoid_print
    print('\n=== Kachelmitschnitt ===\n${berichtAus(Kachelmitschnitt.instanz)
        .split('\nAbrufe:\n')
        .first}\n');

    // Es ist eine Messung, keine Behauptung – belegt wird nur, dass das
    // Messgerät im gebauten Programm überhaupt etwas sieht. Die Zahlen
    // stehen oben und werden gelesen, nicht eingefordert.
    expect(b.abrufe, greaterThan(0));
    expect(b.adressen, greaterThan(0));
  }, skip: !_an);
}
