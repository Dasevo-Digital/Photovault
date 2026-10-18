import 'cube_lut.dart';
import 'develop_color.dart';

/// Regler-Werte des DevelopScreen für [NativeImageConverter.developImage] –
/// unveränderlich, damit sich ein Satz Einstellungen einfach speichern/
/// zurücksetzen lässt. `temperature`/`tint` sind bewusst nullable (statt
/// eines Zahlen-Default): `null` bedeutet "Kamera-Weißabgleich
/// unverändert lassen", nicht "auf 0 setzen" – anders als bei den übrigen
/// Reglern gibt es hier keinen sinnvollen neutralen Zahlenwert.
class DevelopAdjustments {
  final double exposure; // -3..3 EV
  final double? temperature; // 2000..12000 K, null = Kamera-Weißabgleich
  final double? tint; // -100..100, null = Kamera-Weißabgleich
  final double contrast; // -1..1
  final double shadows; // -1..1

  /// Lichter, -1..1 – das Gegenstück zu [shadows]. Negativ holt einen
  /// überstrahlten Himmel zurück.
  final double highlights;
  final double sharpness; // 0..1
  final double noiseReduction; // 0..1

  /// Lokaler Mikrokontrast, -1..1. Negativ weicht auf, positiv arbeitet
  /// Struktur heraus.
  final double clarity;

  /// Randabdunklung, -1..1. Negativ dunkelt ab, positiv hellt auf.
  final double vignette;

  final bool lensCorrectionEnabled;

  /// Tonwertkurve und Farbmischer (siehe develop_color.dart). Anders als
  /// die Regler darüber gehen sie nicht als Zahl über den Kanal, sondern
  /// als fertig ausgerechnete Nachschlagetabelle – die Mathematik liegt
  /// bewusst nur in Dart, nicht noch einmal in Swift.
  final ToneCurve toneCurve;
  final ColorMixer colorMixer;

  /// Eine importierte Farbtabelle und wie stark sie wirkt.
  ///
  /// Sie geht nicht als eigener Schritt über den Kanal: [buildColorCube]
  /// rechnet sie in denselben Würfel hinein, den der Mischer erzeugt.
  /// Beide Renderpfade bekommen dadurch weiterhin genau einen Würfel.
  final CubeLut? lut;
  final double lutStrength;

  const DevelopAdjustments({
    this.exposure = 0,
    this.temperature,
    this.tint,
    this.contrast = 0,
    this.shadows = 0,
    this.highlights = 0,
    this.sharpness = 0,
    this.noiseReduction = 0,
    this.clarity = 0,
    this.vignette = 0,
    this.lensCorrectionEnabled = true,
    this.toneCurve = ToneCurve.neutral,
    this.colorMixer = ColorMixer.neutral,
    this.lut,
    this.lutStrength = 1,
  });

  /// Ob überhaupt ein Farbwürfel gebraucht wird.
  ///
  /// Ein Look allein genügt dafür – ohne diese Prüfung liesse ein neutraler
  /// Mischer die Tabelle fallen, und die Datei hätte keine Wirkung.
  bool get brauchtFarbwuerfel =>
      !colorMixer.istNeutral || (lut != null && lutStrength > 0);

  /// Alle Regler auf "unverändert" – DevelopScreen zeigt bei fehlenden
  /// gespeicherten Einstellungen bewusst direkt die vorhandene Vorschau-/
  /// Originaldatei an, statt hierfür extra nativ neu zu rendern (siehe
  /// DevelopScreen._init).
  static const neutral = DevelopAdjustments();

  /// Neutrale Kurve bzw. neutraler Mischer werden gar nicht erst
  /// übertragen: Die native Seite lässt den jeweiligen Filter dann weg,
  /// statt eine Identität durch Core Image zu schicken.
  Map<String, Object?> toChannelMap() => {
    'exposure': exposure,
    'temperature': temperature,
    'tint': tint,
    'contrast': contrast,
    'shadows': shadows,
    'highlights': highlights,
    'sharpness': sharpness,
    'noiseReduction': noiseReduction,
    'clarity': clarity,
    'vignette': vignette,
    'lensCorrectionEnabled': lensCorrectionEnabled,
    if (!toneCurve.istNeutral) 'toneCurveLut': buildCurveLut(toneCurve),
    if (brauchtFarbwuerfel) ...{
      'colorCube': buildColorCube(
        colorMixer,
        lut: lut,
        lutStaerke: lutStrength,
      ),
      'colorCubeSize': colorCubeSize,
    },
  };
}

/// Ein vollständiger Satz Entwicklungswerte, losgelöst von einem Foto.
///
/// Gebraucht, weil zwei Quellen dasselbe liefern sollen: die
/// Zwischenablage („Einstellungen kopieren") und eine benannte
/// Entwicklungs-Vorgabe. Ohne diesen gemeinsamen Träger stünde der
/// Übertragungsweg zweimal da – und die zweite Fassung vergässe beim
/// nächsten neuen Regler etwas, ohne dass es auffiele.
///
/// [regler] ist das, was zum Rendern gebraucht wird (samt geladener
/// Farbtabelle); die drei Textfelder sind das, was zum Speichern gebraucht
/// wird. Beides getrennt, weil Kurve und Mischer als JSON in der
/// Datenbank stehen, aber ausgerechnet an den Renderer gehen.
class Entwicklungswerte {
  final DevelopAdjustments regler;

  /// Pfad der Farbtabelle relativ zur Bibliothek – wandert unverändert in
  /// die Zieleinstellungen, damit das Zielfoto dieselbe Datei benennt.
  final String? lutPath;
  final String? toneCurveJson;
  final String? colorMixerJson;

  /// Das Foto, von dem die Werte stammen – wird beim Übertragen
  /// übersprungen. Bei einer Vorgabe `null`: Sie gehört zu keinem Foto.
  final String? quellAssetId;

  const Entwicklungswerte({
    required this.regler,
    this.lutPath,
    this.toneCurveJson,
    this.colorMixerJson,
    this.quellAssetId,
  });
}

/// Eine KI-Objektmaske (siehe MaskEditor/DevelopMasks) für
/// [NativeImageConverter.developImage]: [maskFilePath] zeigt auf eine
/// Grauwert-PNG-Alphamaske, [adjustments] gilt nur innerhalb dieser Maske.
///
/// Tonwertkurve und Farbmischer bleiben hier bewusst neutral – Masken
/// führen sie nicht (siehe DevelopMasks in database.dart). Da
/// [DevelopAdjustments.toChannelMap] neutrale Werte ohnehin weglässt,
/// ergibt sich das von selbst, ohne Sonderfall.
class MaskAdjustmentLayer {
  final String maskFilePath;
  final DevelopAdjustments adjustments;

  const MaskAdjustmentLayer({
    required this.maskFilePath,
    required this.adjustments,
  });

  Map<String, Object?> toChannelMap() => {
    'path': maskFilePath,
    ...adjustments.toChannelMap(),
  };
}
