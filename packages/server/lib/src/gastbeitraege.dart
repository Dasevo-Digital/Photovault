import 'dart:convert';
import 'dart:math';

import 'konten/serverdatenbank.dart';

/// Was ein Gast über einen Link hochgeladen hat (Issue #106).
class Gastbeitrag {
  const Gastbeitrag({
    required this.id,
    required this.freigabe,
    required this.konto,
    required this.name,
    required this.von,
    required this.groesse,
    required this.zustand,
    required this.befund,
    required this.angelegt,
  });

  final String id;
  final String freigabe;
  final String konto;

  /// Der Dateiname, wie der Gast ihn geschickt hat – bereinigt.
  final String name;

  /// Der Name, den der Gast angegeben hat, sonst `null`.
  final String? von;
  final int groesse;

  /// `pruefung` (der Prüfprozess läuft oder wartet), `bereit` (geprüft,
  /// wartet auf den Besitzer), `abgewiesen` (die Prüfung lehnte ab).
  final String zustand;

  /// Was die Prüfung fand (Art, Grösse, Zeit, Ort) oder warum sie
  /// ablehnte (`grund`).
  final Map<String, Object?> befund;
  final DateTime angelegt;
}

/// Die Beiträge in server.sqlite. Die Dateien selbst liegen in der
/// Bibliothek des Kontos unter `gaeste/<id>/`.
class Gastbeitraege {
  Gastbeitraege(this._sdb, {DateTime Function()? uhr})
    : _uhr = uhr ?? DateTime.now;

  final Serverdatenbank _sdb;
  final DateTime Function() _uhr;

  /// Höchstens so viele offene Beiträge je Freigabe – danach nimmt sie
  /// nichts mehr an, bis der Besitzer entschieden hat.
  static const hoechstensOffen = 2000;

  static final _zufall = Random.secure();

  /// Eine Kennung, die auch als Ordnername taugt.
  static String _kennung() => List<int>.generate(
    16,
    (_) => _zufall.nextInt(256),
  ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  /// Nur, was als Dateiname nichts anrichten kann.
  static String bereinigt(String name) {
    final ohnePfad = name.split(RegExp(r'[\\/]')).last;
    final sauber = ohnePfad
        .replaceAll(RegExp(r'[^\p{L}\p{N} ._()\-]', unicode: true), '_')
        .replaceAll(RegExp(r'^\.+'), '')
        .trim();
    final kurz = sauber.length > 120 ? sauber.substring(0, 120) : sauber;
    return kurz.isEmpty ? 'beitrag' : kurz;
  }

  Gastbeitrag _aus(Map<String, Object?> z) => Gastbeitrag(
    id: z['id']! as String,
    freigabe: z['freigabe']! as String,
    konto: z['konto']! as String,
    name: z['name']! as String,
    von: z['von'] as String?,
    groesse: z['groesse']! as int,
    zustand: z['zustand']! as String,
    befund: z['befund'] == null
        ? const {}
        : (jsonDecode(z['befund']! as String) as Map).cast<String, Object?>(),
    angelegt: DateTime.fromMillisecondsSinceEpoch(z['angelegt']! as int),
  );

  /// Legt einen Beitrag an, der noch geprüft werden muss.
  Gastbeitrag lege({
    required String freigabe,
    required String konto,
    required String name,
    required String? von,
    required int groesse,
    required String absender,
  }) {
    final id = _kennung();
    _sdb.db.execute(
      'INSERT INTO gastbeitraege (id, freigabe, konto, name, von, groesse, '
      'absender, zustand, angelegt) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        id,
        freigabe,
        konto,
        bereinigt(name),
        von,
        groesse,
        absender,
        'pruefung',
        _uhr().millisecondsSinceEpoch,
      ],
    );
    return eines(konto, id)!;
  }

  /// Wie viele Beiträge zu [freigabe] noch auf eine Entscheidung warten.
  int offen(String freigabe) =>
      _sdb.db.select(
            'SELECT COUNT(*) AS n FROM gastbeitraege WHERE freigabe = ?',
            [freigabe],
          ).first['n']
          as int;

  /// Die Beiträge eines Kontos, die jüngsten zuerst.
  List<Gastbeitrag> von(String konto) => [
    for (final z in _sdb.db.select(
      'SELECT * FROM gastbeitraege WHERE konto = ? ORDER BY angelegt DESC',
      [konto],
    ))
      _aus(z),
  ];

  Gastbeitrag? eines(String konto, String id) {
    final z = _sdb.db.select(
      'SELECT * FROM gastbeitraege WHERE id = ? AND konto = ?',
      [id, konto],
    );
    return z.isEmpty ? null : _aus(z.first);
  }

  /// Die Beiträge einer Freigabe (vor dem Löschen der Freigabe).
  List<Gastbeitrag> zu(String freigabe) => [
    for (final z in _sdb.db.select(
      'SELECT * FROM gastbeitraege WHERE freigabe = ?',
      [freigabe],
    ))
      _aus(z),
  ];

  void geprueft(
    String id, {
    required bool ok,
    required Map<String, Object?> befund,
  }) => _sdb.db.execute(
    'UPDATE gastbeitraege SET zustand = ?, befund = ? WHERE id = ?',
    [ok ? 'bereit' : 'abgewiesen', jsonEncode(befund), id],
  );

  void entferne(String id) =>
      _sdb.db.execute('DELETE FROM gastbeitraege WHERE id = ?', [id]);
}
