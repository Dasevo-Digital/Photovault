import 'dart:convert';

/// Eine gelesene Textstelle mit ihrem Platz im Bild.
///
/// **Warum überhaupt gespeichert.** Die Texterkennung fand die Stellen von
/// jeher – beide Wege tun das, der eine über DBNet, der andere über Vision –,
/// warf sie aber weg und behielt nur die aneinandergehängten Zeilen. Damit
/// war der Text durchsuchbar und sonst nichts: Man konnte ihn weder lesen
/// noch kopieren noch sehen, wo im Bild er steht.
///
/// **Warum in Anteilen und nicht in Pixeln.** Die beiden Wege arbeiten auf
/// verschieden grossen Fassungen desselben Fotos (Vision auf einer
/// 2048er-Miniatur, das Modell auf höchstens seiner eigenen Grenzkante), und die
/// Anzeige zeigt wieder eine dritte Grösse. Pixel eines dieser drei Zustände
/// zu speichern hiesse, den Umrechnungsfaktor mitspeichern zu müssen – und
/// beim nächsten Modellwechsel wären alle alten Werte falsch, ohne dass es
/// auffiele.
///
/// Ursprung ist **oben links**, wie überall sonst in Flutter. Apples Vision
/// rechnet von unten links; das wird an der Schnittstelle umgedreht, nicht
/// hier (siehe `ImageConverter.swift`).
class Textstelle {
  /// Der gelesene Text dieser Stelle – in der Regel eine Zeile.
  final String text;

  /// Alle vier als Anteil der Bildkante, 0..1.
  final double links, oben, breite, hoehe;

  const Textstelle({
    required this.text,
    required this.links,
    required this.oben,
    required this.breite,
    required this.hoehe,
  });

  double get rechts => links + breite;
  double get unten => oben + hoehe;

  Map<String, Object?> toJson() => {
        't': text,
        'x': _gerundet(links),
        'y': _gerundet(oben),
        'b': _gerundet(breite),
        'h': _gerundet(hoehe),
      };

  /// Vier Nachkommastellen. Bei einem 6000 Pixel breiten Foto ist das gut ein
  /// halbes Pixel – genauer wäre eine Behauptung, die die Erkennung gar nicht
  /// deckt, und es machte die gespeicherte Zeichenkette um ein Drittel länger.
  static double _gerundet(double wert) =>
      double.parse(wert.clamp(0.0, 1.0).toStringAsFixed(4));

  static Textstelle? _ausJson(Object? roh) {
    if (roh is! Map) return null;
    final text = roh['t'];
    final x = roh['x'], y = roh['y'], b = roh['b'], h = roh['h'];
    if (text is! String || x is! num || y is! num || b is! num || h is! num) {
      return null;
    }
    return Textstelle(
      text: text,
      links: x.toDouble(),
      oben: y.toDouble(),
      breite: b.toDouble(),
      hoehe: h.toDouble(),
    );
  }

  @override
  String toString() => 'Textstelle("$text", $links/$oben ${breite}x$hoehe)';
}

/// Die Stellen als Zeichenkette für die Datenbank.
String textstellenNachJson(List<Textstelle> stellen) =>
    jsonEncode([for (final s in stellen) s.toJson()]);

/// Liest zurück, was [textstellenNachJson] geschrieben hat.
///
/// Gibt bei allem Unerwarteten eine leere Liste zurück, nie eine Ausnahme:
/// Der Aufrufer ist eine Anzeige, und ein Foto, dessen Kästchen nicht lesbar
/// sind, soll ohne Kästchen erscheinen und nicht gar nicht.
List<Textstelle> textstellenAusJson(String? json) {
  if (json == null || json.isEmpty) return const [];
  try {
    final roh = jsonDecode(json);
    if (roh is! List) return const [];
    return [
      for (final eintrag in roh)
        if (Textstelle._ausJson(eintrag) case final s?) s,
    ];
  } on FormatException {
    return const [];
  }
}

/// Der zusammenhängende Text aus einer Stellenliste, eine Zeile je Stelle.
///
/// Damit bleibt `Assets.ocrText` genau das, was es vorher war, auch wenn es
/// künftig aus den Stellen entsteht – die Volltextsuche darf sich nicht
/// dadurch ändern, dass nebenbei Kästchen mitgespeichert werden.
String textAusStellen(List<Textstelle> stellen) =>
    [for (final s in stellen) s.text].where((z) => z.isNotEmpty).join('\n');
