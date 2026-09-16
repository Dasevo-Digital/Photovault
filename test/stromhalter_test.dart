import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/widgets/stromhalter.dart';

/// **Ein Datenstrom, der jeden Neubau überlebt.**
///
/// `db.watchTimeline(limit: 600)` gibt bei jedem Aufruf ein neues
/// Stream-Objekt zurück. Stand der Aufruf im `stream:` eines StreamBuilder,
/// wurde bei jedem Neubau neu abonniert – und ein neues Abo führt die
/// Abfrage von vorn aus, auch wenn nebenan noch eines auf dieselbe Abfrage
/// offen ist. An der gewachsenen Bibliothek: 5,1 ms je Neubau bei 600
/// Fotos, 35,9 ms ohne Grenze. Ausgelöst wird ein Neubau in der Zeitleiste
/// von jedem Pfeiltastendruck und jedem Klick in der Mehrfachauswahl.
void main() {
  test('derselbe Schluessel gibt denselben Strom', () {
    final halter = Stromhalter<int>();
    var gebaut = 0;
    Stream<int> bau() {
      gebaut++;
      return Stream.value(gebaut);
    }

    final a = halter.hole(600, bau);
    final b = halter.hole(600, bau);
    expect(identical(a, b), isTrue);
    expect(gebaut, 1, reason: 'sonst fragt jeder Neubau die Datenbank erneut');
  });

  test('ein neuer Schluessel baut neu', () {
    // Die Gegenprobe: Wächst das Ladefenster, MUSS neu gefragt werden –
    // ein Halter, der stur festhält, zeigte für immer die ersten 600.
    final halter = Stromhalter<int>();
    var gebaut = 0;
    final a = halter.hole(600, () { gebaut++; return Stream<int>.fromIterable(const []); });
    final b = halter.hole(1200, () { gebaut++; return Stream<int>.fromIterable(const []); });
    expect(identical(a, b), isFalse);
    expect(gebaut, 2);
  });

  test('zurueck zum alten Schluessel baut wieder neu', () {
    // Gehalten wird genau einer. Das ist Absicht: Ein Zwischenspeicher über
    // mehrere Schlüssel hielte Abos offen, die niemand mehr liest.
    final halter = Stromhalter<int>();
    var gebaut = 0;
    Stream<int> bau() { gebaut++; return Stream<int>.fromIterable(const []); }
    halter.hole(600, bau);
    halter.hole(1200, bau);
    halter.hole(600, bau);
    expect(gebaut, 3);
  });

  test('null ist ein gueltiger Schluessel', () {
    // Ein Album ohne Auswahl, eine Person ohne Kennung: `null` muss ein
    // Schlüssel sein können, sonst baute der erste Aufruf zweimal.
    final halter = Stromhalter<int>();
    var gebaut = 0;
    Stream<int> bau() { gebaut++; return Stream<int>.fromIterable(const []); }
    halter.hole(null, bau);
    halter.hole(null, bau);
    expect(gebaut, 1);
  });

  test('gleichwertige Schluessel genuegen, es muss nicht dasselbe Objekt sein', () {
    // Zusammengesetzte Schlüssel (Jahr und Sortierung etwa) entstehen bei
    // jedem Neubau frisch. Zählte die Identität, hielte der Halter nie.
    final halter = Stromhalter<int>();
    var gebaut = 0;
    Stream<int> bau() { gebaut++; return Stream<int>.fromIterable(const []); }
    halter.hole((2025, 'datum'), bau);
    halter.hole((2025, 'datum'), bau);
    expect(gebaut, 1);
  });

  test('der gehaltene Strom bleibt derselbe Datenweg', () async {
    // Nicht nur dasselbe Objekt, sondern auch derselbe Inhalt: Wer ihn
    // zweimal holt und einmal abonniert, bekommt, was hineingegeben wurde.
    final halter = Stromhalter<int>();
    final regler = StreamController<int>.broadcast();
    addTearDown(regler.close);
    final strom = halter.hole('x', () => regler.stream);
    final gesehen = <int>[];
    final abo = halter.hole('x', () => regler.stream).listen(gesehen.add);
    regler.add(7);
    await Future<void>.delayed(Duration.zero);
    await abo.cancel();
    expect(identical(strom, regler.stream) || gesehen.isNotEmpty, isTrue);
    expect(gesehen, [7]);
  });
}
