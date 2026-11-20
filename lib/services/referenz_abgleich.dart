import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/import_service.dart';
import 'package:kern/services/original_referenzen.dart';
import 'package:kern/services/referenz_katalog.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'platform/folder_access.dart';
import 'platform/speicherlaufwerk.dart';

enum ReferenzAenderung { neu, geaendert, fehlt }

class ReferenzPruefeintrag {
  const ReferenzPruefeintrag(this.relativ, this.art, this.sha256);
  final String relativ;
  final ReferenzAenderung art;
  final String? sha256;
  Map<String, Object?> json() => {
    'pfad': relativ,
    'art': art.name,
    'sha256': sha256,
  };
  factory ReferenzPruefeintrag.aus(Map j) {
    final pfad = j['pfad'] as String;
    if (p.isAbsolute(pfad) || p.split(p.normalize(pfad)).contains('..')) {
      throw const FormatException('pv_referenz_abgleich_pfad');
    }
    final hash = j['sha256'] as String?;
    if (hash != null && !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) {
      throw const FormatException('pv_referenz_abgleich_hash');
    }
    return ReferenzPruefeintrag(
      pfad,
      ReferenzAenderung.values.byName(j['art'] as String),
      hash,
    );
  }
}

class ReferenzPruefplan {
  const ReferenzPruefplan(
    this.ordner,
    this.am,
    this.eintraege, {
    required this.erreichbar,
    required this.vollstaendig,
  });
  final String ordner;
  final DateTime am;
  final List<ReferenzPruefeintrag> eintraege;
  final bool erreichbar, vollstaendig;
  Map<String, Object?> json() => {
    'ordner': ordner,
    'am': am.toUtc().toIso8601String(),
    'erreichbar': erreichbar,
    'vollstaendig': vollstaendig,
    'eintraege': [for (final e in eintraege) e.json()],
  };
  factory ReferenzPruefplan.aus(Map j) {
    final werte = j['eintraege'] as List;
    if (werte.length > 200000) {
      throw const FormatException('pv_referenz_abgleich_umfang');
    }
    return ReferenzPruefplan(
      j['ordner'] as String,
      DateTime.parse(j['am'] as String),
      [for (final e in werte) ReferenzPruefeintrag.aus(e as Map)],
      erreichbar: j['erreichbar'] == true,
      vollstaendig: j['vollstaendig'] == true,
    );
  }
}

/// Eine geplante Prüfung erstellt ausschließlich eine Vorschau. Erst die
/// ausdrückliche Übernahme importiert neue Dateien. Änderungen an schon
/// katalogisierten Originalen bleiben sichtbare Konflikte.
class ReferenzAbgleich {
  ReferenzAbgleich(
    this.db,
    this.paths,
    this.importiere, {
    FolderAccess? zugriff,
    DateTime Function()? uhr,
    Future<Speicherlaufwerk?> Function(String)? laufwerk,
  }) : laufwerk = laufwerk ?? Laufwerksauskunft.fuer,
       zugriff = zugriff ?? FolderAccess.forCurrentPlatform(),
       uhr = uhr ?? DateTime.now;
  final AppDatabase db;
  final StoragePaths paths;
  final ImportService importiere;
  final FolderAccess zugriff;
  final Future<Speicherlaufwerk?> Function(String) laufwerk;
  final Map<String, String> laufwerkskennungen = {};
  final Map<String, List<String>> ausschluesse = {};
  final DateTime Function() uhr;
  bool _beendet = false, _laeuft = false;
  void beende() => _beendet = true;
  OriginalReferenzen get refs => paths.referenzen!;
  File get datei => File('${refs.datei.path}.abgleich.json');
  final Map<String, int> intervalle = {};
  final Map<String, ReferenzPruefplan> plaene = {};
  Future<void>? _ladevorgang;
  Future<void> laden() => _ladevorgang ??= _lade();

  Future<void> _lade() async {
    if (await datei.exists()) {
      if (await datei.length() > 32 * 1024 * 1024) {
        throw const FormatException('pv_referenz_abgleich_umfang');
      }
      final bytes = <int>[];
      await for (final teil in datei.openRead()) {
        if (bytes.length + teil.length > 32 * 1024 * 1024) {
          throw const FormatException('pv_referenz_abgleich_umfang');
        }
        bytes.addAll(teil);
      }
      final j = jsonDecode(utf8.decode(bytes)) as Map;
      if (j['fassung'] != 1) {
        throw const FormatException('pv_referenz_abgleich_format');
      }
      final zeiten = (j['intervalle'] as Map).cast<String, int>();
      if (zeiten.length > 1000 || zeiten.values.any((v) => v < 1 || v > 720)) {
        throw const FormatException('pv_referenz_abgleich_intervall');
      }
      final p = j['plaene'] as List;
      if (p.length > 1000) {
        throw const FormatException('pv_referenz_abgleich_umfang');
      }
      final gelesen = [for (final v in p) ReferenzPruefplan.aus(v as Map)];
      final laufwerke = (j['laufwerke'] as Map? ?? {}).cast<String, String>();
      if (laufwerke.length > 1000) {
        throw const FormatException('pv_referenz_abgleich_umfang');
      }
      final ausgeschlossen = (j['ausschluesse'] as Map? ?? {})
          .cast<String, List>();
      if (ausgeschlossen.length > 1000 ||
          ausgeschlossen.values.any((v) => v.length > 100)) {
        throw const FormatException('pv_referenz_abgleich_umfang');
      }
      for (final e in ausgeschlossen.entries) {
        ausschluesse[e.key] = e.value.cast<String>();
        if (ausschluesse[e.key]!.any((v) => v.length > 256)) {
          throw const FormatException('pv_referenz_abgleich_umfang');
        }
      }
      laufwerkskennungen.addAll(laufwerke);
      intervalle.addAll(zeiten);
      plaene.addAll({for (final p in gelesen) p.ordner: p});
    }
  }

  Future<void> _speichern() async {
    if (_beendet) throw const ReferenzAbbruch();
    final text = jsonEncode({
      'fassung': 1,
      'intervalle': intervalle,
      'laufwerke': laufwerkskennungen,
      'ausschluesse': ausschluesse,
      'plaene': [for (final p in plaene.values) p.json()],
    });
    if (utf8.encode(text).length > 32 * 1024 * 1024) {
      throw const FormatException('pv_referenz_abgleich_umfang');
    }
    await datei.parent.create(recursive: true);
    final teil = File('${datei.path}.${const Uuid().v4()}.part');
    try {
      await teil.writeAsString(text, flush: true);
      if (_beendet) throw const ReferenzAbbruch();
      await teil.rename(datei.path);
    } finally {
      if (await teil.exists()) await teil.delete();
    }
  }

  Future<void> plane(
    String ordner,
    int? stunden, {
    List<String>? ausschliessen,
  }) async {
    await laden();
    if (!refs.ordner.containsKey(ordner) ||
        (stunden != null && (stunden < 1 || stunden > 720))) {
      throw const FormatException('pv_referenz_abgleich_intervall');
    }
    if (ausschliessen != null) {
      if (ausschliessen.length > 100 ||
          ausschliessen.any((s) => s.length > 256)) {
        throw const FormatException('pv_referenz_abgleich_umfang');
      }
      ausschluesse[ordner] = List.unmodifiable(ausschliessen);
      plaene.remove(ordner);
    }
    if (stunden == null) {
      intervalle.remove(ordner);
    } else {
      intervalle[ordner] = stunden;
    }
    await _speichern();
  }

  Future<void> bestaetigeNeueZuordnung(String ordner) async {
    await laden();
    laufwerkskennungen.remove(ordner);
    plaene.remove(ordner);
    await _speichern();
  }

  Future<void> pruefeFaellige({bool Function()? abgebrochen}) async {
    if (_laeuft || _beendet) return;
    _laeuft = true;
    try {
      await laden();
      for (final e in intervalle.entries.toList()) {
        if (_beendet || abgebrochen?.call() == true) return;
        final vorher = plaene[e.key];
        if (refs.ordner.containsKey(e.key) &&
            (vorher == null ||
                uhr().difference(vorher.am) >= Duration(hours: e.value))) {
          try {
            await pruefe(
              e.key,
              abgebrochen: abgebrochen,
              ausschliessen:
                  ausschluesse[e.key] ??
                  const ['**/.git/**', '**/@eaDir/**', '**/.Trash/**'],
            );
          } on ReferenzAbbruch {
            rethrow;
          } on Object {
            if (_beendet || abgebrochen?.call() == true) return;
            plaene[e.key] = ReferenzPruefplan(
              e.key,
              uhr(),
              const [],
              erreichbar: false,
              vollstaendig: false,
            );
            await _speichern();
          }
        }
      }
    } finally {
      _laeuft = false;
    }
  }

  Future<String> _hash(File datei, bool Function()? abgebrochen) async =>
      (await sha256
              .bind(
                datei
                    .openRead()
                    .map((teil) {
                      if (_beendet || abgebrochen?.call() == true) {
                        throw const ReferenzAbbruch();
                      }
                      return teil;
                    })
                    .timeout(const Duration(seconds: 30)),
              )
              .first)
          .toString();

  Future<ReferenzPruefplan> pruefe(
    String ordner, {
    bool Function()? abgebrochen,
    List<String> ausschliessen = const [
      '**/.git/**',
      '**/@eaDir/**',
      '**/.Trash/**',
    ],
  }) async {
    await laden();
    if (paths.beschaffe != null || !refs.ordner.containsKey(ordner)) {
      throw const FormatException('pv_referenzen_nur_lokal');
    }
    void pruefeAbbruch() {
      if (_beendet || abgebrochen?.call() == true) {
        throw const ReferenzAbbruch();
      }
    }

    pruefeAbbruch();
    final wurzel = refs.ordner[ordner]!;
    final token = refs.zugriffe[ordner] ?? '';
    String? root = token.isEmpty
        ? wurzel
        : await zugriff.resolveRoot(path: wurzel, token: token);
    if (root == null || !await Directory(root).exists()) {
      final plan = ReferenzPruefplan(
        ordner,
        uhr(),
        const [],
        erreichbar: false,
        vollstaendig: false,
      );
      plaene[ordner] = plan;
      await _speichern();
      return plan;
    }
    root = await Directory(root).resolveSymbolicLinks();
    final bibliothek = await paths.root.resolveSymbolicLinks();
    if (p.equals(root, bibliothek) ||
        p.isWithin(root, bibliothek) ||
        p.isWithin(bibliothek, root)) {
      throw const FormatException('pv_referenzen_bibliothek');
    }
    final volume = await laufwerk(root);
    final vorherigesLaufwerk = laufwerkskennungen[ordner];
    if (vorherigesLaufwerk != null && vorherigesLaufwerk != volume?.id) {
      final plan = ReferenzPruefplan(
        ordner,
        uhr(),
        const [],
        erreichbar: false,
        vollstaendig: false,
      );
      plaene[ordner] = plan;
      await _speichern();
      return plan;
    }
    if (volume != null) laufwerkskennungen[ordner] = volume.id;
    final muster = ReferenzKatalog.ausschlussmuster(ausschliessen);
    bool ignorieren(String rel, bool ordner) =>
        muster.any((m) => m.hasMatch(rel) || ordner && m.hasMatch('$rel/'));
    final bekannt = <String, Set<String>>{};
    for (final e in refs.dateien.values.where((e) => e.ordner == ordner)) {
      bekannt.putIfAbsent(e.relativ, () => {}).add(e.sha256);
    }
    final da = <String>{}, ergebnis = <ReferenzPruefeintrag>[];
    final stapel = <(Directory, int)>[(Directory(root), 0)];
    var dateien = 0, verzeichnisse = 0, vollstaendig = true;
    while (stapel.isNotEmpty) {
      pruefeAbbruch();
      final (dir, tiefe) = stapel.removeLast();
      if (++verzeichnisse > 200000 || tiefe > 128) {
        throw const FormatException('pv_referenz_abgleich_umfang');
      }
      try {
        await for (final e in dir.list(followLinks: false)) {
          pruefeAbbruch();
          final rel = p.relative(e.path, from: root);
          if (ignorieren(rel.replaceAll(r'\', '/'), e is Directory)) continue;
          if (e is Directory) {
            stapel.add((e, tiefe + 1));
            if (stapel.length > 200000) {
              throw const FormatException('pv_referenz_abgleich_umfang');
            }
            continue;
          }
          if (e is! File || !importiere.isSupported(e.path)) continue;
          if (++dateien > 200000) {
            throw const FormatException('pv_referenz_abgleich_umfang');
          }
          da.add(rel);
          final vorher = await e.stat();
          final hash = await _hash(e, abgebrochen);
          final nachher = await e.stat();
          if (vorher.size != nachher.size ||
              vorher.modified != nachher.modified) {
            vollstaendig = false;
            continue;
          }
          if (bekannt[rel]?.contains(hash) == true) continue;
          ergebnis.add(
            ReferenzPruefeintrag(
              rel,
              bekannt.containsKey(rel)
                  ? ReferenzAenderung.geaendert
                  : ReferenzAenderung.neu,
              hash,
            ),
          );
        }
      } on FileSystemException {
        vollstaendig = false;
      }
    }
    if (vollstaendig) {
      for (final rel in bekannt.keys.where(
        (r) => !da.contains(r) && !ignorieren(r.replaceAll(r'\', '/'), false),
      )) {
        ergebnis.add(ReferenzPruefeintrag(rel, ReferenzAenderung.fehlt, null));
      }
    }
    pruefeAbbruch();
    final plan = ReferenzPruefplan(
      ordner,
      uhr(),
      List.unmodifiable(ergebnis),
      erreichbar: true,
      vollstaendig: vollstaendig,
    );
    plaene[ordner] = plan;
    await _speichern();
    return plan;
  }

  Future<int> uebernehmeNeue(
    ReferenzPruefplan plan, {
    bool Function()? abgebrochen,
  }) async {
    if (!plan.erreichbar || !plan.vollstaendig || paths.beschaffe != null) {
      throw const FormatException('pv_referenz_abgleich_plan');
    }
    final basis = refs.ordner[plan.ordner];
    if (basis == null) {
      throw const FormatException('pv_referenz_abgleich_ordner');
    }
    final root = await Directory(basis).resolveSymbolicLinks();
    final bibliothek = await paths.root.resolveSymbolicLinks();
    if (p.equals(root, bibliothek) ||
        p.isWithin(root, bibliothek) ||
        p.isWithin(bibliothek, root)) {
      throw const FormatException('pv_referenzen_bibliothek');
    }
    final erwartet = laufwerkskennungen[plan.ordner];
    if (erwartet != null && (await laufwerk(root))?.id != erwartet) {
      throw const FormatException('pv_referenz_abgleich_laufwerk');
    }
    final neue = plan.eintraege
        .where((e) => e.art == ReferenzAenderung.neu)
        .toList();
    // Gesamte Auswahl prüfen, bevor die erste Aufnahme importiert wird.
    for (final e in neue) {
      if (_beendet || abgebrochen?.call() == true) {
        throw const ReferenzAbbruch();
      }
      final f = File(p.join(root, e.relativ));
      final real = await f.resolveSymbolicLinks();
      if (!p.isWithin(root, real) ||
          await FileSystemEntity.type(f.path, followLinks: false) !=
              FileSystemEntityType.file ||
          await _hash(f, abgebrochen) != e.sha256) {
        throw const FormatException('pv_referenz_geaendert');
      }
    }
    var anzahl = 0;
    for (final e in neue) {
      if (_beendet || abgebrochen?.call() == true) {
        throw const ReferenzAbbruch();
      }
      final f = File(p.join(root, e.relativ));
      final referenz = await refs.aufnehmen(plan.ordner, f);
      try {
        if (refs.dateien[referenz]!.sha256 != e.sha256) {
          throw const FormatException('pv_referenz_geaendert');
        }
        final r = await importiere.importReferenz(
          f.path,
          referenzPfad: referenz,
          erwartetePruefsumme: e.sha256!,
        );
        if (r.outcome == ImportOutcome.imported) {
          anzahl++;
        } else {
          await refs.entfernen(referenz);
        }
      } on Object {
        await refs.entfernen(referenz);
        rethrow;
      }
    }
    await refs.speichern();
    await pruefe(plan.ordner, abgebrochen: abgebrochen);
    return anzahl;
  }
}
