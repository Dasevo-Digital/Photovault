import 'dart:convert';
import 'dart:io';

import 'model_catalog.dart';

/// Die Verarbeitungsergebnisse einer Bibliothek hängen nicht nur vom
/// Programmcode ab, sondern auch von den Gewichten der lokalen KI-Modelle.
/// Diese kleine, lokale Datei merkt deshalb, mit welcher Modellfassung die
/// Ergebnisse zuletzt vollständig erzeugt wurden.
///
/// Sie enthält ausschließlich Modellprüfsummen und Pipeline-Kennungen, keine
/// Bilddaten, Dateinamen oder Suchbegriffe. Bei einer neuen App-Version mit
/// anderen Gewichten bleibt die bisherige Suche benutzbar; die Oberfläche
/// weist aber auf die gezielte Neuverarbeitung hin.
class ModelProcessingState {
  ModelProcessingState(this._file);

  static const _format = 1;
  final File _file;

  /// Die Pipelines, deren Ergebnisse beim nächsten vollständigen Lauf neu
  /// berechnet werden sollten. Gesichtsdetektion und -erkennung gehören
  /// zusammen: Ein Wechsel nur einer der beiden Gewichte verändert das
  /// Gesamtergebnis.
  ///
  /// Die Texterkennung ausserhalb von macOS trägt zusätzlich die Fassung
  /// ihrer Zeilenführung: Seit 3.27.0 wird eine Zeile entlang ihrer Neigung
  /// gelesen statt in einem achsenparallelen Kasten, und schon leicht
  /// schräge Schrift kam vorher als Kauderwelsch an (#92). Die Gewichte sind
  /// dieselben, das Ergebnis nicht. macOS liest mit Vision und behält seinen
  /// Stand.
  static Map<String, String> currentFingerprints({bool? macos}) => {
    'clip': _fingerprint([ModelCatalog.clip]),
    'ocr': (macos ?? Platform.isMacOS)
        ? _fingerprint([ModelCatalog.ocrPaddle])
        : '${_fingerprint([ModelCatalog.ocrPaddle])}:$_ocrZeilenfuehrung',
    'captions': _fingerprint([ModelCatalog.captioningFlorence]),
    'faces': _fingerprint([
      ModelCatalog.faceDetection,
      ModelCatalog.faceRecognition,
    ]),
  };

  static const _ocrZeilenfuehrung = 'zeilen-gedreht-1';

  static String _fingerprint(List<ModelCatalogEntry> entries) => entries
      .expand((entry) => entry.files)
      .map((file) => file.sha256)
      .join(':');

  /// Legt bei einer bestehenden Bibliothek einmalig den aktuellen Stand an.
  /// Ohne diesen Sonderfall würde ein Update auf diese App-Fassung jede alte
  /// Bibliothek sofort zu einer vollständigen KI-Neuberechnung drängen,
  /// obwohl sich ihre bis dahin verwendeten Modelle nicht rekonstruieren
  /// lassen. Spätere Katalogänderungen werden dagegen zuverlässig erkannt.
  Future<Set<String>> initialize(Map<String, String> current) async {
    final saved = await _read();
    if (saved == null) {
      await _write(current);
      return const {};
    }
    return {
      for (final entry in current.entries)
        if (saved[entry.key] != entry.value) entry.key,
    };
  }

  /// Bestätigt eine Pipeline erst nach einem vollständigen Durchlauf.
  Future<void> markCurrent(String pipeline, String fingerprint) async {
    final saved = await _read() ?? <String, String>{};
    saved[pipeline] = fingerprint;
    await _write(saved);
  }

  Future<Map<String, String>?> _read() async {
    if (!await _file.exists()) return null;
    try {
      final decoded = jsonDecode(await _file.readAsString());
      if (decoded is! Map<String, dynamic> || decoded['format'] != _format) {
        return null;
      }
      final pipelines = decoded['pipelines'];
      if (pipelines is! Map) return null;
      return {
        for (final entry in pipelines.entries)
          if (entry.key is String && entry.value is String)
            entry.key as String: entry.value as String,
      };
    } catch (_) {
      // Ein beschädigter Hinweis darf weder die Bibliothek noch die Suche
      // blockieren. Beim nächsten Start wird ein frischer Ausgangsstand
      // geschrieben.
      return null;
    }
  }

  Future<void> _write(Map<String, String> pipelines) async {
    await _file.parent.create(recursive: true);
    await _file.writeAsString(
      jsonEncode({'format': _format, 'pipelines': pipelines}),
    );
  }
}
