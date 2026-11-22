import 'package:onnxruntime_api/onnxruntime_api.dart';

import 'modellthreads.dart';

/// Öffnet eine Sitzung für das Modell unter [pfad] – mit [optionen] oder
/// sonst den [modelloptionen] der App.
typedef SitzungOeffnen =
    Future<OrtSession> Function(String pfad, {OrtSessionOptions? optionen});

/// Lädt ein Modell aus mehreren Teilen und schliesst die schon offenen
/// Sitzungen wieder, wenn ein späterer Teil scheitert.
///
/// **Warum das nötig ist.** Viele Modelle bestehen aus mehreren Dateien:
/// Encoder und Decoder, vier Teile bei der Bildbeschreibung, dazu ein
/// Vokabular. Sie wurden nacheinander geöffnet; scheiterte der zweite Teil
/// – zu wenig Speicher, ein Zahlenformat, das die Laufzeit nicht kennt, ein
/// unlesbares Vokabular –, blieb der erste als offene Sitzung im Speicher
/// liegen, ohne dass ihn noch jemand erreichen konnte. Der `ModellHalter`
/// versucht es beim nächsten Gebrauch erneut, und jeder Versuch liess eine
/// weitere Sitzung zurück – Hunderte Megabyte nativer Speicher, den kein
/// Sammler zurückholt, und gerade dann, wenn der Speicher ohnehin knapp
/// ist.
///
/// [laden] öffnet seine Sitzungen über die übergebene Funktion; was sie
/// geöffnet hat, wird bei einem Fehler geschlossen, und der Fehler geht
/// unverändert weiter.
Future<T> sitzungenLaden<T>(
  Future<T> Function(SitzungOeffnen oeffne) laden,
) async {
  final ort = OnnxRuntime();
  final offen = <OrtSession>[];
  Future<OrtSession> oeffne(String pfad, {OrtSessionOptions? optionen}) async {
    final sitzung = await ort.createSession(
      pfad,
      options: optionen ?? modelloptionen(),
    );
    offen.add(sitzung);
    return sitzung;
  }

  try {
    return await laden(oeffne);
  } catch (_) {
    for (final sitzung in offen.reversed) {
      try {
        await sitzung.close();
      } catch (_) {
        // Bestmöglich: Der ursprüngliche Fehler ist der, der zählt.
      }
    }
    rethrow;
  }
}
