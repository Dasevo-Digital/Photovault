import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kern/abgleich/verbindungsdatei.dart';
import 'package:photo_vault/services/tokenablage.dart';

/// Eine Ablage, die nicht antwortet, sondern wirft – etwa ein gesperrter
/// Schlüsselbund.
class _WerfendeAblage implements Tokenablage {
  @override
  Future<void> loesche(String kennung) async {}

  @override
  Future<String?> lies(String kennung) async => null;

  @override
  Future<bool> schreibe(String kennung, String token) async =>
      throw const FileSystemException('Schlüsselbund gesperrt');
}

class _KaputteAblage implements Tokenablage {
  @override
  Future<void> loesche(String kennung) async {}

  @override
  Future<String?> lies(String kennung) async => null;

  @override
  Future<bool> schreibe(String kennung, String token) async => false;
}

/// Das Server-Token im Datenordner der App statt neben der Bibliothek
/// (Issue #111).
void main() {
  late Directory ordner;
  late Directory bibliothek;
  late AppTokenablage ablage;

  setUp(() async {
    ordner = await Directory.systemTemp.createTemp('pv_tokenablage_');
    bibliothek = Directory('${ordner.path}/bibliothek')..createSync();
    ablage = AppTokenablage(Directory('${ordner.path}/app/tokens'));
  });

  tearDown(() async {
    Verbindungsdatei.tokenablage = null;
    await ordner.delete(recursive: true);
  });

  Verbindungsdatei verbindung(String token) => Verbindungsdatei(
    server: Uri.parse('https://fotos.example.org/'),
    konto: 'erika',
    geraet: 'g1',
    token: token,
  );

  Map<String, Object?> datei() =>
      (jsonDecode(File('${bibliothek.path}/verbindung.json').readAsStringSync())
              as Map)
          .cast<String, Object?>();

  List<File> tokendateien() => ablage.ordner.existsSync()
      ? ablage.ordner.listSync().whereType<File>().toList()
      : const [];

  test('ohne Ablage steht das Token wie bisher in der Datei', () async {
    await verbindung('geheim-1').schreibe(bibliothek);
    expect(datei()['token'], 'geheim-1');
    expect(datei().containsKey('tokenkennung'), isFalse);
    expect((await Verbindungsdatei.lies(bibliothek))!.token, 'geheim-1');
  });

  test('mit Ablage: in der Datei nur die Kennung, das Token nur für den '
      'Besitzer lesbar', () async {
    Verbindungsdatei.tokenablage = ablage;
    final v = await verbindung('geheim-2').schreibe(bibliothek);
    expect(datei()['token'], '', reason: 'ältere Fassungen lesen leer');
    expect(datei()['tokenkennung'], v.tokenkennung);
    expect(tokendateien(), hasLength(1));
    expect(tokendateien().single.readAsStringSync(), 'geheim-2');
    if (Platform.isMacOS || Platform.isLinux) {
      expect(tokendateien().single.statSync().mode & 0x1ff, 0x180); // 600
    }
    final gelesen = await Verbindungsdatei.lies(bibliothek);
    expect(gelesen!.token, 'geheim-2');
    // Eine Änderung an der Datei behält die Kennung.
    await gelesen.mitRechenhilfe(true).schreibe(bibliothek);
    expect(datei()['tokenkennung'], v.tokenkennung);
    expect(tokendateien(), hasLength(1));
  });

  test(
    'eine Datei von früher gibt ihr Token beim Lesen an die Ablage ab',
    () async {
      await verbindung('geheim-3').schreibe(bibliothek);
      Verbindungsdatei.tokenablage = ablage;
      final v = await Verbindungsdatei.lies(bibliothek);
      expect(v!.token, 'geheim-3');
      expect(datei()['token'], '');
      expect(await ablage.lies(datei()['tokenkennung']! as String), 'geheim-3');
    },
  );

  // Issue #222: Beim Umzug einer alten Datei scheiterte die Ablage, und
  // der Start blieb hängen – die Verbindung liess sich nicht mehr lesen.
  for (final (name, kaputt) in [
    ('einen Fehler meldet', _KaputteAblage() as Tokenablage),
    ('wirft', _WerfendeAblage()),
  ]) {
    test(
      'eine Datei von früher bleibt lesbar, wenn die Ablage $name',
      () async {
        await verbindung('geheim-9').schreibe(bibliothek);
        final vorher = File(
          '${bibliothek.path}/verbindung.json',
        ).readAsStringSync();
        Verbindungsdatei.tokenablage = kaputt;
        final v = await Verbindungsdatei.lies(bibliothek);
        expect(v, isNotNull);
        expect(v!.token, 'geheim-9');
        expect(v.tokenkennung, isNull, reason: 'es steht weiter in der Datei');
        expect(
          File('${bibliothek.path}/verbindung.json').readAsStringSync(),
          vorher,
          reason: 'unverändert, der nächste Start versucht es erneut',
        );
      },
    );
  }

  test('fehlt das Token in der Ablage, bleibt es leer – die Kopie bleibt '
      'eine Kopie und fragt nach einer Anmeldung', () async {
    Verbindungsdatei.tokenablage = ablage;
    await verbindung('geheim-4').schreibe(bibliothek);
    for (final f in tokendateien()) {
      f.deleteSync();
    }
    final v = await Verbindungsdatei.lies(bibliothek);
    expect(v, isNotNull);
    expect(v!.token, isEmpty);
  });

  test('neu angemeldet: dieselbe Kennung, kein verwaistes Token', () async {
    Verbindungsdatei.tokenablage = ablage;
    final alt = await verbindung('geheim-5').schreibe(bibliothek);
    final neu = await verbindung('geheim-6').schreibe(bibliothek);
    expect(neu.tokenkennung, alt.tokenkennung);
    expect(tokendateien(), hasLength(1));
    expect((await Verbindungsdatei.lies(bibliothek))!.token, 'geheim-6');
  });

  test('Trennen nimmt das Token mit', () async {
    Verbindungsdatei.tokenablage = ablage;
    await verbindung('geheim-7').schreibe(bibliothek);
    await Verbindungsdatei.loesche(bibliothek);
    expect(File('${bibliothek.path}/verbindung.json').existsSync(), isFalse);
    expect(tokendateien(), isEmpty);
  });

  test('eine fremde Kennung bildet keinen Pfad', () async {
    expect(await ablage.schreibe('../../ausbruch', 'x'), isFalse);
    expect(await ablage.lies('../verbindung'), isNull);
    expect(tokendateien(), isEmpty);
  });

  test(
    'ein Fehler der Ablage schreibt das Token nicht in die Bibliothek',
    () async {
      Verbindungsdatei.tokenablage = _KaputteAblage();
      await expectLater(
        verbindung('geheim-8').schreibe(bibliothek),
        throwsA(isA<TokenablageFehler>()),
      );
      expect(File('${bibliothek.path}/verbindung.json').existsSync(), isFalse);
    },
  );

  test(
    'ein Fehler der Ablage lässt eine vorhandene Verbindung unverändert',
    () async {
      await verbindung('altes-token').schreibe(bibliothek);
      final vorher = File(
        '${bibliothek.path}/verbindung.json',
      ).readAsStringSync();
      Verbindungsdatei.tokenablage = _KaputteAblage();
      await expectLater(
        verbindung('neues-token').schreibe(bibliothek),
        throwsA(isA<TokenablageFehler>()),
      );
      expect(
        File('${bibliothek.path}/verbindung.json').readAsStringSync(),
        vorher,
      );
    },
  );
}
