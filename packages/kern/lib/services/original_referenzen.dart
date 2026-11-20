import 'dart:convert';
import 'dart:collection';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

/// Gerätebezogene Zuordnung ausdrücklich gewählter Originalordner. Diese
/// Pfade gehören weder in den Katalogabgleich noch in einen Sicherungsexport.
class OriginalReferenzen {
  OriginalReferenzen(this.datei);

  final File datei;
  final Map<String, String> _ordner = {};
  final Map<String, String> _zugriffe = {};
  final Map<String, OriginalReferenz> _dateien = {};
  Future<void> _schreiben = Future.value();
  File get _journal => File('${datei.path}.jsonl');

  Map<String, String> get ordner => UnmodifiableMapView(_ordner);
  Map<String, String> get zugriffe => UnmodifiableMapView(_zugriffe);
  Map<String, OriginalReferenz> get dateien => UnmodifiableMapView(_dateien);
  static const hoechstensDateien = 200000;
  static const hoechstensBytes = 64 * 1024 * 1024;
  static bool istReferenz(String pfad) => pfad.startsWith('referenzen/');

  Future<void> laden() async {
    if (await datei.exists()) await _ladeStand();
    if (!await _journal.exists()) return;
    if (await _journal.length() > hoechstensBytes) {
      throw const FormatException('pv_referenzen_umfang');
    }
    // Nur vollständig geschriebene Zeilen sind bestätigt. Ein abgebrochener
    // letzter Anhang liegt vor dem Katalogeintrag und kann verworfen werden.
    final roh = await _journal.readAsBytes();
    final ende = roh.lastIndexOf(10);
    final bestaetigt = ende < 0 ? '' : utf8.decode(roh.sublist(0, ende + 1));
    for (final zeile in const LineSplitter().convert(bestaetigt)) {
      if (zeile.length > 16384) {
        throw const FormatException('pv_referenzen_umfang');
      }
      final j = jsonDecode(zeile) as Map;
      final id = j['id'] as String;
      if (!istReferenz(id)) throw const FormatException('pv_referenzen_format');
      if (j['wert'] == null) {
        _dateien.remove(id);
      } else {
        final wert = OriginalReferenz.ausJson(j['wert'] as Map);
        _relativ(wert.relativ);
        if (!_ordner.containsKey(wert.ordner)) {
          throw const FormatException('pv_referenzen_ordner');
        }
        _dateien[id] = wert;
      }
      if (_dateien.length > hoechstensDateien) {
        throw const FormatException('pv_referenzen_umfang');
      }
    }
    if (ende != roh.length - 1) await speichern();
  }

  Future<void> _ladeStand() async {
    if (await datei.length() > hoechstensBytes) {
      throw const FormatException('pv_referenzen_umfang');
    }
    final j = jsonDecode(await datei.readAsString()) as Map;
    if (j['fassung'] != 1) throw const FormatException('pv_referenzen_format');
    final roots = (j['ordner'] as Map).cast<String, String>();
    final zugriffe = (j['zugriffe'] as Map? ?? {}).cast<String, String>();
    final files = (j['dateien'] as Map).cast<String, Object?>();
    if (files.length > hoechstensDateien || roots.length > 1000) {
      throw const FormatException('pv_referenzen_umfang');
    }
    final parsed = {
      for (final e in files.entries)
        e.key: OriginalReferenz.ausJson(e.value as Map),
    };
    for (final e in parsed.entries) {
      if (!istReferenz(e.key) || !roots.containsKey(e.value.ordner)) {
        throw const FormatException('pv_referenzen_zuordnung');
      }
      _relativ(e.value.relativ);
    }
    _ordner.addAll(roots);
    _zugriffe.addAll(zugriffe);
    _dateien.addAll(parsed);
  }

  Future<String> ordnerHinzufuegen(Directory quelle) async {
    final real = await quelle.resolveSymbolicLinks();
    for (final e in _ordner.entries) {
      if (p.equals(e.value, real)) return e.key;
    }
    if (_ordner.length >= 1000) throw StateError('pv_referenzen_umfang');
    final id = const Uuid().v4();
    _ordner[id] = real;
    await speichern();
    return id;
  }

  Future<void> merkeZugriff(String id, String token) async {
    if (!_ordner.containsKey(id)) {
      throw const FormatException('pv_referenzen_ordner');
    }
    _zugriffe[id] = token;
    await speichern();
  }

  Future<String> aufnehmen(String ordner, File quelle) async {
    if (_dateien.length >= hoechstensDateien) {
      throw StateError('pv_referenzen_umfang');
    }
    final basis = _ordner[ordner];
    if (basis == null) throw const FormatException('pv_referenzen_ordner');
    final real = await quelle.resolveSymbolicLinks();
    if (!p.isWithin(basis, real)) {
      throw const FormatException('pv_referenzen_pfad');
    }
    final f = File(real);
    final vorher = await f.stat();
    if (vorher.type != FileSystemEntityType.file) {
      throw const FormatException('pv_referenzen_datei');
    }
    final hash = (await sha256.bind(f.openRead()).first).toString();
    final nachher = await f.stat();
    if (vorher.size != nachher.size || vorher.modified != nachher.modified) {
      throw const FormatException('pv_referenz_geaendert');
    }
    final id =
        'referenzen/${const Uuid().v4()}${p.extension(real).toLowerCase()}';
    _dateien[id] = OriginalReferenz(
      ordner,
      p.relative(real, from: basis),
      hash,
      nachher.size,
      nachher.modified,
    );
    await _anhaengen(id, _dateien[id]);
    return id;
  }

  /// Nur lesende Auflösung. Schreibpfade der Bibliothek benutzen diese
  /// Zuordnung ausdrücklich nicht.
  Future<File> lesen(String pfad, {bool inhaltPruefen = false}) async {
    final e = _dateien[pfad];
    if (e == null) throw const FormatException('pv_referenzen_unbekannt');
    final f = await _inOrdner(_ordner[e.ordner]!, e.relativ);
    final stat = await f.stat();
    if (stat.type != FileSystemEntityType.file ||
        stat.size != e.bytes ||
        !stat.modified.isAtSameMomentAs(e.geaendert)) {
      throw const FormatException('pv_referenz_geaendert');
    }
    if (inhaltPruefen &&
        (await sha256.bind(f.openRead()).first).toString() != e.sha256) {
      throw const FormatException('pv_referenz_geaendert');
    }
    return f;
  }

  /// Ein verschobener Ordner wird erst nach Prüfung sämtlicher Originale
  /// übernommen. Ein abgezogener Datenträger ändert keine Zuordnung.
  Future<void> ordnerNeuZuordnen(
    String id,
    Directory neu, {
    bool Function()? abgebrochen,
    void Function(int, int)? fortschritt,
  }) async {
    if (!_ordner.containsKey(id)) {
      throw const FormatException('pv_referenzen_ordner');
    }
    final basis = await neu.resolveSymbolicLinks();
    final werte = _dateien.values.where((e) => e.ordner == id).toList();
    var fertig = 0;
    final gepruefteZeiten = <String, DateTime>{};
    for (final e in werte) {
      if (abgebrochen?.call() == true) throw const ReferenzAbbruch();
      final f = await _inOrdner(basis, e.relativ);
      if (await f.length() != e.bytes ||
          (await sha256.bind(f.openRead()).first).toString() != e.sha256) {
        throw const FormatException('pv_referenz_geaendert');
      }
      gepruefteZeiten[e.relativ] = (await f.stat()).modified;
      fortschritt?.call(++fertig, werte.length);
    }
    if (abgebrochen?.call() == true) throw const ReferenzAbbruch();
    // Dateizeiten dürfen sich beim Umzug ändern, der Inhalt muss gleich sein.
    final aktualisiert = <String, OriginalReferenz>{};
    for (final e in _dateien.entries.where((e) => e.value.ordner == id)) {
      final f = await _inOrdner(basis, e.value.relativ);
      final stat = await f.stat();
      if (stat.modified != gepruefteZeiten[e.value.relativ] ||
          stat.size != e.value.bytes) {
        throw const FormatException('pv_referenz_geaendert');
      }
      aktualisiert[e.key] = e.value.mitZeit(stat.modified);
    }
    _ordner[id] = basis;
    _dateien.addAll(aktualisiert);
    await speichern();
  }

  Future<void> dateiNeuZuordnen(String pfad, String ordner, File quelle) async {
    final alt = _dateien[pfad];
    if (alt == null || !_ordner.containsKey(ordner)) {
      throw const FormatException('pv_referenzen_unbekannt');
    }
    final real = await quelle.resolveSymbolicLinks();
    final basis = _ordner[ordner]!;
    if (!p.isWithin(basis, real)) {
      throw const FormatException('pv_referenzen_pfad');
    }
    final stat = await quelle.stat();
    if (stat.size != alt.bytes ||
        (await sha256.bind(quelle.openRead()).first).toString() != alt.sha256) {
      throw const FormatException('pv_referenz_geaendert');
    }
    final jetzt = await quelle.stat();
    if (jetzt.modified != stat.modified || jetzt.size != stat.size) {
      throw const FormatException('pv_referenz_geaendert');
    }
    final neu = OriginalReferenz(
      ordner,
      p.relative(real, from: basis),
      alt.sha256,
      stat.size,
      stat.modified,
    );
    await _anhaengen(pfad, neu);
    _dateien[pfad] = neu;
  }

  Future<void> entfernen(String pfad) async {
    _dateien.remove(pfad);
    await _anhaengen(pfad, null);
  }

  Future<void> _anhaengen(String id, OriginalReferenz? wert) {
    final zeile = '${jsonEncode({'id': id, 'wert': wert?.alsJson()})}\n';
    final lauf = _schreiben.catchError((Object _) {}).then((_) async {
      await _journal.parent.create(recursive: true);
      if (await _journal.exists() &&
          await _journal.length() + utf8.encode(zeile).length >
              hoechstensBytes) {
        await _schreibeStand();
      }
      await _journal.writeAsString(zeile, mode: FileMode.append, flush: true);
    });
    _schreiben = lauf;
    return lauf;
  }

  Future<void> speichern() {
    final lauf = _schreiben
        .catchError((Object _) {})
        .then((_) => _schreibeStand());
    _schreiben = lauf;
    return lauf;
  }

  Future<void> _schreibeStand() async {
    final bytes = utf8.encode(
      jsonEncode({
        'fassung': 1,
        'ordner': _ordner,
        'zugriffe': _zugriffe,
        'dateien': {for (final e in _dateien.entries) e.key: e.value.alsJson()},
      }),
    );
    if (bytes.length > hoechstensBytes) {
      throw StateError('pv_referenzen_umfang');
    }
    await datei.parent.create(recursive: true);
    final teil = File('${datei.path}.${const Uuid().v4()}.part');
    try {
      await teil.writeAsBytes(bytes, flush: true);
      await teil.rename(datei.path);
      if (await _journal.exists()) await _journal.delete();
    } finally {
      if (await teil.exists()) await teil.delete();
    }
  }

  static String _relativ(String wert) {
    if (wert.isEmpty ||
        p.isAbsolute(wert) ||
        p.split(wert).contains('..') ||
        wert.contains('\u0000')) {
      throw const FormatException('pv_referenzen_pfad');
    }
    return wert;
  }

  static Future<File> _inOrdner(String basis, String relativ) async {
    _relativ(relativ);
    final realBasis = await Directory(basis).resolveSymbolicLinks();
    final real = await File(p.join(realBasis, relativ)).resolveSymbolicLinks();
    if (!p.isWithin(realBasis, real)) {
      throw const FormatException('pv_referenzen_pfad');
    }
    return File(real);
  }
}

class OriginalReferenz {
  const OriginalReferenz(
    this.ordner,
    this.relativ,
    this.sha256,
    this.bytes,
    this.geaendert,
  );
  final String ordner, relativ, sha256;
  final int bytes;
  final DateTime geaendert;
  OriginalReferenz mitZeit(DateTime zeit) =>
      OriginalReferenz(ordner, relativ, sha256, bytes, zeit);
  Map<String, Object?> alsJson() => {
    'ordner': ordner,
    'relativ': relativ,
    'sha256': sha256,
    'bytes': bytes,
    'geaendert': geaendert.toUtc().toIso8601String(),
  };
  factory OriginalReferenz.ausJson(Map j) {
    final hash = j['sha256'] as String;
    final bytes = j['bytes'] as int;
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(hash) || bytes < 0) {
      throw const FormatException('pv_referenzen_format');
    }
    return OriginalReferenz(
      j['ordner'] as String,
      j['relativ'] as String,
      hash,
      bytes,
      DateTime.parse(j['geaendert'] as String),
    );
  }
}

class ReferenzAbbruch implements Exception {
  const ReferenzAbbruch();
}
