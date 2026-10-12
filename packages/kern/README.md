# Kern

Datenbank und Dienste von Photo Vault, die ohne Flutter auskommen. Die App
benutzt sie über `package:kern/…`; der geplante Server (Issue #86) soll
denselben Code benutzen, damit Ergebnisse gleich sind, egal wo sie
entstehen.

## Die Regel

Der Kern kennt Flutter nicht: kein `package:flutter`, kein `dart:ui`, keine
Flutter-Plugins. Das ist nicht nur Absicht, sondern gebaut: Die
`pubspec.yaml` hat keine Abhängigkeit auf Flutter, ein solcher Import ist in
der Analyse ein Fehler.

Was die Plattform braucht (Verzeichnisse, Dateiauswahl, native Bildwandlung,
die ONNX Runtime der App), kommt von aussen herein und wird nicht hier
importiert. Ein Wert, den die Oberfläche anzeigt, gehört nur dann hierher,
wenn er ohne Flutter-Typen auskommt; die Darstellung dazu (Farben,
Beschriftungen) bleibt in der App, siehe `services/tageszeit.dart` neben
`lib/services/lichtstimmung.dart`.

## Arbeiten im Kern

```sh
cd packages/kern
dart pub get
dart analyze
```

Der Datenbank-Code (`lib/db/database.g.dart`) liegt erzeugt im Repository.
Nach einer Änderung am Schema:

```sh
cd packages/kern
dart run build_runner build --delete-conflicting-outputs
```

Die Schemastände liegen unter `drift_schemas/`; die Tests dazu stehen im
Wurzelordner unter `test/` (z. B. `test/schemastand_abgelegt_test.dart`).
