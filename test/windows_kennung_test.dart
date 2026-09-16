import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Unter Windows bestimmen **CompanyName und ProductName aus der
/// Versionsressource**, wo die Daten liegen. `path_provider_windows` liest
/// beide mit `GetFileVersionInfo` aus der eigenen .exe und setzt daraus
/// `%APPDATA%\<CompanyName>\<ProductName>\` zusammen (nachgelesen in
/// `path_provider_windows_real.dart`, gemessen in Phase 0: die Bibliothek
/// liegt unter `%APPDATA%\com.example\photo_vault\PhotoVault\`).
///
/// Werden sie geändert, sucht eine bereits benutzte Installation an einer
/// neuen Stelle – und begrüsst den Nutzer mit dem Startbildschirm, als
/// wäre sie frisch. Die alte Bibliothek liegt unerreichbar daneben.
///
/// Genau das ist unter Linux schon einmal passiert, beim Versuch, die
/// Fensterklasse an die Flatpak-Kennung anzugleichen (siehe
/// `linux_kennung_test.dart`). Der sichtbare Name gehört deshalb in den
/// Fenstertitel und in `FileDescription`, nicht hierher.
void main() {
  late String rc;

  setUp(() => rc = File('windows/runner/Runner.rc').readAsStringSync());

  test('CompanyName ist unverändert – er bestimmt den Ablageort', () {
    expect(
      rc,
      contains(r'VALUE "CompanyName", "com.example" "\0"'),
      reason: 'Eine Änderung verschiebt %APPDATA%\\<CompanyName>\\… und '
          'damit die Bibliothek bestehender Installationen. Nur zusammen '
          'mit einer Umzugslogik ändern.',
    );
  });

  test('ProductName ist unverändert – er bestimmt den Ablageort', () {
    expect(
      rc,
      contains(r'VALUE "ProductName", "photo_vault" "\0"'),
      reason: 'Trotz des technisch aussehenden Namens: Er ist Teil des '
          'Pfades. Der sichtbare Name steht in FileDescription.',
    );
  });

  test('der sichtbare Name steht im Fenstertitel', () {
    // Das Fenster hiess "photo_vault" – dasselbe Versäumnis wie unter
    // Linux, wo es bis 1.8.3 so stand.
    final main = File('windows/runner/main.cpp').readAsStringSync();
    expect(main, contains('window.Create(L"Photo Vault"'),
        reason: 'sonst steht in der Taskleiste wieder der technische Name');
  });

  test('der sichtbare Name steht auch in der Dateibeschreibung', () {
    // Was Explorer in der Spalte „Beschreibung" und der Task-Manager in
    // der Prozessliste anzeigen.
    expect(rc, contains(r'VALUE "FileDescription", "Photo Vault" "\0"'));
  });

  test('das Programmsymbol ist nicht mehr das von Flutter mitgelieferte',
      () async {
    // Das Standardsymbol ist Flutters blaues Logo. Es fällt beim ersten
    // Start nicht auf – wohl aber in der Taskleiste, im Startmenü und in
    // jedem Bildschirmfoto.
    final ico = File('windows/runner/resources/app_icon.ico');
    expect(ico.existsSync(), isTrue);

    // Nicht über die Dateigrösse geprüft, sondern über den Inhalt: Das
    // Symbol stammt aus derselben Vorlage wie das von macOS, also muss
    // die 256er-Stufe Byte für Byte der dortigen entsprechen.
    final bytes = await ico.readAsBytes();
    final gross = await File(
            'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_256.png')
        .readAsBytes();
    expect(bytes.length, greaterThan(gross.length),
        reason: 'die .ico muss mindestens die 256er-Stufe enthalten');

    // Nach dem ersten Vorkommen der PNG-Signatur suchen und von dort an
    // vergleichen wäre zu lasch – hier wird die Stufe gesucht, die genau
    // so lang ist wie die macOS-Vorlage.
    final gefunden = _enthaelt(bytes, gross);
    expect(gefunden, isTrue,
        reason: 'die .ico enthält nicht dieselbe Bildvorlage wie macOS – '
            'entweder ist sie noch das Flutter-Symbol oder aus einer '
            'anderen Quelle erzeugt worden');
  });
}

/// Ob [heuhaufen] die Bytefolge [nadel] enthält.
bool _enthaelt(List<int> heuhaufen, List<int> nadel) {
  if (nadel.isEmpty || nadel.length > heuhaufen.length) return false;
  for (var i = 0; i <= heuhaufen.length - nadel.length; i++) {
    var passt = true;
    for (var j = 0; j < nadel.length; j++) {
      if (heuhaufen[i + j] != nadel[j]) {
        passt = false;
        break;
      }
    }
    if (passt) return true;
  }
  return false;
}
