import 'package:drift/drift.dart';

import '../db/database.dart';
import 'storage_paths.dart';

/// **Alle Dateien, die zu einer Aufnahme gehören – an einer Stelle.**
///
/// Diese Liste stand dreimal fast gleich im Quelltext: beim
/// Verschlüsseln, beim Entschlüsseln und beim endgültigen Löschen. Sie
/// ist zweimal auseinandergelaufen, und beide Male fiel es erst einer
/// Prüfrunde auf – zuerst fehlten Videozuschnitt und Objektmasken,
/// danach der XMP-Beipackzettel. Wer eine Dateiart hinzufügt, trägt sie
/// hier ein und ist damit überall richtig – in der App wie am Server
/// (#296).
///
/// Nicht vorhandene Dateien stehen mit in der Liste; die Verwender kommen
/// damit zurecht.
Future<List<String>> dateienDerAufnahme(
  AppDatabase db,
  StoragePaths paths,
  AssetData asset,
) async => [
  asset.relativePath,
  // Der Beipackzettel neben dem Original: Er trägt Beschreibung,
  // Schlagwörter, Bewertung und Ort im Klartext. Beim Sperren blieb
  // er liegen – genau das, wovor der gesperrte Ordner schützen soll
  // (dieselbe Überlegung wie bei metadata.json in backup_service).
  paths.xmpSidecarPath(asset.relativePath),
  if (asset.thumbnailRelativePath != null) asset.thumbnailRelativePath!,
  if (asset.previewRelativePath != null) asset.previewRelativePath!,
  if (asset.developedRelativePath != null) asset.developedRelativePath!,
  if (asset.restoredRelativePath != null) asset.restoredRelativePath!,
  if (asset.trimmedRelativePath != null) asset.trimmedRelativePath!,
  for (final face in await db.facesForAsset(asset.id))
    if (face.cropRelativePath != null) face.cropRelativePath!,
  for (final mask in await db.masksForAsset(asset.id)) mask.maskRelativePath,
];

/// Löscht Aufnahmen aus dem Papierkorb endgültig (#296): erst die Zeilen,
/// dann die Dateien. Gibt die Kennungen zurück, die gingen.
///
/// **Für den Server.** Bis 3.54 ging das nur in der App ohne Server. Am
/// Server gab es keinen Weg dafür, und ein verbundenes Gerät darf seine
/// Kopie nicht selbst ändern (`pv_nur_ueber_server`). Der Papierkorb einer
/// Bibliothek auf dem Server wuchs deshalb ohne Ende, und die Frist aus
/// den Einstellungen galt dort nie.
///
/// **Zeilen zuerst.** In einer Transaktion wird ausgewählt und gelöscht –
/// holt währenddessen jemand eine Aufnahme zurück, ist sie danach nicht
/// mehr dabei. Erst nach dem Abschluss gehen die Dateien. Schlägt dabei
/// etwas fehl, bleibt höchstens eine Datei ohne Zeile liegen; umgekehrt
/// wäre ein Original fort, dessen Zeile noch auf es zeigt. Die gelöschten
/// Zeilen schreibt das Protokoll des Servers mit, so erfahren die Geräte
/// davon.
///
/// Mit [ids] gehen nur die, die im Papierkorb liegen, und ihre
/// Live-Photo-Partner, soweit auch die im Papierkorb liegen – sonst bliebe
/// die Videohälfte unsichtbar zurück (#254). Gesperrte gehen nicht: Der
/// gesperrte Ordner hat seinen eigenen Papierkorb hinter der PIN. Ohne
/// [ids] geht der ganze Papierkorb (ohne Gesperrte); mit [vor] nur, was
/// vor diesem Zeitpunkt hineinkam – das ist der Ablauf nach der Frist,
/// und der nimmt wie in der App auch Gesperrte mit.
///
/// Eine Datei, auf die eine bleibende Aufnahme noch zeigt, bleibt liegen.
/// [mitGesperrten] nimmt auch Gesperrte aus [ids] – für den Papierkorb
/// hinter der PIN.
Future<List<String>> leerePapierkorb(
  AppDatabase db,
  StoragePaths paths, {
  Iterable<String>? ids,
  DateTime? vor,
  bool mitGesperrten = false,
}) async {
  final (weg, dateien) = await db.transaction(() async {
    final List<AssetData> kandidaten;
    if (ids != null) {
      final gewaehlt = ids.toSet();
      if (gewaehlt.isEmpty) return (const <String>[], const <String>{});
      final mitPartnern = await db.zugehoerige(
        gewaehlt.toList(),
        varianten: false,
      );
      kandidaten = [
        for (final a in await db.assetsByIds(mitPartnern.toList()))
          if (a.isTrashed && (mitGesperrten || !a.isLocked)) a,
      ];
    } else if (vor != null) {
      kandidaten = await db.expiredTrashAssets(vor);
    } else {
      kandidaten = await db.papierkorb();
    }
    if (kandidaten.isEmpty) return (const <String>[], const <String>{});
    final dateien = <String>{
      for (final a in kandidaten) ...[
        ...await dateienDerAufnahme(db, paths, a),
        paths.vaultMetadataRelativePath(a.id),
      ],
    };
    final kennungen = [for (final a in kandidaten) a.id];
    await db.deleteAssetRows(kennungen);
    dateien.removeAll(await _nochGebraucht(db, dateien));
    return (kennungen, dateien);
  });
  for (final d in dateien) {
    try {
      await paths.deletePermanently(d);
    } catch (_) {
      // Ein Pfad, den die Ablage nicht annimmt, oder eine Datei, die sich
      // nicht löschen lässt: Die Zeile ist fort, die Datei fällt bei der
      // Prüfung der Bibliothek als verwaist auf.
    }
  }
  return weg;
}

/// Welche von [pfade] eine bleibende Aufnahme noch braucht.
Future<Set<String>> _nochGebraucht(AppDatabase db, Set<String> pfade) async {
  final gebraucht = <String>{};
  final liste = pfade.toList();
  const spalten = [
    'relative_path',
    'thumbnail_relative_path',
    'preview_relative_path',
    'developed_relative_path',
    'restored_relative_path',
    'trimmed_relative_path',
  ];
  for (var i = 0; i < liste.length; i += 500) {
    final teil = liste.sublist(
      i,
      i + 500 > liste.length ? liste.length : i + 500,
    );
    final platz = List.filled(teil.length, '?').join(', ');
    for (final z
        in await db
            .customSelect(
              'SELECT ${spalten.join(', ')} FROM assets WHERE '
              '${spalten.map((s) => '$s IN ($platz)').join(' OR ')}',
              variables: [
                for (var j = 0; j < spalten.length; j++)
                  for (final t in teil) Variable<String>(t),
              ],
              readsFrom: {db.assets},
            )
            .get()) {
      for (final s in spalten) {
        final w = z.readNullable<String>(s);
        if (w != null) gebraucht.add(w);
      }
    }
  }
  return gebraucht..retainAll(pfade);
}

/// Die Dateien von [ids], soweit es die Aufnahmen hier gibt – für die
/// Kopie eines Geräts, bevor der Abgleich ihre Zeilen löscht (#296).
Future<Set<String>> dateienVonAufnahmen(
  AppDatabase db,
  StoragePaths paths,
  Iterable<String> ids,
) async => {
  for (final a in await db.assetsByIds(ids.toList())) ...[
    ...await dateienDerAufnahme(db, paths, a),
    paths.vaultMetadataRelativePath(a.id),
  ],
};

/// Löscht [dateien], soweit keine Aufnahme mehr auf sie zeigt.
///
/// Auf einem verbundenen Gerät ist alles davon nur geholt: Originale,
/// Vorschauen und Fassungen liegen im Zwischenspeicher, Miniaturen und
/// Gesichtsausschnitte im Vorrat fürs Blättern ohne Netz. Der
/// Zwischenspeicher verdrängt sie irgendwann, den Vorrat aber räumt nichts
/// auf. Ohne diesen Schritt blieben von einer endgültig gelöschten Aufnahme
/// Miniatur und Gesichter auf jedem Gerät liegen, das sie einmal gezeigt
/// hat.
Future<void> loescheVerwaisteDateien(
  AppDatabase db,
  StoragePaths paths,
  Set<String> dateien,
) async {
  if (dateien.isEmpty) return;
  final uebrig = {...dateien}..removeAll(await _nochGebraucht(db, dateien));
  for (final d in uebrig) {
    try {
      await paths.deletePermanently(d);
    } catch (_) {
      // s. leerePapierkorb
    }
  }
}
