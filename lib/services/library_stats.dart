/// Anzahl Fotos/Videos zu genau einer Kamera-Kombination (Hersteller +
/// Modell) für die Kamera-Übersicht der Analyseseite.
class CameraStat {
  final String? make;
  final String? model;
  final int count;

  const CameraStat({this.make, this.model, required this.count});

  /// Anzeigename für die Analyseseite – Hersteller wird weggelassen, wenn er
  /// schon Teil des Modellnamens ist (z.B. "Apple" bei "iPhone 15 Pro"),
  /// analog zur Kamera-Anzeige in der Info-Ansicht eines Fotos.
  String get label {
    if (make == null && model == null) return 'Unbekannt';
    if (model == null) return make!;
    if (make == null) return model!;
    if (model!.toLowerCase().startsWith(make!.toLowerCase())) return model!;
    return '$make $model';
  }
}

/// Gebündelte Kennzahlen für die Analyseseite (StatisticsScreen) – eine
/// einzelne Momentaufnahme statt einzelner Streams, da diese Seite bewusst
/// keine Live-Aktualisierung braucht (siehe StatisticsScreen: Pull-to-Refresh
/// statt watch()).
class LibraryStats {
  final int imageCount;
  final int videoCount;
  final int favoriteCount;
  final int trashedCount;
  final int lockedCount;
  final int totalSizeBytes;
  final Map<int, int> countsByYear;

  /// Monat (1-12) -> Anzahl, über alle Jahre hinweg summiert (Saisonalität).
  final Map<int, int> countsByMonth;
  final List<CameraStat> topCameras;

  const LibraryStats({
    required this.imageCount,
    required this.videoCount,
    required this.favoriteCount,
    required this.trashedCount,
    required this.lockedCount,
    required this.totalSizeBytes,
    required this.countsByYear,
    required this.countsByMonth,
    required this.topCameras,
  });

  int get totalCount => imageCount + videoCount;
}
