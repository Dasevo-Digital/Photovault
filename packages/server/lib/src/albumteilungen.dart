import 'dart:math';

import 'konten/serverdatenbank.dart';

/// Ein Album, das ein Konto mit einem anderen teilt (#105).
class Albumteilung {
  const Albumteilung({
    required this.id,
    required this.besitzer,
    required this.album,
    required this.empfaenger,
    required this.beitragen,
    required this.angelegt,
  });

  final String id;

  /// Das Konto, dem das Album gehört; es liegt in seiner Bibliothek.
  final String besitzer;
  final String album;
  final String empfaenger;

  /// Ob der Empfänger eigene Aufnahmen hineinlegen darf. Sonst sieht er
  /// das Album nur.
  final bool beitragen;
  final DateTime angelegt;
}

/// Ein Kommentar in einem geteilten Album (#297) – zum Album selbst
/// ([aufnahme] leer) oder zu einer Aufnahme darin.
class Albumkommentar {
  const Albumkommentar({
    required this.id,
    required this.aufnahme,
    required this.von,
    required this.name,
    required this.text,
    required this.angelegt,
  });

  final String id;
  final String? aufnahme;

  /// Das Konto, das ihn schrieb – `null`, wenn es das Konto nicht mehr
  /// gibt. [name] bleibt stehen.
  final String? von;
  final String name;
  final String text;
  final DateTime angelegt;
}

/// Wer welches Album mit wem teilt, in server.sqlite.
///
/// **Warum hier und nicht in der Bibliothek.** Eine Bibliothek gehört
/// genau einem Konto und weiss nichts von anderen (siehe
/// [Serverdatenbank]). Was zwischen zwei Konten gilt, steht deshalb neben
/// den Konten; die Bibliothek des Besitzers bleibt, wie sie ist, und lässt
/// sich ohne fremde Kennungen sichern und weitergeben.
///
/// **Gelöschte Alben.** Die Bibliothek meldet nicht, wenn ein Album geht.
/// Wer nachsieht, findet die Teilung ohne Album und räumt sie weg (siehe
/// `Teilungsapi`). Gelöschte Konten nimmt die Datenbank selbst mit.
class Albumteilungen {
  Albumteilungen(this._sdb, {DateTime Function()? uhr})
    : _uhr = uhr ?? DateTime.now;

  final Serverdatenbank _sdb;
  final DateTime Function() _uhr;

  /// Mit höchstens so vielen Konten lässt sich ein Album teilen.
  static const hoechstensEmpfaenger = 100;

  static final _zufall = Random.secure();

  static String _kennung() => List<int>.generate(
    16,
    (_) => _zufall.nextInt(256),
  ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  Albumteilung _aus(Map<String, Object?> z) => Albumteilung(
    id: z['id']! as String,
    besitzer: z['besitzer']! as String,
    album: z['album']! as String,
    empfaenger: z['empfaenger']! as String,
    beitragen: z['beitragen'] == 1,
    angelegt: DateTime.fromMillisecondsSinceEpoch(z['angelegt']! as int),
  );

  /// Teilt [album] von [besitzer] mit [empfaenger] – oder ändert, ob er
  /// beitragen darf, wenn es schon geteilt ist.
  Albumteilung teile({
    required String besitzer,
    required String album,
    required String empfaenger,
    required bool beitragen,
  }) {
    if (besitzer == empfaenger) {
      throw ArgumentError('mit sich selbst teilen');
    }
    final da = vonAlbum(besitzer, album);
    final schon = da.where((t) => t.empfaenger == empfaenger).firstOrNull;
    if (schon == null && da.length >= hoechstensEmpfaenger) {
      throw StateError('zu viele Empfänger');
    }
    _sdb.db.execute(
      'INSERT INTO albumteilungen (id, besitzer, album, empfaenger, '
      'beitragen, angelegt) VALUES (?, ?, ?, ?, ?, ?) '
      'ON CONFLICT (besitzer, album, empfaenger) '
      'DO UPDATE SET beitragen = excluded.beitragen',
      [
        _kennung(),
        besitzer,
        album,
        empfaenger,
        beitragen ? 1 : 0,
        _uhr().millisecondsSinceEpoch,
      ],
    );
    return vonAlbum(
      besitzer,
      album,
    ).firstWhere((t) => t.empfaenger == empfaenger);
  }

  /// Mit wem [besitzer] sein [album] teilt, in der Reihenfolge des Teilens.
  List<Albumteilung> vonAlbum(String besitzer, String album) => [
    for (final z in _sdb.db.select(
      'SELECT * FROM albumteilungen WHERE besitzer = ? AND album = ? '
      'ORDER BY angelegt, id',
      [besitzer, album],
    ))
      _aus(z),
  ];

  /// Alle Teilungen von [besitzer] – für die Albenliste, die zeigt, was
  /// geteilt ist.
  List<Albumteilung> vonBesitzer(String besitzer) => [
    for (final z in _sdb.db.select(
      'SELECT * FROM albumteilungen WHERE besitzer = ? ORDER BY angelegt, id',
      [besitzer],
    ))
      _aus(z),
  ];

  /// Was mit [empfaenger] geteilt ist, das zuletzt geteilte zuerst.
  List<Albumteilung> mitKonto(String empfaenger) => [
    for (final z in _sdb.db.select(
      'SELECT * FROM albumteilungen WHERE empfaenger = ? '
      'ORDER BY angelegt DESC, id',
      [empfaenger],
    ))
      _aus(z),
  ];

  /// Die Teilung [id], wenn [konto] sie sehen darf – als Besitzer oder
  /// als Empfänger.
  Albumteilung? eine(String id, String konto) {
    final z = _sdb.db.select(
      'SELECT * FROM albumteilungen WHERE id = ? '
      'AND (empfaenger = ? OR besitzer = ?)',
      [id, konto, konto],
    );
    return z.isEmpty ? null : _aus(z.first);
  }

  /// Hebt die Teilung [id] auf – der Besitzer oder der Empfänger, der
  /// das Album nicht mehr sehen will. `false`, wenn es sie nicht gibt.
  bool entferne(String id, String konto) {
    _sdb.db.execute(
      'DELETE FROM albumteilungen WHERE id = ? '
      'AND (empfaenger = ? OR besitzer = ?)',
      [id, konto, konto],
    );
    return _sdb.db.updatedRows > 0;
  }

  /// Alle Teilungen eines Albums, das es nicht mehr gibt – samt seinen
  /// Kommentaren und „Gefällt mir“ (#297).
  void entferneAlbum(String besitzer, String album) {
    for (final tabelle in const [
      'albumteilungen',
      'albumkommentare',
      'albumgefaellt',
    ]) {
      _sdb.db.execute('DELETE FROM $tabelle WHERE besitzer = ? AND album = ?', [
        besitzer,
        album,
      ]);
    }
  }

  // --- Was andere beigetragen haben ----------------------------------------

  /// Vermerkt, dass [von] die Aufnahme [aufnahme] in die Bibliothek von
  /// [besitzer] gelegt hat. [name] ist der Name des Kontos zu dem Zeitpunkt
  /// – er bleibt stehen, auch wenn das Konto später geht.
  void vermerkeBeitrag({
    required String besitzer,
    required String aufnahme,
    required String von,
    required String name,
    required String album,
  }) => _sdb.db.execute(
    'INSERT OR IGNORE INTO kontobeitraege (besitzer, aufnahme, von, name, '
    'angelegt, album, gesehen) VALUES (?, ?, ?, ?, ?, ?, 0)',
    [besitzer, aufnahme, von, name, _uhr().millisecondsSinceEpoch, album],
  );

  /// Was andere in die Alben von [besitzer] gelegt haben und er noch nicht
  /// gesehen hat (#295), je Album: Aufnahmen, wer, und wann zuletzt.
  List<
    ({String album, List<String> aufnahmen, List<String> von, DateTime zuletzt})
  >
  neueBeitraege(String besitzer) {
    final je =
        <String, ({List<String> aufnahmen, Set<String> von, int zuletzt})>{};
    for (final z in _sdb.db.select(
      'SELECT album, aufnahme, name, angelegt FROM kontobeitraege '
      'WHERE besitzer = ? AND gesehen = 0 AND album IS NOT NULL '
      'ORDER BY angelegt',
      [besitzer],
    )) {
      final album = z['album']! as String;
      final e = je.putIfAbsent(
        album,
        () => (aufnahmen: <String>[], von: <String>{}, zuletzt: 0),
      );
      e.aufnahmen.add(z['aufnahme']! as String);
      e.von.add(z['name']! as String);
      je[album] = (
        aufnahmen: e.aufnahmen,
        von: e.von,
        zuletzt: z['angelegt']! as int,
      );
    }
    return [
      for (final MapEntry(:key, :value) in je.entries)
        (
          album: key,
          aufnahmen: value.aufnahmen,
          von: value.von.toList(),
          zuletzt: DateTime.fromMillisecondsSinceEpoch(value.zuletzt),
        ),
    ]..sort((a, b) => b.zuletzt.compareTo(a.zuletzt));
  }

  /// [besitzer] hat [album] angesehen: Was darin neu war, ist es nicht mehr.
  void beitraegeGesehen(String besitzer, String album) => _sdb.db.execute(
    'UPDATE kontobeitraege SET gesehen = 1 '
    'WHERE besitzer = ? AND album = ? AND gesehen = 0',
    [besitzer, album],
  );

  /// [besitzer] hat [aufnahmen] endgültig gelöscht (#296): Was andere dazu
  /// beigetragen haben, braucht keinen Hinweis mehr.
  ///
  /// Kommentare und „Gefällt mir“ zu ihnen gehen ebenso (#297).
  void vergissBeitraege(String besitzer, List<String> aufnahmen) {
    for (var i = 0; i < aufnahmen.length; i += 500) {
      final teil = aufnahmen.sublist(i, min(i + 500, aufnahmen.length));
      for (final tabelle in const [
        'kontobeitraege',
        'albumkommentare',
        'albumgefaellt',
      ]) {
        _sdb.db.execute(
          'DELETE FROM $tabelle WHERE besitzer = ? AND aufnahme IN '
          '(${List.filled(teil.length, '?').join(', ')})',
          [besitzer, ...teil],
        );
      }
    }
  }

  /// Wer welche der [aufnahmen] von [besitzer] beigetragen hat: Kennung →
  /// Konto (`null`, wenn es das Konto nicht mehr gibt) und Name. Was der
  /// Besitzer selbst hat, fehlt.
  Map<String, ({String? konto, String name})> beitragende(
    String besitzer,
    Iterable<String> aufnahmen,
  ) {
    final ids = aufnahmen.toList();
    final ergebnis = <String, ({String? konto, String name})>{};
    for (var i = 0; i < ids.length; i += 500) {
      final teil = ids.sublist(i, min(i + 500, ids.length));
      final platz = List.filled(teil.length, '?').join(', ');
      for (final z in _sdb.db.select(
        'SELECT aufnahme, von, name FROM kontobeitraege '
        'WHERE besitzer = ? AND aufnahme IN ($platz)',
        [besitzer, ...teil],
      )) {
        ergebnis[z['aufnahme']! as String] = (
          konto: z['von'] as String?,
          name: z['name']! as String,
        );
      }
    }
    return ergebnis;
  }

  // --- Kommentare und „Gefällt mir“ (#297) ----------------------------------

  /// So lang darf ein Kommentar sein (in Zeichen).
  static const kommentarHoechstens = 2000;

  /// So viele Kommentare nimmt ein Album höchstens an.
  static const kommentareJeAlbum = 5000;

  Albumkommentar _kommentarAus(Map<String, Object?> z) => Albumkommentar(
    id: z['id']! as String,
    aufnahme: z['aufnahme'] as String?,
    von: z['von'] as String?,
    name: z['name']! as String,
    text: z['text']! as String,
    angelegt: DateTime.fromMillisecondsSinceEpoch(z['angelegt']! as int),
  );

  /// [von] (mit seinem [name] zu diesem Zeitpunkt) schreibt [text] zu
  /// [album] von [besitzer] – mit [aufnahme] zu diesem Foto.
  Albumkommentar kommentiere({
    required String besitzer,
    required String album,
    String? aufnahme,
    required String von,
    required String name,
    required String text,
  }) {
    final rein = text.trim();
    if (rein.isEmpty || rein.length > kommentarHoechstens) {
      throw ArgumentError('Kommentar leer oder zu lang');
    }
    final n =
        _sdb.db.select(
              'SELECT count(*) AS n FROM albumkommentare '
              'WHERE besitzer = ? AND album = ?',
              [besitzer, album],
            ).single['n']
            as int;
    if (n >= kommentareJeAlbum) throw StateError('zu viele Kommentare');
    final id = _kennung();
    _sdb.db.execute(
      'INSERT INTO albumkommentare (id, besitzer, album, aufnahme, von, '
      'name, text, angelegt) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      [
        id,
        besitzer,
        album,
        aufnahme,
        von,
        name,
        rein,
        _uhr().millisecondsSinceEpoch,
      ],
    );
    return kommentare(besitzer, album).firstWhere((k) => k.id == id);
  }

  /// Die Kommentare in [album], der älteste zuerst.
  List<Albumkommentar> kommentare(String besitzer, String album) => [
    for (final z in _sdb.db.select(
      'SELECT * FROM albumkommentare WHERE besitzer = ? AND album = ? '
      'ORDER BY angelegt, id',
      [besitzer, album],
    ))
      _kommentarAus(z),
  ];

  /// Nimmt den Kommentar [id] aus [album] – [konto] den eigenen, der
  /// Besitzer des Albums jeden. `false`, wenn es ihn nicht gibt oder
  /// [konto] nicht darf.
  bool entferneKommentar(
    String id, {
    required String besitzer,
    required String album,
    required String konto,
  }) {
    _sdb.db.execute(
      'DELETE FROM albumkommentare WHERE id = ? AND besitzer = ? '
      'AND album = ? AND (von = ? OR besitzer = ?)',
      [id, besitzer, album, konto, konto],
    );
    return _sdb.db.updatedRows > 0;
  }

  /// [von] findet [aufnahme] in [album] gut – oder nicht mehr ([an]).
  void gefaellt(
    String besitzer,
    String album,
    String aufnahme,
    String von, {
    required bool an,
  }) => an
      ? _sdb.db.execute(
          'INSERT OR IGNORE INTO albumgefaellt (besitzer, album, aufnahme, '
          'von, angelegt) VALUES (?, ?, ?, ?, ?)',
          [besitzer, album, aufnahme, von, _uhr().millisecondsSinceEpoch],
        )
      : _sdb.db.execute(
          'DELETE FROM albumgefaellt WHERE besitzer = ? AND album = ? '
          'AND aufnahme = ? AND von = ?',
          [besitzer, album, aufnahme, von],
        );

  /// Wem welche Aufnahme in [album] gefällt: Aufnahme → Konten, in der
  /// Reihenfolge, in der sie es sagten.
  Map<String, List<String>> gefaelltIn(String besitzer, String album) {
    final je = <String, List<String>>{};
    for (final z in _sdb.db.select(
      'SELECT aufnahme, von FROM albumgefaellt WHERE besitzer = ? '
      'AND album = ? ORDER BY angelegt',
      [besitzer, album],
    )) {
      (je[z['aufnahme']! as String] ??= []).add(z['von']! as String);
    }
    return je;
  }

  // --- Partnerfreigabe (#293) -----------------------------------------------

  /// [besitzer] lässt [partner] seine ganze Bibliothek sehen.
  void partnerSetzen(String besitzer, String partner) {
    if (besitzer == partner) throw ArgumentError('mit sich selbst teilen');
    _sdb.db.execute(
      'INSERT OR IGNORE INTO partnerfreigaben (besitzer, partner, angelegt) '
      'VALUES (?, ?, ?)',
      [besitzer, partner, _uhr().millisecondsSinceEpoch],
    );
  }

  /// Hebt die Freigabe auf – der Besitzer, oder der Partner, der die
  /// Bibliothek nicht mehr sehen will.
  void partnerEntfernen(String besitzer, String partner) => _sdb.db.execute(
    'DELETE FROM partnerfreigaben WHERE besitzer = ? AND partner = ?',
    [besitzer, partner],
  );

  /// Wen [besitzer] seine Bibliothek sehen lässt.
  List<String> partnerVon(String besitzer) => [
    for (final z in _sdb.db.select(
      'SELECT partner FROM partnerfreigaben WHERE besitzer = ? '
      'ORDER BY angelegt',
      [besitzer],
    ))
      z['partner']! as String,
  ];

  /// Wer [partner] seine Bibliothek sehen lässt.
  List<String> partnerMit(String partner) => [
    for (final z in _sdb.db.select(
      'SELECT besitzer FROM partnerfreigaben WHERE partner = ? '
      'ORDER BY angelegt',
      [partner],
    ))
      z['besitzer']! as String,
  ];

  bool istPartner(String besitzer, String partner) => _sdb.db.select(
    'SELECT 1 FROM partnerfreigaben WHERE besitzer = ? AND partner = ?',
    [besitzer, partner],
  ).isNotEmpty;
}
