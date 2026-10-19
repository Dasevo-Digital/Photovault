import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'konten/passwort.dart';
import 'konten/serverdatenbank.dart';
import 'konten/tresorschluessel.dart';

/// Eine Freigabe nach aussen: ein Album oder eine Auswahl, erreichbar über
/// einen Link ohne Konto (Issue #106).
class Freigabe {
  const Freigabe({
    required this.id,
    required this.konto,
    required this.titel,
    required this.album,
    required this.aufnahmen,
    required this.mitPasswort,
    required this.herunterladen,
    this.hochladen = false,
    required this.angelegt,
    required this.ablauf,
    required this.aufrufe,
    required this.zuletzt,
  });

  /// Zum Verwalten – nicht der Link.
  final String id;
  final String konto;
  final String titel;

  /// Ein Album: gezeigt wird, was beim Aufruf darin liegt.
  final String? album;

  /// Eine Auswahl: genau diese Aufnahmen.
  final List<String>? aufnahmen;
  final bool mitPasswort;
  final bool herunterladen;

  /// Ob Gäste zum Album beitragen dürfen (nur bei Alben).
  final bool hochladen;
  final DateTime angelegt;
  final DateTime? ablauf;
  final int aufrufe;
  final DateTime? zuletzt;
}

/// Legt Freigaben an, findet sie über ihren Link und prüft ihr Passwort.
///
/// **Der Link** trägt 128 Bit Zufall; erraten lässt er sich nicht. In der
/// Datenbank steht er nur als SHA-256 (zum Finden) und mit dem Schlüssel
/// des Servers verschlüsselt (damit der Besitzer ihn später noch einmal
/// kopieren kann).
///
/// **Das Passwort** ist ein Argon2id-Prüfwert wie bei den Konten. Wer es
/// eingegeben hat, bekommt ein Cookie mit einer Signatur über Freigabe und
/// Ablauf (HMAC mit einem Geheimnis je Freigabe); ein neues Passwort oder
/// das Löschen der Freigabe macht alle alten Cookies wertlos.
class Freigabedienst {
  Freigabedienst(
    this._sdb,
    this._tresor, {
    this.passwort = const Passwort(),
    DateTime Function()? uhr,
  }) : _uhr = uhr ?? DateTime.now;

  final Serverdatenbank _sdb;
  final Tresorschluessel _tresor;
  final Passwort passwort;
  final DateTime Function() _uhr;

  /// Wie lange ein eingegebenes Passwort gilt.
  static const sitzungsdauer = Duration(hours: 12);

  /// Höchstens so viele Aufnahmen in einer Auswahl.
  static const hoechstensAufnahmen = 5000;

  static final _zufall = Random.secure();

  static String _zufallstext(int bytes) => base64Url
      .encode(List<int>.generate(bytes, (_) => _zufall.nextInt(256)))
      .replaceAll('=', '');

  static String _pruefwert(String link) =>
      sha256.convert(utf8.encode(link)).toString();

  /// Legt eine Freigabe an und gibt ihre Kennung und den Link zurück.
  Future<({String id, String link})> lege({
    required String konto,
    required String titel,
    String? album,
    List<String>? aufnahmen,
    Duration? gueltig,
    String? passwortKlartext,
    bool herunterladen = false,
    bool hochladen = false,
  }) async {
    if ((album == null) == (aufnahmen == null)) {
      throw ArgumentError('entweder album oder aufnahmen');
    }
    if (hochladen && album == null) {
      throw ArgumentError('Beiträge nur zu einem Album');
    }
    final id = _zufallstext(9);
    final link = _zufallstext(16);
    final jetzt = _uhr();
    _sdb.db.execute(
      'INSERT INTO freigaben (id, konto, pruefwert, link, geheimnis, titel, '
      'album, aufnahmen, passwort, herunterladen, hochladen, angelegt, '
      'ablauf) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        id,
        konto,
        _pruefwert(link),
        await _tresor.verschluessele(utf8.encode(link)),
        _zufallstext(32),
        titel,
        album,
        aufnahmen == null ? null : jsonEncode(aufnahmen),
        passwortKlartext == null || passwortKlartext.isEmpty
            ? null
            : await passwort.pruefwertFuer(passwortKlartext),
        herunterladen ? 1 : 0,
        hochladen ? 1 : 0,
        jetzt.millisecondsSinceEpoch,
        gueltig == null ? null : jetzt.add(gueltig).millisecondsSinceEpoch,
      ],
    );
    return (id: id, link: link);
  }

  Freigabe _aus(Map<String, Object?> z) => Freigabe(
    id: z['id']! as String,
    konto: z['konto']! as String,
    titel: z['titel']! as String,
    album: z['album'] as String?,
    aufnahmen: z['aufnahmen'] == null
        ? null
        : (jsonDecode(z['aufnahmen']! as String) as List).cast<String>(),
    mitPasswort: z['passwort'] != null,
    herunterladen: z['herunterladen'] == 1,
    hochladen: z['hochladen'] == 1,
    angelegt: DateTime.fromMillisecondsSinceEpoch(z['angelegt']! as int),
    ablauf: z['ablauf'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(z['ablauf']! as int),
    aufrufe: z['aufrufe']! as int,
    zuletzt: z['zuletzt'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(z['zuletzt']! as int),
  );

  /// Die Freigaben eines Kontos, die jüngste zuerst, mit ihrem Link.
  Future<List<({Freigabe freigabe, String link})>> von(String konto) async {
    final zeilen = _sdb.db.select(
      'SELECT * FROM freigaben WHERE konto = ? ORDER BY angelegt DESC',
      [konto],
    );
    return [
      for (final z in zeilen)
        (
          freigabe: _aus(z),
          link: utf8.decode(await _tresor.entschluessele(z['link']! as String)),
        ),
    ];
  }

  /// Löscht die Freigabe [id] des Kontos; `false`, wenn es sie nicht gibt.
  bool widerrufe(String konto, String id) {
    _sdb.db.execute('DELETE FROM freigaben WHERE id = ? AND konto = ?', [
      id,
      konto,
    ]);
    return _sdb.db.updatedRows > 0;
  }

  /// Die Freigabe hinter [link] – `null`, wenn es sie nicht (mehr) gibt
  /// oder sie abgelaufen ist.
  Freigabe? fuer(String link) {
    if (link.length < 16 || link.length > 64) return null;
    final z = _sdb.db.select('SELECT * FROM freigaben WHERE pruefwert = ?', [
      _pruefwert(link),
    ]);
    if (z.isEmpty) return null;
    final f = _aus(z.first);
    final ablauf = f.ablauf;
    if (ablauf != null && !_uhr().isBefore(ablauf)) return null;
    return f;
  }

  /// Zählt einen Aufruf.
  void aufgerufen(Freigabe f) => _sdb.db.execute(
    'UPDATE freigaben SET aufrufe = aufrufe + 1, zuletzt = ? WHERE id = ?',
    [_uhr().millisecondsSinceEpoch, f.id],
  );

  /// Ob [klartext] das Passwort der Freigabe ist.
  Future<bool> passwortStimmt(Freigabe f, String klartext) async {
    final z = _sdb.db.select('SELECT passwort FROM freigaben WHERE id = ?', [
      f.id,
    ]);
    final pruefwert = z.isEmpty ? null : z.first['passwort'] as String?;
    if (pruefwert == null) return true;
    return passwort.stimmt(klartext, pruefwert);
  }

  String? _geheimnis(Freigabe f) {
    final z = _sdb.db.select(
      'SELECT geheimnis, passwort FROM freigaben '
      'WHERE id = ?',
      [f.id],
    );
    if (z.isEmpty) return null;
    // Das Passwort gehört in die Signatur: Ändert es sich, gilt kein
    // altes Cookie mehr.
    return '${z.first['geheimnis']}|${z.first['passwort'] ?? ''}';
  }

  /// Der Wert des Cookies nach dem richtigen Passwort.
  String sitzung(Freigabe f) {
    final bis = _uhr().add(sitzungsdauer).millisecondsSinceEpoch;
    return '$bis.${_signatur(f, bis)}';
  }

  /// Ob [wert] eine gültige Sitzung für [f] ist.
  bool sitzungGilt(Freigabe f, String? wert) {
    if (!f.mitPasswort) return true;
    if (wert == null) return false;
    final i = wert.indexOf('.');
    if (i <= 0) return false;
    final bis = int.tryParse(wert.substring(0, i));
    if (bis == null || _uhr().millisecondsSinceEpoch >= bis) return false;
    final soll = _signatur(f, bis);
    final ist = wert.substring(i + 1);
    if (soll == null || soll.length != ist.length) return false;
    var unterschied = 0;
    for (var k = 0; k < soll.length; k++) {
      unterschied |= soll.codeUnitAt(k) ^ ist.codeUnitAt(k);
    }
    return unterschied == 0;
  }

  String? _signatur(Freigabe f, int bis) {
    final g = _geheimnis(f);
    if (g == null) return null;
    return base64Url
        .encode(
          Hmac(
            sha256,
            utf8.encode(g),
          ).convert(utf8.encode('${f.id}:$bis')).bytes,
        )
        .replaceAll('=', '');
  }
}
