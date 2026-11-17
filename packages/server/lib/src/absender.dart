import 'dart:io';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';

/// Von welcher Adresse eine Anfrage kommt – auch hinter einem Reverse
/// Proxy.
///
/// Hinter dem Proxy kommt jede Verbindung vom Proxy. Die eigentliche
/// Adresse steht in `X-Forwarded-For`, aber diesen Kopf kann jeder selbst
/// setzen. Geglaubt wird er deshalb nur, wenn die Verbindung von einem
/// Proxy kommt, dem der Server ausdrücklich traut ([vertraut], aus
/// `PV_PROXY`). Dann gilt von rechts gelesen die erste Adresse, die kein
/// vertrauter Proxy ist: Weiter links kann der Absender selbst etwas
/// hineingeschrieben haben.
///
/// Gebraucht wird die Adresse für die Bremse bei Fehlversuchen und für die
/// Geräteliste. Ohne vertrauten Proxy bremste die Bremse sonst den Proxy
/// selbst – und damit alle.
class Absender {
  Absender([List<String> vertraut = const []])
    : _netze = [
        for (final eintrag in vertraut)
          for (final n in _netzeAus(eintrag.trim())) ?n,
      ];

  final List<_Netz> _netze;

  /// Die Adresse hinter [anfrage].
  String von(Request anfrage) {
    final info = anfrage.context['shelf.io.connection_info'];
    final direkt = info is HttpConnectionInfo
        ? info.remoteAddress.address
        : 'unbekannt';
    if (!_vertraut(direkt)) return direkt;
    final weitergeleitet = anfrage.headers['x-forwarded-for'];
    if (weitergeleitet == null) return direkt;
    final kette = [
      for (final s in weitergeleitet.split(','))
        if (s.trim().isNotEmpty) s.trim(),
    ];
    for (final a in kette.reversed) {
      if (!_vertraut(a)) return a;
    }
    return kette.isEmpty ? direkt : kette.first;
  }

  /// Ob [anfrage] aus dem Heimnetz kommt: von einer privaten Adresse, und
  /// nicht über einen Proxy, dem der Server nicht traut. Hinter so einem
  /// Proxy sähe jede Anfrage aus wie aus dem Heimnetz – auch die von
  /// aussen.
  bool ausDemHeimnetz(Request anfrage) {
    final info = anfrage.context['shelf.io.connection_info'];
    final direkt = info is HttpConnectionInfo
        ? info.remoteAddress.address
        : 'unbekannt';
    final weitergeleitet = anfrage.headers.keys.any(
      (k) => const {'x-forwarded-for', 'forwarded', 'x-real-ip'}.contains(k),
    );
    if (weitergeleitet && !_vertraut(direkt)) return false;
    final a = InternetAddress.tryParse(von(anfrage));
    return a != null && _heimnetz.any((n) => n.enthaelt(a));
  }

  static final _heimnetz = [
    ..._netzeAus('privat').whereType<_Netz>(),
    ?_Netz.aus('fe80::/10'),
  ];

  /// Ob die Verbindung selbst von einem vertrauten Proxy kommt – dann
  /// gelten auch dessen Angaben zum Weg, etwa `X-Forwarded-Proto`.
  bool ueberVertrautenProxy(Request anfrage) {
    final info = anfrage.context['shelf.io.connection_info'];
    return info is HttpConnectionInfo && _vertraut(info.remoteAddress.address);
  }

  /// Schema und Host, unter denen der Browser den Server erreicht hat –
  /// etwa `https://fotos.example.de`, ohne Schrägstrich am Ende.
  ///
  /// **Nicht `Request.requestedUri`.** Das baut dart:io selbst aus
  /// `X-Forwarded-Proto` und `X-Forwarded-Host`, gleich wer die Köpfe
  /// setzt. So bekam ein Freigabe-Link die Adresse, die ein beliebiger
  /// Absender hineinschrieb (#401). Hier gelten diese Köpfe nur von einem
  /// vertrauten Proxy; sonst die Verbindung selbst und der `Host`-Kopf.
  String herkunft(Request anfrage) {
    if (ueberVertrautenProxy(anfrage)) {
      final host = _erster(anfrage.headers['x-forwarded-host']);
      final proto = _erster(anfrage.headers['x-forwarded-proto']);
      if (host != null) return '${_schema(proto ?? 'https')}://$host';
      if (proto != null) {
        return '${_schema(proto)}://${_eigenerHost(anfrage)}';
      }
    }
    return '${_eigenesSchema(anfrage)}://${_eigenerHost(anfrage)}';
  }

  /// Ob der Browser über HTTPS kam – direkt, oder über einen vertrauten
  /// Proxy, der es sagt. Nur dann darf ein Cookie `Secure` tragen.
  bool verschluesselt(Request anfrage) {
    if (ueberVertrautenProxy(anfrage)) {
      final proto = _erster(anfrage.headers['x-forwarded-proto']);
      if (proto != null) return _schema(proto) == 'https';
    }
    return _eigenesSchema(anfrage) == 'https';
  }

  /// Das Schema der Verbindung selbst. Steht ein `X-Forwarded-Proto` da,
  /// hat dart:io es schon in `requestedUri` übernommen – dann ist das
  /// echte Schema nicht mehr abzulesen; der Server spricht selbst nur
  /// HTTP.
  static String _eigenesSchema(Request anfrage) =>
      anfrage.headers['x-forwarded-proto'] == null
      ? anfrage.requestedUri.scheme
      : 'http';

  /// Der Host der Verbindung selbst, ebenso ohne `X-Forwarded-Host`.
  static String _eigenerHost(Request anfrage) {
    if (anfrage.headers['x-forwarded-host'] == null) {
      return anfrage.requestedUri.authority;
    }
    final host = anfrage.headers['host'];
    if (host != null && host.isNotEmpty) return host;
    final info = anfrage.context['shelf.io.connection_info'];
    return info is HttpConnectionInfo
        ? 'localhost:${info.localPort}'
        : 'localhost';
  }

  static String _schema(String proto) =>
      proto.toLowerCase() == 'https' ? 'https' : 'http';

  static String? _erster(String? kopf) {
    final s = kopf?.split(',').first.trim();
    return s == null || s.isEmpty ? null : s;
  }

  bool _vertraut(String adresse) {
    final a = InternetAddress.tryParse(adresse);
    if (a == null) return false;
    return _netze.any((n) => n.enthaelt(a));
  }

  static List<_Netz?> _netzeAus(String eintrag) {
    if (eintrag.isEmpty) return const [];
    // Eine Abkürzung für den häufigsten Fall: Der Proxy läuft im selben
    // Docker-Netz oder im Heimnetz.
    //
    // Die Netze aus RFC 1918 als Zahlen statt als Text: Im Quelltext
    // stehen sonst Adressen, die wie die eines echten Heimnetzes aussehen.
    if (eintrag == 'privat') {
      return [
        _Netz.aus('127.0.0.0/8'),
        _Netz.v4([10, 0, 0, 0], 8),
        _Netz.v4([172, 16, 0, 0], 12),
        _Netz.v4([192, 168, 0, 0], 16),
        _Netz.aus('::1/128'),
        _Netz.aus('fc00::/7'),
      ];
    }
    return [_Netz.aus(eintrag)];
  }
}

class _Netz {
  _Netz(this.adresse, this.praefix);

  final InternetAddress adresse;
  final int praefix;

  _Netz.v4(List<int> oktette, this.praefix)
    : adresse = InternetAddress.fromRawAddress(Uint8List.fromList(oktette));

  static _Netz? aus(String text) {
    final teile = text.split('/');
    final a = InternetAddress.tryParse(teile[0]);
    if (a == null) return null;
    final volle = a.rawAddress.length * 8;
    final praefix = teile.length > 1 ? int.tryParse(teile[1]) : volle;
    if (praefix == null || praefix < 0 || praefix > volle) return null;
    return _Netz(a, praefix);
  }

  bool enthaelt(InternetAddress a) {
    var roh = a.rawAddress;
    // Eine IPv4-Adresse, die als IPv6 ankommt (::ffff:a.b.c.d).
    if (roh.length == 16 && adresse.rawAddress.length == 4) {
      final vorspann = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xff, 0xff];
      for (var i = 0; i < 12; i++) {
        if (roh[i] != vorspann[i]) return false;
      }
      roh = roh.sublist(12);
    }
    final soll = adresse.rawAddress;
    if (roh.length != soll.length) return false;
    var bits = praefix;
    for (var i = 0; i < soll.length && bits > 0; i++) {
      final maske = bits >= 8 ? 0xff : (0xff << (8 - bits)) & 0xff;
      if ((roh[i] & maske) != (soll[i] & maske)) return false;
      bits -= 8;
    }
    return true;
  }
}
