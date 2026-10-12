# Anpassungen gegenüber flutter_onnxruntime 1.9.0

Diese Kopie stammt aus dem Paket `flutter_onnxruntime` 1.9.0 (MIT, © MASIC AI,
<https://github.com/masicai/flutter_onnxruntime>). Weggelassen sind nur
`example/`, `doc/`, `CONTRIBUTING.md` und das Logo. Geändert sind drei Dinge.

## 1. Die Aufrufe laufen nicht im Hauptfaden

Das Original rechnet jedes Modell synchron im Kanal-Handler, also auf dem
Hauptfaden der Plattform. Unter macOS teilen sich Plattform und Oberfläche
diesen Faden; eine Kachel der KI-Restaurierung hielt die App so 5,9 Sekunden
lang an (Issue #14, gemessen mit `integration_test/modell_haelt_an_test.dart`;
danach 37 ms).

| Plattform | Datei | Was |
|---|---|---|
| macOS | `macos/.../FlutterOnnxruntimePlugin.swift` | `handle` reiht in eine serielle `DispatchQueue`; die Antwort geht per `DispatchQueue.main.async` zurück. Die Hintergrund-Warteschlange, die `register` anfordert, bietet macOS nicht an (`makeBackgroundTaskQueue` fehlt). |
| Linux | `linux/src/flutter_onnxruntime_plugin.cc` | Ein `GThreadPool` mit einem Faden; die Antwort per `g_idle_add` im Hauptfaden von GTK. |
| Windows | `windows/flutter_onnxruntime_plugin.cpp` | Ein eigener Arbeitsfaden; die Antwort per Fensternachricht an das Hauptfenster, abgeholt über `RegisterTopLevelWindowProcDelegate` im Plattformfaden. |

Ein einziger Faden je Plattform hält die Reihenfolge der Aufrufe, wie Dart sie
stellt – erst Tensor anlegen, dann rechnen, dann auslesen.

## 2. Windows: keine Telemetrie

`windows/src/session_manager.cc` ruft nach dem Anlegen der Umgebung
`DisableTelemetryEvents()`. Die offiziellen Windows-Bauten von ONNX Runtime
melden sonst Ereignisse über TraceLogging an die Windows-Diagnose. Unter Linux
und macOS enthalten die Bauten keine solche Meldung.

## 3. Linux und Windows: Eingaben ohne Kopie

Vor jedem Aufruf eines Modells kopierte das Original jeden Eingabetensor in
einen frischen Puffer (`cloneTensor`). Bei einem Decoder, der Schritt für
Schritt den Zwischenspeicher der Kreuz-Aufmerksamkeit zurückbekommt, ist das
teuer: Whisper small reicht je Schritt 115 MB herein, die Bildbeschreibung
weniger, aber genauso bei jedem Wort. `TensorManager::viewTensor` legt
stattdessen ein `Ort::Value` über denselben Speicher. Das ist sicher, weil
alle Aufrufe nacheinander auf einem Faden laufen (siehe 1.) – während ein
Modell rechnet, kann kein Aufruf den Tensor freigeben. Zeichenketten und
leere Tensoren werden weiter kopiert. Unter macOS gab es die Kopie nie.

| Plattform | Datei |
|---|---|
| Linux | `linux/src/tensor_manager.{h,cc}`, `linux/src/flutter_onnxruntime_plugin.cc` |
| Windows | `windows/src/tensor_manager.{h,cc}`, `windows/flutter_onnxruntime_plugin.cpp` |

## Sonst

In den beiden podspecs ist die Kontaktadresse des Herstellers durch die Adresse
des Projekts ersetzt (in diesem Repository stehen keine E-Mail-Adressen).

## Der Wechsel von 1.8.5 auf 1.9.0 (Issue #60, 10.10.2026)

1.9.0 hebt ONNX Runtime unter Linux und Windows von 1.22.0 auf 1.28.3, unter
macOS von 1.23.0 auf 1.28.0. Eingespielt als Unterschied der beiden
veröffentlichten Pakete; die Änderungen oben ließen sich unverändert
übernehmen.

Nebenbei behebt 1.9.0 einen Fehler, der unter Linux jede Sitzung betraf: Die
Sitzungsoptionen kamen nie an. `createSession` nahm sie als `void *` entgegen
und wandelte sie in den falschen Typ zurück; ONNX Runtime öffnete jedes Modell
mit den Voreinstellungen. Gemessen mit `integration_test/onnx_wechsel_test.dart`
auf einem Rechner mit vier Kernen: Mit 1.8.5 legte jede Sitzung drei
Rechenfäden an, gleich ob zwei, vier oder gar keine verlangt waren. Die
Begrenzung aus `lib/services/modellthreads.dart`, die zwei Kerne für die
Oberfläche freihält, galt unter Linux also nie.

**Beim nächsten Wechsel** dasselbe Vorgehen: die Änderungen oben nachziehen,
dann `integration_test/onnx_wechsel_test.dart` auf allen drei Plattformen erst
mit der alten, dann mit der neuen Fassung laufen lassen (siehe Kopf der Datei),
dazu `integration_test/modell_haelt_an_test.dart`.
