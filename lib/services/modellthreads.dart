import 'dart:io' show Platform;

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

/// Wie viele Rechenkerne ein Modell benutzen darf – und warum nicht alle.
///
/// **Der Befund.** „Bei der Ausführung der Aufgabe Standbilder generieren
/// war die App nicht mehr oder schlecht bedienbar." Keine der Sitzungen
/// dieser App setzte je eine Threadzahl: `createSession` wurde an
/// zwölf Stellen ohne Angabe gerufen, und ONNX Runtime nimmt sich dann
/// **so viele Threads, wie der Rechner Kerne hat**. Während eines Laufs
/// ist damit jeder Kern belegt – auch der, auf dem das Fenster gezeichnet
/// wird und die Maus ankommt. Die Oberfläche wird nicht langsam, weil die
/// Arbeit langsam ist, sondern weil für sie nichts übrig bleibt.
///
/// **Warum nicht einfach weniger arbeiten.** Ein Durchgang über 8.000
/// Aufnahmen soll zügig fertig werden; wer ihn anstösst, will ihn hinter
/// sich bringen. Zwei Kerne freizulassen kostet auf einem Achtkerner ein
/// Viertel der Rechenzeit und gibt dafür ein bedienbares Fenster zurück –
/// und niemand sieht einem Hintergrundlauf beim Rechnen zu, wohl aber
/// einer stehenden Oberfläche beim Stehen.
///
/// **Zwei Kerne und nicht einer:** Flutter braucht den Plattform-Thread
/// (Fenster, Eingaben) UND den Raster-Thread (Zeichnen). Bleibt nur einer
/// frei, teilen sich beide ihn mit allem übrigen des Systems.
///
/// Auf kleinen Maschinen wird nichts abgezogen, was nicht da ist: Unter
/// vier Kernen bleibt es bei der Hälfte, mindestens aber bei einem.
int modellThreads({int? kerne}) {
  final vorhanden = kerne ?? Platform.numberOfProcessors;
  if (vorhanden <= 1) return 1;
  if (vorhanden < 4) return (vorhanden / 2).floor().clamp(1, vorhanden);
  return vorhanden - 2;
}

/// Die Sitzungsoptionen, mit denen jedes Modell dieser App geladen wird.
///
/// [providers] wie gehabt; die Threadzahl kommt aus [modellThreads].
///
/// `interOpNumThreads: 1` – die zweite Zahl parallelisiert ÜBER Knoten
/// hinweg und wirkt nur bei `ORT_PARALLEL`, das hier nirgends eingestellt
/// ist. Sie ausdrücklich auf eins zu setzen kostet nichts und nimmt einer
/// künftigen Voreinstellung die Gelegenheit, unbemerkt Kerne zu belegen.
OrtSessionOptions modelloptionen({List<OrtProvider>? providers}) =>
    OrtSessionOptions(
      providers: providers,
      intraOpNumThreads: modellThreads(),
      interOpNumThreads: 1,
    );
