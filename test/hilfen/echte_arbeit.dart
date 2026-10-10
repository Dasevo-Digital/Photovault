import 'package:flutter_test/flutter_test.dart';

/// Wartet in einem `testWidgets`, bis [fertig] zutrifft, während der
/// Produktionscode echte Arbeit tut: Datei-Ein-/Ausgabe oder ein Isolat
/// über `compute`.
///
/// **Warum es dafür eine eigene Hilfe gibt (#50).** Ein `testWidgets` läuft
/// an einer gestellten Uhr. Die Antwort auf einen echten Plattenzugriff
/// kommt zwar in der echten Ereignisschleife an, ihre Fortsetzung landet
/// aber in der Warteschlange der gestellten Uhr – und die wird nur geleert,
/// wenn der Test ein Bild pumpt oder ein `runAsync` endet. Zwei Fehler
/// standen deshalb in den Tests:
///
/// * **Nur warten, nie pumpen.** Ein `runAsync` mit einer Warteschleife
///   darin lässt die Platte arbeiten, die Fortsetzung aber nicht. Im Test
///   „Erkennung löschen“ lief die Schleife jedes Mal alle 100 Runden ins
///   Leere; gelöscht wurde erst danach, und der Test bestand nur, wenn die
///   Platte das Wettrennen gegen die nächste Zeile gewann.
/// * **Eine feste Zahl Runden.** Die Staubsuche braucht allein schon 55
///   von 120 Runden; im vollen Lauf, mit vielen Testprozessen nebeneinander,
///   reichte die Grenze nicht mehr.
///
/// Deshalb abwechselnd: ein Stück echte Zeit, dann ein Bild, und als
/// Grenze eine Zeitspanne statt einer Rundenzahl. Wer schnell fertig ist,
/// wartet nicht länger; die grosszügige Grenze kostet nur den, der ohnehin
/// fehlschlagen würde.
///
/// Gibt zurück, ob [fertig] innerhalb von [hoechstens] eingetreten ist.
Future<bool> warteAufEchteArbeit(
  WidgetTester tester,
  bool Function() fertig, {
  Duration schritt = const Duration(milliseconds: 10),
  Duration hoechstens = const Duration(seconds: 60),
}) async {
  final uhr = Stopwatch()..start();
  while (!fertig()) {
    if (uhr.elapsed > hoechstens) return false;
    await tester.runAsync(() => Future<void>.delayed(schritt));
    await tester.pump();
  }
  return true;
}
