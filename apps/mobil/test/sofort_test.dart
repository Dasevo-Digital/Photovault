import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault_mobil/sicherung/sofort.dart';
import 'package:photo_vault_mobil/sicherung/stand.dart';

/// Was die Erweiterung unter iOS berichtet (#308) und wie die App auf
/// Plattformen ohne sie reagiert.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('der Bericht liest sich auch ohne die freiwilligen Felder', () {
    final b = Sofortbericht.ausJson({'zeit': 1000});
    expect(b.zeit, DateTime.fromMillisecondsSinceEpoch(1000));
    expect(b.gesichert, 0);
    expect(b.gescheitert, 0);
    expect(b.unterwegs, 0);
    expect(b.fehler, isNull);
  });

  test('der Bericht trägt, was die Erweiterung geschrieben hat', () {
    final b = Sofortbericht.ausJson({
      'zeit': 2000,
      'gesichert': 7,
      'gescheitert': 1,
      'unterwegs': 2,
      'fehler': 'kaputt',
    });
    expect(b.gesichert, 7);
    expect(b.gescheitert, 1);
    expect(b.unterwegs, 2);
    expect(b.fehler, 'kaputt');
  });

  group('unter iOS', () {
    const kanal = MethodChannel('de.dasevo.photovault/gemeinsam');
    final bote =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    Map<Object?, Object?>? werte;

    void antworte(Object? Function() antwort) =>
        bote.setMockMethodCallHandler(kanal, (aufruf) async {
          expect(aufruf.method, 'sofort');
          werte = aufruf.arguments as Map<Object?, Object?>;
          return antwort();
        });

    setUp(() => werte = null);
    tearDown(() => bote.setMockMethodCallHandler(kanal, null));

    test('reicht die Einstellungen weiter', () async {
      antworte(() => 'an');
      final stand = await stelleSofort(
        const Sicherungseinstellungen(
          an: true,
          videos: false,
          nurWlan: false,
          alben: ['a'],
        ),
        serverKann: true,
        ios: true,
      );
      expect(stand, Sofortstand.an);
      expect(werte!['an'], isTrue);
      expect(werte!['videos'], isFalse);
      expect(werte!['nurWlan'], isFalse);
      expect(werte!['alben'], ['a']);
    });

    test('nur beim Laden bleibt die Erweiterung aus', () async {
      antworte(() => 'aus');
      final stand = await stelleSofort(
        const Sicherungseinstellungen(an: true, nurBeimLaden: true),
        serverKann: true,
        ios: true,
      );
      expect(stand, Sofortstand.beimLaden);
      expect(werte!['an'], isFalse);
    });

    test('ein Server ohne die Funktion lässt sie aus', () async {
      antworte(() => 'aus');
      final stand = await stelleSofort(
        const Sicherungseinstellungen(an: true),
        serverKann: false,
        ios: true,
      );
      expect(stand, Sofortstand.server);
      expect(werte!['an'], isFalse);
    });

    test('ausgeschaltet heisst aus', () async {
      antworte(() => 'aus');
      final stand = await stelleSofort(
        const Sicherungseinstellungen(),
        serverKann: true,
        ios: true,
      );
      expect(stand, Sofortstand.aus);
      expect(werte!['an'], isFalse);
    });

    test('sagt, woran es hängt', () async {
      for (final (antwort, stand) in [
        ('zugriff', Sofortstand.zugriff),
        ('system', Sofortstand.system),
        ('Error Domain=PHPhotosErrorDomain', Sofortstand.fehler),
      ]) {
        antworte(() => antwort);
        expect(
          await stelleSofort(
            const Sicherungseinstellungen(an: true),
            serverKann: true,
            ios: true,
          ),
          stand,
        );
      }
    });

    test('ein Fehler des Kanals ist kein Absturz', () async {
      antworte(() => throw PlatformException(code: 'kaputt'));
      expect(
        await stelleSofort(
          const Sicherungseinstellungen(an: true),
          serverKann: true,
          ios: true,
        ),
        Sofortstand.fehler,
      );
    });
  });

  test('ohne Telefon ist nichts eingeschaltet', () async {
    expect(
      await stelleSofort(
        const Sicherungseinstellungen(an: true),
        serverKann: true,
      ),
      Sofortstand.aus,
    );
    expect(await leseSofortbericht(), isNull);
  });
}
