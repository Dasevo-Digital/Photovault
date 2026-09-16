import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as pfad;
import 'package:photo_vault/db/database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:photo_vault/services/cube_lut.dart';
import 'package:photo_vault/services/develop_color.dart';

/// Das Einlesen von `.cube`-Dateien und das Hineinrechnen in den
/// vorhandenen Farbwürfel.
///
/// Eine falsch eingelesene Farbtabelle sieht nicht nach Dateifehler aus,
/// sondern nach kaputtem Foto – niemand käme auf die Datei als Ursache.
/// Deshalb wird hier eher abgelehnt als geraten.
void main() {
  /// Eine Identitätstabelle der Kantenlänge [n]: Jede Farbe bildet auf sich
  /// selbst ab. Damit lässt sich prüfen, dass die Reihenfolge der Zeilen
  /// richtig verstanden wird – bei vertauschten Achsen käme ein Farbstich
  /// heraus, den ein Vergleich gegen „irgendein Ergebnis" nicht fände.
  String identitaet(int n, {String? kopf}) {
    final zeilen = <String>[kopf ?? '', 'LUT_3D_SIZE $n'];
    for (var b = 0; b < n; b++) {
      for (var g = 0; g < n; g++) {
        for (var r = 0; r < n; r++) {
          zeilen.add('${r / (n - 1)} ${g / (n - 1)} ${b / (n - 1)}');
        }
      }
    }
    return zeilen.join('\n');
  }

  group('Einlesen', () {
    test('eine Identitätstabelle kommt als Identität an', () {
      final lut = parseCubeLut(identitaet(4));
      expect(lut.size, 4);
      for (final punkt in [
        [0.0, 0.0, 0.0],
        [1.0, 1.0, 1.0],
        [1.0, 0.0, 0.0],
        [0.0, 0.0, 1.0],
        [0.25, 0.5, 0.75],
      ]) {
        final aus = lut.abtasten(punkt[0], punkt[1], punkt[2]);
        for (var k = 0; k < 3; k++) {
          expect(aus[k], closeTo(punkt[k], 1e-5),
              reason: 'bei $punkt, Kanal $k – Achsen vertauscht?');
        }
      }
    });

    test('Rot läuft am schnellsten, nicht Blau', () {
      // Der Klassiker beim Einlesen. Eine Tabelle, die NUR Rot durchreicht
      // und Grün/Blau auf 0 setzt, entlarvt eine vertauschte Reihenfolge
      // sofort.
      final zeilen = <String>['LUT_3D_SIZE 2'];
      for (var b = 0; b < 2; b++) {
        for (var g = 0; g < 2; g++) {
          for (var r = 0; r < 2; r++) {
            zeilen.add('${r.toDouble()} 0.0 0.0');
          }
        }
      }
      final lut = parseCubeLut(zeilen.join('\n'));
      expect(lut.abtasten(1, 0, 0)[0], closeTo(1, 1e-6));
      expect(lut.abtasten(0, 0, 1)[0], closeTo(0, 1e-6),
          reason: 'Blau darf den Rotkanal nicht steuern');
    });

    test('Titel, Kommentare und Leerzeilen stören nicht', () {
      final lut = parseCubeLut('''
# Ein Kommentar
TITLE "Mein Look"

${identitaet(2)}
# noch einer
''');
      expect(lut.titel, 'Mein Look');
      expect(lut.size, 2);
    });

    test('ein Kommentar hinter Daten wird abgeschnitten', () {
      final zeilen = identitaet(2).split('\n');
      zeilen[zeilen.length - 1] = '${zeilen.last} # letzter Wert';
      expect(() => parseCubeLut(zeilen.join('\n')), returnsNormally);
    });

    test('ohne LUT_3D_SIZE wird abgelehnt', () {
      expect(
        () => parseCubeLut('0.0 0.0 0.0\n1.0 1.0 1.0'),
        throwsA(isA<CubeAusnahme>()
            .having((e) => e.grund, 'Grund', CubeFehler.keineGroesse)),
      );
    });

    test('eine eindimensionale Tabelle wird als solche abgelehnt', () {
      // Sie beschreibt eine Kurve, keinen Farbraum – dafür gibt es die
      // Tonwertkurve. Sie stillschweigend zu ignorieren hiesse, eine Datei
      // ohne Wirkung zu laden.
      expect(
        () => parseCubeLut('LUT_1D_SIZE 16\n0 0 0'),
        throwsA(isA<CubeAusnahme>()
            .having((e) => e.grund, 'Grund', CubeFehler.nurEindimensional)),
      );
    });

    test('zu wenige Zeilen werden abgelehnt statt aufgefüllt', () {
      final zeilen = identitaet(4).split('\n')..removeLast();
      expect(
        () => parseCubeLut(zeilen.join('\n')),
        throwsA(isA<CubeAusnahme>()
            .having((e) => e.grund, 'Grund', CubeFehler.falscheZeilenzahl)),
      );
    });

    test('eine unsinnige Kantenlänge wird abgelehnt', () {
      for (final n in ['0', '1', '9999', 'viele']) {
        expect(() => parseCubeLut('LUT_3D_SIZE $n\n0 0 0'),
            throwsA(isA<CubeAusnahme>()), reason: n);
      }
    });

    test('eine unlesbare Zeile nennt ihre Nummer', () {
      final zeilen = identitaet(2).split('\n');
      zeilen.insert(3, 'hier stimmt etwas nicht');
      try {
        parseCubeLut(zeilen.join('\n'));
        fail('hätte werfen müssen');
      } on CubeAusnahme catch (e) {
        expect(e.grund, CubeFehler.unlesbareZeile);
        expect(e.zeile, 4, reason: 'einsbasiert, wie in einem Editor');
      }
    });

    test('DOMAIN gilt für die Eingabe, nicht für die Werte', () {
      // Der Punkt, an dem ich es zuerst falsch hatte: DOMAIN_MIN/MAX
      // beschreiben, welchen Wertebereich die Tabelle erwartet. Die Zeilen
      // selbst sind Ausgabefarben und bleiben unangetastet.
      final lut = parseCubeLut('''
LUT_3D_SIZE 2
DOMAIN_MIN 0.0 0.0 0.0
DOMAIN_MAX 2.0 2.0 2.0
${identitaet(2).split('\n').skip(2).join('\n')}
''');
      // Der Tabelleneintrag für „ganz oben" ist unverändert 1.
      expect(lut.werte.last, closeTo(1, 1e-6));
      // Eine Eingabe von 1.0 liegt bei einem Bereich bis 2.0 in der Mitte.
      expect(lut.abtasten(1, 1, 1)[0], closeTo(0.5, 1e-5));
    });
  });

  group('Hineinrechnen in den Würfel', () {
    test('eine Identitätstabelle ändert den Würfel nicht', () {
      final ohne = buildColorCube(ColorMixer.neutral, size: 8);
      final mit = buildColorCube(ColorMixer.neutral,
          size: 8, lut: parseCubeLut(identitaet(8)));
      for (var i = 0; i < ohne.length; i++) {
        expect(mit[i], closeTo(ohne[i], 1e-4), reason: 'Eintrag $i');
      }
    });

    test('Stärke 0 lässt den Würfel unberührt', () {
      // Sonst wäre ein Look, den man auf null gestellt hat, immer noch
      // schwach zu sehen.
      final grau = parseCubeLut(_konstanteTabelle(2, 0.5));
      final ohne = buildColorCube(ColorMixer.neutral, size: 8);
      final mit = buildColorCube(ColorMixer.neutral,
          size: 8, lut: grau, lutStaerke: 0);
      expect(mit, orderedEquals(ohne));
    });

    test('Stärke 1 setzt die Tabelle voll durch', () {
      final grau = parseCubeLut(_konstanteTabelle(2, 0.5));
      final mit = buildColorCube(ColorMixer.neutral, size: 4, lut: grau);
      for (var i = 0; i < mit.length; i += 4) {
        expect(mit[i], closeTo(0.5, 1e-4));
      }
    });

    test('halbe Stärke liegt in der Mitte', () {
      final grau = parseCubeLut(_konstanteTabelle(2, 0.0));
      final mit = buildColorCube(ColorMixer.neutral,
          size: 4, lut: grau, lutStaerke: 0.5);
      // Eingang Weiss (letzte Stützstelle), Ziel Schwarz – erwartet 0,5.
      final letzterRot = mit.length - 4;
      expect(mit[letzterRot], closeTo(0.5, 1e-4));
    });

    test('der Alphawert bleibt 1', () {
      // Core Image setzt vorvervielfachte Daten voraus.
      final mit = buildColorCube(ColorMixer.neutral,
          size: 4, lut: parseCubeLut(_konstanteTabelle(2, 0.3)));
      for (var i = 3; i < mit.length; i += 4) {
        expect(mit[i], 1);
      }
    });

    test('die Grösse des Würfels ist unabhängig von der der Tabelle', () {
      // Eine 17er-Datei muss in einen 32er-Würfel passen – dafür ist die
      // trilineare Abtastung da.
      final lut = parseCubeLut(identitaet(3));
      final wuerfel = buildColorCube(ColorMixer.neutral, size: 16, lut: lut);
      expect(wuerfel.length, 16 * 16 * 16 * 4);
      expect(Float32List.fromList(wuerfel.sublist(0, 4)),
          orderedEquals([0.0, 0.0, 0.0, 1.0]));
    });
  });

  group('Migration und Speicherung', () {
    test('eine Datenbank von Schema 38 bekommt die Spalten nachgereicht',
        () async {
      final ordner = Directory.systemTemp.createTempSync('pv_lut_mig');
      addTearDown(() => ordner.deleteSync(recursive: true));
      final datei = File(pfad.join(ordner.path, 'alt.sqlite'));

      var alt = AppDatabase(NativeDatabase(datei));
      await alt.into(alt.assets).insert(AssetsCompanion.insert(
            id: 'a1',
            originalFileName: 'a1.jpg',
            relativePath: 'originals/a1.jpg',
            checksum: 'a1',
            type: 'IMAGE',
            fileCreatedAt: DateTime(2026, 1, 1),
            importedAt: DateTime(2026, 1, 1),
          ));
      await alt.close();

      final roh = sqlite.sqlite3.open(datei.path);
      for (final tabelle in ['develop_settings', 'develop_history']) {
        for (final spalte in ['clarity', 'vignette', 'lut_path', 'lut_strength']) {
          roh.execute('ALTER TABLE $tabelle DROP COLUMN $spalte;');
        }
      }
      roh.execute('PRAGMA user_version = 38;');
      roh.close();

      // Öffnen löst die Migration auf 39 aus.
      final neu = AppDatabase(NativeDatabase(datei));
      await neu.saveDevelopResult(
        'a1',
        settings: DevelopSettingsCompanion.insert(
          assetId: 'a1',
          clarity: const Value(0.4),
          vignette: const Value(-0.3),
          lutPath: const Value('luts/kodak.cube'),
          lutStrength: const Value(0.8),
          updatedAt: DateTime(2026, 2, 1),
        ),
        developedRelativePath: 'developed/a1.jpg',
      );
      final gespeichert = await neu.developSettingsForAsset('a1');
      await neu.close();

      expect(gespeichert!.clarity, closeTo(0.4, 1e-9));
      expect(gespeichert.vignette, closeTo(-0.3, 1e-9));
      expect(gespeichert.lutPath, 'luts/kodak.cube');
      expect(gespeichert.lutStrength, closeTo(0.8, 1e-9));
    });

    test('vorhandene Zeilen bekommen unauffällige Vorgabewerte', () async {
      // Wer eine gespeicherte Entwicklung hat, darf nach dem Update kein
      // anderes Bild sehen: Klarheit und Vignettierung müssen bei 0 landen
      // und die Stärke bei 1 (wirkungslos, solange kein Pfad gesetzt ist).
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.into(db.assets).insert(AssetsCompanion.insert(
            id: 'a1',
            originalFileName: 'a1.jpg',
            relativePath: 'originals/a1.jpg',
            checksum: 'a1',
            type: 'IMAGE',
            fileCreatedAt: DateTime(2026, 1, 1),
            importedAt: DateTime(2026, 1, 1),
          ));
      await db.saveDevelopResult(
        'a1',
        settings: DevelopSettingsCompanion.insert(
            assetId: 'a1', updatedAt: DateTime(2026, 1, 1)),
        developedRelativePath: 'developed/a1.jpg',
      );
      final s = await db.developSettingsForAsset('a1');
      expect(s!.clarity, 0);
      expect(s.vignette, 0);
      expect(s.lutPath, isNull);
      expect(s.lutStrength, 1);
    });
  });
}

/// Eine Tabelle, die jede Farbe auf denselben Grauwert abbildet.
String _konstanteTabelle(int n, double wert) {
  final zeilen = <String>['LUT_3D_SIZE $n'];
  for (var i = 0; i < n * n * n; i++) {
    zeilen.add('$wert $wert $wert');
  }
  return zeilen.join('\n');
}
