import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:kern/abgleich/anmeldung.dart' show passwortMindestlaenge;
import 'package:kern/db/database.dart';
import 'package:kern/protokoll.dart';
import 'package:kern/services/backup_service.dart';
import 'package:kern/services/vault_crypto.dart';
import 'package:path/path.dart' as p;

import 'bibliotheken.dart';
import 'konten/kontodienst.dart';
import 'konten/tresorschluessel.dart';

/// Wie die Sicherung steht – für die Apps.
enum Sicherungsstufe {
  /// Kein Ziel eingestellt (`PV_SICHERUNG`).
  aus,

  /// Ziel da, aber noch keine Passphrase.
  nichtEingerichtet,

  /// Die Kennmarke fehlt am Ziel: nicht eingehängt, oder ein neues Ziel.
  zielFehlt,

  /// Der letzte Lauf ist gescheitert.
  fehler,

  /// Seit über 36 Stunden kein gelungener Lauf.
  veraltet,
  ok,
}

/// Sichert jede Nacht jede Bibliothek des Servers in [ziel] (Issue #125) –
/// verschlüsselt und im Format der App, also mit ihr wiederherstellbar.
///
/// **Nur, was am Ziel fehlt:** siehe `BackupService.performAutoBackup` mit
/// `amZielPruefen`. Ein neues, leeres Ziel füllt sich von selbst.
///
/// **Nie auf die eigene Platte:** Ist das NAS nicht eingehängt, ist [ziel]
/// ein leerer Ordner auf dem Server – eine Sicherung dorthin füllte still
/// dessen Platte und wäre beim Ausfall des Servers mit verloren. Gesichert
/// wird deshalb nur, wenn dort die Kennmarke liegt, die beim Einrichten
/// entsteht ([markeName]). Für ein neues Ziel legt [zielNeu] sie neu an.
///
/// **Schlüssel:** Die Passphrase verpackt einen zufälligen Hauptschlüssel
/// (Argon2id, wie in der App). Verpackt liegt er in jeder Bibliothek und
/// damit in jeder Sicherung – mit der Passphrase lässt sie sich überall
/// öffnen. Damit der Server nachts ohne Passphrase sichern kann, liegt er
/// zusätzlich mit dem Schlüssel des Servers verschlüsselt im Datenordner,
/// wie die TOTP-Geheimnisse.
class Serversicherung {
  Serversicherung({
    required this.daten,
    required this.ziel,
    required this.tresor,
    required this.konten,
    required this.bibliotheken,
    this.um = (stunde: 3, minute: 30),
    DateTime Function()? uhr,
  }) : _uhr = uhr ?? DateTime.now;

  final Directory daten;

  /// `null`: keine Sicherung eingestellt.
  final Directory? ziel;
  final Tresorschluessel tresor;
  final Kontodienst konten;
  final Bibliotheken bibliotheken;

  /// Wann sie täglich läuft (Ortszeit des Servers).
  final ({int stunde, int minute}) um;
  final DateTime Function() _uhr;

  static const markeName = 'PHOTOVAULT-SICHERUNGSZIEL.json';
  static const _veraltetNach = Duration(hours: 36);

  File get _schluesselDatei =>
      File(p.join(daten.path, 'sicherung-schluessel.json'));
  File get _standDatei => File(p.join(daten.path, 'sicherung-stand.json'));
  File? get _marke => ziel == null ? null : File(p.join(ziel!.path, markeName));

  bool get eingerichtet => _schluesselDatei.existsSync();
  bool get laeuft => _lauf != null;
  Future<void>? _lauf;
  Timer? _wecker;

  /// Legt den Schlüssel an und die Kennmarke am Ziel. Nur einmal: Eine
  /// neue Passphrase hiesse, dass ältere Sicherungen eine andere brauchen.
  Future<void> einrichten(String passphrase) async {
    final z = ziel;
    if (z == null) throw StateError('Kein Sicherungsziel eingestellt.');
    if (eingerichtet) {
      throw StateError('Die Sicherung ist schon eingerichtet.');
    }
    if (passphrase.length < passwortMindestlaenge) {
      throw ArgumentError(
        'Die Passphrase braucht mindestens $passwortMindestlaenge Zeichen.',
      );
    }
    if (!await z.exists()) {
      throw StateError('Das Sicherungsziel ${z.path} gibt es nicht.');
    }
    final w = await VaultCrypto.createMasterKey(passphrase);
    final roh = await w.masterKey.extractBytes();
    await _schreibe(_schluesselDatei, {
      'kdfSalt': base64.encode(w.kdfSalt),
      'nonce': base64.encode(w.nonce),
      'wrapped': base64.encode(w.wrapped),
      'server': await tresor.verschluessele(roh),
      'angelegt': _uhr().toUtc().toIso8601String(),
    });
    await _legeMarkeAn();
    protokoll('Sicherung eingerichtet, Ziel ${z.path}');
  }

  /// Ein neues (leeres) Ziel annehmen: neue Kennmarke. Was fehlt, kommt
  /// beim nächsten Lauf von selbst.
  Future<void> zielNeu() async {
    if (!eingerichtet) {
      throw StateError('Die Sicherung ist nicht eingerichtet.');
    }
    await _legeMarkeAn();
    protokoll('Sicherungsziel neu angenommen: ${ziel!.path}');
  }

  Future<void> _legeMarkeAn() async {
    final z = Random.secure();
    await _schreibe(_marke!, {
      'kennung': [
        for (var i = 0; i < 8; i++) z.nextInt(256).toRadixString(16),
      ].join(),
      'angelegt': _uhr().toUtc().toIso8601String(),
    });
  }

  bool get _markeDa => _marke?.existsSync() ?? false;

  Future<Map<String, Object?>> _lies(File f) async =>
      (jsonDecode(await f.readAsString()) as Map).cast<String, Object?>();

  Future<void> _schreibe(File f, Map<String, Object?> j) async {
    final teil = File('${f.path}.neu');
    await teil.writeAsString(jsonEncode(j), flush: true);
    if (!Platform.isWindows) {
      await Process.run('chmod', ['600', teil.path]);
    }
    await teil.rename(f.path);
  }

  /// Der Stand für die Apps.
  Future<Map<String, Object?>> stand() async {
    final letzter = await _standDatei.exists()
        ? await _lies(_standDatei)
        : const <String, Object?>{};
    return {
      'stufe': (await stufe(letzter)).name,
      'ziel': ziel?.path,
      'eingerichtet': eingerichtet,
      'laeuft': laeuft,
      'um':
          '${um.stunde.toString().padLeft(2, '0')}:'
          '${um.minute.toString().padLeft(2, '0')}',
      'naechster': naechsterLauf().toUtc().toIso8601String(),
      ...letzter,
    };
  }

  Future<Sicherungsstufe> stufe([Map<String, Object?>? letzter]) async {
    if (ziel == null) return Sicherungsstufe.aus;
    if (!eingerichtet) return Sicherungsstufe.nichtEingerichtet;
    if (!_markeDa) return Sicherungsstufe.zielFehlt;
    final l =
        letzter ??
        (await _standDatei.exists() ? await _lies(_standDatei) : const {});
    if (l['ok'] == false) return Sicherungsstufe.fehler;
    // Seit dem letzten Erfolg – oder, vor dem ersten Lauf, seit dem
    // Einrichten: Eine Sicherung, die nie läuft, ist nicht „ok“.
    final seit =
        DateTime.tryParse('${l['letzterErfolg']}') ??
        DateTime.tryParse('${(await _lies(_schluesselDatei))['angelegt']}');
    if (seit == null || _uhr().difference(seit) > _veraltetNach) {
      return Sicherungsstufe.veraltet;
    }
    return Sicherungsstufe.ok;
  }

  DateTime naechsterLauf() {
    final jetzt = _uhr();
    var t = DateTime(jetzt.year, jetzt.month, jetzt.day, um.stunde, um.minute);
    if (!t.isAfter(jetzt)) t = t.add(const Duration(days: 1));
    return t;
  }

  void starte() {
    if (ziel == null) return;
    _plane();
  }

  void _plane() {
    _wecker?.cancel();
    _wecker = Timer(naechsterLauf().difference(_uhr()), () async {
      await jetzt();
      _plane();
    });
  }

  void beende() => _wecker?.cancel();

  /// Sichert jetzt; läuft schon ein Lauf, wartet es auf diesen.
  Future<void> jetzt() => _lauf ??= _laufe().whenComplete(() => _lauf = null);

  Future<void> _laufe() async {
    if (ziel == null || !eingerichtet) return;
    final beginn = _uhr();
    final ergebnis = <Map<String, Object?>>[];
    String? fehler;
    try {
      if (!_markeDa) {
        throw StateError(
          'Am Ziel ${ziel!.path} fehlt die Kennmarke – ist das NAS '
          'eingehängt? Für ein neues, leeres Ziel: „Ziel neu einrichten“.',
        );
      }
      final s = await _lies(_schluesselDatei);
      final schluessel = SecretKey(
        await tresor.entschluessele('${s['server']}'),
      );
      final verpackt = (
        kdfSalt: base64.decode('${s['kdfSalt']}'),
        nonce: base64.decode('${s['nonce']}'),
        wrapped: base64.decode('${s['wrapped']}'),
      );
      for (final k in konten.alle()) {
        final b = (await bibliotheken.fuer(k.id)).bibliothek;
        await _verpackterSchluesselIn(b.db, verpackt);
        final dienst = BackupService(b.db, b.pfade);
        var gesamt = 0, fehlgeschlagen = 0;
        await for (final f in dienst.performAutoBackup(
          p.join(ziel!.path, ordnerFuer(k)),
          schluessel,
          amZielPruefen: true,
        )) {
          gesamt = f.total;
          fehlgeschlagen += f.fehlgeschlagen ?? 0;
        }
        await b.db.setLastAutoBackupAt(_uhr());
        ergebnis.add({
          'konto': k.name,
          'dateien': gesamt,
          'neu': dienst.letzterLaufNeu,
          'fehlgeschlagen': fehlgeschlagen,
        });
        if (fehlgeschlagen > 0) {
          fehler ??= '$fehlgeschlagen Dateien von „${k.name}“ nicht gesichert';
        }
      }
    } catch (e) {
      fehler = '$e';
    }
    final vorher = await _standDatei.exists()
        ? await _lies(_standDatei)
        : const <String, Object?>{};
    final ende = _uhr();
    await _schreibe(_standDatei, {
      'beginn': beginn.toUtc().toIso8601String(),
      'ende': ende.toUtc().toIso8601String(),
      'ok': fehler == null,
      'fehler': ?fehler,
      'konten': ergebnis,
      'letzterErfolg': fehler == null
          ? ende.toUtc().toIso8601String()
          : vorher['letzterErfolg'],
    });
    final neu = ergebnis.fold<int>(0, (n, e) => n + (e['neu']! as int));
    protokoll(
      fehler == null
          ? 'Sicherung fertig nach ${ende.difference(beginn).inSeconds} s: '
                '$neu neue Dateien'
          : 'Sicherung gescheitert: $fehler',
    );
  }

  /// Der verpackte Schlüssel gehört in die Bibliothek – von dort schreibt
  /// die Sicherung ihn als `vault.key` ins Ziel.
  Future<void> _verpackterSchluesselIn(
    AppDatabase db,
    ({Uint8List kdfSalt, Uint8List nonce, Uint8List wrapped}) v,
  ) async {
    final zeile = await db.backupSettingsRow();
    bool gleich(Uint8List? a, Uint8List b) =>
        a != null &&
        a.length == b.length &&
        base64.encode(a) == base64.encode(b);
    if (gleich(zeile?.kdfSalt, v.kdfSalt) &&
        gleich(zeile?.wrappedMasterKeyNonce, v.nonce) &&
        gleich(zeile?.wrappedMasterKey, v.wrapped)) {
      return;
    }
    await db.saveBackupKey(
      kdfSalt: v.kdfSalt,
      nonce: v.nonce,
      wrapped: v.wrapped,
    );
  }

  /// Ein Ordner je Konto: lesbar, und eindeutig, falls ein Name nach dem
  /// Entfernen eines Kontos wieder vergeben wird.
  static String ordnerFuer(Konto k) => '${k.name}_${k.id.substring(0, 8)}';
}
