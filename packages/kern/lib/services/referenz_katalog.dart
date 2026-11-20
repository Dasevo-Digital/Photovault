import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Value;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../db/database.dart';
import 'import_service.dart';
import 'original_referenzen.dart';
import 'storage_paths.dart';

class Katalogfortschritt {
  const Katalogfortschritt(
    this.gelesen,
    this.neu,
    this.doppelt,
    this.fehler,
    this.name,
  );
  final int gelesen, neu, doppelt, fehler;
  final String name;
}

/// Ein Scan verändert nur den Katalog und seine Vorschaubilder. Fremde
/// Originale und Beilagen werden weder umbenannt noch beschrieben.
class ReferenzKatalog {
  ReferenzKatalog(this.db, this.paths, this.importiere);
  final AppDatabase db;
  final StoragePaths paths;
  final ImportService importiere;

  Future<void> uebernehmen(String assetId) async {
    if (paths.beschaffe != null) {
      throw const FormatException('pv_referenzen_nur_lokal');
    }
    final a = await db.assetById(assetId);
    if (a == null || !paths.istReferenziert(a.relativePath)) return;
    final quelle = await paths.referenzen!.lesen(
      a.relativePath,
      inhaltPruefen: true,
    );
    final neu = paths.originalRelativePath(
      a.fileCreatedAt,
      a.id,
      p.extension(a.originalFileName),
    );
    final ziel = paths.absolute(neu);
    final teil = File('${ziel.path}.${const Uuid().v4()}.part');
    if (await ziel.exists()) throw StateError('pv_referenzen_ziel_belegt');
    var eintrag = false;
    var geschrieben = false;
    try {
      await ziel.parent.create(recursive: true);
      await quelle.copy(teil.path);
      if ((await sha256.bind(teil.openRead()).first).toString() != a.checksum) {
        throw const FormatException('pv_referenz_geaendert');
      }
      await teil.rename(ziel.path);
      geschrieben = true;
      await db.transaction(() async {
        final frisch = await db.assetById(a.id);
        if (frisch == null ||
            frisch.relativePath != a.relativePath ||
            frisch.checksum != a.checksum) {
          throw StateError('pv_referenzen_konflikt');
        }
        await (db.update(db.assets)..where((t) => t.id.equals(a.id))).write(
          AssetsCompanion(relativePath: Value(neu)),
        );
      });
      eintrag = true;
      await paths.referenzen!.entfernen(a.relativePath);
    } finally {
      if (await teil.exists()) await teil.delete();
      if (geschrieben && !eintrag && await ziel.exists()) await ziel.delete();
    }
  }

  Stream<Katalogfortschritt> scanne(
    Directory ordner, {
    List<String> ausschliessen = const [
      '**/.git/**',
      '**/@eaDir/**',
      '**/.Trash/**',
    ],
    bool Function()? abgebrochen,
    int hoechstens = 200000,
  }) async* {
    if (paths.beschaffe != null) {
      throw const FormatException('pv_referenzen_nur_lokal');
    }
    final refs = paths.referenzen;
    if (refs == null) throw const FormatException('pv_referenzen_unbekannt');
    final root = await ordner.resolveSymbolicLinks();
    final bibliothek = await paths.root.resolveSymbolicLinks();
    if (p.equals(root, bibliothek) ||
        p.isWithin(root, bibliothek) ||
        p.isWithin(bibliothek, root)) {
      throw const FormatException('pv_referenzen_bibliothek');
    }
    final muster = ausschlussmuster(ausschliessen);
    bool ausgeschlossen(String pfad, {bool ordner = false}) {
      final rel = p.relative(pfad, from: root).replaceAll(r'\', '/');
      return muster.any(
        (r) => r.hasMatch(rel) || ordner && r.hasMatch('$rel/'),
      );
    }

    final rootId = await refs.ordnerHinzufuegen(Directory(root));
    var gelesen = 0, neu = 0, doppelt = 0, fehler = 0, directories = 0;
    final pending = <(Directory, int)>[(Directory(root), 0)];
    try {
      while (pending.isNotEmpty) {
        if (abgebrochen?.call() == true) throw const ReferenzAbbruch();
        final (aktuell, tiefe) = pending.removeLast();
        if (++directories > hoechstens || tiefe > 128) {
          throw StateError('pv_referenzen_umfang');
        }
        await for (final e in aktuell.list(followLinks: false)) {
          if (abgebrochen?.call() == true) throw const ReferenzAbbruch();
          if (e is Directory) {
            if (!ausgeschlossen(e.path, ordner: true)) {
              pending.add((e, tiefe + 1));
            }
            if (pending.length > hoechstens) {
              throw StateError('pv_referenzen_umfang');
            }
            continue;
          }
          if (e is! File || ausgeschlossen(e.path)) continue;
          if (++gelesen > hoechstens) throw StateError('pv_referenzen_umfang');
          if (!importiere.isSupported(e.path)) continue;
          String? referenz;
          try {
            referenz = await refs.aufnehmen(rootId, e);
            final record = refs.dateien[referenz]!;
            final ergebnis = await importiere.importReferenz(
              e.path,
              referenzPfad: referenz,
              erwartetePruefsumme: record.sha256,
            );
            switch (ergebnis.outcome) {
              case ImportOutcome.imported:
                neu++;
              case ImportOutcome.duplicateSkipped:
                doppelt++;
              case ImportOutcome.failed:
                fehler++;
            }
            if (ergebnis.outcome != ImportOutcome.imported) {
              await refs.entfernen(referenz);
            }
          } on Object {
            if (referenz != null) await refs.entfernen(referenz);
            fehler++;
          }
          yield Katalogfortschritt(
            gelesen,
            neu,
            doppelt,
            fehler,
            p.basename(e.path),
          );
        }
      }
    } finally {
      await refs.speichern();
    }
  }

  static List<RegExp> ausschlussmuster(Iterable<String> werte) => [
    for (final s in werte.where((s) => s.trim().isNotEmpty)) _muster(s.trim()),
  ];

  static RegExp _muster(String wert) {
    if (wert.length > 512 ||
        wert.contains('\u0000') ||
        p.isAbsolute(wert) ||
        p.split(wert).contains('..')) {
      throw const FormatException('pv_referenzen_ausschluss');
    }
    final b = StringBuffer('^');
    for (var i = 0; i < wert.length; i++) {
      if (wert[i] == '*') {
        if (i + 1 < wert.length && wert[i + 1] == '*') {
          i++;
          if (i + 1 < wert.length && wert[i + 1] == '/') {
            i++;
            b.write('(?:.*/)?');
          } else {
            b.write('.*');
          }
        } else {
          b.write('[^/]*');
        }
      } else if (wert[i] == '?') {
        b.write('[^/]');
      } else {
        b.write(RegExp.escape(wert[i]));
      }
    }
    return RegExp('${b.toString()}\$');
  }
}
