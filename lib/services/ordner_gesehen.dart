import 'dart:convert';
import 'dart:io';

/// Was im überwachten Ordner lag, mit Grösse und Änderungszeit, und ob es
/// seither eingelesen ist (#252).
typedef OrdnerEintrag = ({
  int groesse,
  DateTime geaendert,
  bool eingelesen,
  int fehlversuche,
});

/// Hält den Stand des überwachten Ordners über einen Neustart hinaus
/// (#424). Bis hierher lag er nur im Speicher: Nach jedem Start galt jede
/// Datei als neu. Ohne Server las der Import dann jede ganz für ihre
/// Prüfsumme, verbunden ging jede vollständig zum Server, nur damit der sie
/// als Dublette verwarf.
///
/// Eine Datei je Bibliothek im lokalen Datenordner: Der überwachte Ordner
/// gehört zu diesem Rechner, nicht zur Bibliothek.
class OrdnerGesehenAblage {
  OrdnerGesehenAblage(this.datei);

  final File datei;

  static const _fassung = 1;

  /// Der gespeicherte Stand; leer, wenn es keinen gibt oder er nicht
  /// lesbar ist. Dann liest der erste Durchgang eben einmal alles.
  Future<Map<String, OrdnerEintrag>> lies() async {
    try {
      if (!await datei.exists()) return {};
      final json = jsonDecode(await datei.readAsString());
      if (json is! Map || json['v'] != _fassung) return {};
      final dateien = json['dateien'];
      if (dateien is! Map) return {};
      final stand = <String, OrdnerEintrag>{};
      for (final e in dateien.entries) {
        final w = e.value;
        if (e.key is! String || w is! List || w.length != 4) continue;
        final [groesse, geaendert, eingelesen, fehl] = w;
        if (groesse is! int ||
            geaendert is! int ||
            eingelesen is! bool ||
            fehl is! int) {
          continue;
        }
        stand[e.key as String] = (
          groesse: groesse,
          geaendert: DateTime.fromMicrosecondsSinceEpoch(geaendert),
          eingelesen: eingelesen,
          fehlversuche: fehl,
        );
      }
      return stand;
    } on Object {
      return {};
    }
  }

  /// Schreibt [stand] über eine Zwischendatei, damit ein Absturz mitten im
  /// Schreiben keinen halben Stand hinterlässt.
  Future<void> schreibe(Map<String, OrdnerEintrag> stand) async {
    await datei.parent.create(recursive: true);
    final teil = File('${datei.path}.part');
    await teil.writeAsString(
      jsonEncode({
        'v': _fassung,
        'dateien': {
          for (final e in stand.entries)
            e.key: [
              e.value.groesse,
              e.value.geaendert.microsecondsSinceEpoch,
              e.value.eingelesen,
              e.value.fehlversuche,
            ],
        },
      }),
      flush: true,
    );
    await teil.rename(datei.path);
  }
}
