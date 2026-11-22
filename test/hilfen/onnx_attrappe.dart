import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

/// Eine ONNX Runtime ohne Modell, für Tests ohne Plattformkanal.
///
/// Merkt sich, welche Sitzungen und Tensoren offen sind. [scheitertBei]
/// lässt das Öffnen jeder Sitzung scheitern, deren Pfad so endet. [rechne]
/// liefert die Ausgaben eines Laufs: je Name die Daten und die Form; ohne
/// [rechne] gibt es keine Ausgaben.
///
/// Einsetzen mit `OnnxRuntimePlatform.instance = OnnxAttrappe()` – das
/// gilt für das ganze Isolat der Testdatei.
class OnnxAttrappe extends OnnxRuntimePlatform {
  OnnxAttrappe({this.scheitertBei = const {}, this.rechne});

  final Set<String> scheitertBei;
  final Map<String, ({Object daten, List<int> form})> Function(
    String pfad,
    Map<String, Object> eingaben,
  )?
  rechne;

  /// Offene Sitzungen: Kennung -> Pfad.
  final offeneSitzungen = <String, String>{};

  /// Wie oft eine Sitzung geöffnet wurde, auch die gescheiterten.
  var geoeffnet = 0;

  final _tensoren = <String, ({Object daten, String art, List<int> form})>{};
  var _naechste = 0;

  int get offeneTensoren => _tensoren.length;

  @override
  Future<Map<String, dynamic>> createSession(
    String modelPath, {
    Map<String, dynamic>? sessionOptions,
  }) async {
    geoeffnet++;
    if (scheitertBei.any(modelPath.endsWith)) {
      throw StateError('Attrappe: $modelPath lässt sich nicht laden');
    }
    final id = 's${_naechste++}';
    offeneSitzungen[id] = modelPath;
    return {
      'sessionId': id,
      'inputNames': ['eingabe'],
      'outputNames': ['ausgabe'],
    };
  }

  @override
  Future<void> closeSession(String sessionId) async {
    offeneSitzungen.remove(sessionId);
  }

  @override
  Future<Map<String, dynamic>> createOrtValue(
    String sourceType,
    dynamic data,
    List<int> shape,
  ) async {
    final id = 'v${_naechste++}';
    _tensoren[id] = (daten: data as Object, art: sourceType, form: shape);
    return {'valueId': id, 'dataType': sourceType, 'shape': shape};
  }

  @override
  Future<Map<String, dynamic>> runInference(
    String sessionId,
    Map<String, OrtValue> inputs, {
    Map<String, dynamic>? runOptions,
  }) async {
    final pfad = offeneSitzungen[sessionId];
    if (pfad == null) throw StateError('Attrappe: Sitzung geschlossen');
    final ausgaben =
        rechne?.call(pfad, {
          for (final e in inputs.entries) e.key: _tensoren[e.value.id]!.daten,
        }) ??
        const {};
    return {
      for (final e in ausgaben.entries)
        e.key: () {
          final id = 'v${_naechste++}';
          _tensoren[id] = (
            daten: e.value.daten,
            art: 'float32',
            form: e.value.form,
          );
          return [id, 'float32', e.value.form];
        }(),
    };
  }

  @override
  Future<Map<String, dynamic>> getOrtValueData(String valueId) async => {
    'data': _tensoren[valueId]!.daten,
  };

  @override
  Future<void> releaseOrtValue(String valueId) async {
    _tensoren.remove(valueId);
  }
}
