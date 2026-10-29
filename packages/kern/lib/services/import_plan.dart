import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../db/database.dart';
import 'import_service.dart';
import 'regelpruefung.dart';

enum ImportPlanArt { neu, vorhanden, doppelt, format, fehler }

class ImportPlanEintrag {
  const ImportPlanEintrag({
    required this.pfad,
    required this.art,
    this.angaben,
    this.alben = const [],
    this.tags = const [],
    this.regeln = const [],
    this.favorit = false,
    this.ungueltigeZiele = false,
  });
  final String pfad;
  final ImportPlanArt art;
  final ImportDateiangaben? angaben;
  final List<String> alben, tags, regeln;
  final bool favorit, ungueltigeZiele;
}

class ImportPlan {
  const ImportPlan({
    required this.eintraege,
    required this.regelstand,
    required this.am,
    required this.spaetereRegeln,
    this.dateiregeln = false,
  });
  final List<ImportPlanEintrag> eintraege;
  final String regelstand;
  final DateTime am;
  final int spaetereRegeln;
  final bool dateiregeln;

  int get originalBytes => eintraege
      .where((e) => e.art == ImportPlanArt.neu)
      .fold(0, (n, e) => n + e.angaben!.bytes);
  Map<String, String> get pruefsummen => {
    for (final e in eintraege.where((e) => e.art == ImportPlanArt.neu))
      e.pfad: e.angaben!.pruefsumme,
  };

  ImportPlan auswahl(Set<String> pfade) => ImportPlan(
    eintraege: eintraege
        .where((e) => pfade.contains(e.pfad) && e.art == ImportPlanArt.neu)
        .toList(),
    regelstand: regelstand,
    am: am,
    spaetereRegeln: spaetereRegeln,
    dateiregeln: dateiregeln,
  );
}

class ImportPlanAbgebrochen implements Exception {
  const ImportPlanAbgebrochen();
}

class ImportPlanDienst {
  ImportPlanDienst(this.db, this.importe);
  final AppDatabase db;
  final ImportService importe;

  /// Auch nicht unterstützte Dateien erscheinen im Bericht. Versteckte
  /// Ordner und Verzeichnisverweise werden nicht verfolgt.
  static Future<List<String>> dateienImOrdner(String ordner) async {
    final r = <String>[];
    final offen = <Directory>[Directory(ordner)];
    while (offen.isNotEmpty) {
      await for (final f in offen.removeLast().list(followLinks: false)) {
        if (p.basename(f.path).startsWith('.')) continue;
        if (f is Directory) {
          offen.add(f);
        }
        if (f is File) {
          r.add(f.path);
        }
      }
    }
    r.sort();
    return r;
  }

  Future<String> aktuellerRegelstand() async {
    final daten = <String, Object?>{};
    final albumIds = <String>{}, tagIds = <String>{};
    for (final dynamic t in [
      db.cameraPresets,
      db.cameraPresetTags,
      db.automationRules,
      db.automationRuleTags,
    ]) {
      final liste = <Map<String, dynamic>>[
        for (final dynamic z in await db.select(t).get())
          z.toJson() as Map<String, dynamic>,
      ];
      for (final z in liste) {
        if (z['targetAlbumId'] case final String id) albumIds.add(id);
        if (z['tagId'] case final String id) tagIds.add(id);
      }
      liste.sort((a, b) => jsonEncode(a).compareTo(jsonEncode(b)));
      daten[t.actualTableName as String] = liste;
    }
    daten['ziele'] = [
      for (final a
          in (await (db.select(
              db.albums,
            )..where((t) => t.id.isIn(albumIds))).get())
            ..sort((a, b) => a.id.compareTo(b.id)))
        if (albumIds.contains(a.id)) {'album': a.id, 'name': a.name},
      for (final t
          in (await (db.select(db.tags)..where((t) => t.id.isIn(tagIds))).get())
            ..sort((a, b) => a.id.compareTo(b.id)))
        if (tagIds.contains(t.id)) {'tag': t.id, 'name': t.name},
    ];
    return sha256.convert(utf8.encode(jsonEncode(daten))).toString();
  }

  Future<ImportPlan> erstelle(
    List<String> dateien, {
    bool Function()? abgebrochen,
    void Function(int fertig, int gesamt)? fortschritt,
  }) async {
    final stand = await aktuellerRegelstand();
    final regeln = await db.allAutomationRules();
    final kameras = await db.select(db.cameraPresets).get();
    final alben = {
      for (final a in await db.select(db.albums).get()) a.id: a.name,
    };
    final tags = {for (final t in await db.alleTags()) t.id: t.name};
    final kameraTags = <String, List<String>>{};
    for (final t in await db.select(db.cameraPresetTags).get()) {
      kameraTags.putIfAbsent(t.presetId, () => []).add(t.tagId);
    }
    final regelTags = <String, List<String>>{};
    for (final t in await db.select(db.automationRuleTags).get()) {
      regelTags.putIfAbsent(t.ruleId, () => []).add(t.tagId);
    }
    final vorhandeneHashes = {
      for (final r
          in await db.customSelect('SELECT checksum FROM assets').get())
        r.read<String>('checksum'),
    };
    final gesehen = <String>{};
    final ergebnis = <ImportPlanEintrag>[];
    for (final pfad in dateien.toSet()) {
      if (abgebrochen?.call() ?? false) throw const ImportPlanAbgebrochen();
      if (!importe.isSupported(pfad)) {
        ergebnis.add(ImportPlanEintrag(pfad: pfad, art: ImportPlanArt.format));
      } else {
        try {
          final a = await importe.untersucheDatei(pfad);
          final art = vorhandeneHashes.contains(a.pruefsumme)
              ? ImportPlanArt.vorhanden
              : !gesehen.add(a.pruefsumme)
              ? ImportPlanArt.doppelt
              : ImportPlanArt.neu;
          final zielAlben = <String>{},
              zielTags = <String>{},
              treffen = <String>[];
          var favorit = false;
          void aktion(String? album, bool fav, List<String> tagIds) {
            if (album != null) zielAlben.add(album);
            favorit |= fav;
            zielTags.addAll(tagIds);
          }

          for (final k
              in kameras
                  .where(
                    (k) =>
                        a.kamera != null &&
                        a.modell != null &&
                        k.cameraMake == a.kamera &&
                        k.cameraModel == a.modell,
                  )
                  .take(1)) {
            aktion(k.targetAlbumId, k.autoFavorite, kameraTags[k.id] ?? []);
          }
          for (final r in regeln) {
            if (regelTrifftZu(
              r,
              breite: a.breite,
              laenge: a.laenge,
              datum: a.datum,
              dateiname: p.basename(pfad),
            )) {
              treffen.add(r.name);
              aktion(r.targetAlbumId, r.autoFavorite, regelTags[r.id] ?? []);
            }
          }
          ergebnis.add(
            ImportPlanEintrag(
              pfad: pfad,
              art: art,
              angaben: a,
              favorit: favorit,
              regeln: treffen,
              alben: [
                for (final id in zielAlben)
                  if (alben[id] != null) alben[id]!,
              ],
              tags: [
                for (final id in zielTags)
                  if (tags[id] != null) tags[id]!,
              ],
              ungueltigeZiele:
                  zielAlben.any((id) => !alben.containsKey(id)) ||
                  zielTags.any((id) => !tags.containsKey(id)),
            ),
          );
        } on Object {
          ergebnis.add(
            ImportPlanEintrag(pfad: pfad, art: ImportPlanArt.fehler),
          );
        }
      }
      fortschritt?.call(ergebnis.length, dateien.length);
    }
    if (abgebrochen?.call() ?? false) throw const ImportPlanAbgebrochen();
    if (stand != await aktuellerRegelstand()) {
      throw const FormatException('pv_import_regeln_geaendert');
    }
    return ImportPlan(
      eintraege: ergebnis,
      regelstand: stand,
      am: DateTime.now(),
      spaetereRegeln: regeln.where((r) => r.triggerType == 'aiTag').length,
      dateiregeln: regeln.any(
        (r) => const {'dateiname', 'dateiendung'}.contains(r.triggerType),
      ),
    );
  }
}
