/// **Anmelden mit Passkeys** (WebAuthn, #277) – wie Immich 3.4.
///
/// Ein Passkey ist ein Schlüsselpaar, das der Browser oder das Telefon
/// (iCloud-Schlüsselbund, Google, 1Password, ein Sicherheitsschlüssel)
/// für genau diesen Server anlegt. Der Server bekommt nur den öffentlichen
/// Teil; beim Anmelden unterschreibt das Gerät eine Herausforderung, und
/// der Server prüft die Unterschrift. Ein Passwort geht dabei nirgends
/// hin, und eine nachgebaute Seite unter anderer Adresse bekommt keine
/// Unterschrift – der Browser bindet jeden Passkey an die Adresse.
///
/// **Zwei Faktoren in einem.** Verlangt wird, dass das Gerät den Menschen
/// geprüft hat (Fingerabdruck, Gesicht, Geräte-PIN; Merkmal `UV`). Der
/// Passkey ist dann Besitz und Wissen bzw. Körper zugleich – deshalb
/// folgt auf ihn kein TOTP-Code, auch wenn TOTP Pflicht ist.
///
/// **Was hier nicht geprüft wird: die Herkunftsbescheinigung**
/// (`attestation`). Verlangt wird `none`, wie bei Immich und fast allen
/// Diensten: Welches Gerät den Schlüssel hält, geht den Server nichts an.
///
/// Die Unterschriften: ES256 (fast alle Geräte), EdDSA und RS256
/// (Windows Hello) – über pointycastle bzw. cryptography in reinem Dart.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart' as kr;
import 'package:pointycastle/export.dart' as pc;
import 'package:sqlite3/sqlite3.dart';

// --- CBOR -------------------------------------------------------------------

/// Liest einen CBOR-Wert (RFC 8949) – nur, was in WebAuthn vorkommt:
/// Ganzzahlen, Byte- und Textketten, Listen, Tabellen, einfache Werte.
/// [ende] erfährt, wo der Wert aufhört; die Schlüsseldaten in `authData`
/// stehen ohne Längenangabe vor den Erweiterungen.
Object? cborLies(Uint8List b, {int ab = 0, void Function(int ende)? ende}) {
  final l = _CborLeser(b, ab);
  final wert = l.wert(0);
  ende?.call(l.o);
  return wert;
}

class _CborLeser {
  _CborLeser(this.b, this.o);

  final Uint8List b;
  int o;

  int _byte() {
    if (o >= b.length) throw const FormatException('CBOR zu kurz');
    return b[o++];
  }

  int _laenge(int info) {
    if (info < 24) return info;
    final n = switch (info) {
      24 => 1,
      25 => 2,
      26 => 4,
      27 => 8,
      _ => throw const FormatException('CBOR: unbestimmte Länge'),
    };
    var v = 0;
    for (var i = 0; i < n; i++) {
      v = v * 256 + _byte();
    }
    return v;
  }

  Uint8List _bytes(int n) {
    if (n < 0 || o + n > b.length) throw const FormatException('CBOR zu kurz');
    final r = Uint8List.sublistView(b, o, o + n);
    o += n;
    return r;
  }

  Object? wert(int tiefe) {
    if (tiefe > 16) throw const FormatException('CBOR zu tief');
    final k = _byte();
    final art = k >> 5, info = k & 0x1F;
    switch (art) {
      case 0:
        return _laenge(info);
      case 1:
        return -1 - _laenge(info);
      case 2:
        return Uint8List.fromList(_bytes(_laenge(info)));
      case 3:
        return utf8.decode(_bytes(_laenge(info)));
      case 4:
        final n = _laenge(info);
        return [for (var i = 0; i < n; i++) wert(tiefe + 1)];
      case 5:
        final n = _laenge(info);
        final m = <Object?, Object?>{};
        for (var i = 0; i < n; i++) {
          final schluessel = wert(tiefe + 1);
          m[schluessel] = wert(tiefe + 1);
        }
        return m;
      case 6:
        _laenge(info); // Etikett überlesen
        return wert(tiefe + 1);
      default:
        return switch (info) {
          20 => false,
          21 => true,
          22 || 23 => null,
          _ => throw const FormatException('CBOR: Wert nicht unterstützt'),
        };
    }
  }
}

// --- Schlüssel und Unterschriften ----------------------------------------------

/// Prüft [signatur] über [daten] mit dem COSE-Schlüssel [cose] (RFC 9053).
Future<bool> pruefeCoseUnterschrift(
  Map<Object?, Object?> cose,
  Uint8List daten,
  Uint8List signatur,
) async {
  final alg = cose[3];
  try {
    switch (alg) {
      case -7: // ES256: ECDSA über P-256 mit SHA-256, Unterschrift als DER
        if (cose[1] != 2 || cose[-1] != 1) return false;
        final x = cose[-2], y = cose[-3];
        if (x is! Uint8List || y is! Uint8List) return false;
        final kurve = pc.ECCurve_secp256r1();
        final punkt = kurve.curve.createPoint(_zahl(x), _zahl(y));
        final (r, s) = _derSignatur(signatur);
        final pruefer = pc.ECDSASigner(pc.SHA256Digest())
          ..init(false, pc.PublicKeyParameter(pc.ECPublicKey(punkt, kurve)));
        return pruefer.verifySignature(daten, pc.ECSignature(r, s));
      case -257: // RS256: RSASSA-PKCS1-v1_5 mit SHA-256
        if (cose[1] != 3) return false;
        final n = cose[-1], e = cose[-2];
        if (n is! Uint8List || e is! Uint8List) return false;
        final pruefer =
            pc.RSASigner(pc.SHA256Digest(), '0609608648016503040201')..init(
              false,
              pc.PublicKeyParameter<pc.RSAPublicKey>(
                pc.RSAPublicKey(_zahl(n), _zahl(e)),
              ),
            );
        return pruefer.verifySignature(daten, pc.RSASignature(signatur));
      case -8: // EdDSA über Ed25519
        if (cose[1] != 1 || cose[-1] != 6) return false;
        final x = cose[-2];
        if (x is! Uint8List) return false;
        return await kr.Ed25519().verify(
          daten,
          signature: kr.Signature(
            signatur,
            publicKey: kr.SimplePublicKey(x, type: kr.KeyPairType.ed25519),
          ),
        );
      default:
        return false;
    }
  } on Object {
    return false;
  }
}

BigInt _zahl(List<int> bytes) {
  var v = BigInt.zero;
  for (final b in bytes) {
    v = (v << 8) | BigInt.from(b);
  }
  return v;
}

/// `SEQUENCE { INTEGER r, INTEGER s }`.
(BigInt, BigInt) _derSignatur(Uint8List d) {
  var o = 0;
  int laenge() {
    final l = d[o++];
    if (l < 0x80) return l;
    var v = 0;
    for (var i = 0; i < (l & 0x7F); i++) {
      v = v * 256 + d[o++];
    }
    return v;
  }

  if (d[o++] != 0x30) throw const FormatException('keine DER-Folge');
  laenge();
  BigInt ganz() {
    if (d[o++] != 0x02) throw const FormatException('keine DER-Zahl');
    final l = laenge();
    final v = _zahl(d.sublist(o, o + l));
    o += l;
    return v;
  }

  return (ganz(), ganz());
}

// --- authData -----------------------------------------------------------------

/// Was die Daten des Geräts (`authenticatorData`) sagen.
class Geraetedaten {
  Geraetedaten._(
    this.rpHash,
    this.merkmale,
    this.zaehler,
    this.kennung,
    this.cose,
  );

  /// Aus den rohen Bytes; [mitSchluessel] beim Anlegen.
  factory Geraetedaten.aus(Uint8List b, {bool mitSchluessel = false}) {
    if (b.length < 37) throw const FormatException('authData zu kurz');
    final merkmale = b[32];
    final zaehler = ByteData.sublistView(b, 33, 37).getUint32(0);
    Uint8List? kennung;
    Map<Object?, Object?>? cose;
    if (mitSchluessel) {
      if (merkmale & 0x40 == 0 || b.length < 55) {
        throw const FormatException('authData ohne Schlüssel');
      }
      final l = ByteData.sublistView(b, 53, 55).getUint16(0);
      if (b.length < 55 + l) throw const FormatException('authData zu kurz');
      kennung = Uint8List.fromList(b.sublist(55, 55 + l));
      final schluessel = cborLies(b, ab: 55 + l);
      if (schluessel is! Map) {
        throw const FormatException('kein COSE-Schlüssel');
      }
      cose = schluessel.cast<Object?, Object?>();
    }
    return Geraetedaten._(
      Uint8List.fromList(b.sublist(0, 32)),
      merkmale,
      zaehler,
      kennung,
      cose,
    );
  }

  final Uint8List rpHash;
  final int merkmale;
  final int zaehler;
  final Uint8List? kennung;
  final Map<Object?, Object?>? cose;

  /// Jemand war da (`UP`).
  bool get anwesend => merkmale & 0x01 != 0;

  /// Das Gerät hat den Menschen geprüft (`UV`).
  bool get geprueft => merkmale & 0x04 != 0;
}

// --- Dienst -------------------------------------------------------------------

/// Ein gespeicherter Passkey, wie die Oberflächen ihn zeigen.
class Passkey {
  const Passkey(this.id, this.name, this.angelegt, this.zuletzt);
  final String id;
  final String name;
  final DateTime angelegt;
  final DateTime? zuletzt;

  Map<String, Object?> alsJson() => {
    'id': id,
    'name': name,
    'angelegt': angelegt.toUtc().toIso8601String(),
    'zuletzt': zuletzt?.toUtc().toIso8601String(),
  };
}

/// Wofür die Antwort des Geräts gilt – sonst liesse sich eine
/// Herausforderung der Anmeldung zum Anlegen benutzen.
enum _Zweck { anlegen, anmelden }

class _Herausforderung {
  _Herausforderung(this.zweck, this.rp, this.ablauf, {this.konto});
  final _Zweck zweck;
  final String rp;
  final DateTime ablauf;
  final String? konto;
}

/// Ein Fehler, den die Oberfläche zeigen darf.
class PasskeyFehler implements Exception {
  const PasskeyFehler(this.text);
  final String text;
  @override
  String toString() => text;
}

/// Passkeys anlegen, prüfen, auflisten und entfernen. Die Herausforderungen
/// liegen nur im Speicher und gelten fünf Minuten.
class Passkeys {
  Passkeys(this._db, {DateTime Function()? uhr}) : _uhr = uhr ?? DateTime.now;

  final Database _db;
  final DateTime Function() _uhr;
  final _offen = <String, _Herausforderung>{};

  static const _dauer = Duration(minutes: 5);

  /// Die Kennung des Servers für WebAuthn (`rp.id`) aus der Herkunft der
  /// Seite – der Hostname, unter dem der Browser ihn sieht. Nur über HTTPS
  /// oder auf diesem Rechner; anders legt kein Browser einen Passkey an.
  static String rpAus(String? herkunft) {
    final u = herkunft == null ? null : Uri.tryParse(herkunft);
    if (u == null || u.host.isEmpty) {
      throw const PasskeyFehler('Unbekannte Herkunft der Anfrage.');
    }
    final lokal = const {'localhost', '127.0.0.1', '::1'}.contains(u.host);
    if (u.scheme != 'https' && !(u.scheme == 'http' && lokal)) {
      throw const PasskeyFehler('Passkeys gehen nur über HTTPS.');
    }
    return u.host;
  }

  String _neu(_Zweck zweck, String rp, {String? konto}) {
    _raeumeAuf();
    final r = Random.secure();
    final roh = Uint8List.fromList(List.generate(32, (_) => r.nextInt(256)));
    final h = _b64(roh);
    _offen[h] = _Herausforderung(zweck, rp, _uhr().add(_dauer), konto: konto);
    return h;
  }

  void _raeumeAuf() {
    final jetzt = _uhr();
    _offen.removeWhere((_, h) => h.ablauf.isBefore(jetzt));
  }

  /// Die Vorgaben für `navigator.credentials.create`.
  Map<String, Object?> anlegeoptionen({
    required String kontoId,
    required String kontoName,
    required String rp,
    required String servername,
  }) => {
    'challenge': _neu(_Zweck.anlegen, rp, konto: kontoId),
    'rp': {'id': rp, 'name': servername},
    'user': {
      'id': _b64(utf8.encode(kontoId)),
      'name': kontoName,
      'displayName': kontoName,
    },
    'pubKeyCredParams': [
      {'type': 'public-key', 'alg': -7},
      {'type': 'public-key', 'alg': -8},
      {'type': 'public-key', 'alg': -257},
    ],
    'timeout': _dauer.inMilliseconds,
    'attestation': 'none',
    'authenticatorSelection': {
      'residentKey': 'required',
      'requireResidentKey': true,
      'userVerification': 'required',
    },
    'excludeCredentials': [
      for (final id in _kennungenVon(kontoId)) {'type': 'public-key', 'id': id},
    ],
  };

  /// Die Vorgaben für `navigator.credentials.get` – ohne Liste erlaubter
  /// Schlüssel: Das Gerät bietet an, was es für diesen Server hat, und
  /// sagt mit `userHandle`, zu welchem Konto er gehört.
  Map<String, Object?> anmeldeoptionen({required String rp}) => {
    'challenge': _neu(_Zweck.anmelden, rp),
    'rpId': rp,
    'timeout': _dauer.inMilliseconds,
    'userVerification': 'required',
  };

  /// Legt aus der Antwort von `navigator.credentials.create` einen Passkey
  /// für [kontoId] an. [herkunft] ist die `Origin` der Anfrage.
  Future<Passkey> lege({
    required String kontoId,
    required String herkunft,
    required Map<String, Object?> antwort,
    required String name,
  }) async {
    final rp = rpAus(herkunft);
    final r = antwort['response'];
    if (r is! Map) throw const PasskeyFehler('Antwort unvollständig.');
    final client = _clientdaten(r['clientDataJSON']);
    final h = _pruefeClient(
      client,
      'webauthn.create',
      herkunft,
      _Zweck.anlegen,
    );
    if (h.konto != kontoId || h.rp != rp) {
      throw const PasskeyFehler('Die Herausforderung gehört woanders hin.');
    }
    final bescheinigung = cborLies(_ausB64(r['attestationObject']));
    if (bescheinigung is! Map || bescheinigung['authData'] is! Uint8List) {
      throw const PasskeyFehler('Antwort unvollständig.');
    }
    final g = Geraetedaten.aus(
      bescheinigung['authData'] as Uint8List,
      mitSchluessel: true,
    );
    _pruefeGeraet(g, rp);
    if (!const {-7, -8, -257}.contains(g.cose![3])) {
      throw const PasskeyFehler(
        'Dieses Schlüsselverfahren kennt der Server nicht.',
      );
    }
    final id = _b64(g.kennung!);
    final jetzt = _uhr();
    final sauber = name.trim().isEmpty ? 'Passkey' : name.trim();
    try {
      _db.execute(
        'INSERT INTO passkeys (id, konto, name, rp, schluessel, zaehler, angelegt) '
        'VALUES (?, ?, ?, ?, ?, ?, ?)',
        [
          id,
          kontoId,
          sauber.length > 80 ? sauber.substring(0, 80) : sauber,
          rp,
          _cborSchreibeSchluessel(g.cose!),
          g.zaehler,
          jetzt.millisecondsSinceEpoch,
        ],
      );
    } on SqliteException {
      throw const PasskeyFehler('Diesen Passkey gibt es schon.');
    }
    return Passkey(id, sauber, jetzt, null);
  }

  /// Prüft die Antwort von `navigator.credentials.get` und gibt das Konto
  /// zurück, oder wirft [PasskeyFehler].
  Future<String> pruefeAnmeldung({
    required String herkunft,
    required Map<String, Object?> antwort,
  }) async {
    final rp = rpAus(herkunft);
    final r = antwort['response'];
    final id = antwort['id'];
    if (r is! Map || id is! String) {
      throw const PasskeyFehler('Antwort unvollständig.');
    }
    final clientRoh = _ausB64(r['clientDataJSON']);
    final client = _clientdaten(r['clientDataJSON']);
    final h = _pruefeClient(client, 'webauthn.get', herkunft, _Zweck.anmelden);
    if (h.rp != rp) throw const PasskeyFehler('Falscher Server.');
    final z = _db.select(
      'SELECT konto, rp, schluessel, zaehler FROM passkeys WHERE id = ?',
      [id],
    );
    if (z.isEmpty) {
      throw const PasskeyFehler('Diesen Passkey kennt der Server nicht.');
    }
    final zeile = z.first;
    if (zeile['rp'] != rp) throw const PasskeyFehler('Falscher Server.');
    final konto = zeile['konto'] as String;
    final handle = r['userHandle'];
    if (handle is String &&
        handle.isNotEmpty &&
        utf8.decode(_ausB64(handle), allowMalformed: true) != konto) {
      throw const PasskeyFehler('Der Passkey gehört zu einem anderen Konto.');
    }
    final geraeteRoh = _ausB64(r['authenticatorData']);
    final g = Geraetedaten.aus(geraeteRoh);
    _pruefeGeraet(g, rp);
    final cose = cborLies(zeile['schluessel'] as Uint8List);
    if (cose is! Map) {
      throw const PasskeyFehler('Gespeicherter Schlüssel kaputt.');
    }
    final daten = Uint8List.fromList([
      ...geraeteRoh,
      ...sha256.convert(clientRoh).bytes,
    ]);
    final stimmt = await pruefeCoseUnterschrift(
      cose.cast<Object?, Object?>(),
      daten,
      _ausB64(r['signature']),
    );
    if (!stimmt) throw const PasskeyFehler('Die Unterschrift stimmt nicht.');
    // Ein Zähler, der nicht wächst, heisst: Der Schlüssel wurde kopiert.
    // Synchronisierte Passkeys (iCloud, Google) zählen gar nicht – 0.
    final vorher = zeile['zaehler'] as int;
    if (g.zaehler != 0 || vorher != 0) {
      if (g.zaehler <= vorher) {
        throw const PasskeyFehler('Dieser Passkey wurde vermutlich kopiert.');
      }
    }
    _db.execute('UPDATE passkeys SET zaehler = ?, zuletzt = ? WHERE id = ?', [
      g.zaehler,
      _uhr().millisecondsSinceEpoch,
      id,
    ]);
    return konto;
  }

  List<Passkey> von(String kontoId) => [
    for (final z in _db.select(
      'SELECT id, name, angelegt, zuletzt FROM passkeys WHERE konto = ? '
      'ORDER BY angelegt',
      [kontoId],
    ))
      Passkey(
        z['id'] as String,
        z['name'] as String,
        DateTime.fromMillisecondsSinceEpoch(z['angelegt'] as int),
        z['zuletzt'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(z['zuletzt'] as int),
      ),
  ];

  /// Entfernt den Passkey [id] von [kontoId]; `false`, wenn es ihn dort
  /// nicht gibt.
  bool entferne(String kontoId, String id) {
    _db.execute('DELETE FROM passkeys WHERE id = ? AND konto = ?', [
      id,
      kontoId,
    ]);
    return _db.updatedRows == 1;
  }

  Iterable<String> _kennungenVon(String kontoId) => [
    for (final z in _db.select('SELECT id FROM passkeys WHERE konto = ?', [
      kontoId,
    ]))
      z['id'] as String,
  ];

  Map<String, Object?> _clientdaten(Object? b64) {
    try {
      final d = jsonDecode(utf8.decode(_ausB64(b64)));
      if (d is Map<String, Object?>) return d;
    } on FormatException {
      // unten
    }
    throw const PasskeyFehler('Antwort unvollständig.');
  }

  _Herausforderung _pruefeClient(
    Map<String, Object?> client,
    String typ,
    String herkunft,
    _Zweck zweck,
  ) {
    _raeumeAuf();
    if (client['type'] != typ) throw const PasskeyFehler('Falsche Antwortart.');
    if (client['origin'] != herkunft) {
      throw const PasskeyFehler('Die Antwort kam von einer anderen Seite.');
    }
    if (client['crossOrigin'] == true) {
      throw const PasskeyFehler('Die Antwort kam von einer anderen Seite.');
    }
    final h = _offen.remove(client['challenge']);
    if (h == null || h.zweck != zweck) {
      throw const PasskeyFehler(
        'Die Anfrage ist abgelaufen. Bitte neu beginnen.',
      );
    }
    return h;
  }

  void _pruefeGeraet(Geraetedaten g, String rp) {
    final soll = sha256.convert(utf8.encode(rp)).bytes;
    var gleich = g.rpHash.length == soll.length;
    for (var i = 0; gleich && i < soll.length; i++) {
      gleich = g.rpHash[i] == soll[i];
    }
    if (!gleich) throw const PasskeyFehler('Falscher Server.');
    if (!g.anwesend || !g.geprueft) {
      throw const PasskeyFehler(
        'Das Gerät hat nicht nach Fingerabdruck, Gesicht oder PIN gefragt.',
      );
    }
  }
}

/// Der COSE-Schlüssel zum Ablegen – als CBOR, so wie er kam. Nur
/// Ganzzahlen und Byteketten kommen darin vor.
Uint8List _cborSchreibeSchluessel(Map<Object?, Object?> cose) {
  final aus = BytesBuilder();
  void kopf(int art, int n) {
    if (n < 24) {
      aus.addByte(art << 5 | n);
    } else if (n < 256) {
      aus
        ..addByte(art << 5 | 24)
        ..addByte(n);
    } else if (n < 65536) {
      aus
        ..addByte(art << 5 | 25)
        ..addByte(n >> 8)
        ..addByte(n & 0xFF);
    } else {
      aus.addByte(art << 5 | 26);
      for (final s in [24, 16, 8, 0]) {
        aus.addByte((n >> s) & 0xFF);
      }
    }
  }

  void wert(Object? v) {
    switch (v) {
      case int i when i >= 0:
        kopf(0, i);
      case int i:
        kopf(1, -1 - i);
      case Uint8List b:
        kopf(2, b.length);
        aus.add(b);
      case String s:
        final u = utf8.encode(s);
        kopf(3, u.length);
        aus.add(u);
      default:
        throw const PasskeyFehler('COSE-Schlüssel mit unbekanntem Wert.');
    }
  }

  kopf(5, cose.length);
  for (final e in cose.entries) {
    wert(e.key);
    wert(e.value);
  }
  return aus.toBytes();
}

String _b64(List<int> b) => base64Url.encode(b).replaceAll('=', '');

Uint8List _ausB64(Object? s) {
  if (s is! String) throw const PasskeyFehler('Antwort unvollständig.');
  try {
    return base64Url.decode(s.padRight((s.length + 3) ~/ 4 * 4, '='));
  } on FormatException {
    throw const PasskeyFehler('Antwort unvollständig.');
  }
}
