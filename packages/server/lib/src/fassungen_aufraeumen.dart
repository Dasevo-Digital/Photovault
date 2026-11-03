import 'dart:io';

import 'package:drift/drift.dart';
import 'package:kern/services/asset_display_path.dart';
import 'package:path/path.dart' as p;

import 'bibliothek.dart';
import 'videofassung.dart';
import 'vollbild.dart';

/// Hält [speicher] unter [grenze] Bytes: die ältesten zuerst, bis vier
/// Fünftel frei sind, damit nicht jede nächste Wandlung wieder aufräumt.
/// [behalten] (die gerade fertige Fassung) bleibt in jedem Fall.
///
/// Die Zeit wird beim Ausliefern nicht aufgefrischt – sie steckt im ETag,
/// und der Browser soll seine Kopie behalten dürfen.
Future<void> begrenzeZwischenspeicher(
  Directory speicher,
  int grenze, {
  required File behalten,
}) async {
  final dateien = <(File, int, DateTime)>[];
  var summe = 0;
  await for (final e in speicher.list(followLinks: false)) {
    if (e is! File || e.path == behalten.path) continue;
    // Eine Wandlung, die gerade schreibt.
    if (e.path.endsWith('.teil')) continue;
    try {
      final s = await e.stat();
      dateien.add((e, s.size, s.modified));
      summe += s.size;
    } on FileSystemException {
      // Zwischen Auflisten und Messen gelöscht.
    }
  }
  summe += await behalten.length();
  if (summe <= grenze) return;
  dateien.sort((a, b) => a.$3.compareTo(b.$3));
  final ziel = grenze * 4 ~/ 5;
  for (final (f, bytes, _) in dateien) {
    if (summe <= ziel) break;
    try {
      await f.delete();
      summe -= bytes;
    } on FileSystemException {
      // Gerade weg – dann eben beim nächsten Mal.
    }
  }
}

/// Räumt die gewandelten Fassungen von [b] auf (#261): Vollbilder
/// (`vollbild/`) und Videofassungen (`abspielbar/`). Gibt zurück, wie
/// viele Dateien gingen.
///
/// **Warum.** Bis 3.52 blieb eine Fassung liegen, bis die Grenze sie
/// verdrängte – auch die einer Aufnahme, die es nicht mehr gibt oder die
/// inzwischen gesperrt ist. Erreichbar war sie nicht mehr, aber sie lag
/// auf der Platte und in jeder Sicherung des Containers, ohne Schlüssel.
///
/// Gehen darf, was zu keiner Aufnahme mehr gehört, was zu einer
/// gesperrten gehört, und was nicht mehr der Fassung entspricht, die der
/// Betrachter heute zeigt (etwa das Vollbild vor einer neuen Entwicklung,
/// die Fassung des ganzen Videos neben der gekürzten). Was im Papierkorb
/// liegt, bleibt: Es lässt sich zurückholen.
///
/// Läuft beim Öffnen der Bibliothek, bevor eine Anfrage sie erreicht –
/// deshalb gehen auch halbe Dateien (`.teil`) einer abgebrochenen
/// Wandlung.
Future<int> raeumeFassungenAuf(Bibliothek b) async {
  final vollbild = Directory(p.join(b.ordner.path, 'vollbild'));
  final abspielbar = Directory(p.join(b.ordner.path, 'abspielbar'));
  final dateien = [
    for (final d in [vollbild, abspielbar])
      if (await d.exists())
        ...(await d.list(followLinks: false).toList()).whereType<File>(),
  ];
  if (dateien.isEmpty) return 0;

  // Die Kennungen aus den Namen: `<id>-<12 Zeichen>.jpg`, `<id>.mp4` und
  // `<id>-gekuerzt.mp4`.
  String? kennung(File f) {
    var name = p.basename(f.path);
    if (name.endsWith('.teil')) return null;
    if (p.dirname(f.path) == vollbild.path) {
      return RegExp(r'^(.+)-[0-9a-f]{12}\.jpg$').firstMatch(name)?.group(1);
    }
    if (!name.endsWith('.mp4')) return null;
    name = name.substring(0, name.length - 4);
    return name.endsWith('-gekuerzt')
        ? name.substring(0, name.length - '-gekuerzt'.length)
        : name;
  }

  final ids = {for (final f in dateien) ?kennung(f)};
  final behalten = <String>{};
  final liste = ids.toList();
  for (var i = 0; i < liste.length; i += 500) {
    final teil = liste.sublist(i, (i + 500).clamp(0, liste.length));
    final zeilen = await (b.db.select(
      b.db.assets,
    )..where((t) => t.id.isIn(teil) & t.isLocked.equals(false))).get();
    for (final a in zeilen) {
      if (a.type == 'VIDEO') {
        final name = a.trimmedRelativePath != null ? '${a.id}-gekuerzt' : a.id;
        behalten.add(Videofassungen.ziel(abspielbar, name).path);
      } else {
        final quelle = b.pfade.absolute(vollbildQuelle(a)).path;
        behalten.add(Vollbilder.ziel(vollbild, a.id, quelle).path);
      }
    }
  }

  var weg = 0;
  for (final f in dateien) {
    if (behalten.contains(f.path)) continue;
    try {
      await f.delete();
      weg++;
    } on FileSystemException {
      // Schon weg.
    }
  }
  return weg;
}
