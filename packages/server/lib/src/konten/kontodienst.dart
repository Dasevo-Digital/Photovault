import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../freigaben.dart';
import 'package:kern/abgleich/anmeldung.dart' show kontonameGueltig;
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

import 'bremse.dart';
import 'passwort.dart';
import 'serverdatenbank.dart';
import 'totp.dart';
import 'tresorschluessel.dart';

/// Ein Konto auf dem Server – mit eigener Bibliothek.
class Konto {
  const Konto({
    required this.id,
    required this.name,
    required this.verwalter,
    required this.hatPasswort,
    required this.hatTotp,
    required this.angelegt,
    this.gesperrtBis,
  });

  final String id;
  final String name;
  final bool verwalter;
  final bool hatPasswort;
  final bool hatTotp;
  final DateTime angelegt;

  /// Nach zu vielen Fehlversuchen gesperrt bis dann.
  final DateTime? gesperrtBis;

  static Konto _aus(Row z) => Konto(
    id: z['id'] as String,
    name: z['name'] as String,
    verwalter: z['verwalter'] == 1,
    hatPasswort: z['passwort'] != null,
    hatTotp: z['totp'] != null,
    angelegt: DateTime.fromMillisecondsSinceEpoch(z['angelegt'] as int),
    gesperrtBis: z['gesperrt_bis'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(z['gesperrt_bis'] as int),
  );
}

/// Ein angemeldetes Gerät: ein Token, einzeln abmeldbar.
class Geraet {
  const Geraet({
    required this.id,
    required this.konto,
    required this.name,
    required this.angelegt,
    required this.zuletzt,
    this.adresse,
  });

  final String id;
  final String konto;
  final String name;
  final DateTime angelegt;
  final DateTime zuletzt;
  final String? adresse;

  Map<String, Object?> alsJson() => {
    'id': id,
    'name': name,
    'angelegt': angelegt.toUtc().toIso8601String(),
    'zuletzt': zuletzt.toUtc().toIso8601String(),
    'adresse': adresse,
  };

  static Geraet _aus(Row z) => Geraet(
    id: z['id'] as String,
    konto: z['konto'] as String,
    name: z['name'] as String,
    angelegt: DateTime.fromMillisecondsSinceEpoch(z['angelegt'] as int),
    zuletzt: DateTime.fromMillisecondsSinceEpoch(z['zuletzt'] as int),
    adresse: z['adresse'] as String?,
  );
}

/// Was eine Anmeldung ergab.
sealed class Anmeldeergebnis {
  const Anmeldeergebnis();
}

/// Fertig: Das Gerät ist angemeldet und bekommt sein [token].
final class Angemeldet extends Anmeldeergebnis {
  const Angemeldet(this.token, this.geraet, {this.wiederherstellungscodes});

  /// Nur jetzt im Klartext zu sehen; der Server hält nur den Prüfwert.
  final String token;
  final Geraet geraet;

  /// Gesetzt, wenn TOTP gerade eingerichtet wurde – einmal zu zeigen.
  final List<String>? wiederherstellungscodes;
}

/// Passwort stimmt, jetzt den Code aus der Authenticator-App.
final class TotpNoetig extends Anmeldeergebnis {
  const TotpNoetig(this.vorgang);
  final String vorgang;
}

/// Passwort stimmt, aber TOTP ist Pflicht und noch nicht eingerichtet:
/// [adresse] als QR-Code zeigen, dann den ersten Code schicken.
final class TotpEinrichten extends Anmeldeergebnis {
  const TotpEinrichten(this.vorgang, this.geheimnis, this.adresse);
  final String vorgang;

  /// Base32, zum Abtippen.
  final String geheimnis;

  /// `otpauth://…` für den QR-Code.
  final String adresse;
}

/// Abgewiesen. Mit [warte], wenn gebremst wurde.
final class Abgewiesen extends Anmeldeergebnis {
  const Abgewiesen({this.warte});
  final Duration? warte;
}

/// Eine angefangene Anmeldung zwischen Passwort und Code.
class _Vorgang {
  _Vorgang(this.konto, this.geraet, this.ablauf, {this.neuesGeheimnis});
  final String konto;
  final String geraet;
  final DateTime ablauf;
  final List<int>? neuesGeheimnis;
  var fehlversuche = 0;
}

/// Konten, Anmeldung und Geräte.
///
/// **Ablauf einer Anmeldung.** Name und Passwort; stimmen sie, folgt der
/// Code aus der Authenticator-App (oder ein Wiederherstellungscode). Erst
/// dann bekommt das Gerät ein Token, das es von da an bei jeder Anfrage
/// mitschickt. Ist TOTP Pflicht ([totpPflicht], die Vorgabe) und noch nicht
/// eingerichtet, richtet die erste Anmeldung es ein.
///
/// **Tokens** sind 256 Bit Zufall. In der Datenbank steht nur ihr SHA-256 –
/// wer die Datenbank liest, kann sich damit nicht anmelden. Ein Gerät, das
/// [geraetAblauf] lang nicht da war, ist abgemeldet.
class Kontodienst {
  Kontodienst(
    this._sdb,
    this._tresor, {
    this.passwort = const Passwort(),
    this.totpPflicht = true,
    this.geraetAblauf = const Duration(days: 180),
    DateTime Function()? uhr,
    Bremse? bremse,
  }) : _uhr = uhr ?? DateTime.now,
       bremse = bremse ?? Bremse(uhr: uhr);

  final Serverdatenbank _sdb;
  final Tresorschluessel _tresor;
  final Passwort passwort;
  final bool totpPflicht;
  final Duration geraetAblauf;
  final Bremse bremse;
  final DateTime Function() _uhr;

  Database get _db => _sdb.db;

  /// Die Freigaben nach aussen – in derselben Serverdatenbank, mit
  /// demselben Schlüssel und denselben Passwortprüfwerten.
  late final freigaben = Freigabedienst(
    _sdb,
    _tresor,
    passwort: passwort,
    uhr: _uhr,
  );

  final _vorgaenge = <String, _Vorgang>{};
  static const _vorgangDauer = Duration(minutes: 5);
  static const _vorgangVersuche = 5;

  /// Höchstens so viele Passwortprüfungen zugleich: Jede belegt 19 MiB.
  final _ampel = _Ampel(2);

  // --- Konten ------------------------------------------------------------

  List<Konto> alle() => [
    for (final z in _db.select('SELECT * FROM konten ORDER BY angelegt'))
      Konto._aus(z),
  ];

  Konto? konto(String id) {
    final z = _db.select('SELECT * FROM konten WHERE id = ?', [id]);
    return z.isEmpty ? null : Konto._aus(z.first);
  }

  /// Ob es schon ein Konto gibt – vorher lässt sich das erste über die App
  /// anlegen (siehe `Anmeldungsapi.einrichten`).
  bool get eingerichtet =>
      _db.select('SELECT 1 FROM konten LIMIT 1').isNotEmpty;

  Konto? kontoNamens(String name) {
    final z = _db.select('SELECT * FROM konten WHERE name = ?', [name.trim()]);
    return z.isEmpty ? null : Konto._aus(z.first);
  }

  /// Ein neues Konto. Das erste ist Verwalter, gleich was [verwalter] sagt.
  ///
  /// Mit [nurAlsErstes] nur, solange es noch keines gibt – geprüft
  /// unmittelbar vor dem Eintragen, ohne Pause dazwischen: Zwei, die
  /// zugleich einrichten, bekommen nicht beide ein Verwalterkonto.
  Future<Konto> legeAn(
    String name,
    String passwortKlartext, {
    bool verwalter = false,
    bool nurAlsErstes = false,
  }) async {
    final n = name.trim();
    if (!kontonameGueltig(n)) {
      throw ArgumentError(
        'Der Name braucht 2 bis 40 Buchstaben, Ziffern, Punkt, Strich '
        'oder Unterstrich.',
      );
    }
    pruefeNeuesPasswort(passwortKlartext);
    if (kontoNamens(n) != null) {
      throw StateError('Ein Konto „$n“ gibt es schon.');
    }
    final pruefwert = await _ampel.mit(
      () => passwort.pruefwertFuer(passwortKlartext),
    );
    final id = const Uuid().v4();
    final erstes = !eingerichtet;
    if (nurAlsErstes && !erstes) {
      throw StateError('Der Server ist schon eingerichtet.');
    }
    if (kontoNamens(n) != null) {
      throw StateError('Ein Konto „$n“ gibt es schon.');
    }
    _db.execute(
      'INSERT INTO konten (id, name, passwort, verwalter, angelegt) '
      'VALUES (?, ?, ?, ?, ?)',
      [
        id,
        n,
        pruefwert,
        (verwalter || erstes) ? 1 : 0,
        _uhr().millisecondsSinceEpoch,
      ],
    );
    return konto(id)!;
  }

  /// Wirft, wenn [p] als neues Passwort nicht taugt.
  static void pruefeNeuesPasswort(String p) {
    if (p.length < Passwort.mindestlaenge) {
      throw ArgumentError(
        'Das Passwort braucht mindestens ${Passwort.mindestlaenge} Zeichen.',
      );
    }
  }

  /// Setzt ein neues Passwort und meldet alle Geräte ab: Wer das Passwort
  /// neu setzen muss, weiss oft nicht, wer es noch kennt.
  Future<void> setzePasswort(String kontoId, String neu) async {
    pruefeNeuesPasswort(neu);
    final pruefwert = await _ampel.mit(() => passwort.pruefwertFuer(neu));
    _db.execute(
      'UPDATE konten SET passwort = ?, fehlversuche = 0, gesperrt_bis = NULL '
      'WHERE id = ?',
      [pruefwert, kontoId],
    );
    alleAbmelden(kontoId);
  }

  /// Ändert das Passwort auf Wunsch des Nutzers: mit dem alten und, wenn
  /// eingerichtet, einem Code. Die anderen Geräte bleiben angemeldet, wenn
  /// [andereAbmelden] es nicht anders sagt.
  Future<bool> aenderePasswort(
    String kontoId,
    String alt,
    String neu, {
    String? code,
    String? behalteGeraet,
    bool andereAbmelden = false,
  }) async {
    pruefeNeuesPasswort(neu);
    final z = _zeile(kontoId);
    if (z == null) return false;
    final bisher = z['passwort'] as String?;
    if (bisher == null ||
        !await _ampel.mit(() => passwort.stimmt(alt, bisher))) {
      _fehlschlag(kontoId);
      return false;
    }
    if (z['totp'] != null) {
      if (code == null || !await _pruefeZweitenFaktor(kontoId, code)) {
        _fehlschlag(kontoId);
        return false;
      }
    }
    final pruefwert = await _ampel.mit(() => passwort.pruefwertFuer(neu));
    _db.execute('UPDATE konten SET passwort = ? WHERE id = ?', [
      pruefwert,
      kontoId,
    ]);
    if (andereAbmelden) {
      _db.execute('DELETE FROM geraete WHERE konto = ? AND id IS NOT ?', [
        kontoId,
        behalteGeraet,
      ]);
    }
    return true;
  }

  /// Entfernt das Konto samt Geräten, Codes und Verknüpfungen. Seine
  /// Bibliothek legt `Bibliotheken.legeBeiseite` beiseite – die gehört nicht
  /// hierher.
  void entferne(String kontoId) {
    _vorgaenge.removeWhere((_, v) => v.konto == kontoId);
    _db.execute('DELETE FROM konten WHERE id = ?', [kontoId]);
  }

  void entsperre(String kontoId) => _db.execute(
    'UPDATE konten SET fehlversuche = 0, gesperrt_bis = NULL WHERE id = ?',
    [kontoId],
  );

  /// Löscht TOTP und Wiederherstellungscodes. Die nächste Anmeldung
  /// richtet es neu ein, wenn es Pflicht ist.
  void totpZuruecksetzen(String kontoId) {
    _db.execute(
      'UPDATE konten SET totp = NULL, totp_letzter_schritt = 0 WHERE id = ?',
      [kontoId],
    );
    _db.execute('DELETE FROM wiederherstellung WHERE konto = ?', [kontoId]);
  }

  /// Richtet TOTP für [kontoId] mit [geheimnis] ein, wenn [code] dazu
  /// passt, und gibt die Wiederherstellungscodes zurück – `null`, wenn
  /// der Code nicht passt.
  Future<List<String>?> richteTotpEin(
    String kontoId,
    List<int> geheimnis,
    String code,
  ) async {
    final schritt = Totp.pruefe(geheimnis, code, _uhr());
    if (schritt == null) return null;
    _db.execute(
      'UPDATE konten SET totp = ?, totp_letzter_schritt = ? WHERE id = ?',
      [await _tresor.verschluessele(geheimnis), schritt, kontoId],
    );
    return neueWiederherstellungscodes(kontoId);
  }

  // --- Anmeldung ---------------------------------------------------------

  /// Erster Schritt: Name und Passwort.
  Future<Anmeldeergebnis> anmelden(
    String name,
    String passwortKlartext, {
    required String geraet,
    required String adresse,
  }) async {
    final warte = bremse.wartezeit(adresse);
    if (warte != null) return Abgewiesen(warte: warte);

    final z = _db.select('SELECT * FROM konten WHERE name = ?', [name.trim()]);
    if (z.isEmpty) {
      final bis = bremse.unbekanntGesperrtBis(name);
      if (bis != null) return Abgewiesen(warte: bis.difference(_uhr()));
      await _ampel.mit(() => passwort.rechneUmsonst(passwortKlartext));
      bremse.unbekanntFehlschlag(name);
      bremse.fehlschlag(adresse);
      return const Abgewiesen();
    }
    final zeile = z.first;
    final kontoId = zeile['id'] as String;
    final gesperrt = zeile['gesperrt_bis'] as int?;
    if (gesperrt != null && gesperrt > _uhr().millisecondsSinceEpoch) {
      return Abgewiesen(
        warte: Duration(milliseconds: gesperrt - _uhr().millisecondsSinceEpoch),
      );
    }
    final pruefwert = zeile['passwort'] as String?;
    final stimmt = pruefwert == null
        ? await _ampel.mit(() async {
            await passwort.rechneUmsonst(passwortKlartext);
            return false;
          })
        : await _ampel.mit(() => passwort.stimmt(passwortKlartext, pruefwert));
    if (!stimmt) {
      _fehlschlag(kontoId);
      bremse.fehlschlag(adresse);
      return const Abgewiesen();
    }
    if (passwort.veraltet(pruefwert!)) {
      final neu = await _ampel.mit(
        () => passwort.pruefwertFuer(passwortKlartext),
      );
      _db.execute('UPDATE konten SET passwort = ? WHERE id = ?', [
        neu,
        kontoId,
      ]);
    }

    _raeumeVorgaengeAuf();
    final vorgang = _zufallstext(24);
    if (zeile['totp'] != null) {
      _vorgaenge[vorgang] = _Vorgang(
        kontoId,
        geraet,
        _uhr().add(_vorgangDauer),
      );
      return TotpNoetig(vorgang);
    }
    if (totpPflicht) {
      final geheimnis = Totp.neuesGeheimnis();
      _vorgaenge[vorgang] = _Vorgang(
        kontoId,
        geraet,
        _uhr().add(_vorgangDauer),
        neuesGeheimnis: geheimnis,
      );
      return TotpEinrichten(
        vorgang,
        Totp.base32(geheimnis),
        Totp.adresse(geheimnis, zeile['name'] as String),
      );
    }
    _erfolg(kontoId);
    return meldeAn(kontoId, geraet, adresse);
  }

  /// Zweiter Schritt: der Code – oder ein Wiederherstellungscode.
  Future<Anmeldeergebnis> bestaetige(
    String vorgang,
    String code, {
    required String adresse,
  }) async {
    final warte = bremse.wartezeit(adresse);
    if (warte != null) return Abgewiesen(warte: warte);
    _raeumeVorgaengeAuf();
    final v = _vorgaenge[vorgang];
    if (v == null) {
      bremse.fehlschlag(adresse);
      return const Abgewiesen();
    }
    final neu = v.neuesGeheimnis;
    if (neu != null) {
      final codes = await richteTotpEin(v.konto, neu, code);
      if (codes == null) return _codeFalsch(vorgang, v, adresse);
      _vorgaenge.remove(vorgang);
      _erfolg(v.konto);
      final a = meldeAn(v.konto, v.geraet, adresse);
      return Angemeldet(a.token, a.geraet, wiederherstellungscodes: codes);
    }
    if (!await _pruefeZweitenFaktor(v.konto, code)) {
      return _codeFalsch(vorgang, v, adresse);
    }
    _vorgaenge.remove(vorgang);
    _erfolg(v.konto);
    return meldeAn(v.konto, v.geraet, adresse);
  }

  Abgewiesen _codeFalsch(String vorgang, _Vorgang v, String adresse) {
    _fehlschlag(v.konto);
    bremse.fehlschlag(adresse);
    if (++v.fehlversuche >= _vorgangVersuche) _vorgaenge.remove(vorgang);
    return const Abgewiesen();
  }

  /// Prüft einen TOTP-Code oder verbraucht einen Wiederherstellungscode.
  Future<bool> _pruefeZweitenFaktor(String kontoId, String code) async {
    final z = _zeile(kontoId);
    final verschluesselt = z?['totp'] as String?;
    if (z == null || verschluesselt == null) return false;
    if (RegExp(r'^\s*\d{3}\s*\d{3}\s*$').hasMatch(code)) {
      final geheimnis = await _tresor.entschluessele(verschluesselt);
      final schritt = Totp.pruefe(
        geheimnis,
        code,
        _uhr(),
        letzterSchritt: z['totp_letzter_schritt'] as int,
      );
      if (schritt == null) return false;
      _db.execute('UPDATE konten SET totp_letzter_schritt = ? WHERE id = ?', [
        schritt,
        kontoId,
      ]);
      return true;
    }
    _db.execute(
      'DELETE FROM wiederherstellung WHERE konto = ? AND pruefwert = ?',
      [kontoId, _hash(_normalisiereCode(code))],
    );
    return _db.updatedRows == 1;
  }

  /// Ein Gerät für [kontoId] anmelden – nach bestandener Prüfung (auch
  /// über OIDC).
  Angemeldet meldeAn(String kontoId, String name, String adresse) {
    final token = 'pv1_${_zufallstext(43)}';
    final id = const Uuid().v4();
    final jetzt = _uhr().millisecondsSinceEpoch;
    final geraetName = name.trim().isEmpty
        ? 'Gerät'
        : name.trim().substring(0, min(80, name.trim().length));
    _db.execute(
      'INSERT INTO geraete (id, konto, name, pruefwert, angelegt, zuletzt, '
      'adresse) VALUES (?, ?, ?, ?, ?, ?, ?)',
      [id, kontoId, geraetName, _hash(token), jetzt, jetzt, adresse],
    );
    final z = _db.select('SELECT * FROM geraete WHERE id = ?', [id]).first;
    return Angemeldet(token, Geraet._aus(z));
  }

  void _erfolg(String kontoId) => entsperre(kontoId);

  void _fehlschlag(String kontoId) {
    _db.execute(
      'UPDATE konten SET fehlversuche = fehlversuche + 1 WHERE id = ?',
      [kontoId],
    );
    final n =
        _db.select('SELECT fehlversuche FROM konten WHERE id = ?', [
              kontoId,
            ]).first['fehlversuche']
            as int;
    final dauer = Bremse.sperrdauer(n);
    if (dauer != null) {
      _db.execute('UPDATE konten SET gesperrt_bis = ? WHERE id = ?', [
        _uhr().add(dauer).millisecondsSinceEpoch,
        kontoId,
      ]);
    }
  }

  void _raeumeVorgaengeAuf() {
    final jetzt = _uhr();
    _vorgaenge.removeWhere((_, v) => v.ablauf.isBefore(jetzt));
  }

  // --- Geräte ------------------------------------------------------------

  /// Konto und Gerät zu einem Token – `null`, wenn es keins (mehr) ist.
  ({Konto konto, Geraet geraet})? pruefeToken(String token, String adresse) {
    if (!token.startsWith('pv1_')) return null;
    // Ein Gerät gibt es nur mit Konto: Wird das Konto gelöscht, gehen
    // seine Geräte mit (ON DELETE CASCADE).
    final z = _db.select('SELECT * FROM geraete WHERE pruefwert = ?', [
      _hash(token),
    ]);
    if (z.isEmpty) return null;
    final geraet = Geraet._aus(z.first);
    final jetzt = _uhr();
    if (jetzt.difference(geraet.zuletzt) > geraetAblauf) {
      _db.execute('DELETE FROM geraete WHERE id = ?', [geraet.id]);
      return null;
    }
    // Nicht bei jeder Anfrage schreiben: Die Zeitleiste fragt dutzendfach
    // in der Sekunde nach Miniaturen.
    if (jetzt.difference(geraet.zuletzt) > const Duration(minutes: 1) ||
        geraet.adresse != adresse) {
      _db.execute('UPDATE geraete SET zuletzt = ?, adresse = ? WHERE id = ?', [
        jetzt.millisecondsSinceEpoch,
        adresse,
        geraet.id,
      ]);
    }
    return (konto: konto(geraet.konto)!, geraet: geraet);
  }

  List<Geraet> geraete(String kontoId) => [
    for (final z in _db.select(
      'SELECT * FROM geraete WHERE konto = ? ORDER BY zuletzt DESC',
      [kontoId],
    ))
      Geraet._aus(z),
  ];

  /// Meldet ein Gerät ab – nur eines des eigenen Kontos.
  bool abmelden(String kontoId, String geraetId) {
    _db.execute('DELETE FROM geraete WHERE konto = ? AND id = ?', [
      kontoId,
      geraetId,
    ]);
    return _db.updatedRows == 1;
  }

  int alleAbmelden(String kontoId) {
    _db.execute('DELETE FROM geraete WHERE konto = ?', [kontoId]);
    return _db.updatedRows;
  }

  // --- Wiederherstellungscodes -------------------------------------------

  /// Zehn neue Codes; die alten gelten nicht mehr.
  List<String> neueWiederherstellungscodes(String kontoId) {
    const zeichen = '23456789abcdefghjkmnpqrstuvwxyz';
    final zufall = Random.secure();
    final codes = [
      for (var i = 0; i < 10; i++)
        [
          for (var g = 0; g < 3; g++)
            String.fromCharCodes([
              for (var j = 0; j < 4; j++)
                zeichen.codeUnitAt(zufall.nextInt(zeichen.length)),
            ]),
        ].join('-'),
    ];
    _db.execute('BEGIN');
    try {
      _db.execute('DELETE FROM wiederherstellung WHERE konto = ?', [kontoId]);
      for (final c in codes) {
        _db.execute(
          'INSERT INTO wiederherstellung (konto, pruefwert) VALUES (?, ?)',
          [kontoId, _hash(_normalisiereCode(c))],
        );
      }
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
    return codes;
  }

  /// Neue Codes auf Wunsch des Nutzers – nur mit gültigem TOTP-Code.
  Future<List<String>?> erneuereWiederherstellungscodes(
    String kontoId,
    String code,
  ) async {
    if (!RegExp(r'^\s*\d{3}\s*\d{3}\s*$').hasMatch(code) ||
        !await _pruefeZweitenFaktor(kontoId, code)) {
      _fehlschlag(kontoId);
      return null;
    }
    return neueWiederherstellungscodes(kontoId);
  }

  int uebrigeCodes(String kontoId) =>
      _db.select(
            'SELECT count(*) AS n FROM wiederherstellung WHERE konto = ?',
            [kontoId],
          ).first['n']
          as int;

  // --- OIDC --------------------------------------------------------------

  Konto? kontoFuerOidc(String aussteller, String subjekt) {
    final z = _db.select(
      'SELECT konto FROM oidc WHERE aussteller = ? AND subjekt = ?',
      [aussteller, subjekt],
    );
    return z.isEmpty ? null : konto(z.first['konto'] as String);
  }

  /// Verknüpft eine Kennung beim Anbieter mit [kontoId]. Wirft, wenn sie
  /// schon zu einem anderen Konto gehört.
  void verknuepfe(String kontoId, String aussteller, String subjekt) {
    final bisher = kontoFuerOidc(aussteller, subjekt);
    if (bisher != null && bisher.id != kontoId) {
      throw StateError('Diese Anmeldung gehört schon zu einem anderen Konto.');
    }
    _db.execute(
      'INSERT OR IGNORE INTO oidc (aussteller, subjekt, konto, angelegt) '
      'VALUES (?, ?, ?, ?)',
      [aussteller, subjekt, kontoId, _uhr().millisecondsSinceEpoch],
    );
  }

  List<String> oidcAussteller(String kontoId) => [
    for (final z in _db.select('SELECT aussteller FROM oidc WHERE konto = ?', [
      kontoId,
    ]))
      z['aussteller'] as String,
  ];

  int loeseOidc(String kontoId) {
    _db.execute('DELETE FROM oidc WHERE konto = ?', [kontoId]);
    return _db.updatedRows;
  }

  // -----------------------------------------------------------------------

  Row? _zeile(String kontoId) {
    final z = _db.select('SELECT * FROM konten WHERE id = ?', [kontoId]);
    return z.isEmpty ? null : z.first;
  }

  static String _hash(String s) => sha256.convert(utf8.encode(s)).toString();

  static String _normalisiereCode(String c) =>
      c.toLowerCase().replaceAll(RegExp(r'[\s-]'), '');

  static String _zufallstext(int laenge) {
    final zufall = Random.secure();
    final bytes = List<int>.generate(
      (laenge * 3 + 3) ~/ 4,
      (_) => zufall.nextInt(256),
    );
    return base64Url.encode(bytes).replaceAll('=', '').substring(0, laenge);
  }
}

/// Lässt höchstens [plaetze] Arbeiten zugleich laufen.
class _Ampel {
  _Ampel(this.plaetze);
  final int plaetze;
  var _belegt = 0;
  final _wartende = <Completer<void>>[];

  Future<T> mit<T>(Future<T> Function() arbeit) async {
    if (_belegt >= plaetze) {
      final c = Completer<void>();
      _wartende.add(c);
      await c.future;
    } else {
      _belegt++;
    }
    try {
      return await arbeit();
    } finally {
      if (_wartende.isNotEmpty) {
        _wartende.removeAt(0).complete();
      } else {
        _belegt--;
      }
    }
  }
}
