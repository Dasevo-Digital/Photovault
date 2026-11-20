import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:kern/db/database.dart';
import 'package:kern/services/backup_auswahl.dart';
import 'package:kern/services/storage_paths.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'arbeitsvorschauen.dart';
import 'importquittungen.dart' show Kopienbefund;
import 'library_location.dart';
import 'bibliotheksgeraetedaten.dart';
import 'platform/folder_access.dart';

enum Speichergruppe {
  bibliothek,
  extern,
  server,
  kopien,
  arbeitsvorschauen,
  nachgewiesen,
  unbekannt,
  fehlt,
  papierkorb,
}

class Speicherfoto {
  const Speicherfoto(
    this.id,
    this.name,
    this.pfad,
    this.sha256,
    this.bytes,
    this.papierkorb,
  );
  final String id, name, pfad, sha256;
  final int bytes;
  final bool papierkorb;
}

class Sicherungsnachweis {
  const Sicherungsnachweis(
    this.id,
    this.ziel,
    this.token,
    this.am,
    this.befunde,
    this.vollstaendig, {
    this.erreichbar = false,
  });
  final String id, ziel, token;
  final DateTime am;
  final Map<String, Kopienbefund> befunde;
  final bool vollstaendig, erreichbar;
  int get bestaetigt =>
      befunde.values.where((x) => x == Kopienbefund.bestaetigt).length;
}

class SpeicherkarteStand {
  const SpeicherkarteStand(
    this.fotos,
    this.gruppen,
    this.nachweise,
    this.originalorte,
    this.gesperrt, {
    this.nachweiseUnlesbar = false,
    this.arbeitsvorschauenUnlesbar = false,
  });
  final Map<String, Speicherfoto> fotos;
  final Map<Speichergruppe, Set<String>> gruppen;
  final List<Sicherungsnachweis> nachweise;
  final Map<String, int> originalorte;
  final int gesperrt;
  final bool nachweiseUnlesbar;
  final bool arbeitsvorschauenUnlesbar;
  int anzahl(Speichergruppe g) => gruppen[g]?.length ?? 0;
  int get gesamt => fotos.length + gesperrt;
}

class SpeicherkarteDienst {
  SpeicherkarteDienst(this.db, this.paths, this.nachweisdatei);
  final AppDatabase db;
  final StoragePaths paths;
  final File nachweisdatei;
  static Future<SpeicherkarteDienst> fuer(
    AppDatabase db,
    StoragePaths paths,
  ) async {
    final lokal = await LibraryLocation.datenordner();
    final ort = await Bibliotheksgeraetedaten.kennung(paths);
    return SpeicherkarteDienst(
      db,
      paths,
      File(p.join(lokal.path, 'speicherkarte', '$ort.json')),
    );
  }

  Future<List<Sicherungsnachweis>> nachweise() async {
    if (!await nachweisdatei.exists()) return const [];
    if (await nachweisdatei.length() > 32 * 1024 * 1024) {
      throw const FormatException('pv_speicherkarte_umfang');
    }
    final j = jsonDecode(await nachweisdatei.readAsString()) as Map;
    if (j['fassung'] != 1) {
      throw const FormatException('pv_speicherkarte_format');
    }
    final werte = j['nachweise'] as List;
    if (werte.length > 20) {
      throw const FormatException('pv_speicherkarte_umfang');
    }
    final aus = <Sicherungsnachweis>[];
    for (final w in werte) {
      final v = w as Map;
      final befunde = (v['befunde'] as Map).cast<String, String>();
      if (befunde.length > 200000 ||
          befunde.keys.any((s) => !RegExp(r'^[a-f0-9]{64}$').hasMatch(s))) {
        throw const FormatException('pv_speicherkarte_format');
      }
      final ziel = v['ziel'] as String, token = v['token'] as String? ?? '';
      String? aufgeloest;
      try {
        aufgeloest = token.isEmpty
            ? ziel
            : await FolderAccess.forCurrentPlatform().resolveRoot(
                path: ziel,
                token: token,
              );
      } on Object {
        aufgeloest = null;
      }
      final erreichbar =
          aufgeloest != null && await Directory(aufgeloest).exists();
      aus.add(
        Sicherungsnachweis(
          v['id'] as String,
          ziel,
          token,
          DateTime.parse(v['am'] as String),
          {
            for (final e in befunde.entries)
              e.key: Kopienbefund.values.byName(e.value),
          },
          v['vollstaendig'] == true,
          erreichbar: erreichbar,
        ),
      );
    }
    return aus;
  }

  Future<void> _speichere(Sicherungsnachweis neu) async {
    List<Sicherungsnachweis> vorher;
    try {
      vorher = await nachweise();
    } on Object {
      await nachweisdatei.rename(
        '${nachweisdatei.path}.${const Uuid().v4()}.unlesbar',
      );
      vorher = [];
    }
    final werte = [neu, ...vorher.where((v) => v.id != neu.id)].take(20);
    await nachweisdatei.parent.create(recursive: true);
    final teil = File('${nachweisdatei.path}.${const Uuid().v4()}.part');
    try {
      final text = jsonEncode({
        'fassung': 1,
        'nachweise': [
          for (final n in werte)
            {
              'id': n.id,
              'ziel': n.ziel,
              'token': n.token,
              'am': n.am.toUtc().toIso8601String(),
              'vollstaendig': n.vollstaendig,
              'befunde': {
                for (final e in n.befunde.entries) e.key: e.value.name,
              },
            },
        ],
      });
      if (utf8.encode(text).length > 32 * 1024 * 1024) {
        throw const FormatException('pv_speicherkarte_umfang');
      }
      await teil.writeAsString(text, flush: true);
      await teil.rename(nachweisdatei.path);
    } finally {
      if (await teil.exists()) await teil.delete();
    }
  }

  Future<SpeicherkarteStand> laden({bool Function()? abgebrochen}) async {
    final fotos = <String, Speicherfoto>{};
    final gruppen = {for (final g in Speichergruppe.values) g: <String>{}};
    final orte = <String, int>{};
    List<Sicherungsnachweis> belege;
    var nachweiseUnlesbar = false;
    try {
      belege = await nachweise();
    } on Object {
      belege = [];
      nachweiseUnlesbar = true;
    }
    final bestaetigt = {
      for (final n in belege)
        if (n.erreichbar)
          for (final e in n.befunde.entries)
            if (e.value == Kopienbefund.bestaetigt) e.key,
    };
    var gesperrt = 0;
    for (var offset = 0; ; offset += 500) {
      if (abgebrochen?.call() == true) {
        throw StateError('pv_speicherkarte_abbruch');
      }
      final zeilen = await db
          .customSelect(
            'SELECT id, original_file_name, relative_path, checksum, file_size_bytes, is_locked, is_trashed FROM assets ORDER BY id LIMIT 500 OFFSET ?',
            variables: [Variable.withInt(offset)],
          )
          .get();
      for (final r in zeilen) {
        if (abgebrochen?.call() == true) {
          throw StateError('pv_speicherkarte_abbruch');
        }
        if (r.read<bool>('is_locked')) {
          gesperrt++;
          continue;
        }
        final f = Speicherfoto(
          r.read<String>('id'),
          r.read<String>('original_file_name'),
          r.read<String>('relative_path'),
          r.read<String>('checksum'),
          r.read<int>('file_size_bytes'),
          r.read<bool>('is_trashed'),
        );
        fotos[f.id] = f;
        if (f.papierkorb) {
          gruppen[Speichergruppe.papierkorb]!.add(f.id);
          continue;
        }
        final extern = paths.istReferenziert(f.pfad);
        gruppen[extern
                ? Speichergruppe.extern
                : paths.beschaffe != null
                ? Speichergruppe.server
                : Speichergruppe.bibliothek]!
            .add(f.id);
        if (extern) {
          final ref = paths.referenzen?.dateien[f.pfad];
          final ort = ref == null ? null : paths.referenzen?.ordner[ref.ordner];
          if (ort != null) orte[ort] = (orte[ort] ?? 0) + 1;
        }
        try {
          // Bei verbundenen Bibliotheken wird nur der lokale Vorrat geprüft,
          // niemals zum Anzeigen der Karte eine Originaldatei heruntergeladen.
          final file = extern
              ? await paths.bereit(f.pfad)
              : paths.absolute(f.pfad);
          final stat = await file.stat();
          final vorhanden =
              stat.type == FileSystemEntityType.file &&
              (f.bytes <= 0 || stat.size == f.bytes);
          if (vorhanden) {
            if (!extern) gruppen[Speichergruppe.kopien]!.add(f.id);
          } else if (paths.beschaffe == null || extern) {
            gruppen[Speichergruppe.fehlt]!.add(f.id);
          }
        } on Object {
          if (paths.beschaffe == null || extern) {
            gruppen[Speichergruppe.fehlt]!.add(f.id);
          }
        }
        gruppen[bestaetigt.contains(f.sha256)
                ? Speichergruppe.nachgewiesen
                : Speichergruppe.unbekannt]!
            .add(f.id);
      }
      if (zeilen.length < 500) break;
    }
    var arbeitsvorschauenUnlesbar = false;
    try {
      for (final a in await Arbeitsvorschauen(db, paths).liste()) {
        gruppen[Speichergruppe.arbeitsvorschauen]!.add(a.asset.id);
      }
    } on Object {
      arbeitsvorschauenUnlesbar = true;
    }
    return SpeicherkarteStand(
      Map.unmodifiable(fotos),
      gruppen,
      belege,
      Map.unmodifiable(orte),
      gesperrt,
      nachweiseUnlesbar: nachweiseUnlesbar,
      arbeitsvorschauenUnlesbar: arbeitsvorschauenUnlesbar,
    );
  }

  /// Positive Einträge entstehen ausschließlich nach einer vollständigen
  /// Inhaltsprüfung. Ein Abbruch speichert einen sichtbar unvollständigen Lauf.
  Future<Sicherungsnachweis> pruefe(
    BackupAuswahl sicherung,
    PickedFolder ziel,
    Set<String> hashes, {
    bool Function()? abgebrochen,
    void Function(int, int)? fortschritt,
  }) async {
    if (hashes.length > 200000 ||
        hashes.any((s) => !RegExp(r'^[a-f0-9]{64}$').hasMatch(s))) {
      throw const FormatException('pv_speicherkarte_umfang');
    }
    final befunde = <String, Kopienbefund>{};
    for (final hash in hashes) {
      if (abgebrochen?.call() == true) break;
      try {
        befunde[hash] = await sicherung.pruefeOriginal(hash)
            ? Kopienbefund.bestaetigt
            : Kopienbefund.fehlt;
      } on Object {
        befunde[hash] = Kopienbefund.unlesbar;
      }
      fortschritt?.call(befunde.length, hashes.length);
    }
    final real = await Directory(ziel.path).resolveSymbolicLinks();
    final nachweis = Sicherungsnachweis(
      sha256.convert(utf8.encode(real)).toString(),
      real,
      ziel.token,
      DateTime.now(),
      Map.unmodifiable(befunde),
      befunde.length == hashes.length,
      erreichbar: true,
    );
    await _speichere(nachweis);
    return nachweis;
  }
}
