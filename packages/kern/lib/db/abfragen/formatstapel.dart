part of '../database.dart';

/// Stapel aus derselben Aufnahme in mehreren Dateiformaten (#361).
///
/// Eine Kamera legt RAW und JPEG nebeneinander ab, ein Telefon oder ein
/// Bildprogramm macht aus einem HEIC ein JPEG. Jede Datei ist eine eigene
/// Aufnahme, und bis hierher verband der Import nur Bild und Video eines
/// Live Photos. Es sind gewöhnliche Variantenstapel: Raster, Suche, Abgleich
/// und Sicherungen kennen sie schon. Am Vorsatz erkennt der Schalter in den
/// Einstellungen, welche Stapel er selbst gebildet hat.
const formatstapelPraefix = '${variantenstapelPraefix}format-';

bool istFormatstapel(String? stackId) =>
    stackId?.startsWith(formatstapelPraefix) ?? false;

/// So weit dürfen die Aufnahmezeiten zweier Formate auseinanderliegen.
///
/// Der Name allein reicht nicht: Ein iPhone zählt bis `IMG_9999` und fängt
/// von vorn an (siehe `Nachbearbeitung.verknuepfeLivePhoto`). Zwei Sekunden
/// lassen Raum für Programme, die beim Umwandeln auf- oder abrunden.
const formatgleichAbstand = Duration(seconds: 2);

/// Unter diesem Schlüssel merkt sich `verworfene_serien`, dass jemand eine
/// Aufnahme von Hand aus ihrem Formatstapel geholt hat.
String formatausnahme(String assetId) => 'format:$assetId';

/// Der Name bis zum letzten Punkt: rtrim nimmt vom Ende her alles weg, was
/// kein Punkt ist.
const _stammSql =
    "lower(rtrim(original_file_name, replace(original_file_name, '.', '')))";

String _stammVon(String name) => p.basenameWithoutExtension(name).toLowerCase();

/// Das Format ohne die Unterschiede, die nur die Schreibweise betreffen.
String? _formatVon(AssetData a) => switch (a.dateiformat ??
    p.extension(a.originalFileName).replaceFirst('.', '').toLowerCase()) {
  '' => null,
  'jpeg' || 'jpe' => 'jpg',
  'heif' => 'heic',
  'tiff' => 'tif',
  final f => f,
};

bool _selbeKamera(AssetData a, AssetData b) {
  final x = a.cameraModel?.trim().toLowerCase() ?? '';
  final y = b.cameraModel?.trim().toLowerCase() ?? '';
  return x.isEmpty || y.isEmpty || x == y;
}

/// Welche der [bilder] dieselbe Aufnahme in verschiedenen Formaten sind.
///
/// Gleicher Name ohne Endung, Aufnahmezeit innerhalb von
/// [formatgleichAbstand], keine zwei verschiedenen Kameras, und mindestens
/// zwei Formate in der Gruppe. Ein geschätztes Datum zählt nicht: Es sagt
/// nichts darüber, ob zwei Dateien zur selben Aufnahme gehören. Was in einer
/// Serie oder in von Hand gebildeten Varianten liegt, bleibt, wo es ist.
List<List<AssetData>> formatgruppen(Iterable<AssetData> bilder) {
  final jeStamm = <String, List<AssetData>>{};
  for (final a in bilder) {
    if (a.type != 'IMAGE' ||
        a.isTrashed ||
        a.isLocked ||
        a.datumGeschaetzt ||
        _formatVon(a) == null ||
        (a.stackId != null && !istFormatstapel(a.stackId))) {
      continue;
    }
    (jeStamm[_stammVon(a.originalFileName)] ??= []).add(a);
  }
  final gruppen = <List<AssetData>>[];
  for (final gleichnamig in jeStamm.values) {
    if (gleichnamig.length < 2) continue;
    gleichnamig.sort((a, b) => a.fileCreatedAt.compareTo(b.fileCreatedAt));
    final offen = <List<AssetData>>[];
    for (final a in gleichnamig) {
      final passend = offen
          .where(
            (g) =>
                a.fileCreatedAt.difference(g.first.fileCreatedAt) <=
                    formatgleichAbstand &&
                g.every((b) => _selbeKamera(a, b)),
          )
          .firstOrNull;
      if (passend == null) {
        offen.add([a]);
      } else {
        passend.add(a);
      }
    }
    gruppen.addAll(
      offen.where((g) => {for (final a in g) _formatVon(a)}.length > 1),
    );
  }
  return gruppen;
}

/// Welche Fassung einer [gruppe] in der Zeitleiste steht.
///
/// Zuerst, was sonst aus einer Ansicht verschwände: Benannte Gesichter
/// ([benannt] je Aufnahme) hängen an genau einer Datei. Dann die Fassung,
/// die Angaben trägt ([mitAngaben]: Album, Favorit, Sterne, Farbe,
/// Beschreibung, eigenes Schlagwort) – nach dem Ausschalten ist das die
/// frühere Hauptversion, und so kommt nach dem Wiedereinschalten dieselbe
/// nach oben. Dann das Video eines Live Photos und die Bearbeitung, die
/// jemand gemacht hat. Unter dem Rest ein fertiges Bild vor dem RAW, das
/// Bild mit den meisten Pixeln und HEIC vor JPEG – das HEIC ist beim
/// Telefon das Original, das JPEG die Umwandlung.
AssetData hauptfassung(
  List<AssetData> gruppe, {
  Map<String, int> benannt = const {},
  Set<String> mitAngaben = const {},
}) {
  int wenn(bool b) => b ? 0 : 1;
  int pixel(AssetData a) => (a.widthPx ?? 0) * (a.heightPx ?? 0);
  bool roh(AssetData a) => rawImageExtensions.contains('.${_formatVon(a)}');
  final sortiert = [...gruppe]
    ..sort((a, b) {
      for (final v in [
        (benannt[b.id] ?? 0).compareTo(benannt[a.id] ?? 0),
        wenn(
          mitAngaben.contains(a.id),
        ).compareTo(wenn(mitAngaben.contains(b.id))),
        wenn(a.linkedAssetId != null).compareTo(wenn(b.linkedAssetId != null)),
        wenn(
          a.developedRelativePath != null,
        ).compareTo(wenn(b.developedRelativePath != null)),
        wenn(!roh(a)).compareTo(wenn(!roh(b))),
        pixel(b).compareTo(pixel(a)),
        wenn(_formatVon(a) == 'heic').compareTo(wenn(_formatVon(b) == 'heic')),
      ]) {
        if (v != 0) return v;
      }
      return a.id.compareTo(b.id);
    });
  return sortiert.first;
}

extension Formatstapel on AppDatabase {
  /// Alle Bilder, deren Name ohne Endung in mehr als einem Format vorkommt.
  /// Gelesen wird nur, was in Frage kommt. Nach der Zahl allein zu gehen
  /// hiesse, fast alles zu lesen: Ein iPhone fängt nach `IMG_9999` von vorn
  /// an, in einer grossen Bibliothek kommt fast jeder Name mehrmals vor.
  /// `jpg` und `jpeg` zählen hier noch als zwei – das gleicht
  /// [formatgruppen] aus; hier soll nichts verloren gehen.
  Future<List<AssetData>> _gleichnamigeBilder() async {
    const stamm = _stammSql;
    const bild =
        "type = 'IMAGE' AND is_trashed = 0 AND is_locked = 0 "
        'AND datum_geschaetzt = 0';
    final zeilen = await customSelect(
      'SELECT id FROM assets WHERE $bild AND $stamm IN ('
      'SELECT $stamm FROM assets WHERE $bild GROUP BY 1 '
      'HAVING count(DISTINCT lower(coalesce(dateiformat, original_file_name))) > 1)',
      readsFrom: {assets},
    ).get();
    return assetsByIds([for (final z in zeilen) z.read<String>('id')]);
  }

  /// Wie `unverknuepfteMitStamm` über den Index auf dem Dateinamen.
  Future<List<AssetData>> _bilderMitStamm(String stamm) {
    final name = assets.originalFileName.collate(Collate.noCase);
    return (select(assets)..where(
          (t) =>
              t.type.equals('IMAGE') &
              t.isTrashed.equals(false) &
              t.isLocked.equals(false) &
              name.isBiggerOrEqualValue('$stamm.') &
              name.isSmallerThanValue('$stamm/'),
        ))
        .get();
  }

  Future<Map<String, int>> _benannteGesichter(Iterable<String> ids) async {
    final anzahl = <String, int>{};
    final zahl = faces.id.count();
    for (final stueck in inStuecken(ids)) {
      final q = selectOnly(faces)
        ..addColumns([faces.assetId, zahl])
        ..where(faces.assetId.isIn(stueck) & faces.personId.isNotNull())
        ..groupBy([faces.assetId]);
      for (final z in await q.get()) {
        anzahl[z.read(faces.assetId)!] = z.read(zahl)!;
      }
    }
    return anzahl;
  }

  /// Welche von [ids] Angaben tragen, die jemand gesetzt hat.
  Future<Set<String>> _mitAngaben(List<AssetData> bilder) async {
    final mit = {
      for (final a in bilder)
        if (a.isFavorite ||
            a.rating > 0 ||
            a.colorLabel != null ||
            (a.description?.trim().isNotEmpty ?? false))
          a.id,
    };
    final ids = [for (final a in bilder) a.id];
    for (final stueck in inStuecken(ids)) {
      final alben = selectOnly(albumAssets, distinct: true)
        ..addColumns([albumAssets.assetId])
        ..where(albumAssets.assetId.isIn(stueck));
      mit.addAll([
        for (final z in await alben.get()) z.read(albumAssets.assetId)!,
      ]);
      final eigene = selectOnly(assetTags, distinct: true)
        ..addColumns([assetTags.assetId])
        ..where(
          assetTags.assetId.isIn(stueck) &
              assetTags.quelle.equals(Tagquelle.hand),
        );
      mit.addAll([
        for (final z in await eigene.get()) z.read(assetTags.assetId)!,
      ]);
    }
    return mit;
  }

  /// Stapelt gleiche Aufnahmen in verschiedenen Formaten – alle oder nur
  /// die mit dem Namensstamm [stamm]. Gibt zurück, wie viele Stapel neu
  /// entstanden oder gewachsen sind.
  ///
  /// Angaben der verdeckten Fassungen ziehen auf die sichtbare um (nicht
  /// nur kopiert): Alben, Favoriten und Suche zeigen nur die oberste, ein
  /// Foto verschwände sonst aus seinem Album. Und weil sie umziehen, bringt
  /// ein späteres Stapeln nichts zurück, was jemand an der Hauptversion
  /// entfernt hat. Wer eine Fassung von Hand herausgeholt hat, bekommt sie
  /// nicht wieder gestapelt ([formatausnahme]). Kommt zu einem Stapel ein
  /// weiteres Format dazu, bleiben Kennung und Hauptversion.
  Future<int> stapleFormate({String? stamm}) => transaction(() async {
    final bilder = stamm == null
        ? await _gleichnamigeBilder()
        : await _bilderMitStamm(stamm);
    if (bilder.length < 2) return 0;
    final verworfen = await _formatausnahmen([for (final a in bilder) a.id]);
    final gruppen = formatgruppen(
      bilder.where((a) => !verworfen.contains(formatausnahme(a.id))),
    );
    if (gruppen.isEmpty) return 0;
    final alle = [for (final g in gruppen) ...g];
    final benannt = await _benannteGesichter([for (final a in alle) a.id]);
    final mitAngaben = await _mitAngaben(alle);
    var gebildet = 0;
    for (final gruppe in gruppen) {
      final stapel = {for (final a in gruppe) ?a.stackId};
      if (stapel.length == 1 && gruppe.every((a) => a.stackId != null)) {
        continue;
      }
      final bisher = [for (final s in stapel) ...await assetsInStack(s)];
      final titel =
          bisher
              .where((a) => a.isStackCover && !a.isTrashed && !a.isLocked)
              .firstOrNull ??
          hauptfassung(gruppe, benannt: benannt, mitAngaben: mitAngaben);
      final ids = {
        for (final a in gruppe) a.id,
        for (final a in bisher) a.id,
      }.toList();
      await _uebertrageAngaben(
        titel.id,
        ids,
        beschreibungenVerbinden: false,
        verschieben: true,
      );
      // Wächst ein Stapel, behält er seine Kennung: Ein Befehl, der noch auf
      // sie wartet (Hauptversion, Auflösen), träfe sonst ins Leere.
      await createStack(
        stapel.length == 1
            ? stapel.single
            : variantenstapelId('format-${const Uuid().v4()}'),
        ids,
        titel.id,
      );
      // Im Archiv (#304) liegt der Stapel nur, wenn alles darin dort lag:
      // Sonst verschwände ein Foto aus der Zeitleiste, das dort zu sehen war.
      final archiv = [
        for (final a in gruppe) a.isArchived,
        for (final a in bisher) a.isArchived,
      ].every((x) => x);
      if (titel.isArchived != archiv) {
        await (update(assets)..where((t) => t.id.equals(titel.id))).write(
          AssetsCompanion(isArchived: Value(archiv)),
        );
      }
      gebildet++;
    }
    return gebildet;
  });

  /// Zeigt die Formate wieder einzeln. Gibt zurück, wie viele Aufnahmen
  /// es betraf. Keine Ausnahmen: Wer den Schalter wieder einschaltet, will
  /// den Stand von vorher.
  Future<int> loeseFormatstapelAuf() =>
      (update(
        assets,
      )..where((t) => t.stackId.like('$formatstapelPraefix%'))).write(
        const AssetsCompanion(
          stackId: Value(null),
          isStackCover: Value(false),
          stackSize: Value(null),
        ),
      );

  Future<Set<String>> _formatausnahmen(List<String> ids) async {
    final aus = <String>{};
    for (final stueck in inStuecken([
      for (final id in ids) formatausnahme(id),
    ])) {
      final q = select(verworfeneSerien)
        ..where((t) => t.schluessel.isIn(stueck));
      aus.addAll([for (final z in await q.get()) z.schluessel]);
    }
    return aus;
  }

  /// Merkt sich vor dem Auflösen von Hand, dass die Mitglieder von
  /// [stackId] nicht wieder gestapelt werden sollen.
  Future<void> merkeFormatausnahmen(String stackId) async {
    if (!istFormatstapel(stackId)) return;
    for (final a in await assetsInStack(stackId)) {
      await verwirfSerienvorschlag(formatausnahme(a.id));
    }
  }

  /// Wohin Angaben gehören, die für [id] gedacht sind: auf die Fassung, die
  /// in Zeitleiste, Alben und Suche steht. Liegt [id] verdeckt in einem
  /// Stapel, ist das dessen Titelbild – etwa nach dem Import, wenn ein RAW
  /// gerade hinter sein JPEG gerückt ist und dann seine XMP-Beilage, ein
  /// Album aus der Fotokammer oder ein geteiltes Album dazukommt.
  Future<String> sichtbareFassung(String id) async {
    final a = await assetById(id);
    final stapel = a?.stackId;
    if (a == null || a.isStackCover || stapel == null) return id;
    for (final m in await assetsInStack(stapel)) {
      if (m.isStackCover && !m.isTrashed && !m.isLocked) return m.id;
    }
    return id;
  }
}
