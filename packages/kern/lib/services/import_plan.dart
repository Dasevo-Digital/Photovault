import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../db/database.dart';
import 'import_service.dart';
import 'beilagenangaben.dart';
import 'regelpruefung.dart';

/// [beilage]: eine `.xmp`-Beilage neben einem Foto derselben Auswahl. Sie
/// wird nicht eigens importiert, sondern mit ihrem Foto übernommen (siehe
/// [ImportPlanEintrag.beilageZu]). Vorher stand sie als „Format wird nicht
/// unterstützt“ da, obwohl ihre Angaben ankamen (IMP-082).
enum ImportPlanArt { neu, vorhanden, doppelt, format, fehler, beilage }

class ImportPlanEintrag {
  const ImportPlanEintrag({
    required this.pfad,
    required this.art,
    this.angaben,
    this.albumIds = const [],
    this.tagIds = const [],
    this.alben = const [],
    this.tags = const [],
    this.regeln = const [],
    this.favorit = false,
    this.regelnOhneZiel = const [],
    this.beilage,
    this.beilageZu,
  });
  final String pfad;
  final ImportPlanArt art;

  /// Bei einer [ImportPlanArt.beilage]: das Foto, zu dem sie gehört.
  final String? beilageZu;
  final ImportDateiangaben? angaben;
  final List<String> alben, tags, regeln;
  final List<String> albumIds, tagIds;
  final bool favorit;

  /// Regeln und Kameravorgaben, die hier zutreffen, deren Zielalbum oder
  /// Schlagwort es aber nicht mehr gibt (IMP-024) – für den Hinweis in der
  /// Prüfung. Das fehlende Ziel fällt weg, die übrigen Aktionen gelten,
  /// und das Foto bleibt wählbar – wie beim nachträglichen Anwenden einer
  /// Regel (`regelAnwenden`). Vorher war es gesperrt, und gesagt wurde nur
  /// allgemein, dass „eine Regel“ auf ein fehlendes Ziel verweist.
  final List<String> regelnOhneZiel;
  final Beilagenangaben? beilage;
  ImportPlanEintrag mitBeilage(Beilagenangaben? wert) => ImportPlanEintrag(
    pfad: pfad,
    art: art,
    angaben: angaben,
    albumIds: albumIds,
    tagIds: tagIds,
    alben: alben,
    tags: tags,
    regeln: regeln,
    favorit: favorit,
    regelnOhneZiel: regelnOhneZiel,
    beilage: wert,
    beilageZu: beilageZu,
  );
}

class ImportPlan {
  const ImportPlan({
    required this.eintraege,
    required this.regelstand,
    required this.am,
    required this.spaetereRegeln,
    this.dateiregeln = false,
    this.umzug = false,
    this.kammer = false,
    this.ausgelassen = const [],
  });
  final List<ImportPlanEintrag> eintraege;
  final List<ImportPlanEintrag> ausgelassen;
  final String regelstand;
  final DateTime am;
  final int spaetereRegeln;
  final bool dateiregeln;
  final bool umzug;

  /// Erst in die Fotokammer des Servers statt gleich in die Bibliothek
  /// (#336). Regeln, Vorgaben und Alben greifen dann beim Freigeben.
  final bool kammer;

  ImportPlan mitKammer(bool an) => ImportPlan(
    eintraege: eintraege,
    regelstand: regelstand,
    am: am,
    spaetereRegeln: spaetereRegeln,
    dateiregeln: dateiregeln,
    umzug: umzug,
    kammer: an,
    ausgelassen: ausgelassen,
  );

  int get originalBytes => eintraege
      .where((e) => e.art == ImportPlanArt.neu)
      .fold(0, (n, e) => n + e.angaben!.bytes);

  /// Die Einträge nach ihrem Pfad – einmal je Lauf zu bilden (#434). Ein
  /// `singleWhere` je Datei ging jedes Mal die ganze Liste durch; bei einem
  /// Umzug mit 200 000 Dateien waren das Minuten auf dem Faden der
  /// Oberfläche.
  Map<String, ImportPlanEintrag> get nachPfad => {
    for (final e in eintraege) e.pfad: e,
  };

  Map<String, String> get pruefsummen => {
    for (final e in eintraege.where((e) => e.art == ImportPlanArt.neu))
      e.pfad: e.angaben!.pruefsumme,
  };

  ImportPlan auswahl(Set<String> pfade, {bool mitAusgelassenen = false}) =>
      ImportPlan(
        eintraege: eintraege
            .where((e) => pfade.contains(e.pfad) && e.art == ImportPlanArt.neu)
            .toList(),
        regelstand: regelstand,
        am: am,
        spaetereRegeln: spaetereRegeln,
        dateiregeln: dateiregeln,
        umzug: umzug,
        kammer: kammer,
        ausgelassen: mitAusgelassenen
            ? eintraege
                  .where(
                    (e) =>
                        !pfade.contains(e.pfad) || e.art != ImportPlanArt.neu,
                  )
                  .toList()
            : const [],
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
  static Future<List<String>> dateienImOrdner(
    String ordner, {
    int? hoechstensDateien,
    int? hoechstensOrdner,
    void Function(int)? fortschritt,
  }) async {
    final r = <String>[];
    var ordnerzahl = 1;
    final offen = <Directory>[Directory(ordner)];
    while (offen.isNotEmpty) {
      await for (final f in offen.removeLast().list(followLinks: false)) {
        if (p.basename(f.path).startsWith('.')) continue;
        if (f is Directory) {
          if (hoechstensOrdner != null && ++ordnerzahl > hoechstensOrdner) {
            throw const FormatException('pv_umzug_metadaten_budget');
          }
          offen.add(f);
        }
        if (f is File) {
          if (hoechstensDateien != null && r.length >= hoechstensDateien) {
            throw const FormatException('pv_umzug_metadaten_budget');
          }
          r.add(f.path);
          if (r.length % 100 == 0) fortschritt?.call(r.length);
        }
      }
    }
    r.sort();
    fortschritt?.call(r.length);
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

  Future<void> uebernehme(
    ImportPlan plan,
    ImportPlanEintrag eintrag,
    String id,
  ) async {
    if (plan.regelstand != await aktuellerRegelstand()) {
      throw const FormatException('pv_import_regeln_geaendert');
    }
    await eintrag.beilage?.wendeAn(db, id);
    for (final album in eintrag.albumIds) {
      await db.fuehreAus(AlbumFuellen(album, [id]));
    }
    for (final tag in eintrag.tagIds) {
      await db.fuehreAus(SchlagwortAnheftenPerKennung(id, tag));
    }
    if (eintrag.favorit) await db.fuehreAus(FavoritSetzen([id], true));
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
    final beilagen = beilagenDerAuswahl(dateien, importe.isSupported);
    for (final pfad in dateien.toSet()) {
      if (abgebrochen?.call() ?? false) throw const ImportPlanAbgebrochen();
      if (!importe.isSupported(pfad)) {
        final zu = beilagen[pfad];
        ergebnis.add(
          ImportPlanEintrag(
            pfad: pfad,
            art: zu == null ? ImportPlanArt.format : ImportPlanArt.beilage,
            beilageZu: zu,
          ),
        );
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
              treffen = <String>[],
              ohneZiel = <String>[];
          var favorit = false;
          void aktion(
            String name,
            String? album,
            bool fav,
            List<String> tagIds,
          ) {
            final fehlt =
                (album != null && !alben.containsKey(album)) ||
                tagIds.any((id) => !tags.containsKey(id));
            if (fehlt) ohneZiel.add(name);
            if (album != null && alben.containsKey(album)) zielAlben.add(album);
            favorit |= fav;
            zielTags.addAll(tagIds.where(tags.containsKey));
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
            aktion(
              '${k.cameraMake} ${k.cameraModel}',
              k.targetAlbumId,
              k.autoFavorite,
              kameraTags[k.id] ?? [],
            );
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
              aktion(
                r.name,
                r.targetAlbumId,
                r.autoFavorite,
                regelTags[r.id] ?? [],
              );
            }
          }
          ergebnis.add(
            ImportPlanEintrag(
              pfad: pfad,
              art: art,
              angaben: a,
              favorit: favorit,
              albumIds: List.unmodifiable(zielAlben),
              tagIds: List.unmodifiable(zielTags),
              regeln: treffen,
              alben: [
                for (final id in zielAlben)
                  if (alben[id] != null) alben[id]!,
              ],
              tags: [
                for (final id in zielTags)
                  if (tags[id] != null) tags[id]!,
              ],
              regelnOhneZiel: ohneZiel,
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

/// Die `.xmp`-Beilagen unter [dateien], die zu einem unterstützten Foto
/// derselben Auswahl gehören: Beilage → Foto.
///
/// Nach denselben Regeln, nach denen der Import sie liest (`beilageNeben`
/// in der App): `foto.xmp` (Lightroom, Photo Vault) oder `foto.jpg.xmp`
/// (darktable), neben dem Foto und unter genau diesem Namen. Liegen beide,
/// zählt die zuletzt geänderte; die andere bleibt eine fremde Datei.
Map<String, String> beilagenDerAuswahl(
  Iterable<String> dateien,
  bool Function(String pfad) unterstuetzt,
) {
  // Die Schreibweise in der Auswahl kann von der des Fotos abweichen
  // (macOS und Windows unterscheiden Gross und Klein nicht); ob die Datei
  // unter dem Namen des Fotos zu finden ist, entscheidet das Dateisystem
  // – wie beim Import.
  final xmpJeName = <String, String>{
    for (final d in dateien)
      if (p.extension(d).toLowerCase() == '.xmp') d.toLowerCase(): d,
  };
  if (xmpJeName.isEmpty) return const {};
  final ergebnis = <String, String>{};
  for (final foto in dateien) {
    if (!unterstuetzt(foto)) continue;
    String? beste;
    DateTime? zeit;
    for (final name in [p.setExtension(foto, '.xmp'), '$foto.xmp']) {
      final gewaehlt = xmpJeName[name.toLowerCase()];
      if (gewaehlt == null) continue;
      try {
        final datei = File(name);
        if (!datei.existsSync()) continue;
        final t = datei.lastModifiedSync();
        if (zeit == null || t.isAfter(zeit)) {
          beste = gewaehlt;
          zeit = t;
        }
      } on FileSystemException {
        continue;
      }
    }
    if (beste != null) ergebnis[beste] = foto;
  }
  return ergebnis;
}
