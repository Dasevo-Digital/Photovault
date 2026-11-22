import 'dart:io';

import 'package:drift/drift.dart';
import 'package:kern/berechne.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/storage_paths.dart';

/// Wie viele Aufnahmen `LibraryState.aufnahmenOhneVorschaubild` fände –
/// für die Zahl auf der Karte „Vorschaubilder“ in den Aufgaben.
///
/// **Warum nicht einfach dessen Länge.** Die Liste lädt jede Aufnahme mit
/// allen Spalten, und drift wandelt die Zeilen im Isolat der Oberfläche um.
/// Danach prüft sie Datei für Datei mit je einem eigenen `await`. Bei
/// jedem Öffnen der Aufgaben stockte das bei grossen Bibliotheken, und die
/// Zahl kam erst nach Sekunden. Hier zählt die Datenbank die fehlenden
/// Einträge selbst, gelesen werden nur die beiden Pfade, und die Dateien
/// prüft ein eigenes Isolat.
///
/// In einer verbundenen Bibliothek ([StoragePaths.beschaffe]) ist der
/// Ordner ein Zwischenspeicher; dort zählen nur die fehlenden Einträge.
Future<int> zahlOhneVorschaubild(AppDatabase db, StoragePaths paths) async {
  final ohneEintrag = await db.countThumbnailRegen(onlyMissing: true);
  if (paths.beschaffe != null) return ohneEintrag;
  final a = db.assets;
  final zeilen =
      await (db.selectOnly(a)
            ..addColumns([
              a.type,
              a.thumbnailRelativePath,
              a.previewRelativePath,
            ])
            ..where(
              a.isTrashed.equals(false) &
                  a.isLocked.equals(false) &
                  a.thumbnailRelativePath.isNotNull(),
            ))
          .get();
  final paare = <(String, String?)>[];
  for (final z in zeilen) {
    final miniatur = z.read(a.thumbnailRelativePath)!;
    final vorschau = z.read(a.previewRelativePath);
    // Ein Video ohne Vorschau steht schon unter den fehlenden Einträgen
    // (siehe `_fehlendeVorschau` im Kern).
    if (z.read(a.type) == 'VIDEO' && vorschau == null) continue;
    paare.add((
      paths.absolute(miniatur).path,
      vorschau == null ? null : paths.absolute(vorschau).path,
    ));
  }
  return ohneEintrag + await berechne(_fehlendeDateien, paare);
}

int _fehlendeDateien(List<(String, String?)> paare) {
  var fehlend = 0;
  for (final (miniatur, vorschau) in paare) {
    if (!File(miniatur).existsSync() ||
        (vorschau != null && !File(vorschau).existsSync())) {
      fehlend++;
    }
  }
  return fehlend;
}
