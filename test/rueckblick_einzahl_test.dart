import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/l10n/app_localizations_de.dart';
import 'package:photo_vault/l10n/app_localizations_en.dart';

/// **„Im November vor 1 Jahren“.** Die Überschrift des Monatsrückblicks
/// hatte keine Einzahl – anders als die des Tagesrückblicks daneben.
void main() {
  test('ein Jahr in der Einzahl, mehrere in der Mehrzahl', () {
    final de = AppTexteDe();
    expect(
      de.erkundenImMonatVorJahren('November', 1),
      'Im November vor 1 Jahr',
    );
    expect(
      de.erkundenImMonatVorJahren('November', 2),
      'Im November vor 2 Jahren',
    );
    final en = AppTexteEn();
    expect(
      en.erkundenImMonatVorJahren('November', 1),
      'In November, 1 year ago',
    );
    expect(
      en.erkundenImMonatVorJahren('November', 3),
      'In November, 3 years ago',
    );
  });
}
