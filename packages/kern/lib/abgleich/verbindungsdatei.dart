import 'dart:convert';
import 'dart:io';
import 'dart:math' show Random;

import 'package:path/path.dart' as p;

import 'rechenzeit.dart';

/// Womit eine Bibliothek verbunden ist – `verbindung.json` neben ihrer
/// `library.sqlite`. Gibt es die Datei, ist die Bibliothek die Kopie einer
/// Bibliothek auf dem Server.
///
/// Das Token steht mit darin, nur für den Besitzer lesbar – es sei denn,
/// die App hat eine [Tokenablage] eingetragen (Issue #111). Dann steht in
/// der Datei nur noch eine Kennung, und das Token liegt dort. Lässt es sich
/// dort nicht sicher ablegen, scheitert das Schreiben; es fällt nicht auf
/// Klartext neben einer womöglich externen Bibliothek zurück. Der Grund:
/// Am Rechner liegt die Bibliothek oft auf einer externen Platte, und wer
/// die an einen anderen Rechner steckt, hätte sonst das Token mit. Wer es
/// hat, kann sich als dieses Gerät anmelden, bis es abgemeldet wird (auf
/// einem anderen Gerät oder auf dem Server mit `konto abmelden`).
/// Wo das Token liegt, wenn nicht in der Datei: am Rechner im eigenen
/// Datenordner der App, später vielleicht im Schlüsselbund.
abstract interface class Tokenablage {
  Future<String?> lies(String kennung);

  /// `false`, wenn es nicht ging. Die Verbindungsdatei darf das Token dann
  /// nicht ersatzweise selbst speichern.
  Future<bool> schreibe(String kennung, String token);

  Future<void> loesche(String kennung);
}

/// Die getrennte Ablage konnte ein Server-Token nicht sicher übernehmen.
/// Der sichtbare Text entsteht erst in der Oberfläche, in ihrer Sprache.
class TokenablageFehler implements Exception {
  const TokenablageFehler();

  @override
  String toString() => 'pv_tokenablage_schreiben';
}

class Verbindungsdatei {
  /// Die Ablage dieser App – einmal beim Start gesetzt, sonst steht das
  /// Token in der Datei (Handy: deren Ordner ist ohnehin nur der App).
  static Tokenablage? tokenablage;

  const Verbindungsdatei({
    required this.server,
    required this.konto,
    required this.geraet,
    required this.token,
    this.rechenhilfe = false,
    this.rechenzeit = Rechenzeit.amNetz,
    this.zwischenspeicherMb,
    this.rasterspalten,
    this.sortierung,
    this.form,
    this.nurMonate = false,
    this.liste = false,
    this.gliederung,
    this.listenspalten,
    this.sprache,
    this.tokenkennung,
  });

  /// Unter welcher Kennung das Token in der [tokenablage] liegt – `null`,
  /// solange es in der Datei steht.
  final String? tokenkennung;

  /// Die Adresse des Servers, z. B. `https://fotos.example.de/`.
  final Uri server;
  final String konto;
  final String geraet;
  final String token;

  /// Rechnet dieser Rechner für den Server mit (siehe `Rechenhilfe`)?
  final bool rechenhilfe;

  /// Wann er dafür rechnen darf (#120).
  final Rechenzeit rechenzeit;

  /// Wie viele MB Vorschauen und Originale hier liegen dürfen (siehe
  /// `Zwischenspeicher`); `null` heisst Vorgabe, 0 heisst ohne Grenze.
  final int? zwischenspeicherMb;

  /// Wie viele Spalten das Raster auf diesem Gerät zeigt (Zwei-Finger-
  /// Geste in der Handy-App); `null` heisst Vorgabe.
  final int? rasterspalten;

  /// Die Ansicht der Zeitleiste auf diesem Gerät (Issue #194), wie am
  /// Rechner: die Reihenfolge (Index in `Rastersortierung`), die Form
  /// (Index in `Zeitleistenform`) und ob nur nach Monaten gegliedert wird.
  /// `null` heisst Vorgabe.
  final int? sortierung;
  final int? form;
  final bool nurMonate;

  /// Liste statt Raster (Issue #195), wonach sie gegliedert ist (Index in
  /// `ListenGruppierung`) und welche Spalten sie zeigt
  /// (`Listenspaltenwahl.alsText`).
  final bool liste;
  final int? gliederung;
  final String? listenspalten;

  /// Die Sprache der Handy-App (`de`, `en`), wie in den Einstellungen
  /// gewählt; `null` heisst: die des Telefons. Gilt nur für dieses Gerät –
  /// wie die Sprachwahl im Browser.
  final String? sprache;

  Verbindungsdatei _mit({
    bool? rechenhilfe,
    Rechenzeit? rechenzeit,
    int? Function()? zwischenspeicherMb,
    int? Function()? rasterspalten,
    int? Function()? sortierung,
    int? Function()? form,
    bool? nurMonate,
    bool? liste,
    int? Function()? gliederung,
    String? Function()? listenspalten,
    String? Function()? sprache,
  }) => Verbindungsdatei(
    server: server,
    konto: konto,
    geraet: geraet,
    token: token,
    rechenhilfe: rechenhilfe ?? this.rechenhilfe,
    rechenzeit: rechenzeit ?? this.rechenzeit,
    zwischenspeicherMb: zwischenspeicherMb == null
        ? this.zwischenspeicherMb
        : zwischenspeicherMb(),
    rasterspalten: rasterspalten == null ? this.rasterspalten : rasterspalten(),
    sortierung: sortierung == null ? this.sortierung : sortierung(),
    form: form == null ? this.form : form(),
    nurMonate: nurMonate ?? this.nurMonate,
    liste: liste ?? this.liste,
    gliederung: gliederung == null ? this.gliederung : gliederung(),
    listenspalten: listenspalten == null ? this.listenspalten : listenspalten(),
    sprache: sprache == null ? this.sprache : sprache(),
    tokenkennung: tokenkennung,
  );

  Verbindungsdatei mitRechenhilfe(bool an) => _mit(rechenhilfe: an);

  Verbindungsdatei mitRechenzeit(Rechenzeit z) => _mit(rechenzeit: z);

  Verbindungsdatei mitZwischenspeicher(int? mb) =>
      _mit(zwischenspeicherMb: () => mb);

  Verbindungsdatei mitRasterspalten(int? n) => _mit(rasterspalten: () => n);

  Verbindungsdatei mitAnsicht({
    int? sortierung,
    int? form,
    bool? nurMonate,
    bool? liste,
    int? gliederung,
    String? listenspalten,
  }) => _mit(
    sortierung: sortierung == null ? null : () => sortierung,
    form: form == null ? null : () => form,
    nurMonate: nurMonate,
    liste: liste,
    gliederung: gliederung == null ? null : () => gliederung,
    listenspalten: listenspalten == null ? null : () => listenspalten,
  );

  Verbindungsdatei mitSprache(String? s) => _mit(sprache: () => s);

  static File _datei(Directory bibliothek) =>
      File(p.join(bibliothek.path, 'verbindung.json'));

  /// Die Verbindung der Bibliothek in [bibliothek] – `null`, wenn sie für
  /// sich steht.
  static Future<Verbindungsdatei?> lies(Directory bibliothek) async {
    final f = _datei(bibliothek);
    if (!await f.exists()) return null;
    final j = jsonDecode(await f.readAsString()) as Map;
    final kennung = j['tokenkennung'] as String?;
    final ablage = tokenablage;
    // Liegt das Token in der Ablage und fehlt es dort (anderer Rechner,
    // gelöschter Datenordner), bleibt es leer: Der Server antwortet dann
    // mit 401, und die App fragt nach einer neuen Anmeldung – statt die
    // Kopie für eine eigenständige Bibliothek zu halten.
    final token = kennung == null
        ? j['token'] as String? ?? ''
        : await ablage?.lies(kennung) ?? '';
    final v = Verbindungsdatei(
      server: Uri.parse(j['server'] as String),
      konto: j['konto'] as String,
      geraet: j['geraet'] as String,
      token: token,
      rechenhilfe: j['rechenhilfe'] == true,
      rechenzeit:
          Rechenzeit.values.asNameMap()[j['rechenzeit']] ?? Rechenzeit.amNetz,
      zwischenspeicherMb: (j['zwischenspeicherMb'] as num?)?.toInt(),
      rasterspalten: (j['rasterspalten'] as num?)?.toInt(),
      sortierung: (j['sortierung'] as num?)?.toInt(),
      form: (j['form'] as num?)?.toInt(),
      nurMonate: j['nurMonate'] == true,
      liste: j['liste'] == true,
      gliederung: (j['gliederung'] as num?)?.toInt(),
      listenspalten: j['listenspalten'] as String?,
      sprache: j['sprache'] as String?,
      tokenkennung: kennung,
    );
    // Eine Datei von früher, mit dem Token darin: Es zieht in die Ablage.
    if (kennung == null && ablage != null && token.isNotEmpty) {
      return v.schreibe(bibliothek);
    }
    return v;
  }

  /// Schreibt die Datei – das Token in die [tokenablage], wenn es eine
  /// gibt und sie es nimmt. Gibt zurück, was jetzt gilt (mit der Kennung,
  /// unter der das Token liegt).
  Future<Verbindungsdatei> schreibe(Directory bibliothek) async {
    final f = _datei(bibliothek);
    final ablage = tokenablage;
    var kennung = tokenkennung;
    if (ablage != null && token.isNotEmpty) {
      // Eine neue Anmeldung ersetzt das alte Token unter derselben Kennung,
      // statt es verwaist in der Ablage zu lassen.
      kennung ??= await _kennungIn(f);
      final neu = kennung ?? _neueKennung();
      if (!await ablage.schreibe(neu, token)) {
        throw const TokenablageFehler();
      }
      kennung = neu;
    }
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
        // Leer, wenn es in der Ablage liegt: Eine ältere Fassung der App
        // liest so ein leeres Token, bekommt 401 und fragt nach einer
        // Anmeldung, statt am fehlenden Feld abzubrechen.
        'token': kennung == null ? token : '',
        'tokenkennung': ?kennung,
        if (rechenhilfe) 'rechenhilfe': true,
        if (rechenzeit != Rechenzeit.amNetz) 'rechenzeit': rechenzeit.name,
        if (zwischenspeicherMb != null)
          'zwischenspeicherMb': zwischenspeicherMb,
        if (rasterspalten != null) 'rasterspalten': rasterspalten,
        if (sortierung != null) 'sortierung': sortierung,
        if (form != null) 'form': form,
        if (nurMonate) 'nurMonate': true,
        if (liste) 'liste': true,
        if (gliederung != null) 'gliederung': gliederung,
        if (listenspalten != null) 'listenspalten': listenspalten,
        if (sprache != null) 'sprache': sprache,
      }),
      flush: true,
    );
    await teil.rename(f.path);
    return Verbindungsdatei(
      server: server,
      konto: konto,
      geraet: geraet,
      token: token,
      rechenhilfe: rechenhilfe,
      rechenzeit: rechenzeit,
      zwischenspeicherMb: zwischenspeicherMb,
      rasterspalten: rasterspalten,
      sortierung: sortierung,
      form: form,
      nurMonate: nurMonate,
      liste: liste,
      gliederung: gliederung,
      listenspalten: listenspalten,
      sprache: sprache,
      tokenkennung: kennung,
    );
  }

  static Future<String?> _kennungIn(File f) async {
    try {
      if (!await f.exists()) return null;
      final k = (jsonDecode(await f.readAsString()) as Map)['tokenkennung'];
      return k is String ? k : null;
    } catch (_) {
      return null;
    }
  }

  static String _neueKennung() {
    final r = Random.secure();
    return [
      for (var i = 0; i < 16; i++)
        r.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
  }

  static Future<void> loesche(Directory bibliothek) async {
    final f = _datei(bibliothek);
    if (!await f.exists()) return;
    try {
      final kennung =
          (jsonDecode(await f.readAsString()) as Map)['tokenkennung'];
      if (kennung is String) await tokenablage?.loesche(kennung);
    } catch (_) {
      // Eine kaputte Datei geht trotzdem weg.
    }
    await f.delete();
  }
}
