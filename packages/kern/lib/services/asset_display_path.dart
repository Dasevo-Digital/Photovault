import '../db/database.dart';

/// Bestes verfügbares Anzeigebild/-video eines Assets, in Prioritätsreihen-
/// folge: KI-restauriert (RestoreQueueService, nur Fotos) > entwickelt
/// (Nutzer-Anpassungen aus dem DevelopScreen, nur Fotos) > zugeschnitten
/// (VideoTrimScreen, nur Videos) > konvertierte Vorschau (HEIC/RAW & Co.)
/// > Originaldatei. Restauriert steht vor entwickelt, weil eine
/// Restaurierung – anders als die live nachregelbaren Entwickeln-Regler –
/// ein bewusst einmalig angestoßenes, abgeschlossenes Ergebnis ist, das der
/// Nutzer typischerweise auch sehen will, wenn es vorliegt.
/// `developedRelativePath` und `trimmedRelativePath` schließen sich
/// gegenseitig aus (ein Asset ist entweder Foto oder Video), die
/// Reihenfolge zwischen ihnen spielt daher keine Rolle.
///
/// Bewusst NICHT für KI-Verarbeitung (Gesichtserkennung/CLIP) verwendet –
/// die soll immer das unveränderte Originalbild sehen, nicht die
/// Belichtungs-/Weißabgleich-Anpassungen des Nutzers, siehe
/// LibraryState._decodableFile. Aus demselben Grund auch nicht im
/// (destruktiven) ImageEditorScreen oder der Gesichts-Review verwendet.
/// **Bei einem Video zählt die Vorschau nicht.** Seit die Auswertung auch
/// Videos erreicht, trägt jedes Video eine Vorschau – ein Standbild aus
/// der ersten Sekunde. Als Anzeigepfad genommen ersetzte es den Film durch
/// ein Foto: Der Betrachter bekäme ein unbewegliches Bild und keinen
/// Abspieler. Ein zugeschnittenes Video (`trimmedRelativePath`) steht
/// weiterhin davor, denn das ist ein Film.
String displayRelativePath(AssetData asset) =>
    asset.restoredRelativePath ??
    asset.developedRelativePath ??
    asset.trimmedRelativePath ??
    (asset.type == 'VIDEO' ? null : asset.previewRelativePath) ??
    asset.relativePath;
