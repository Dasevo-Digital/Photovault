import 'package:path/path.dart' as p;

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
///
/// **Das Ansichtsbild eines grossen JPEG zählt mit (#333)**, ausser mit
/// [mitAnsichtsbild] `false`. Handy und Browser zeigen es wie die Vorschau
/// eines HEIC und holen das Original erst zum Zoomen; der Rechner zeigt
/// weiter das Original (siehe [hatAnsichtsbild]).
String displayRelativePath(AssetData asset, {bool mitAnsichtsbild = true}) =>
    asset.restoredRelativePath ??
    asset.developedRelativePath ??
    asset.trimmedRelativePath ??
    (asset.type == 'VIDEO' || (!mitAnsichtsbild && hatAnsichtsbild(asset))
        ? null
        : asset.previewRelativePath) ??
    asset.relativePath;

/// Woran das Ansichtsbild eines JPEG zu erkennen ist (#333): der Zusatz am
/// Namen seiner Vorschau, `previews/<id>-ansicht.jpg`.
const ansichtsbildZusatz = '-ansicht';

/// Ob die Vorschau von [asset] nur ein Ansichtsbild ist (#333).
///
/// **Warum es das gibt.** Ein JPEG lesen Browser und Handy selbst; es bekam
/// deshalb keine Vorschau, und der Betrachter lud das ganze Original vom
/// Server – aus einer Kamera oft 8 bis 20 MB, ehe das Foto erschien. Der
/// Server legt grossen JPEG deshalb ein verkleinertes Bild daneben, so
/// gross wie die Vorschau eines HEIC.
///
/// **Warum es keine gewöhnliche Vorschau ist.** Eine Vorschau steht für ein
/// Original, das Flutter und `package:image` nicht lesen; darum rechnen die
/// Auswertungen aus ihr, und der Rechner zeigt sie. Ein JPEG ist selbst
/// lesbar und schärfer: Aus dem Ansichtsbild kämen Gesichter, Texte und
/// Schärfewerte aus einem Viertel der Punkte, anders als bei jedem bisher
/// ausgewerteten JPEG (siehe [lesbarerPfad]). Erkannt wird es am Namen,
/// nicht an der Endung des Originals: In der Bibliothek liegt auch HEIC
/// unter `.jpg`, und dessen Vorschau ist nötig.
bool hatAnsichtsbild(AssetData asset) {
  final vorschau = asset.previewRelativePath;
  return asset.type == 'IMAGE' &&
      vorschau != null &&
      p.basenameWithoutExtension(vorschau).endsWith(ansichtsbildZusatz);
}

/// Die Datei, aus der sich ein Bild in voller Güte dekodieren lässt: die
/// Vorschau, wo Flutter und `package:image` das Original nicht lesen (HEIC,
/// RAW, PSD, sehr grosse Dateien; bei einem Video das Standbild), sonst das
/// Original – nie das Ansichtsbild eines JPEG (#333).
///
/// Für die Auswertungen, für das, was verbundene Rechner für den Server
/// rechnen, und für die Ansichten am Rechner, die genau hinsehen.
String lesbarerPfad(AssetData asset) =>
    (hatAnsichtsbild(asset) ? null : asset.previewRelativePath) ??
    asset.relativePath;

/// Woraus die volle Auflösung eines Fotos kommt (#256): dasselbe Bild wie
/// [displayRelativePath], nur nie die verkleinerte Vorschau – restauriert,
/// entwickelt, sonst das Original.
///
/// Bis 3.49.9 zeigte der Betrachter auf dem Handy und im Browser von HEIC,
/// RAW und DNG nur die Vorschau mit 2048 Punkten an der langen Seite. Ein
/// iPhone fotografiert in HEIC – beim Zoomen war also fast jedes Foto
/// unscharf.
String vollbildQuelle(AssetData asset) =>
    asset.restoredRelativePath ??
    asset.developedRelativePath ??
    asset.relativePath;

/// Ob der Betrachter für die volle Auflösung mehr braucht als
/// [displayRelativePath] – also gerade die Vorschau oder das Ansichtsbild
/// zeigt.
bool zeigtVorschau(AssetData asset) =>
    asset.type == 'IMAGE' &&
    displayRelativePath(asset) != vollbildQuelle(asset);

/// Was Browser und Handy selbst lesen. Alles andere wandelt der Server für
/// die volle Auflösung in ein JPEG (#256).
const direktAnzeigbareEndungen = {'.jpg', '.jpeg', '.png', '.webp', '.gif'};

/// Ob [relativ] ohne Wandlung angezeigt werden kann.
bool istDirektAnzeigbar(String relativ) =>
    direktAnzeigbareEndungen.contains(p.extension(relativ).toLowerCase());
