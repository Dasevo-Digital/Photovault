import 'dart:async';
import 'dart:io';

import 'package:photo_vault_server/photo_vault_server.dart';
import 'package:test/test.dart';

class _PasswortTor extends Passwort {
  _PasswortTor() : super(speicher: 64, durchgaenge: 1);
  Completer<void>? erreicht;
  Completer<void>? weiter;

  @override
  Future<bool> stimmt(String passwort, String pruefwert) async {
    final ok = await super.stimmt(passwort, pruefwert);
    erreicht?.complete();
    await weiter?.future;
    return ok;
  }
}

class _TresorTor extends Tresorschluessel {
  _TresorTor() : super(List.filled(32, 7));
  Completer<void>? erreicht;
  Completer<void>? weiter;

  @override
  Future<List<int>> entschluessele(String text) async {
    final klar = await super.entschluessele(text);
    erreicht?.complete();
    await weiter?.future;
    return klar;
  }
}

List<int> _ausBase32(String s) {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  final aus = <int>[];
  var puffer = 0, bits = 0;
  for (final z in s.split('')) {
    puffer = (puffer << 5) | alphabet.indexOf(z);
    bits += 5;
    if (bits >= 8) {
      aus.add((puffer >> (bits - 8)) & 255);
      bits -= 8;
      puffer &= (1 << bits) - 1;
    }
  }
  return aus;
}

void main() {
  late Serverdatenbank db;
  late Kontodienst konten;
  late DateTime jetzt;
  late _PasswortTor passwortDienst;
  late _TresorTor tresor;
  const passwort = 'synthetisches testpasswort';
  final geheimnis = List<int>.generate(20, (i) => i + 1);

  setUp(() {
    jetzt = DateTime.utc(2026, 10, 27, 12);
    db = Serverdatenbank.imSpeicher();
    passwortDienst = _PasswortTor();
    tresor = _TresorTor();
    konten = Kontodienst(
      db,
      tresor,
      passwort: passwortDienst,
      uhr: () => jetzt,
    );
  });
  tearDown(() => db.schliesse());

  Kontodienst andererDienst() => Kontodienst(
    db,
    Tresorschluessel(List.filled(32, 7)),
    passwort: const Passwort(speicher: 64, durchgaenge: 1),
    uhr: () => jetzt,
  );

  Future<String> vorbereiten() async {
    final k = await konten.legeAn('pruefkonto', passwort);
    await konten.richteTotpEin(
      k.id,
      geheimnis,
      Totp.code(geheimnis, Totp.schritt(jetzt)),
    );
    jetzt = jetzt.add(const Duration(seconds: 30));
    return k.id;
  }

  Future<String> beginnen() async =>
      (await konten.anmelden(
                'pruefkonto',
                passwort,
                geraet: 'Pruefgeraet',
                adresse: '192.0.2.1',
              )
              as TotpNoetig)
          .vorgang;

  for (final gleicherVorgang in [false, true]) {
    test(
      'TOTP gilt parallel einmal, gleicher Vorgang: $gleicherVorgang',
      () async {
        final id = await vorbereiten();
        final a = await beginnen(), b = gleicherVorgang ? a : await beginnen();
        final code = Totp.code(geheimnis, Totp.schritt(jetzt));
        final resultate = await Future.wait([
          konten.bestaetige(a, code, adresse: '192.0.2.1'),
          konten.bestaetige(b, code, adresse: '192.0.2.1'),
        ]);
        expect(resultate.whereType<Angemeldet>(), hasLength(1));
        expect(konten.geraete(id), hasLength(1));
      },
    );
  }

  for (final faktor in [false, true]) {
    test('Rücksetzung widerruft offene Vorgänge, Faktor: $faktor', () async {
      final id = await vorbereiten();
      final a = await beginnen();
      if (faktor) {
        andererDienst().totpZuruecksetzen(id);
      } else {
        await andererDienst().setzePasswort(
          id,
          'anderes synthetisches testpasswort',
        );
      }
      expect(
        await konten.bestaetige(
          a,
          Totp.code(geheimnis, Totp.schritt(jetzt)),
          adresse: '192.0.2.1',
        ),
        isA<Abgewiesen>(),
      );
      expect(konten.geraete(id), isEmpty);
    });
  }

  test('Rücksetzung während einer Passwortprüfung wird erkannt', () async {
    final id = await vorbereiten();
    passwortDienst.erreicht = Completer<void>();
    passwortDienst.weiter = Completer<void>();
    final lauf = konten.anmelden(
      'pruefkonto',
      passwort,
      geraet: 'Pruefgeraet',
      adresse: '192.0.2.1',
    );
    await passwortDienst.erreicht!.future;
    await andererDienst().setzePasswort(
      id,
      'anderes synthetisches testpasswort',
    );
    passwortDienst.weiter!.complete();
    expect(await lauf, isA<Abgewiesen>());
  });

  test('Faktorrücksetzung während der TOTP-Prüfung wird erkannt', () async {
    final id = await vorbereiten();
    final a = await beginnen();
    tresor.erreicht = Completer<void>();
    tresor.weiter = Completer<void>();
    final lauf = konten.bestaetige(
      a,
      Totp.code(geheimnis, Totp.schritt(jetzt)),
      adresse: '192.0.2.1',
    );
    await tresor.erreicht!.future;
    andererDienst().totpZuruecksetzen(id);
    tresor.weiter!.complete();
    expect(await lauf, isA<Abgewiesen>());
    expect(konten.geraete(id), isEmpty);
  });

  test(
    'alte Ersteinrichtung ersetzt keinen inzwischen bestätigten Faktor',
    () async {
      final konto = await konten.legeAn('pruefkonto', passwort);
      Future<TotpEinrichten> beginn() async =>
          await konten.anmelden(
                'pruefkonto',
                passwort,
                geraet: 'Pruefgeraet',
                adresse: '192.0.2.1',
              )
              as TotpEinrichten;
      final a = await beginn(), b = await beginn();
      expect(
        await konten.bestaetige(
          a.vorgang,
          Totp.code(_ausBase32(a.geheimnis), Totp.schritt(jetzt)),
          adresse: '192.0.2.1',
        ),
        isA<Angemeldet>(),
      );
      final vorher = db.db.select('SELECT totp FROM konten WHERE id = ?', [
        konto.id,
      ]).single['totp'];
      expect(
        await konten.bestaetige(
          b.vorgang,
          Totp.code(_ausBase32(b.geheimnis), Totp.schritt(jetzt)),
          adresse: '192.0.2.1',
        ),
        isA<Abgewiesen>(),
      );
      expect(
        db.db.select('SELECT totp FROM konten WHERE id = ?', [
          konto.id,
        ]).single['totp'],
        vorher,
      );
      expect(konten.geraete(konto.id), hasLength(1));
      expect(konten.uebrigeCodes(konto.id), 10);
    },
  );

  test('ein falscher Code verbraucht den Vorgang nicht vorzeitig', () async {
    final id = await vorbereiten();
    final a = await beginnen();
    expect(
      await konten.bestaetige(a, 'kein-code', adresse: '192.0.2.1'),
      isA<Abgewiesen>(),
    );
    expect(
      await konten.bestaetige(
        a,
        Totp.code(geheimnis, Totp.schritt(jetzt)),
        adresse: '192.0.2.1',
      ),
      isA<Angemeldet>(),
    );
    expect(konten.geraete(id), hasLength(1));
  });

  test(
    'TOTP wird auch über getrennte Datenbankverbindungen nur einmal verbraucht',
    () async {
      final ordner = await Directory.systemTemp.createTemp(
        'pv_konten_parallel_',
      );
      final datei = File('${ordner.path}/server.sqlite');
      final bankA = Serverdatenbank.oeffne(datei);
      final bankB = Serverdatenbank.oeffne(datei);
      Kontodienst dienst(Serverdatenbank bank) => Kontodienst(
        bank,
        Tresorschluessel(List.filled(32, 7)),
        passwort: const Passwort(speicher: 64, durchgaenge: 1),
        uhr: () => jetzt,
      );
      final a = dienst(bankA), b = dienst(bankB);
      try {
        final konto = await a.legeAn('pruefkonto', passwort);
        await a.richteTotpEin(
          konto.id,
          geheimnis,
          Totp.code(geheimnis, Totp.schritt(jetzt)),
        );
        jetzt = jetzt.add(const Duration(seconds: 30));
        Future<TotpNoetig> beginn(Kontodienst k) async =>
            await k.anmelden(
                  'pruefkonto',
                  passwort,
                  geraet: 'Pruefgeraet',
                  adresse: '192.0.2.1',
                )
                as TotpNoetig;
        final va = await beginn(a), vb = await beginn(b);
        final code = Totp.code(geheimnis, Totp.schritt(jetzt));
        final resultate = await Future.wait([
          a.bestaetige(va.vorgang, code, adresse: '192.0.2.1'),
          b.bestaetige(vb.vorgang, code, adresse: '192.0.2.1'),
        ]);
        expect(resultate.whereType<Angemeldet>(), hasLength(1));
        expect(a.geraete(konto.id), hasLength(1));
        final offen = await beginn(a);
        await b.setzePasswort(konto.id, 'anderes synthetisches testpasswort');
        jetzt = jetzt.add(const Duration(seconds: 30));
        expect(
          await a.bestaetige(
            offen.vorgang,
            Totp.code(geheimnis, Totp.schritt(jetzt)),
            adresse: '192.0.2.1',
          ),
          isA<Abgewiesen>(),
        );
        expect(a.geraete(konto.id), isEmpty);
      } finally {
        bankB.schliesse();
        bankA.schliesse();
        await ordner.delete(recursive: true);
      }
    },
  );

  test('Serverdatenbank 3 wird mit vorhandenen Konten auf 4 gehoben', () async {
    final ordner = await Directory.systemTemp.createTemp(
      'pv_konten_migration_',
    );
    final datei = File('${ordner.path}/server.sqlite');
    var dateibank = Serverdatenbank.oeffne(datei);
    try {
      dateibank.db.execute(
        "INSERT INTO konten (id, name, angelegt) VALUES ('konto', 'pruefkonto', 1)",
      );
      dateibank.db.execute('ALTER TABLE konten DROP COLUMN anmelde_stand');
      dateibank.db.execute('PRAGMA user_version = 3');
      dateibank.schliesse();
      dateibank = Serverdatenbank.oeffne(datei);
      expect(
        dateibank.db
            .select('SELECT name, anmelde_stand FROM konten')
            .single['anmelde_stand'],
        0,
      );
      expect(dateibank.db.select('PRAGMA user_version').single.columnAt(0), 4);
    } finally {
      dateibank.schliesse();
      await ordner.delete(recursive: true);
    }
  });
}
