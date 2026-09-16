import 'dart:io';

/// Goldbilder werden nur auf der Plattform geprüft, auf der sie entstanden
/// sind – hier macOS.
///
/// Der erste vollständige Testlauf unter Linux hat es gezeigt: Von 1089
/// Tests fielen genau neun durch, und das waren genau die neun
/// `matchesGoldenFile`-Vergleiche. Kein einziger Sachtest. Die Ursache ist
/// nicht die App, sondern die Schriftrasterung: Linux und macOS zeichnen
/// dieselbe Schrift unterschiedlich, und ein Pixelvergleich merkt das.
///
/// Die Bilder deshalb überall neu zu erzeugen hiesse, je Plattform einen
/// eigenen Satz zu pflegen – für Bilder, die eine Anordnung festhalten
/// sollen, nicht die Schriftglättung des Betriebssystems. Sie hier zu
/// überspringen ist die ehrlichere Antwort: Der Lauf unter Linux bleibt
/// aussagekräftig, statt neun bekannte Fehlschläge mitzuschleppen, in
/// denen ein echter untergehen würde.
/// `testWidgets` nimmt für `skip` nur ein Bool – der Grund steht deshalb
/// hier oben statt in der Meldung des Testlaufs.
final bool nurAufReferenzplattform = !Platform.isMacOS;
