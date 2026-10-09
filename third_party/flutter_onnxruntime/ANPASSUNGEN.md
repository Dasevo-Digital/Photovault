# Anpassungen gegenüber flutter_onnxruntime 1.8.5

Diese Kopie stammt aus dem Paket `flutter_onnxruntime` 1.8.5 (MIT, © MASIC AI,
<https://github.com/masicai/flutter_onnxruntime>). Weggelassen sind nur
`example/`, `doc/`, `CONTRIBUTING.md` und das Logo. Geändert ist genau eine
Sache, auf allen drei Desktop-Plattformen gleich:

**Die Aufrufe laufen nicht mehr im Hauptfaden.** Das Original rechnet jedes
Modell synchron im Kanal-Handler, also auf dem Hauptfaden der Plattform. Unter
macOS teilen sich Plattform und Oberfläche diesen Faden; eine Kachel der
KI-Restaurierung hielt die App so 5,9 Sekunden lang an (Issue #14, gemessen mit
`integration_test/modell_haelt_an_test.dart`; danach 37 ms).

| Plattform | Datei | Was |
|---|---|---|
| macOS | `macos/.../FlutterOnnxruntimePlugin.swift` | `handle` reiht in eine serielle `DispatchQueue`; die Antwort geht per `DispatchQueue.main.async` zurück. Die Hintergrund-Warteschlange, die `register` anfordert, bietet macOS nicht an (`makeBackgroundTaskQueue` fehlt). |
| Linux | `linux/src/flutter_onnxruntime_plugin.cc` | Ein `GThreadPool` mit einem Faden; die Antwort per `g_idle_add` im Hauptfaden von GTK. |
| Windows | `windows/flutter_onnxruntime_plugin.cpp` | Ein eigener Arbeitsfaden; die Antwort per Fensternachricht an das Hauptfenster, abgeholt über `RegisterTopLevelWindowProcDelegate` im Plattformfaden. |

Ein einziger Faden je Plattform hält die Reihenfolge der Aufrufe, wie Dart sie
stellt – erst Tensor anlegen, dann rechnen, dann auslesen.

In den beiden podspecs ist die Kontaktadresse des Herstellers durch die Adresse
des Projekts ersetzt (in diesem Repository stehen keine E-Mail-Adressen).

**Beim Wechsel auf eine neuere Fassung** (Issue #60) die drei Änderungen
nachziehen und die Probe `integration_test/modell_haelt_an_test.dart` auf allen
drei Plattformen laufen lassen. Die Fassung 1.9.0 rechnet weiterhin im
Hauptfaden.
