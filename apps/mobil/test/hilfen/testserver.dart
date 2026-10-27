import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:kern/abgleich/anmeldung.dart';
import 'package:kern/abgleich/tus.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:path/path.dart' as p;

/// Ein echter Server-Prozess aus packages/server mit dem Konto `erika`
/// (ohne TOTP) und eigenen Daten in [ordner].
class Testserver {
  Testserver._(this.ordner, this._prozess, this.adresse);

  static const passwort = 'ein langes passwort';
  static const _serverOrdner = '../../packages/server';

  final Directory ordner;
  final Process _prozess;
  final Uri adresse;

  /// Startet einen Server – **einen nach dem anderen**.
  ///
  /// Die Testdateien laufen gleichzeitig, und mehrere von ihnen starten
  /// einen Server. Zwei `dart run` im selben Paket übersetzen zugleich in
  /// dessen `.dart_tool`, und ab und zu scheiterte dann das Anlegen des
  /// Kontos – etwa jeder fünfte Lauf, auch im pre-push-Hook und in der CI
  /// (#238). Eine Dateisperre reiht die Starts auf; laufen dürfen die
  /// Server danach nebeneinander.
  static Future<Testserver> starte(String praefix) async {
    final ordner = Directory.systemTemp.createTempSync(praefix);
    final umgebung = {
      'PV_DATEN': p.join(ordner.path, 'server'),
      'PV_PORT': '0',
      'PV_TOTP': 'frei',
    };
    final sperre = await File(
      p.join(_serverOrdner, '.dart_tool', 'pv_testserver.sperre'),
    ).open(mode: FileMode.append);
    await sperre.lock(FileLock.blockingExclusive);
    try {
      final anlegen = await Process.start(
        'dart',
        [
          'run',
          'bin/photo_vault_server.dart',
          'konto',
          'anlegen',
          'erika',
          '--totp-spaeter',
        ],
        workingDirectory: _serverOrdner,
        environment: umgebung,
      );
      final ausgabe = StringBuffer();
      final mitlesen = [
        anlegen.stdout.transform(utf8.decoder).forEach(ausgabe.write),
        anlegen.stderr.transform(utf8.decoder).forEach(ausgabe.write),
      ];
      anlegen.stdin.writeln(passwort);
      await anlegen.stdin.close();
      final ende = await anlegen.exitCode;
      await Future.wait(mitlesen);
      if (ende != 0) {
        // Mit der Ausgabe – vorher stand hier nur der Satz, und warum es
        // scheiterte, war nicht mehr zu erfahren.
        throw StateError('Konto ließ sich nicht anlegen ($ende):\n$ausgabe');
      }
      final prozess = await Process.start(
        'dart',
        ['run', 'bin/photo_vault_server.dart'],
        workingDirectory: _serverOrdner,
        environment: umgebung,
      );
      final bereit = Completer<Uri>();
      prozess.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((z) {
            final m = RegExp(r'auf (http://127\.0\.0\.1:\d+)').firstMatch(z);
            if (m != null && !bereit.isCompleted) {
              bereit.complete(Uri.parse('${m.group(1)}/'));
            }
          });
      prozess.stderr.drain<void>();
      final adresse = await bereit.future.timeout(const Duration(seconds: 60));
      return Testserver._(ordner, prozess, adresse);
    } finally {
      await sperre.unlock();
      await sperre.close();
    }
  }

  Future<String> anmelden(String geraet) async {
    final a = Anmeldung(adresse);
    final s = await a.anmelden('erika', passwort, geraet: geraet);
    a.schliesse();
    return (s as AnmeldungFertig).token;
  }

  Future<Serververbindung> verbinde(String geraet) async =>
      Serververbindung(adresse, await anmelden(geraet));

  /// Ein kleines JPEG in [ordner]/eingang.
  File jpeg(String name, int farbe) {
    final bild = img.Image(width: 64, height: 48);
    img.fill(bild, color: img.ColorRgb8(farbe, 120, 255 - farbe));
    return File(p.join(ordner.path, 'eingang', name))
      ..createSync(recursive: true)
      ..writeAsBytesSync(img.encodeJpg(bild));
  }

  /// Lädt [datei] über [v] hoch, wie es ein anderes Gerät täte.
  static Future<Map<String, String>> hochladen(
    Serververbindung v,
    File datei,
  ) => TusHochladen(
    v,
  ).lade(datei, 'api/v1/hochladen', {'filename': p.basename(datei.path)});

  Future<void> beende() async {
    _prozess.kill(ProcessSignal.sigint);
    await _prozess.exitCode.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        _prozess.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
    ordner.deleteSync(recursive: true);
  }
}
