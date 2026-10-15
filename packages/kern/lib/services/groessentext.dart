/// Eine Byte-Zahl als Text, den man lesen kann.
///
/// Stand bisher als private Methode im Einstellungs-Bildschirm. Der
/// Papierkorb braucht sie jetzt auch, und zwei Fassungen derselben
/// Rundungsregel laufen früher oder später auseinander – dieselbe
/// Überlegung wie bei `LibraryState.dateienVon`.
///
/// Stufen bewusst bei 1024 und nicht bei 1000: Es geht um belegten Platz,
/// und den zeigt sowohl der Finder als auch der Dateimanager unter Linux
/// auf dieselbe Weise an.
String groessentext(int bytes) {
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}
