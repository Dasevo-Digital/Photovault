import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/native_image_converter.dart';
import 'package:photo_vault/services/platform/desktop_image_tools.dart';

/// Der Werkzeuge-Bildschirm fragte für seine Statuszeile
/// `NativeImageConverter.isSupported()` ab – das ist ausserhalb von macOS
/// grundsätzlich `false`. Unter Linux stand dort deshalb „inaktiv", obwohl
/// HEIC, RAW und Video nachweislich arbeiteten. Unter Windows gilt seit
/// der gemeinsamen Werkzeugschicht dasselbe.
void main() {
  tearDown(DesktopImageTools.vergissWerkzeuge);

  /// Ob hier der Werkzeug-Weg gilt. Bewusst als Verneinung von macOS und
  /// nicht als Aufzählung – genau wie in der geprüften Klasse. Stünde hier
  /// eine Aufzählung, prüfte dieser Test unter Windows den falschen Zweig
  /// und wäre trotzdem grün.
  final ueberWerkzeuge = !Platform.isMacOS;

  test('meldet ausserhalb von macOS nicht pauschal „nicht unterstützt"',
      () async {
    final stand = await NativeImageConverter.bildwerkzeugstand();

    if (ueberWerkzeuge) {
      // Die Auskunft muss aus den Werkzeugen kommen, nicht aus dem nativen
      // Kanal: „bereit" genau dann, wenn nichts fehlt.
      expect(stand.bereit, stand.fehlende.isEmpty,
          reason: 'bereit und fehlende dürfen sich nicht widersprechen');
    } else {
      // Auf macOS entscheidet der native Kanal, und die Liste der
      // fehlenden Werkzeuge ist gegenstandslos.
      expect(stand.fehlende, isEmpty);
    }
  });

  test('nennt jedes fehlende Werkzeug beim Namen', () async {
    final stand = await NativeImageConverter.bildwerkzeugstand();

    // Was gemeldet wird, muss auch ein bekanntes Werkzeug sein – sonst
    // stünde im Bildschirm ein Name, mit dem niemand etwas anfangen kann.
    for (final name in stand.fehlende) {
      expect(DesktopImageTools.werkzeuge.keys, contains(name));
    }
  }, skip: ueberWerkzeuge ? null : 'auf macOS gibt es keine Werkzeugliste');

  test('bereit und fehlende widersprechen sich nie', () async {
    final stand = await NativeImageConverter.bildwerkzeugstand();
    if (stand.fehlende.isNotEmpty) {
      expect(stand.bereit, isFalse);
    }
  });
}
