import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kern/abgleich/rechenhilfe.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:kern/abgleich/verbindungsdatei.dart';
import 'package:kern/auswertung/rechenhilfe.dart' show Rechenart;
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/services/rechnerzustand.dart';

/// Die Rechenhilfe rechnet auf Laptops nur am Netzteil, auf Wunsch nur
/// unbenutzt (#120).
void main() {
  late Directory ordner;

  setUp(() => ordner = Directory.systemTemp.createTempSync('pv_rechenzeit_'));
  tearDown(() => ordner.deleteSync(recursive: true));

  group('rechenpause', () {
    const kurz = Duration(seconds: 20);
    const lang = Duration(minutes: 9);

    test('„immer“ pausiert nie', () {
      expect(
        rechenpause(Rechenzeit.immer, amNetz: false, ohneEingabe: kurz),
        isNull,
      );
    });

    test('„am Netz“ pausiert nur auf Akku', () {
      expect(
        rechenpause(Rechenzeit.amNetz, amNetz: false, ohneEingabe: lang),
        Rechenpause.akku,
      );
      expect(
        rechenpause(Rechenzeit.amNetz, amNetz: true, ohneEingabe: kurz),
        isNull,
      );
    });

    test('„unbenutzt“ wartet zusätzlich auf Ruhe an Maus und Tastatur', () {
      expect(
        rechenpause(Rechenzeit.unbenutzt, amNetz: true, ohneEingabe: kurz),
        Rechenpause.inBenutzung,
      );
      expect(
        rechenpause(Rechenzeit.unbenutzt, amNetz: true, ohneEingabe: lang),
        isNull,
      );
      expect(
        rechenpause(Rechenzeit.unbenutzt, amNetz: false, ohneEingabe: lang),
        Rechenpause.akku,
      );
    });

    test('was sich nicht sagen lässt, hält nicht auf', () {
      expect(
        rechenpause(Rechenzeit.unbenutzt, amNetz: null, ohneEingabe: null),
        isNull,
      );
    });
  });

  test('die Rechenzeit steht in verbindung.json, die Vorgabe nicht', () async {
    final v = Verbindungsdatei(
      server: Uri.parse('https://fotos.example/'),
      konto: 'k',
      geraet: 'g',
      token: 't',
      rechenhilfe: true,
    );
    expect(v.rechenzeit, Rechenzeit.amNetz);
    await v.schreibe(ordner);
    final roh = File(p.join(ordner.path, 'verbindung.json')).readAsStringSync();
    expect(jsonDecode(roh), isNot(contains('rechenzeit')));

    await v.mitRechenzeit(Rechenzeit.unbenutzt).schreibe(ordner);
    final gelesen = (await Verbindungsdatei.lies(ordner))!;
    expect(gelesen.rechenzeit, Rechenzeit.unbenutzt);
    expect(gelesen.rechenhilfe, isTrue);
  });

  test('pausiert, ohne nach Aufträgen zu fragen, und rechnet danach', () async {
    final anfragen = <String>[];
    final verbindung = Serververbindung(
      Uri.parse('https://fotos.example/'),
      't',
      client: MockClient((r) async {
        anfragen.add(r.url.path);
        return http.Response(jsonEncode({'auftraege': <Object>[]}), 200);
      }),
    );
    Rechenpause? grund = Rechenpause.akku;
    final hilfe = Rechenhilfe(
      verbindung,
      await StoragePaths.forTesting(Directory(p.join(ordner.path, 'lib'))),
      arten: () => {Rechenart.texterkennung},
      teile: () => const {},
      rechne: (_, _) async => null,
      pausiert: () => grund,
      ruhe: const Duration(milliseconds: 20),
    );
    final staende = <Rechenhilfestand>[];
    final abo = hilfe.stand.listen(staende.add);
    hilfe.starte();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(anfragen, isEmpty, reason: 'auf Akku fragt sie gar nicht erst');
    expect(staende.last.lage, Rechenhilfelage.pausiert);
    expect(staende.last.pause, Rechenpause.akku);

    grund = null;
    hilfe.wecke();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(anfragen, contains('/api/v1/rechnen/auftraege'));
    expect(staende.last.lage, Rechenhilfelage.wartet);
    await hilfe.schliesse();
    await abo.cancel();
  });

  group('Netzteil unter Linux', () {
    Directory eintrag(String name, Map<String, String> werte) {
      final d = Directory(p.join(ordner.path, 'strom', name))
        ..createSync(recursive: true);
      for (final MapEntry(:key, :value) in werte.entries) {
        File(p.join(d.path, key)).writeAsStringSync('$value\n');
      }
      return d;
    }

    Directory strom() => Directory(p.join(ordner.path, 'strom'));

    test('am Netz, auf Akku, ganz ohne Akku', () {
      eintrag('BAT0', {'type': 'Battery'});
      final ac = eintrag('AC', {'type': 'Mains', 'online': '1'});
      expect(Rechnerzustand.amNetzteilLinux(strom()), isTrue);
      File(p.join(ac.path, 'online')).writeAsStringSync('0\n');
      expect(Rechnerzustand.amNetzteilLinux(strom()), isFalse);

      strom().deleteSync(recursive: true);
      eintrag('hidpp_battery_0', {'type': 'Battery'}); // eine Funkmaus
      expect(
        Rechnerzustand.amNetzteilLinux(strom()),
        isNull,
        reason: 'nur ein Akku, kein Netzteil: nicht zu sagen',
      );

      strom().deleteSync(recursive: true);
      strom().createSync();
      expect(Rechnerzustand.amNetzteilLinux(strom()), isTrue);
      expect(
        Rechnerzustand.amNetzteilLinux(Directory(p.join(ordner.path, 'x'))),
        isNull,
      );
    });
  });

  test('macOS antwortet über IOKit und CoreGraphics', () {
    expect(Rechnerzustand.amNetzteil(), isNotNull);
    final ruhe = Rechnerzustand.ohneEingabe();
    expect(ruhe, isNotNull);
    expect(ruhe!.isNegative, isFalse);
  }, skip: Platform.isMacOS ? false : 'nur unter macOS');
}
