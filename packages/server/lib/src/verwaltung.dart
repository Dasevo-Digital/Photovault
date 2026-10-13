import 'dart:convert';
import 'dart:io';

import 'package:qr/qr.dart';

import 'bibliotheken.dart';
import 'einstellungen.dart';
import 'konten/kontodienst.dart';
import 'konten/passwort.dart';
import 'konten/serverdatenbank.dart';
import 'konten/totp.dart';
import 'konten/tresorschluessel.dart';

const hilfe = '''
Photo Vault Server

  photo_vault_server                     den Server starten
  photo_vault_server konto anlegen NAME [--verwalter] [--totp-spaeter]
  photo_vault_server konto liste
  photo_vault_server konto passwort NAME          neues Passwort, alle Geräte abmelden
  photo_vault_server konto totp-zuruecksetzen NAME
  photo_vault_server konto entsperren NAME        nach zu vielen Fehlversuchen
  photo_vault_server konto geraete NAME
  photo_vault_server konto abmelden NAME (GERÄT | --alle)
  photo_vault_server konto oidc-loesen NAME

Die Einstellungen kommen wie beim Server aus der Umgebung (PV_DATEN …).
Unter Docker: docker exec -it CONTAINER photo_vault_server konto …
''';

/// Die Verwaltung auf der Kommandozeile. Gibt den Rückgabewert des
/// Programms zurück.
///
/// Über die Kommandozeile und nicht über die Schnittstelle, weil das erste
/// Konto entstehen muss, bevor sich jemand anmelden kann – und wer auf der
/// Maschine einen Befehl ausführen darf, darf ohnehin alles.
Future<int> verwalte(List<String> argumente, Einstellungen e) async {
  if (argumente.isEmpty || argumente.first != 'konto' || argumente.length < 2) {
    stdout.write(hilfe);
    return argumente.isEmpty || argumente.first == 'hilfe' ? 0 : 64;
  }
  final sdb = Serverdatenbank.oeffne(e.serverdatenbank);
  final konten = Kontodienst(
    sdb,
    Tresorschluessel.ladeOderLegeAn(e.tresorschluessel),
    totpPflicht: e.totpPflicht,
  );
  try {
    final befehl = argumente[1];
    final rest = argumente.skip(2).toList();
    if (befehl == 'liste') return _liste(konten);
    final namen = rest.where((a) => !a.startsWith('--')).toList();
    if (namen.isEmpty) {
      stderr.writeln('Welches Konto?');
      return 64;
    }
    final name = namen.first;
    if (befehl == 'anlegen') {
      return await _anlegen(
        konten,
        e,
        name,
        verwalter: rest.contains('--verwalter'),
        totpSpaeter: rest.contains('--totp-spaeter'),
      );
    }
    final konto = konten.kontoNamens(name);
    if (konto == null) {
      stderr.writeln('Ein Konto „$name“ gibt es nicht.');
      return 1;
    }
    switch (befehl) {
      case 'passwort':
        final neu = _neuesPasswort();
        if (neu == null) return 1;
        await konten.setzePasswort(konto.id, neu);
        stdout.writeln('Passwort gesetzt, alle Geräte abgemeldet.');
      case 'totp-zuruecksetzen':
        konten.totpZuruecksetzen(konto.id);
        stdout.writeln(
          e.totpPflicht
              ? 'TOTP gelöscht. Die nächste Anmeldung richtet es neu ein.'
              : 'TOTP gelöscht.',
        );
      case 'entsperren':
        konten.entsperre(konto.id);
        stdout.writeln('Entsperrt.');
      case 'geraete':
        for (final g in konten.geraete(konto.id)) {
          stdout.writeln(
            '${g.id}  ${g.name}  zuletzt ${_zeit(g.zuletzt)}'
            '${g.adresse == null ? '' : '  von ${g.adresse}'}',
          );
        }
      case 'abmelden':
        if (rest.contains('--alle')) {
          stdout.writeln('${konten.alleAbmelden(konto.id)} Geräte abgemeldet.');
        } else if (namen.length > 1) {
          final ok = konten.abmelden(konto.id, namen[1]);
          stdout.writeln(ok ? 'Abgemeldet.' : 'Kein solches Gerät.');
          if (!ok) return 1;
        } else {
          stderr.writeln('Welches Gerät? (Kennung oder --alle)');
          return 64;
        }
      case 'oidc-loesen':
        stdout.writeln('${konten.loeseOidc(konto.id)} Verknüpfungen gelöst.');
      default:
        stdout.write(hilfe);
        return 64;
    }
    return 0;
  } on ArgumentError catch (f) {
    stderr.writeln(f.message);
    return 1;
  } on StateError catch (f) {
    stderr.writeln(f.message);
    return 1;
  } finally {
    sdb.schliesse();
  }
}

int _liste(Kontodienst konten) {
  final alle = konten.alle();
  if (alle.isEmpty) {
    stdout.writeln(
      'Noch kein Konto. Anlegen: photo_vault_server konto anlegen NAME',
    );
  }
  for (final k in alle) {
    stdout.writeln(
      '${k.name}${k.verwalter ? ' (Verwalter)' : ''}  '
      'TOTP ${k.hatTotp ? 'ja' : 'nein'}  '
      '${konten.geraete(k.id).length} Geräte  angelegt ${_zeit(k.angelegt)}',
    );
  }
  return 0;
}

Future<int> _anlegen(
  Kontodienst konten,
  Einstellungen e,
  String name, {
  required bool verwalter,
  required bool totpSpaeter,
}) async {
  final erstes = konten.alle().isEmpty;
  final passwort = _neuesPasswort();
  if (passwort == null) return 1;
  final konto = await konten.legeAn(name, passwort, verwalter: verwalter);
  stdout.writeln(
    'Konto „${konto.name}“ angelegt${konto.verwalter ? ' (Verwalter)' : ''}.',
  );
  if (erstes && Bibliotheken.uebernimmStandard(e.bibliotheken, konto.id)) {
    stdout.writeln(
      'Die bisherige Bibliothek (bibliotheken/standard) gehört jetzt diesem '
      'Konto.',
    );
  }
  if (totpSpaeter) {
    stdout.writeln(
      e.totpPflicht
          ? 'TOTP wird bei der ersten Anmeldung eingerichtet.'
          : 'Ohne TOTP.',
    );
    return 0;
  }

  final geheimnis = Totp.neuesGeheimnis();
  final adresse = Totp.adresse(geheimnis, konto.name);
  stdout
    ..writeln()
    ..writeln('Zwei-Faktor-Anmeldung (TOTP): Diesen Code mit einer')
    ..writeln('Authenticator-App einlesen …')
    ..writeln()
    ..write(qrImTerminal(adresse))
    ..writeln()
    ..writeln('… oder das Geheimnis abtippen:')
    ..writeln('  ${_gruppiert(Totp.base32(geheimnis))}')
    ..writeln();
  for (var versuch = 0; versuch < 3; versuch++) {
    stdout.write('Code aus der App: ');
    final code = stdin.readLineSync(encoding: utf8)?.trim() ?? '';
    final codes = await konten.richteTotpEin(konto.id, geheimnis, code);
    if (codes != null) {
      stdout
        ..writeln()
        ..writeln('TOTP eingerichtet. Wiederherstellungscodes – jeder gilt')
        ..writeln('einmal, falls das Telefon fehlt. Jetzt sicher aufbewahren,')
        ..writeln('sie werden nicht noch einmal gezeigt:')
        ..writeln();
      for (final c in codes) {
        stdout.writeln('  $c');
      }
      return 0;
    }
    stdout.writeln('Der Code passt nicht.');
  }
  stdout.writeln(
    'TOTP nicht eingerichtet – das Konto besteht. Die erste Anmeldung '
    'richtet es ein, oder: konto totp-zuruecksetzen und neu anlegen.',
  );
  return 1;
}

/// Fragt zweimal nach dem Passwort, ohne es anzuzeigen. Ohne Terminal
/// (in einem Skript) gilt die erste Zeile der Eingabe.
String? _neuesPasswort() {
  if (!stdin.hasTerminal) {
    final p = stdin.readLineSync(encoding: utf8) ?? '';
    return _taugt(p) ? p : null;
  }
  stdout.write('Passwort (mindestens ${Passwort.mindestlaenge} Zeichen): ');
  stdin.echoMode = false;
  try {
    final p1 = stdin.readLineSync(encoding: utf8) ?? '';
    stdout
      ..writeln()
      ..write('Noch einmal: ');
    final p2 = stdin.readLineSync(encoding: utf8) ?? '';
    stdout.writeln();
    if (p1 != p2) {
      stderr.writeln('Die beiden Eingaben unterscheiden sich.');
      return null;
    }
    return _taugt(p1) ? p1 : null;
  } finally {
    stdin.echoMode = true;
  }
}

bool _taugt(String p) {
  try {
    Kontodienst.pruefeNeuesPasswort(p);
    return true;
  } on ArgumentError catch (f) {
    stderr.writeln(f.message);
    return false;
  }
}

String _gruppiert(String s) => [
  for (var i = 0; i < s.length; i += 4)
    s.substring(i, i + 4 > s.length ? s.length : i + 4),
].join(' ');

String _zeit(DateTime t) => t.toLocal().toString().substring(0, 16);

/// [daten] als QR-Code aus Halbblöcken – zwei Zeilen des Codes je
/// Textzeile, schwarz auf weiss, unabhängig von den Farben des Terminals.
String qrImTerminal(String daten) {
  final bild = QrImage(
    QrCode.fromData(data: daten, errorCorrectLevel: QrErrorCorrectLevel.L),
  );
  const rand = 2;
  final n = bild.moduleCount;
  bool dunkel(int z, int s) =>
      z >= 0 && s >= 0 && z < n && s < n && bild.isDark(z, s);
  const schwarz = 16, weiss = 231;
  final aus = StringBuffer();
  for (var z = -rand; z < n + rand; z += 2) {
    aus.write('  ');
    for (var s = -rand; s < n + rand; s++) {
      final oben = dunkel(z, s) ? schwarz : weiss;
      final unten = dunkel(z + 1, s) ? schwarz : weiss;
      aus.write('\x1b[38;5;${oben}m\x1b[48;5;${unten}m▀');
    }
    aus.writeln('\x1b[0m');
  }
  return aus.toString();
}
