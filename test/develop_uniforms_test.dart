import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/develop_color.dart';
import 'package:photo_vault/services/native_image_converter.dart';
import 'package:photo_vault/widgets/develop_preview.dart';

/// Prüft die Übersetzung der Regler in Shader-Uniforms. Reine Rechenlogik,
/// deshalb ohne GPU testbar – die tatsächliche Darstellung wird separat per
/// Pixelmessung geprüft.
///
/// Die Reihenfolge ist der eigentliche Prüfgegenstand: Sie muss zur
/// Deklarationsreihenfolge in `shaders/develop_adjustments.frag` passen.
/// Ein eingeschobener Uniform verschiebt alle folgenden, und das Bild wird
/// falsch, ohne dass irgendwo ein Fehler auftritt.
///
///   0 Belichtung · 1 Temperatur · 2 Tint · 3 Kontrast · 4 Schatten
///   5 Lichter · 6 Weissabgleich an · 7 Kurve an · 8 Mischer an
///   9 Würfelkante · 10 Beschneidungswarnung
void main() {
  test('neutrale Einstellungen ergeben neutrale Uniforms', () {
    final u = developUniforms(DevelopAdjustments.neutral);

    expect(u, hasLength(11));
    expect(u[0], 0.0, reason: 'Belichtung');
    expect(u[3], 0.0, reason: 'Kontrast');
    expect(u[4], 0.0, reason: 'Schatten');
    expect(u[5], 0.0, reason: 'Lichter');
    expect(u[7], 0.0, reason: 'Tonwertkurve aus');
    expect(u[8], 0.0, reason: 'Farbmischer aus');
    expect(u[10], 0.0, reason: 'Beschneidungswarnung aus');
  });

  test('automatischer Weißabgleich schaltet den Shader-Weißabgleich ab', () {
    // temperature == null bedeutet Automatik (siehe DevelopAdjustments).
    final u = developUniforms(const DevelopAdjustments(
      exposure: 0,
      temperature: null,
      tint: null,
      contrast: 0,
      shadows: 0,
      sharpness: 0,
      noiseReduction: 0,
    ));

    expect(u[6], 0.0, reason: 'Weißabgleich muss aus sein');
    // Der Platzhalterwert darf trotzdem gültig sein, damit der Shader nicht
    // mit NaN/0 Kelvin rechnet, falls das Flag je ignoriert würde.
    expect(u[1], 6500.0);
    expect(u[2], 0.0);
  });

  test('manueller Weißabgleich wird durchgereicht und aktiviert', () {
    final u = developUniforms(const DevelopAdjustments(
      exposure: 0,
      temperature: 3200,
      tint: -25,
      contrast: 0,
      shadows: 0,
      sharpness: 0,
      noiseReduction: 0,
    ));

    expect(u[1], 3200.0);
    expect(u[2], -25.0);
    expect(u[6], 1.0, reason: 'Weißabgleich muss an sein');
  });

  test('alle Regler landen an der richtigen Stelle', () {
    // Bewusst paarweise verschiedene Werte: eine vertauschte Zuordnung
    // fiele bei gleichen Werten nicht auf.
    final u = developUniforms(const DevelopAdjustments(
      exposure: 1.5,
      temperature: 8000,
      tint: 40,
      contrast: -0.25,
      shadows: 0.75,
      highlights: -0.4,
      sharpness: 0.5,
      noiseReduction: 0.5,
    ));

    expect(u[0], 1.5, reason: 'Belichtung');
    expect(u[1], 8000.0, reason: 'Temperatur');
    expect(u[2], 40.0, reason: 'Tint');
    expect(u[3], -0.25, reason: 'Kontrast');
    expect(u[4], 0.75, reason: 'Schatten');
    expect(u[5], -0.4, reason: 'Lichter');
  });

  test('Lichter und Schatten werden nicht verwechselt', () {
    // Der Fall, der beim Einbau am leichtesten passiert: beide sind
    // -1..1, beide stehen nebeneinander, und ein vertauschtes Paar sähe
    // auf einem durchschnittlichen Foto fast richtig aus.
    final u = developUniforms(const DevelopAdjustments(shadows: 1, highlights: -1));
    expect(u[4], 1.0, reason: 'Schatten angehoben');
    expect(u[5], -1.0, reason: 'Lichter zurückgenommen');
  });

  test('Schärfe und Rauschunterdrückung erscheinen NICHT in den Uniforms', () {
    // Sie sind bewusst nicht Teil der Live-Vorschau (siehe Shader-Kopf) –
    // dieser Test hält das fest, damit es nicht versehentlich "repariert"
    // wird, ohne den Shader anzupassen.
    final ohne = developUniforms(DevelopAdjustments.neutral);
    final mit = developUniforms(const DevelopAdjustments(
      exposure: 0,
      temperature: null,
      tint: null,
      contrast: 0,
      shadows: 0,
      sharpness: 1.0,
      noiseReduction: 1.0,
    ));

    expect(mit, ohne, reason: 'dürfen die Uniforms nicht verändern');
  });

  test('Tonwertkurve und Farbmischer schalten sich einzeln ein', () {
    // Die Schalter entscheiden, ob der Shader überhaupt nachschlägt. Steht
    // einer fälschlich auf 1, liest er einen 1×1-Platzhalter und das Bild
    // würde einfarbig.
    final nurKurve = developUniforms(const DevelopAdjustments(
      toneCurve: ToneCurve(rot: [CurvePoint(0, 0), CurvePoint(1, 0.5)]),
    ));
    expect(nurKurve[7], 1.0, reason: 'Kurve an');
    expect(nurKurve[8], 0.0, reason: 'Mischer bleibt aus');

    final nurMischer = developUniforms(const DevelopAdjustments(
      colorMixer: ColorMixer({ColorBand.gruen: BandAnpassung(saettigung: 0.5)}),
    ));
    expect(nurMischer[7], 0.0, reason: 'Kurve bleibt aus');
    expect(nurMischer[8], 1.0, reason: 'Mischer an');
  });

  test('ein Band mit lauter Nullen schaltet den Mischer nicht ein', () {
    // Sonst liefe der Farbwürfel für eine Anpassung, die nichts tut.
    final u = developUniforms(const DevelopAdjustments(
      colorMixer: ColorMixer({ColorBand.blau: BandAnpassung()}),
    ));
    expect(u[8], 0.0);
  });

  test('die Kantenlänge des Würfels geht an den Shader', () {
    // Der Shader rechnet die Scheibenanordnung daraus aus; ein Wert, der
    // nicht zur hochgeladenen Textur passt, ergäbe verschobene Farben.
    expect(developUniforms(DevelopAdjustments.neutral)[9],
        colorCubePreviewSize.toDouble());
    expect(
      developUniforms(DevelopAdjustments.neutral, wuerfelKante: colorCubeSize)[9],
      colorCubeSize.toDouble(),
    );
  });

  test('die Beschneidungswarnung ist ohne Zutun aus', () {
    // Der wichtigste Test dieser Datei. Derselbe Shader rendert unter
    // Linux und Windows die ENDERGEBNISSE (develop_render.dart). Ist die
    // Warnung dort an, trägt jede exportierte Datei rote und blaue
    // Flächen. Sicher ist sie deshalb durch Weglassen, nicht durch
    // Sorgfalt an jeder Aufrufstelle.
    expect(developUniforms(DevelopAdjustments.neutral)[10], 0.0);
    expect(
      developUniforms(DevelopAdjustments.neutral, beschneidungZeigen: true)[10],
      1.0,
      reason: 'nur auf ausdrücklichen Wunsch an',
    );
  });

  test('Grenzwerte werden unverändert weitergegeben', () {
    // Das Begrenzen übernimmt der Shader (clamp), nicht diese Funktion –
    // so bleibt eine Stelle dafür zuständig.
    final u = developUniforms(const DevelopAdjustments(
      exposure: -3,
      temperature: 12000,
      tint: 100,
      contrast: 1,
      shadows: -1,
      highlights: 1,
      sharpness: 0,
      noiseReduction: 0,
    ));

    expect(u[0], -3.0);
    expect(u[1], 12000.0);
    expect(u[2], 100.0);
    expect(u[3], 1.0);
    expect(u[4], -1.0);
    expect(u[5], 1.0);
  });
}
