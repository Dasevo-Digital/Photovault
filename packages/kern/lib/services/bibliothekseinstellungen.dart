import '../db/database.dart';

/// Die Einstellungen, die der Bibliothek gehören und für alle verbundenen
/// Geräte gelten – so, wie Browser (über den Server) und Telefon sie
/// zeigen. Geändert wird über die Befehle aus befehle/vorgaben.dart.
typedef Bibliothekseinstellungen = ({
  bool papierkorbLeeren,
  int papierkorbTage,
  double gesichtsschwelle,

  /// `null` heisst: sichere Vorschläge nicht automatisch übernehmen.
  double? vorschlaegeAb,
  bool auswertenNachImport,
  bool sucheUebersetzen,
  bool angabenSchuetzen,
});

Future<Bibliothekseinstellungen> bibliothekseinstellungen(
  AppDatabase db,
) async {
  final papierkorb = await db.trashSettingsRow();
  final app = await (db.select(
    db.appSettings,
  )..where((t) => t.id.equals(0))).getSingleOrNull();
  final privat = await db.privacySettingsRow();
  return (
    papierkorbLeeren: papierkorb?.autoDeleteEnabled ?? false,
    papierkorbTage: papierkorb?.autoDeleteAfterDays ?? 30,
    gesichtsschwelle: await db.faceSimilarityThresholdWert(),
    vorschlaegeAb: await db.vorschlaegeAutomatischAbWert(),
    auswertenNachImport: app?.autoAnalyzeAfterImport ?? true,
    sucheUebersetzen: await db.uebersetzeSucheUndTags(),
    angabenSchuetzen: privat?.protectMetadata ?? true,
  );
}
