part of 'abgleich.dart';

extension Abgleichsfaelle on Abgleich {
  Future<SecretKey> _fallschluessel() async {
    if (_festerFallschluessel != null) return _festerFallschluessel;
    if (verbindung.token.isEmpty) throw const TokenablageFehler();
    return SecretKey(
      (await Sha256().hash(
        utf8.encode('pv_abgleichsfall_1:${verbindung.token}'),
      )).bytes,
    );
  }

  Future<Map<String, Object?>> _leseAuftrag(String text) async {
    final j = (jsonDecode(text) as Map).cast<String, Object?>();
    if (j['art'] is String) return {'befehl': j, 'basis': const []};
    return _oeffneFall(text);
  }

  Future<String> _verpackeFall(Map<String, Object?> wert) async {
    final box = await AesGcm.with256bits().encrypt(
      utf8.encode(jsonEncode(wert)),
      secretKey: await _fallschluessel(),
    );
    return jsonEncode({
      'n': base64Encode(box.nonce),
      'c': base64Encode(box.cipherText),
      'm': base64Encode(box.mac.bytes),
    });
  }

  Future<Map<String, Object?>> _oeffneFall(String text) async {
    final j = jsonDecode(text) as Map;
    final klar = await AesGcm.with256bits().decrypt(
      SecretBox(
        base64Decode(j['c'] as String),
        nonce: base64Decode(j['n'] as String),
        mac: Mac(base64Decode(j['m'] as String)),
      ),
      secretKey: await _fallschluessel(),
    );
    return (jsonDecode(utf8.decode(klar)) as Map).cast<String, Object?>();
  }

  Future<List<Abgleichsfall>> faelle({int limit = 200, int offset = 0}) async {
    if (limit < 1 || limit > 1000 || offset < 0) {
      throw ArgumentError('pv_sync_limit');
    }
    final rows = await db
        .customSelect(
          'SELECT kennung, angelegt AS am, befehl AS vorschau, NULL AS grund, 1 AS offen '
          'FROM pv_ausgang WHERE bestaetigt IS NULL UNION ALL '
          'SELECT kennung, am, inhalt AS vorschau, grund, 0 AS offen FROM pv_abgleichsfaelle '
          'ORDER BY am DESC, kennung LIMIT ? OFFSET ?',
          variables: [Variable<int>(limit), Variable<int>(offset)],
        )
        .get();
    final result = <Abgleichsfall>[];
    for (final r in rows) {
      final kennung = r.read<String>('kennung');
      final am = DateTime.fromMillisecondsSinceEpoch(r.read<int>('am'));
      try {
        final payload = await _leseAuftrag(r.read<String>('vorschau'));
        result.add(
          Abgleichsfall(
            kennung: kennung,
            am: am,
            befehl: (payload['befehl'] as Map).cast<String, Object?>(),
            basis: [
              for (final b in payload['basis'] as List)
                Befehlsbasis.ausJson((b as Map).cast<String, Object?>()),
            ],
            grund: r.readNullable<String>('grund'),
            ausstehend: r.read<int>('offen') == 1,
          ),
        );
      } on Object {
        result.add(
          Abgleichsfall(
            kennung: kennung,
            am: am,
            befehl: const {},
            basis: const [],
            grund: 'pv_sync_sitzung',
            ausstehend: r.read<int>('offen') == 1,
            lesbar: false,
          ),
        );
      }
    }
    return result;
  }

  Future<Abgleichsvergleich> vergleiche(Abgleichsfall fall) async {
    if (fall.ausstehend) {
      final fotos = [for (final id in fall.fotoIds) ?await db.assetById(id)];
      final geschuetzt = fotos.any((a) => a.isLocked);
      return Abgleichsvergleich(
        fall: fall,
        serverwerte: List.filled(fall.basis.length, null),
        stand: '',
        geschuetzt: geschuetzt,
        entfernt: fotos.any((a) => a.isTrashed),
        fotobezeichnungen: geschuetzt
            ? const {}
            : {for (final a in fotos) a.id: a.originalFileName},
        fotonamen: geschuetzt
            ? const []
            : [for (final a in fotos.take(20)) a.originalFileName],
      );
    }
    // Änderungen anderer Geräte werden vor einer Entscheidung abgeholt.
    await empfange();
    final ids = fall.fotoIds;
    final anfragen = <Map<String, Object?>>[
      for (final b in fall.basis) {'t': b.tabelle, 's': b.schluessel},
      for (final id in ids)
        {
          't': 'assets',
          's': [id],
        },
    ];
    String zeilenschluessel(String t, List<Object?> s) =>
        '$t\u0000${jsonEncode(s)}';
    final gelesen = <String, Zeilenstand>{};
    for (var i = 0; i < anfragen.length; i += 500) {
      final antwort = await verbindung.schicke('api/v1/abgleich/zeilen', {
        'schluessel': anfragen.sublist(i, min(i + 500, anfragen.length)),
      });
      for (final j in antwort['zeilen'] as List) {
        final row = Zeilenstand.ausJson((j as Map).cast<String, Object?>());
        gelesen[zeilenschluessel(row.tabelle, row.schluessel)] = row;
      }
    }
    final fotos = [
      for (final id in ids) ?gelesen[zeilenschluessel('assets', [id])]?.werte,
    ];
    final geschuetzt = fotos.any((a) => a['is_locked'] == 1);
    final werte = <Map<String, Object?>?>[];
    final hashes = <String>[];
    var entfernt =
        fotos.length != ids.length || fotos.any((a) => a['is_trashed'] == 1);
    for (final basis in fall.basis) {
      final row = gelesen[zeilenschluessel(basis.tabelle, basis.schluessel)];
      if (row == null) throw const FormatException('pv_sync_zeile_fehlt');
      if (row.werte == null &&
          basis.vorher != Befehlsbasis.hash(null, basis.spalten)) {
        entfernt = true;
      }
      hashes.add(Befehlsbasis.hash(row.werte, basis.spalten));
      werte.add(
        geschuetzt
            ? null
            : row.werte == null
            ? null
            : {for (final s in basis.spalten) s: wertAlsJson(row.werte![s])},
      );
    }
    return Abgleichsvergleich(
      fall: fall,
      serverwerte: werte,
      stand: jsonEncode(hashes),
      geschuetzt: geschuetzt,
      entfernt: entfernt,
      fotobezeichnungen: geschuetzt
          ? const {}
          : {
              for (final a in fotos)
                a['id'] as String: a['original_file_name'] as String,
            },
      fotonamen: [
        for (final a in fotos.take(20))
          if (a['is_locked'] != 1) a['original_file_name'] as String,
      ],
    );
  }

  Future<void> behalteServerstand(Abgleichsfall fall) async {
    if (fall.ausstehend) throw StateError('pv_sync_ausstehend');
    await empfange();
    await db.customStatement(
      'DELETE FROM pv_abgleichsfaelle WHERE kennung = ?',
      [fall.kennung],
    );
    await _melde();
  }

  Future<void> erneutAnwenden(Abgleichsvergleich vergleich) async {
    final fall = vergleich.fall;
    if (fall.ausstehend ||
        !fall.lesbar ||
        vergleich.geschuetzt ||
        vergleich.entfernt) {
      throw StateError('pv_sync_nicht_anwendbar');
    }
    final aktuell = await vergleiche(fall);
    if (aktuell.stand != vergleich.stand ||
        aktuell.geschuetzt ||
        aktuell.entfernt) {
      throw const AbgleichsstandGeaendert();
    }
    final z = await verbindung.hole('api/v1/zustand');
    if ((z['funktionen'] as Map?)?['konfliktpruefung'] != 1) {
      throw const AbgleichsserverZuAlt();
    }
    await db.transaction(() async {
      final nochDa = await db
          .customSelect(
            'SELECT 1 FROM pv_abgleichsfaelle WHERE kennung = ?',
            variables: [Variable<String>(fall.kennung)],
          )
          .getSingleOrNull();
      if (nochDa == null) throw const AbgleichsstandGeaendert();
      await _stelleEin(Befehl.ausJson(fall.befehl));
      await db.customStatement(
        'DELETE FROM pv_abgleichsfaelle WHERE kennung = ?',
        [fall.kennung],
      );
    });
    final befehl = Befehl.ausJson(fall.befehl);
    for (final beobachter in db.befehlsbeobachter) {
      beobachter(befehl);
    }
    await _melde();
    sendeBald();
  }
}
