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

const _formatgastPraefix = 'formatgast:';

/// Unter diesem Schlüssel merkt sich `verworfene_serien`, dass das Stapeln
/// [assetId] in den fremden Stapel [stackId] gelegt hat – eine Serie oder
/// Varianten, in denen schon ein anderes Format derselben Aufnahme lag
/// (#365). Der Schalter holt sie beim Ausschalten wieder heraus, und nur
/// dann, wenn sie noch in genau diesem Stapel liegt.
String formatgast(String assetId, String stackId) =>
    '$_formatgastPraefix$assetId|$stackId';

/// Was Programme an einen Namen hängen, damit eine Datei im Zielordner
/// nicht mit einer gleichnamigen kollidiert (#365): acht Hexziffern
/// (`IMG_0531-1bd0b0c6.jpg`), eine Nummer in Klammern oder mit Leerzeichen
/// (`IMG_1144 (2).CR3`, `IMG_1144 2.CR3`) und Immichs `+1`. In einer echten
/// Bibliothek trugen 1561 Dateien so einen Zusatz, und rund 90 RAW/JPEG-Paare
/// blieben deshalb einzeln.
final _namenszusatz = RegExp(
  r'(-[0-9a-f]{8}| \(\d{1,3}\)| \d{1,2}|\+\d{1,3})$',
);

/// Der Name ohne Endung, klein geschrieben und ohne [_namenszusatz]: Daran
/// erkennen sich die Formate einer Aufnahme. Die Zusätze dürfen sich
/// stapeln (`IMG_0361+1-88c523ca.jpg`). Ein Name, der nur aus einem Zusatz
/// besteht, bleibt, wie er ist.
///
/// Dass zwei verschiedene Aufnahmen so denselben Stamm bekommen, ist kein
/// Fehler: [formatgruppen] verlangt dazu noch höchstens zwei Sekunden
/// Abstand, keine zwei Kameras, keine zwei Nummern ([_formatnummer]) und
/// zwei verschiedene Formate.
String formatstamm(String name) => _zerlege(name).$1;

/// Die Nummern unter den Zusätzen (` 2`, ` (2)`, `+2`), als Zahl
/// (` (02)` ist ` 2`), leer ohne. Die Hexziffern zählen nicht: Sie sind je
/// Datei zufällig.
///
/// `Hochzeit 1.CR3` und `Hochzeit 2.JPG` haben denselben Stamm, sind aber
/// zwei Aufnahmen, auch wenn eine Serie sie in derselben Sekunde
/// aufnahm (#367). Zusammen gehören darum zwei Dateien mit derselben
/// Nummer, und eine ohne Nummer nur, wenn sie eindeutig zu einer passt
/// ([_ordneNachNummer]).
String _formatnummer(String name) => _zerlege(name).$2;

final _keineZiffer = RegExp(r'\D');

(String, String) _zerlege(String name) {
  var stamm = p.basenameWithoutExtension(name).toLowerCase();
  final nummern = <String>[];
  for (var i = 0; i < 3; i++) {
    final zusatz = _namenszusatz.firstMatch(stamm);
    if (zusatz == null || zusatz.start == 0) break;
    if (!zusatz[0]!.startsWith('-')) {
      nummern.add('${int.parse(zusatz[0]!.replaceAll(_keineZiffer, ''))}');
    }
    stamm = stamm.substring(0, zusatz.start);
  }
  return (stamm, nummern.join(','));
}

/// Das Format ohne die Unterschiede, die nur die Schreibweise betreffen.
String? _formatAus(String? dateiformat, String name) =>
    switch ((dateiformat ?? p.extension(name).replaceFirst('.', ''))
        .toLowerCase()) {
      '' => null,
      'jpeg' || 'jpe' => 'jpg',
      'heif' => 'heic',
      'tiff' => 'tif',
      final f => f,
    };

String? _formatVon(AssetData a) =>
    _formatAus(a.dateiformat, a.originalFileName);

bool _selbeKamera(AssetData a, AssetData b) {
  final x = a.cameraModel?.trim().toLowerCase() ?? '';
  final y = b.cameraModel?.trim().toLowerCase() ?? '';
  return x.isEmpty || y.isEmpty || x == y;
}

/// Welche der [bilder] dieselbe Aufnahme in verschiedenen Formaten sind.
///
/// Gleicher [formatstamm], Aufnahmezeit innerhalb von [formatgleichAbstand],
/// keine zwei verschiedenen Kameras, keine zwei verschiedenen Nummern
/// ([_ordneNachNummer]) und mindestens zwei Formate in der Gruppe. Ein
/// geschätztes Datum zählt nicht: Es sagt nichts darüber, ob
/// zwei Dateien zur selben Aufnahme gehören. Auch was schon in einer Serie
/// oder in Varianten liegt, gehört dazu; was damit geschieht, entscheidet
/// [Formatstapel.stapleFormate].
List<List<AssetData>> formatgruppen(Iterable<AssetData> bilder) {
  final jeStamm = <String, List<AssetData>>{};
  for (final a in bilder) {
    if (a.type != 'IMAGE' ||
        a.isTrashed ||
        a.isLocked ||
        a.datumGeschaetzt ||
        _formatVon(a) == null) {
      continue;
    }
    (jeStamm[formatstamm(a.originalFileName)] ??= []).add(a);
  }
  return [
    for (final gleichnamig in jeStamm.values)
      if (gleichnamig.length > 1)
        for (final g in _ordneNachNummer(gleichnamig))
          if ({for (final a in g) _formatVon(a)}.length > 1) g,
  ];
}

/// Teilt Bilder mit demselben [formatstamm] in Aufnahmen.
///
/// Zuerst nach Nummer ([_formatnummer]): Nur gleiche Nummern, und Bilder
/// ohne Nummer unter sich, je innerhalb von [formatgleichAbstand] und ohne
/// zwei Kameras. Dann kommt eine Gruppe ohne Nummer zu einer mit Nummer,
/// etwa `IMG_1144.jpg` zu `IMG_1144 (2).CR3` – aber nur, wenn beide
/// füreinander die einzige sind, die passt. Bei `Hochzeit.jpg` neben
/// `Hochzeit 1.CR3` und `Hochzeit 2.CR3` aus derselben Sekunde hinge es
/// sonst nur an der Reihenfolge, zu welchem RAW das JPEG käme (#369); im
/// Zweifel bleibt es sichtbar.
List<List<AssetData>> _ordneNachNummer(List<AssetData> gleichnamig) {
  final nummer = {
    for (final a in gleichnamig) a.id: _formatnummer(a.originalFileName),
  };
  gleichnamig.sort((a, b) => a.fileCreatedAt.compareTo(b.fileCreatedAt));
  final offen = <List<AssetData>>[];
  for (final a in gleichnamig) {
    final passend = offen
        .where(
          (g) =>
              nummer[g.first.id] == nummer[a.id] &&
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
  final ohne = [
    for (final g in offen)
      if (nummer[g.first.id]!.isEmpty) g,
  ];
  final mit = [
    for (final g in offen)
      if (nummer[g.first.id]!.isNotEmpty) g,
  ];
  final passt = {
    for (final u in ohne)
      u: [
        for (final n in mit)
          if (_passenZusammen(u, n)) n,
      ],
  };
  final dazu = <List<AssetData>>{};
  for (final u in ohne) {
    if (passt[u]!.length != 1) continue;
    final n = passt[u]!.single;
    if (ohne.where((v) => passt[v]!.contains(n)).length != 1) continue;
    n.addAll(u);
    dazu.add(u);
  }
  return [
    for (final g in offen)
      if (!dazu.contains(g)) g,
  ];
}

/// Ob [u] und [n] zusammen noch eine Aufnahme sein können: alles innerhalb
/// von [formatgleichAbstand] und keine zwei Kameras.
bool _passenZusammen(List<AssetData> u, List<AssetData> n) {
  final zeiten = [
    for (final a in [...u, ...n]) a.fileCreatedAt,
  ]..sort();
  return zeiten.last.difference(zeiten.first) <= formatgleichAbstand &&
      u.every((a) => n.every((b) => _selbeKamera(a, b)));
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
  /// Alle Bilder, deren [formatstamm] in mehr als einem Format vorkommt.
  ///
  /// Zuerst nur Kennung, Name und Format aller Bilder: Seit Zusätze wie
  /// `-1bd0b0c6` nicht mehr trennen (#365), lässt sich der Stamm nicht mehr
  /// in SQL bilden. Ganze Zeilen liest es erst für die Kandidaten. Nach der
  /// Zahl allein zu gehen hiesse dagegen, fast alles ganz zu lesen: Ein
  /// iPhone fängt nach `IMG_9999` von vorn an, in einer grossen Bibliothek
  /// kommt fast jeder Name mehrmals vor.
  Future<List<AssetData>> _gleichnamigeBilder() async {
    final zeilen = await customSelect(
      'SELECT id, original_file_name, dateiformat FROM assets '
      "WHERE type = 'IMAGE' AND is_trashed = 0 AND is_locked = 0 "
      'AND datum_geschaetzt = 0',
      readsFrom: {assets},
    ).get();
    final formate = <String, Set<String>>{};
    final kennungen = <String, List<String>>{};
    for (final z in zeilen) {
      final name = z.read<String>('original_file_name');
      final format = _formatAus(z.readNullable<String>('dateiformat'), name);
      if (format == null) continue;
      final stamm = formatstamm(name);
      (formate[stamm] ??= {}).add(format);
      (kennungen[stamm] ??= []).add(z.read<String>('id'));
    }
    return assetsByIds([
      for (final e in kennungen.entries)
        if (formate[e.key]!.length > 1) ...e.value,
    ]);
  }

  /// Die Bilder mit dem [formatstamm] [stamm], über den Index auf dem
  /// Dateinamen: Jeder Name, der so beginnt, liegt zwischen [stamm] und
  /// `stamm~` – Punkt, Bindestrich, Leerzeichen und `+` sortieren vor der
  /// Tilde. Was dort sonst noch liegt (`IMG_05310`), fällt danach heraus.
  Future<List<AssetData>> _bilderMitStamm(String stamm) async {
    final name = assets.originalFileName.collate(Collate.noCase);
    final kandidaten =
        await (select(assets)..where(
              (t) =>
                  t.type.equals('IMAGE') &
                  t.isTrashed.equals(false) &
                  t.isLocked.equals(false) &
                  name.isBiggerOrEqualValue(stamm) &
                  name.isSmallerThanValue('$stamm~'),
            ))
            .get();
    return [
      for (final a in kandidaten)
        if (formatstamm(a.originalFileName) == stamm) a,
    ];
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
  /// die mit demselben [formatstamm] wie die Datei [name]. Gibt zurück, wie
  /// viele Stapel neu entstanden oder gewachsen sind.
  ///
  /// Angaben der verdeckten Fassungen ziehen auf die sichtbare um (nicht
  /// nur kopiert): Alben, Favoriten und Suche zeigen nur die oberste, ein
  /// Foto verschwände sonst aus seinem Album. Und weil sie umziehen, bringt
  /// ein späteres Stapeln nichts zurück, was jemand an der Hauptversion
  /// entfernt hat. Wer eine Fassung von Hand herausgeholt hat, bekommt sie
  /// nicht wieder gestapelt ([formatausnahme]). Kommt zu einem Stapel ein
  /// weiteres Format dazu, bleiben Kennung und Hauptversion.
  ///
  /// Liegt ein Format schon in einer Serie oder in Varianten, kommt der
  /// Rest dorthin ([_nimmInStapelAuf]); einen eigenen Formatstapel daneben
  /// gibt es nicht, ein Stapel im Stapel auch nicht.
  Future<int> stapleFormate({String? name}) => transaction(() async {
    final bilder = name == null
        ? await _gleichnamigeBilder()
        : await _bilderMitStamm(formatstamm(name));
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
      if (stapel.any((s) => !istFormatstapel(s))) {
        // Nur in genau einen fremden Stapel, und nur, was frei liegt: Zwei
        // Serien oder eine Serie neben einem Formatstapel bleiben, wie sie
        // sind.
        if (stapel.length == 1 &&
            await _nimmInStapelAuf(stapel.single, [
              for (final a in gruppe)
                if (a.stackId == null) a,
            ], mitAngaben: mitAngaben)) {
          gebildet++;
        }
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

  /// Legt [frei] verdeckt in den Stapel [stackId] – eine Serie oder
  /// Varianten, in denen schon ein anderes Format derselben Aufnahme liegt
  /// (#365). Sonst stünde das JPEG einzeln neben der Serie, in der sein RAW
  /// steckt.
  ///
  /// Anders als im Formatstapel ziehen hier keine Angaben um: Das Titelbild
  /// einer Serie ist meist ein anderes Bild, Sterne oder ein Album gehörten
  /// dort nicht hin. Deshalb bleibt sichtbar, was Angaben trägt, und ebenso,
  /// was nicht so im Archiv liegt wie das Titelbild. Wer dann stapeln will,
  /// tut es von Hand.
  ///
  /// Ein Live Photo bleibt ebenfalls sichtbar (#368): Läge es verdeckt
  /// hinter seinem JPEG als Titelbild, spielte das Raster sein Video nicht
  /// mehr. Im Formatstapel kommt es dagegen nach oben ([hauptfassung]).
  ///
  /// Benannte Gesichter halten nicht ab: Sie bleiben an der Datei, und die
  /// Seite einer Person zeigt auch verdeckte Bilder eines Stapels
  /// (`watchAssetsForPerson`). In einer echten Bibliothek blieben sonst acht
  /// JPEGs einer Serie sichtbar, nur weil auf ihnen jemand erkannt war.
  Future<bool> _nimmInStapelAuf(
    String stackId,
    List<AssetData> frei, {
    required Set<String> mitAngaben,
  }) async {
    final bisher = await assetsInStack(stackId);
    final titel = bisher
        .where((a) => a.isStackCover && !a.isTrashed && !a.isLocked)
        .firstOrNull;
    if (titel == null) return false;
    final gaeste = [
      for (final a in frei)
        if (!mitAngaben.contains(a.id) &&
            a.linkedAssetId == null &&
            a.isArchived == titel.isArchived)
          a,
    ];
    if (gaeste.isEmpty) return false;
    await createStack(stackId, [
      for (final a in bisher) a.id,
      for (final a in gaeste) a.id,
    ], titel.id);
    for (final a in gaeste) {
      await verwirfSerienvorschlag(formatgast(a.id, stackId));
    }
    return true;
  }

  /// Zeigt die Formate wieder einzeln. Gibt zurück, wie viele Aufnahmen
  /// es betraf. Keine Ausnahmen: Wer den Schalter wieder einschaltet, will
  /// den Stand von vorher. Auch was das Stapeln in eine Serie oder in
  /// Varianten gelegt hat ([formatgast]), kommt wieder heraus.
  Future<int> loeseFormatstapelAuf() => transaction(() async {
    final n =
        await (update(
          assets,
        )..where((t) => t.stackId.like('$formatstapelPraefix%'))).write(
          const AssetsCompanion(
            stackId: Value(null),
            isStackCover: Value(false),
            stackSize: Value(null),
          ),
        );
    return n + await _entlasseFormatgaeste();
  });

  /// Holt jede Aufnahme mit einer [formatgast]-Marke aus ihrem Stapel,
  /// sofern sie noch verdeckt in genau diesem liegt. Wurde der Stapel
  /// inzwischen aufgelöst oder ist sie dort Titelbild geworden, bleibt sie,
  /// wo sie ist. Die Marken gehen in jedem Fall.
  Future<int> _entlasseFormatgaeste() async {
    final marken = await (select(
      verworfeneSerien,
    )..where((t) => t.schluessel.like('$_formatgastPraefix%'))).get();
    final betroffen = <String>{};
    var n = 0;
    for (final m in marken) {
      await (delete(
        verworfeneSerien,
      )..where((t) => t.schluessel.equals(m.schluessel))).go();
      final rest = m.schluessel.substring(_formatgastPraefix.length);
      final trenner = rest.indexOf('|');
      if (trenner < 1) continue;
      final id = rest.substring(0, trenner);
      final stackId = rest.substring(trenner + 1);
      final a = await assetById(id);
      if (a == null || a.stackId != stackId || a.isStackCover) continue;
      await (update(assets)..where((t) => t.id.equals(id))).write(
        const AssetsCompanion(
          stackId: Value(null),
          isStackCover: Value(false),
          stackSize: Value(null),
        ),
      );
      betroffen.add(stackId);
      n++;
    }
    for (final stackId in betroffen) {
      final rest = await assetsInStack(stackId);
      final titel = rest.where((a) => a.isStackCover).firstOrNull;
      if (rest.length < 2 || titel == null) {
        await unstackAssets(stackId);
      } else {
        await createStack(stackId, [for (final a in rest) a.id], titel.id);
      }
    }
    return n;
  }

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
