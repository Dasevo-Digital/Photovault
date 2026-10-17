import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Womit eine Bibliothek verbunden ist – `verbindung.json` neben ihrer
/// `library.sqlite`. Gibt es die Datei, ist die Bibliothek die Kopie einer
/// Bibliothek auf dem Server.
///
/// Das Token steht mit darin, nur für den Besitzer lesbar. Wer es hat, kann
/// sich als dieses Gerät anmelden, bis es abgemeldet wird (auf einem
/// anderen Gerät oder auf dem Server mit `konto abmelden`).
class Verbindungsdatei {
  const Verbindungsdatei({
    required this.server,
    required this.konto,
    required this.geraet,
    required this.token,
    this.rechenhilfe = false,
    this.zwischenspeicherMb,
    this.rasterspalten,
  });

  /// Die Adresse des Servers, z. B. `https://fotos.example.de/`.
  final Uri server;
  final String konto;
  final String geraet;
  final String token;

  /// Rechnet dieser Rechner für den Server mit (siehe `Rechenhilfe`)?
  final bool rechenhilfe;

  /// Wie viele MB Vorschauen und Originale hier liegen dürfen (siehe
  /// `Zwischenspeicher`); `null` heisst Vorgabe, 0 heisst ohne Grenze.
  final int? zwischenspeicherMb;

  /// Wie viele Spalten das Raster auf diesem Gerät zeigt (Zwei-Finger-
  /// Geste in der Handy-App); `null` heisst Vorgabe.
  final int? rasterspalten;

  Verbindungsdatei _mit({
    bool? rechenhilfe,
    int? Function()? zwischenspeicherMb,
    int? Function()? rasterspalten,
  }) => Verbindungsdatei(
    server: server,
    konto: konto,
    geraet: geraet,
    token: token,
    rechenhilfe: rechenhilfe ?? this.rechenhilfe,
    zwischenspeicherMb: zwischenspeicherMb == null
        ? this.zwischenspeicherMb
        : zwischenspeicherMb(),
    rasterspalten: rasterspalten == null ? this.rasterspalten : rasterspalten(),
  );

  Verbindungsdatei mitRechenhilfe(bool an) => _mit(rechenhilfe: an);

  Verbindungsdatei mitZwischenspeicher(int? mb) =>
      _mit(zwischenspeicherMb: () => mb);

  Verbindungsdatei mitRasterspalten(int? n) => _mit(rasterspalten: () => n);

  static File _datei(Directory bibliothek) =>
      File(p.join(bibliothek.path, 'verbindung.json'));

  /// Die Verbindung der Bibliothek in [bibliothek] – `null`, wenn sie für
  /// sich steht.
  static Future<Verbindungsdatei?> lies(Directory bibliothek) async {
    final f = _datei(bibliothek);
    if (!await f.exists()) return null;
    final j = jsonDecode(await f.readAsString()) as Map;
    return Verbindungsdatei(
      server: Uri.parse(j['server'] as String),
      konto: j['konto'] as String,
      geraet: j['geraet'] as String,
      token: j['token'] as String,
      rechenhilfe: j['rechenhilfe'] == true,
      zwischenspeicherMb: (j['zwischenspeicherMb'] as num?)?.toInt(),
      rasterspalten: (j['rasterspalten'] as num?)?.toInt(),
    );
  }

  Future<void> schreibe(Directory bibliothek) async {
    final f = _datei(bibliothek);
    await f.parent.create(recursive: true);
    final teil = File('${f.path}.neu');
    await teil.create();
    // Auf dem Telefon darf eine App kein Programm starten (auf dem iPhone
    // hing die Anmeldung daran); dort schützt ohnehin ihr eigener Ordner.
    if (Platform.isMacOS || Platform.isLinux) {
      await Process.run('chmod', ['600', teil.path]);
    }
    await teil.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'server': '$server',
        'konto': konto,
        'geraet': geraet,
        'token': token,
        if (rechenhilfe) 'rechenhilfe': true,
        if (zwischenspeicherMb != null)
          'zwischenspeicherMb': zwischenspeicherMb,
        if (rasterspalten != null) 'rasterspalten': rasterspalten,
      }),
      flush: true,
    );
    await teil.rename(f.path);
  }

  static Future<void> loesche(Directory bibliothek) async {
    final f = _datei(bibliothek);
    if (await f.exists()) await f.delete();
  }
}
