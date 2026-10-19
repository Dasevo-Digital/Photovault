import 'dart:io';

/// Die Ordner mit eigenem Quelltext: die App und der Kern, den App und
/// Server gemeinsam benutzen (`packages/kern`).
///
/// Prüfungen, die den Quelltext lesen, gehen über beide. Seit Datenbank
/// und Dienste im Kern liegen, sähe ein Blick nur in `lib/` die Hälfte.
const quellordner = ['lib', 'packages/kern/lib', 'packages/gelaende/lib'];

/// Jede Dart-Datei in [quellordner].
List<File> dartQuellen() => [
  for (final ordner in quellordner)
    ...Directory(ordner)
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart')),
];
