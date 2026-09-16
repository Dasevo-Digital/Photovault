import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/l10n/app_localizations_de.dart';
import 'package:photo_vault/l10n/app_localizations_en.dart';
import 'package:photo_vault/services/native_image_converter.dart';

/// Der Objektivkorrektur-Schalter sagt jetzt je Datei, was er bewirkt.
///
/// Gemessen an der echten Bibliothek war die alte, allgemeine Auskunft für
/// die Mehrheit der RAW-Fotos irreführend: Von vier Kameras kannte Apples
/// Datenbank genau eine. Diese Tests halten fest, dass jeder Stand einen
/// eigenen Satz bekommt – ein Zustand ohne eigenen Text fiele sonst
/// stillschweigend auf den allgemeinen zurück.
void main() {
  /// Dieselbe Zuordnung wie in `develop_screen.dart`. Sie steht hier
  /// nachgebaut, weil der Bildschirm dafür einen ganzen Zustand samt
  /// nativer Anbindung bräuchte – geprüft wird die Vollständigkeit der
  /// Texte, nicht die Verdrahtung.
  String hinweis(AppTexte t, Objektivkorrekturstand stand) => switch (stand) {
        Objektivkorrekturstand.keinRaw => t.entwObjektivkorrekturKeinRaw,
        Objektivkorrekturstand.verfuegbar => t.entwObjektivkorrekturVerfuegbar,
        Objektivkorrekturstand.nichtInDatenbank =>
          t.entwObjektivkorrekturUnbekanntesObjektiv,
        Objektivkorrekturstand.nichtLesbar =>
          t.entwObjektivkorrekturNichtLesbar,
        Objektivkorrekturstand.unbekannt => t.entwObjektivkorrekturHinweis,
      };

  for (final sprache in [AppTexteDe(), AppTexteEn()]) {
    test('jeder Stand hat einen eigenen Satz (${sprache.localeName})', () {
      final saetze = <String>{};
      for (final stand in Objektivkorrekturstand.values) {
        final text = hinweis(sprache, stand);
        expect(text, isNotEmpty, reason: 'für $stand fehlt ein Text');
        expect(saetze.add(text), isTrue,
            reason: '$stand sagt dasselbe wie ein anderer Stand');
      }
    });
  }

  test('nur „verfügbar" und „unbekannt" lassen den Schalter bedienbar', () {
    // Dieselbe Bedingung wie im Bildschirm. Ein Schalter, der nachweislich
    // nichts bewirkt, soll ausgegraut sein – aber solange die Antwort noch
    // aussteht, bleibt er bedienbar.
    bool bedienbar(Objektivkorrekturstand stand) => switch (stand) {
          Objektivkorrekturstand.keinRaw ||
          Objektivkorrekturstand.nichtInDatenbank ||
          Objektivkorrekturstand.nichtLesbar =>
            false,
          _ => true,
        };

    expect(bedienbar(Objektivkorrekturstand.verfuegbar), isTrue);
    expect(bedienbar(Objektivkorrekturstand.unbekannt), isTrue);
    expect(bedienbar(Objektivkorrekturstand.keinRaw), isFalse);
    expect(bedienbar(Objektivkorrekturstand.nichtInDatenbank), isFalse);
    expect(bedienbar(Objektivkorrekturstand.nichtLesbar), isFalse);
  });

  test('ohne nativen Kanal bleibt es beim allgemeinen Hinweis', () async {
    // In der Testumgebung gibt es keinen MethodChannel – die Abfrage muss
    // dann „unbekannt" liefern und nicht etwa fälschlich „kein RAW".
    TestWidgetsFlutterBinding.ensureInitialized();
    final stand = await NativeImageConverter.lensCorrectionStatus(
        File('/gibt/es/nicht.dng'));
    expect(stand, Objektivkorrekturstand.unbekannt);
  });
}
