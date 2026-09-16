import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/widgets/zoomsteuerung.dart';

/// Die Regel: **Eine Karte, die man bedienen kann, muss man auch zoomen
/// können – auf jedem Gerät.**
///
/// Sie galt bisher nur für den Kartenbildschirm und die kleine Ortskarte.
/// Die Weltkarte der Reisen und die Familienorte hatten weder die
/// Zoomknöpfe noch den Wisch-Zoom: An einer Maus ohne Rad liess sich
/// dort überhaupt nicht zoomen, und mit Rad gab es keine Anzeige, dass
/// es ginge.
///
/// Der Prüfstand liest den Quelltext, weil das die Form des Fehlers ist:
/// nicht ein falsches Ergebnis, sondern eine vergessene Stelle.
void main() {
  Iterable<File> quelldateien() sync* {
    for (final ordner in ['lib/screens', 'lib/widgets']) {
      for (final e in Directory(ordner).listSync(recursive: true)) {
        if (e is File && e.path.endsWith('.dart')) yield e;
      }
    }
  }

  test('jede bedienbare Karte hat Zoomknöpfe und Wisch-Zoom', () {
    final ohne = <String>[];
    for (final datei in quelldateien()) {
      final quelle = datei.readAsStringSync();
      if (!quelle.contains('FlutterMap(')) continue;
      // Zwei Karten sind ausdrücklich unbedienbar: die Kartenvorschau
      // der Übersicht, die als Ganzes ein Knopf ist (`IgnorePointer`),
      // und alles, was `InteractiveFlag.none` setzt. Dort wäre ein
      // Zoomknopf eine Behauptung, man könne etwas tun.
      if (quelle.contains('InteractiveFlag.none') ||
          quelle.contains('IgnorePointer(')) {
        continue;
      }
      // Eine Karte MITTEN IN EINER ROLLBAREN SEITE ist der dritte Fall,
      // und er kam mit der Übersichtskarte der Reisen dazu. Dort ist der
      // Zweifingerwisch die Geste zum Rollen der Seite; nähme die Karte
      // sie an, verschluckte sie jeden zweiten Wisch – genau der Schaden,
      // um dessentwillen sie vorher gar nicht bedienbar war.
      //
      // Der Zweck der Regel bleibt gewahrt, denn er ist nicht „Wischen",
      // sondern „auf JEDEM Gerät zoomen": Die Knöpfe leisten das. Die
      // Ausnahme muss deshalb im Quelltext ausgesprochen werden – sie
      // gilt nur, wo jemand sie hingeschrieben hat, und die Knöpfe
      // werden trotzdem verlangt.
      final nurKnoepfe = quelle.contains('zoomregel: nur Knoepfe');
      final fehlt = [
        if (!nurKnoepfe && !quelle.contains('WischZoom(')) 'WischZoom',
        // Entweder die gemeinsame Leiste oder eigene Knöpfe – die kleine
        // Ortskarte hat aus Platzgründen ihre eigenen.
        if (!quelle.contains('Zoomsteuerung(') &&
            !quelle.contains('karteHineinzoomen'))
          'Zoomknöpfe',
      ];
      if (fehlt.isNotEmpty) ohne.add('${datei.path}: ${fehlt.join(', ')}');
    }
    expect(
      ohne,
      isEmpty,
      reason: 'Diese Karten lassen sich verschieben, aber nicht auf jedem '
          'Gerät zoomen. Eine Magic Mouse hat kein Rad, und eine einfache '
          'Maus hat gar keine Zoomgeste:\n${ohne.join('\n')}',
    );
  });

  test('die Karten, um die es ging, sind wirklich noch Karten', () {
    // Gegenprobe: Die Regel oben liesse sich auch dadurch erfüllen, dass
    // jemand die Karte entfernt.
    for (final pfad in [
      'lib/screens/weltkarte_screen.dart',
      'lib/screens/familienorte_screen.dart',
    ]) {
      final quelle = File(pfad).readAsStringSync();
      expect(quelle, contains('FlutterMap('), reason: '$pfad zeigt eine Karte');
      expect(quelle, contains('Zoomsteuerung('));
    }
  });

  group('Zoomsteuerung', () {
    Widget rahmen(Widget kind) => MaterialApp(
          locale: const Locale('de'),
          localizationsDelegates: AppTexte.localizationsDelegates,
          supportedLocales: AppTexte.supportedLocales,
          home: Scaffold(body: kind),
        );

    testWidgets('beide Zoomknöpfe melden ihren Druck', (tester) async {
      var naeher = 0, weiter = 0;
      await tester.pumpWidget(rahmen(Zoomsteuerung(
        beiNaeher: () => naeher++,
        beiWeiter: () => weiter++,
      )));
      await tester.tap(find.byIcon(Icons.add));
      await tester.tap(find.byIcon(Icons.remove));
      expect(naeher, 1);
      expect(weiter, 1);
    });

    testWidgets('ohne Standort und ohne Ereignisse bleiben zwei Knöpfe',
        (tester) async {
      // Ein Knopf, der nichts tun kann, wäre schlechter als keiner.
      await tester.pumpWidget(rahmen(const Zoomsteuerung()));
      expect(find.byIcon(Icons.my_location), findsNothing);
      expect(find.byIcon(Icons.event_available_outlined), findsNothing);
      expect(find.byIcon(Icons.add), findsOneWidget);
      expect(find.byIcon(Icons.remove), findsOneWidget);
    });
  });

  test('die Ausnahme „nur Knoepfe" gilt nur, wo sie begruendet ist', () {
    // Sonst waere sie ein Freibrief: Ein hingeschriebener Kommentar
    // schaltet eine Regel ab. Wer sie zieht, muss (a) die Zoomknoepfe
    // trotzdem haben und (b) die Karte wirklich in eine rollbare Seite
    // stellen - erkennbar daran, dass sie nur das Ziehen annimmt.
    for (final datei in quelldateien()) {
      final quelle = datei.readAsStringSync();
      if (!quelle.contains('zoomregel: nur Knoepfe')) continue;
      expect(quelle.contains('Zoomsteuerung('), isTrue,
          reason: '${datei.path}: ohne Wischen sind die Knoepfe der '
              'einzige Weg zu zoomen - sie muessen da sein');
      expect(quelle.contains('InteractiveFlag.drag'), isTrue,
          reason: '${datei.path}: die Ausnahme ist fuer Karten, die nur '
              'das Ziehen annehmen; wer Rad und Kneifen nimmt, hat das '
              'Rollproblem nicht und braucht die Ausnahme nicht');
    }
  });
}
