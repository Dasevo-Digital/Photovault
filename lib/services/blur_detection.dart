import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Schwellenwert für "unscharf" beim Score aus [computeBlurScore] –
/// empirischer Richtwert für ein auf 400px längste Kante herunterskaliertes
/// Graustufenbild mit 3x3-Laplace-Kernel: deutlich unscharfe Fotos liegen
/// meist darunter, scharfe Fotos üblicherweise weit darüber (oft im drei-
/// bis vierstelligen Bereich).
const blurryScoreThreshold = 100.0;

/// Schwellenwert für „dieses Gesicht ist zu weich", angewandt auf einen
/// 160x160-Gesichtsausschnitt (siehe [gesichtsschaerfe]).
///
/// **Warum eine eigene Zahl.** [blurryScoreThreshold] gilt für ein ganzes,
/// auf 400 Punkte verkleinertes Foto. Auf Gesichtsausschnitte angewandt
/// träfe sie ein Drittel aller Gesichter dieser Bibliothek – gemessen:
/// 32,9 %.
///
/// **Woher die 40 kommt.** An 1625 echten Ausschnitten aus der Bibliothek
/// gemessen (`tool/messe_gesichtsschaerfe.dart`), alle 160x160:
///
/// ```
///  1%    6,5      50%   167,8
///  5%   18,2      75%   386,4
/// 10%   33,7      90%   812,0
/// 25%   80,1      99%  2886,3
/// ```
///
/// 40 trifft 12,4 % – und zwar die richtigen: Die Ausschnitte im Bereich um
/// 25 wurden angesehen und sind sichtbar unbrauchbar (verwackelt, verrauscht
/// oder zu dunkel), die um den Median herum sind es nicht.
///
/// **Was der Wert mitmisst.** Ein dunkles Gesicht hat wenig Kontrast und
/// damit eine niedrige Varianz, auch wenn es scharf ist. Für die Sichtung
/// ist das kein Schaden – ein Gesicht, das man nicht erkennt, will man in
/// beiden Fällen nicht behalten –, aber die Zahl heisst deshalb
/// „Gesichtsschärfe" und nicht „Unschärfe".
const gesichtUnscharfSchwelle = 40.0;

/// Die Schärfe eines Gesichtsausschnitts.
///
/// Dieselbe Rechnung wie [computeBlurScore] – die Trennung ist die
/// Bezugsgrösse, nicht die Formel. Ausschnitte sind immer 160x160 (siehe
/// `FaceEngineService.cropFaceImage`) und damit untereinander vergleichbar,
/// unabhängig davon, wie gross die Person im Bild war. Genau das ist beim
/// Sichten die richtige Frage: nicht „wie viele Pixel hat dieses Gesicht",
/// sondern „sieht es aus der Nähe scharf aus".
double gesichtsschaerfe(img.Image ausschnitt) => computeBlurScore(ausschnitt);

/// Berechnet einen Schärfe-Score (Laplace-Varianz) für [image] – je niedriger
/// der Wert, desto unschärfer das Bild. Reine, isolate-taugliche Funktion
/// (kein Zugriff auf Widgets/Plugins), analog zu ClipService.embedImage:
/// nimmt ein bereits dekodiertes [img.Image] entgegen, statt selbst von der
/// Platte zu lesen, damit der Import-Pipeline dieselbe Dekodierung wie für
/// Gesichtserkennung/CLIP wiederverwenden kann.
double computeBlurScore(img.Image image) {
  const targetLongEdge = 400;
  final longEdge = math.max(image.width, image.height);
  final scale = longEdge > targetLongEdge ? targetLongEdge / longEdge : 1.0;
  final resized = scale < 1.0
      ? img.copyResize(
          image,
          width: (image.width * scale).round(),
          height: (image.height * scale).round(),
          interpolation: img.Interpolation.average,
        )
      : image;
  final gray = img.grayscale(resized);
  final width = gray.width;
  final height = gray.height;
  if (width < 3 || height < 3) return 0;

  var sum = 0.0;
  var sumSquares = 0.0;
  var count = 0;
  for (var y = 1; y < height - 1; y++) {
    for (var x = 1; x < width - 1; x++) {
      final center = gray.getPixel(x, y).r;
      final top = gray.getPixel(x, y - 1).r;
      final bottom = gray.getPixel(x, y + 1).r;
      final left = gray.getPixel(x - 1, y).r;
      final right = gray.getPixel(x + 1, y).r;
      final laplacian = (top + bottom + left + right - 4 * center).toDouble();
      sum += laplacian;
      sumSquares += laplacian * laplacian;
      count++;
    }
  }
  if (count == 0) return 0;
  final mean = sum / count;
  return sumSquares / count - mean * mean;
}

/// Schwellenwert für "gilt als scharfe Kante" im Fokus-Peaking-Overlay –
/// höher als bei [computeBlurScore] nötig, da hier nicht der Mittelwert
/// über ein ganzes (herunterskaliertes) Bild gebildet wird, sondern jeder
/// einzelne Pixel-Ausschlag für sich zählt.
const _focusPeakingEdgeThreshold = 40;

/// Reine, isolate-taugliche Funktion (kein Zugriff auf Widgets/Plugins,
/// analog zu [computeBlurScore]): liefert ein eingefärbtes RGBA-Overlay-PNG
/// derselben Auflösung wie [image], das lokal scharfe Kanten hervorhebt
/// ("Fokus-Peaking", wie im Sucher mancher Kameras) – wiederverwendet
/// denselben 4-Nachbar-Kreuz-Laplace-Kernel wie [computeBlurScore], aber als
/// ortsaufgelöste Karte statt als einzelnen Skalar. Einheitliche Einfärbung
/// (keine Heatmap) statt kontinuierlicher Farbverläufe, damit auf einen
/// Blick klar ist, was als "scharf" zählt. Skaliert [image] selbst NICHT
/// herunter – das übernimmt bewusst der Aufrufer (Performance-Kompromiss
/// zwischen Overlay-Genauigkeit und Rechenzeit liegt dort, siehe
/// AssetViewerScreen).
Uint8List renderFocusPeakingOverlayPng(img.Image image, {int threshold = _focusPeakingEdgeThreshold}) {
  final gray = img.grayscale(image);
  final width = gray.width;
  final height = gray.height;
  final overlay = img.Image(width: width, height: height, numChannels: 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      if (x == 0 || y == 0 || x == width - 1 || y == height - 1) {
        overlay.setPixelRgba(x, y, 255, 0, 0, 0);
        continue;
      }
      final center = gray.getPixel(x, y).r;
      final top = gray.getPixel(x, y - 1).r;
      final bottom = gray.getPixel(x, y + 1).r;
      final left = gray.getPixel(x - 1, y).r;
      final right = gray.getPixel(x + 1, y).r;
      final laplacian = (top + bottom + left + right - 4 * center).abs();
      final isEdge = laplacian > threshold;
      overlay.setPixelRgba(x, y, 255, 0, 0, isEdge ? 200 : 0);
    }
  }
  return Uint8List.fromList(img.encodePng(overlay));
}

/// Zwischenauflösung für das Fokus-Peaking-Overlay – bewusst deutlich unter
/// der vollen Anzeigeauflösung (siehe `_maxFullscreenDecodeDimension` in
/// asset_viewer_screen.dart), da das Overlay nur eine grobe, visuelle
/// Orientierung geben soll ("wo genau ist das scharf?"), keine pixelgenaue
/// Analyse. Die Anzeige gleicht die abweichende Auflösung per
/// `BoxFit.contain` gegenüber dem Originalbild aus (Muster: die
/// KI-Masken-Vorschau in develop_screen.dart läuft ebenfalls in einer
/// anderen Auflösung als das Basisbild).
const _focusPeakingIntermediateLongEdge = 1280;

/// Kombiniert Dekodieren + Herunterskalieren + Overlay-Berechnung in einem
/// einzelnen `compute()`-Aufruf (Muster: renderMaskPreviewPng in
/// segmentation_service.dart) – vermeidet einen zusätzlichen Isolate-
/// Rundweg, der beim separaten Dekodieren und Zurückreichen eines vollen
/// [img.Image] nötig wäre. Gibt `null` zurück, wenn die Datei nicht
/// dekodierbar ist (z.B. Video oder beschädigtes Bild).
Future<Uint8List?> computeFocusPeakingOverlay(Uint8List fileBytes) async {
  final decoded = img.decodeImage(fileBytes);
  if (decoded == null) return null;
  final longEdge = math.max(decoded.width, decoded.height);
  final scale = longEdge > _focusPeakingIntermediateLongEdge ? _focusPeakingIntermediateLongEdge / longEdge : 1.0;
  final resized = scale < 1.0
      ? img.copyResize(
          decoded,
          width: (decoded.width * scale).round(),
          height: (decoded.height * scale).round(),
          interpolation: img.Interpolation.average,
        )
      : decoded;
  return renderFocusPeakingOverlayPng(resized);
}
