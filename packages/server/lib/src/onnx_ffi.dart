import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:onnxruntime_api/onnxruntime_api.dart';

import 'beschleuniger.dart';

/// ONNX Runtime für ein Programm ohne Flutter: die C-Schnittstelle der
/// Bibliothek über `dart:ffi`, hinter derselben Plattform-Schnittstelle, die
/// in der App das Plugin bedient. Die Dienste im Kern merken keinen
/// Unterschied.
///
/// **Wie das Plugin:** dieselbe Bibliothek (1.28), dieselben Vorgaben einer
/// Sitzung (nur Fäden, Konfigurationseinträge und Arena aus den Optionen,
/// alles andere wie ONNX Runtime es vorgibt) und alle Aufrufe nacheinander
/// in einem einzigen Arbeitsfaden – hier einem eigenen Isolate. Ein Modell
/// rechnet blockierend; im Isolate des Servers hielte es jede Anfrage an.
///
/// **Beschleuniger** (Issue #104, siehe [Beschleuniger]): Ein Modell, das
/// ohne ausdrückliche Anbieter geladen wird – so lädt der Kern alle ausser
/// dem Kratzermodell –, rechnet auf dem eingestellten Beschleuniger. Seine
/// ersten Läufe rechnen zur Gegenprobe auch auf der CPU; weicht etwas ab,
/// bleibt es auf der CPU. [zustand] sagt, wie es steht, [anbieterFuer]
/// womit ein Modell gerade rechnet (für die Herkunft der Ergebnisse).
class FfiOnnxPlattform extends OnnxRuntimePlatform {
  FfiOnnxPlattform._(
    this._an,
    this._von,
    this.fassung,
    this.eintraege,
    this.beschleuniger,
  );

  /// Konfigurationseinträge, die jede Sitzung zusätzlich bekommt.
  final Map<String, String> eintraege;

  final Beschleuniger beschleuniger;

  /// Je Sitzung ihr Modell, je Modell (Dateiname), womit es zuletzt
  /// rechnete.
  final _modellJeSitzung = <String, String>{};
  final _anbieterJeModell = <String, String>{};

  final SendPort _an;
  final ReceivePort _von;

  /// Die Fassung der geladenen Bibliothek, etwa „1.28.3“.
  final String fassung;

  final _offen = <int, Completer<Object?>>{};
  var _naechste = 0;

  /// Startet den Arbeitsfaden und lädt die Bibliothek unter [pfad].
  static Future<FfiOnnxPlattform> starte(
    String pfad, {
    Map<String, String> eintraege = const {},
    Beschleuniger beschleuniger = Beschleuniger.cpu,
    String? zwischenspeicher,
  }) async {
    final von = ReceivePort();
    await Isolate.spawn(_arbeite, [
      von.sendPort,
      pfad,
      beschleuniger.art,
      beschleuniger.name,
      beschleuniger.optionen(zwischenspeicher: zwischenspeicher),
    ]);
    final erste = Completer<List<Object?>>();
    late FfiOnnxPlattform plattform;
    von.listen((nachricht) {
      if (!erste.isCompleted) {
        erste.complete((nachricht as List).cast<Object?>());
        return;
      }
      plattform._antwort((nachricht as List).cast<Object?>());
    });
    final hallo = await erste.future;
    if (hallo[0] == null) {
      von.close();
      throw StateError('ONNX Runtime unter $pfad nicht ladbar: ${hallo[1]}');
    }
    return plattform = FfiOnnxPlattform._(
      hallo[0]! as SendPort,
      von,
      hallo[1]! as String,
      eintraege,
      beschleuniger,
    );
  }

  /// Beendet den Arbeitsfaden; offene Sitzungen und Werte gehen mit.
  void beende() {
    _an.send(null);
    _von.close();
  }

  void _antwort(List<Object?> n) {
    final c = _offen.remove(n[0]! as int);
    if (c == null) return;
    if (n.length > 2) {
      c.completeError(StateError(n[2]! as String));
    } else {
      c.complete(n[1]);
    }
  }

  Future<T> _frag<T>(String methode, [List<Object?> argumente = const []]) {
    final nr = _naechste++;
    final c = Completer<Object?>();
    _offen[nr] = c;
    _an.send([nr, methode, ...argumente]);
    return c.future.then((e) => e as T);
  }

  @override
  Future<String?> getPlatformVersion() async => 'ONNX Runtime $fassung (FFI)';

  @override
  Future<List<String>> getAvailableProviders() async =>
      (await _frag<List<Object?>>('anbieter')).cast<String>();

  @override
  Future<Map<String, dynamic>> createSession(
    String modelPath, {
    Map<String, dynamic>? sessionOptions,
  }) async {
    final o = sessionOptions ?? const {};
    final anbieter = (o['providers'] as List?)?.cast<String>() ?? const [];
    final fremd = anbieter.where((a) => a != 'CPU');
    if (fremd.isNotEmpty) {
      // Welcher Beschleuniger rechnet, stellt der Server ein (siehe
      // [Beschleuniger]), nicht das Modell.
      throw UnsupportedError('Anbieter $fremd fordert ein Modell über FFI an');
    }
    final r = await _frag<List<Object?>>('sitzung', [
      modelPath,
      o['intraOpNumThreads'],
      o['interOpNumThreads'],
      o['useArena'],
      {...eintraege, ...?(o['sessionConfigs'] as Map?)?.cast<String, String>()},
      // Wer ausdrücklich die CPU verlangt (das Kratzermodell), bekommt sie.
      anbieter.isEmpty && !beschleuniger.istCpu,
    ]);
    final modell = modelPath.split(RegExp(r'[/\\]')).last;
    _modellJeSitzung[r[0]! as String] = modell;
    _anbieterJeModell[modell] = r[3]! as String;
    return {
      'sessionId': r[0],
      'inputNames': (r[1]! as List).cast<String>(),
      'outputNames': (r[2]! as List).cast<String>(),
    };
  }

  @override
  Future<void> closeSession(String sessionId) {
    _modellJeSitzung.remove(sessionId);
    return _frag<void>('schliesse', [sessionId]);
  }

  /// Womit das Modell [datei] (Dateiname) zuletzt rechnete: `CPU` oder der
  /// Name des Beschleunigers; `CPU` auch während der Gegenprobe, denn
  /// solange zählt, was die CPU gerechnet hat.
  String anbieterFuer(String datei) => _anbieterJeModell[datei] ?? 'CPU';

  /// Wie es um den Beschleuniger steht: Name, ein Fehler, welche Modelle
  /// die Gegenprobe bestanden haben, welche noch geprüft werden und welche
  /// mit welchem Grund durchfielen.
  Future<Map<String, Object?>> zustand() async =>
      (await _frag<Map<Object?, Object?>>('zustand')).cast<String, Object?>();

  @override
  Future<Map<String, dynamic>> createOrtValue(
    String sourceType,
    dynamic data,
    List<int> shape,
  ) async {
    final TypedData daten = switch (sourceType) {
      'bool' => Uint8List.fromList([
        for (final b in (data as List).cast<bool>()) b ? 1 : 0,
      ]),
      'float32' || 'int32' || 'int64' || 'uint8' => data as TypedData,
      _ => throw UnsupportedError('Tensoren vom Typ $sourceType über FFI'),
    };
    final id = await _frag<String>('wert', [
      sourceType,
      TransferableTypedData.fromList([daten]),
      shape,
    ]);
    return {'valueId': id, 'dataType': sourceType, 'shape': shape};
  }

  @override
  Future<Map<String, dynamic>> runInference(
    String sessionId,
    Map<String, OrtValue> inputs, {
    Map<String, dynamic>? runOptions,
  }) async {
    final r = await _frag<List<Object?>>('rechne', [
      sessionId,
      {for (final e in inputs.entries) e.key: e.value.id},
    ]);
    final modell = _modellJeSitzung[sessionId];
    if (modell != null) _anbieterJeModell[modell] = r[1]! as String;
    return (r[0]! as Map).cast<String, dynamic>();
  }

  @override
  Future<Map<String, dynamic>> getOrtValueData(String valueId) async {
    final r = await _frag<List<Object?>>('lies', [valueId]);
    final typ = r[0]! as String;
    final bytes = (r[1]! as TransferableTypedData).materialize();
    final TypedData daten = switch (typ) {
      'float32' => bytes.asFloat32List(),
      'int32' => bytes.asInt32List(),
      'int64' => bytes.asInt64List(),
      _ => bytes.asUint8List(),
    };
    return {'data': daten, 'shape': r[2], 'dataType': typ};
  }

  @override
  Future<void> releaseOrtValue(String valueId) =>
      _frag<void>('frei', [valueId]);
}

// ---------------------------------------------------------------------------
// Der Arbeitsfaden
// ---------------------------------------------------------------------------

void _arbeite(List<Object?> start) {
  final antwort = start[0]! as SendPort;
  final _Ort ort;
  try {
    ort = _Ort(
      start[1]! as String,
      art: start[2]! as String,
      name: start[3]! as String,
      anbieterOptionen: (start[4]! as Map).cast<String, String>(),
    );
  } on Object catch (e) {
    antwort.send([null, '$e']);
    return;
  }
  final eingang = ReceivePort();
  antwort.send([eingang.sendPort, ort.fassung]);
  eingang.listen((nachricht) {
    if (nachricht == null) {
      ort.raeumeAuf();
      eingang.close();
      return;
    }
    final n = (nachricht as List).cast<Object?>();
    final nr = n[0]! as int;
    try {
      antwort.send([nr, ort.fuehreAus(n[1]! as String, n.sublist(2))]);
    } on Object catch (e) {
      antwort.send([nr, null, '$e']);
    }
  });
}

/// Was die Typen für ONNX Runtime heissen und wie viele Bytes ein Element
/// hat.
const _typen = <String, (int, int)>{
  'float32': (1, 4),
  'uint8': (2, 1),
  'int8': (3, 1),
  'int32': (6, 4),
  'int64': (7, 8),
  'bool': (9, 1),
};

/// Die Stellen der Funktionen in der Tabelle `OrtApi` der Fassung 28,
/// ausgerechnet mit `offsetof` gegen `onnxruntime_c_api.h` 1.28.3. Die
/// Tabelle wächst nur hinten, die Stellen bleiben in jeder späteren
/// Fassung dieselben.
abstract final class _Stelle {
  static const getErrorMessage = 2;
  static const createEnv = 3;
  static const createSession = 7;
  static const run = 9;
  static const createSessionOptions = 10;
  static const disableCpuMemArena = 19;
  static const setIntraOpNumThreads = 24;
  static const setInterOpNumThreads = 25;
  static const sessionGetInputCount = 30;
  static const sessionGetOutputCount = 31;
  static const sessionGetInputName = 36;
  static const sessionGetOutputName = 37;
  static const createTensorAsOrtValue = 48;
  static const getTensorMutableData = 51;
  static const getTensorElementType = 60;
  static const getDimensionsCount = 61;
  static const getDimensions = 62;
  static const getTensorShapeElementCount = 64;
  static const getTensorTypeAndShape = 65;
  static const allocatorFree = 76;
  static const getAllocatorWithDefaultOptions = 78;
  static const releaseEnv = 92;
  static const releaseStatus = 93;
  static const releaseSession = 95;
  static const releaseValue = 96;
  static const releaseTensorTypeAndShapeInfo = 99;
  static const releaseSessionOptions = 100;
  static const getAvailableProviders = 125;
  static const releaseAvailableProviders = 126;
  static const addSessionConfigEntry = 130;
  static const appendCudaV2 = 204;
  static const createCudaOptions = 205;
  static const updateCudaOptions = 206;
  static const releaseCudaOptions = 208;
  static const appendExecutionProvider = 216;
  static const appendOpenVinoV2 = 275;
}

/// So viele Läufe rechnet ein beschleunigtes Modell zur Probe auch auf der
/// CPU, bevor der Beschleuniger allein übernimmt.
const _probelaeufe = 3;

/// Die API-Fassung, die verlangt wird: die älteste, die alle hier
/// benutzten Funktionen hat (die jüngste ist `…_OpenVINO_V2` aus 1.17).
/// ONNX Runtime liefert für jede ältere Fassung dieselbe Tabelle; so lädt
/// auch eine ältere Bibliothek mit Beschleuniger – Intels OpenVINO-Bau etwa
/// gibt es nur bis 1.24. Gemessen und bitgleich zur App ist 1.28 (siehe
/// [geprueftFassung]).
const _apiFassung = 17;

/// Die Fassung, mit der die App rechnet und gegen die der Server gemessen
/// ist. Eine andere rechnet auf der CPU womöglich minimal anders.
const geprueftFassung = '1.28.3';

typedef _Zeiger = Pointer<Void>;
typedef _Status = Pointer<Void>;

final class _Sitzung {
  _Sitzung(
    this.pfad,
    this.zeiger,
    this.eingaenge,
    this.ausgaenge,
    this.anbieter,
    this.optionen, {
    this.zwilling,
  });
  final String pfad;
  _Zeiger zeiger;
  final List<String> eingaenge;
  final List<String> ausgaenge;

  /// Womit [zeiger] rechnet: `CPU` oder der Name des Beschleunigers.
  String anbieter;

  /// Wie die Sitzung angelegt wurde – für eine CPU-Sitzung, falls der
  /// Beschleuniger später ausfällt.
  final _Sitzungsoptionen optionen;

  /// Dieselbe Sitzung auf der CPU, solange die Gegenprobe läuft.
  _Zeiger? zwilling;
  var offen = _probelaeufe;
}

typedef _Sitzungsoptionen = ({
  int? intra,
  int? inter,
  bool? arena,
  Map<String, String> eintraege,
});

/// Der Beschleuniger liess sich nicht an die Sitzung hängen – fehlt in der
/// Bibliothek oder auf dem Rechner.
final class _AnbieterFehlt implements Exception {
  _AnbieterFehlt(this.grund);
  final String grund;
}

final class _Wert {
  _Wert(this.zeiger, this.typ, this.form);
  final _Zeiger zeiger;
  final String typ;
  final List<int> form;
}

class _Ort {
  _Ort(
    String pfad, {
    required this.art,
    required this.name,
    required this.anbieterOptionen,
  }) : _lib = DynamicLibrary.open(pfad) {
    final basis = _lib
        .lookupFunction<
          Pointer<Pointer<Void>> Function(),
          Pointer<Pointer<Void>> Function()
        >('OrtGetApiBase')();
    final getApi = basis[0]
        .cast<NativeFunction<Pointer<Pointer<Void>> Function(Uint32)>>()
        .asFunction<Pointer<Pointer<Void>> Function(int)>();
    _api = getApi(_apiFassung);
    if (_api == nullptr) {
      throw StateError(
        'die Bibliothek kennt die API-Fassung $_apiFassung nicht (zu alt)',
      );
    }
    fassung = basis[1]
        .cast<NativeFunction<Pointer<Utf8> Function()>>()
        .asFunction<Pointer<Utf8> Function()>()()
        .toDartString();
    _bind();
    _env = using((a) {
      final aus = a<Pointer<Void>>();
      // Pegel 3 (Fehler) statt der Warnungen wie im Plugin: Die Modelle
      // melden beim Laden jedes unbenutzte Gewicht einzeln, und auf dem
      // Server landet das farbig im Journal. Am Rechnen ändert das nichts.
      _pruefe(
        _createEnv(3, 'PhotoVaultServer'.toNativeUtf8(allocator: a), aus),
      );
      return aus.value;
    });
    _allocator = using((a) {
      final aus = a<Pointer<Void>>();
      _pruefe(_getAllocatorWithDefaultOptions(aus));
      return aus.value;
    });
  }

  final DynamicLibrary _lib;

  /// Der Beschleuniger (siehe `Beschleuniger`): `cpu`, `openvino`, `cuda`,
  /// `coreml`, mit seinem Namen und den Optionen für ONNX Runtime.
  final String art;
  final String name;
  final Map<String, String> anbieterOptionen;

  /// Warum der Beschleuniger gar nicht geht – dann rechnet alles auf der
  /// CPU.
  String? _anbieterFehler;

  /// Modelle (Pfad), die die Gegenprobe bestanden haben …
  final _bestanden = <String>{};

  /// … und die, die durchfielen, mit Grund.
  final _verworfen = <String, String>{};

  late final Pointer<Pointer<Void>> _api;
  late final String fassung;
  late final _Zeiger _env;
  late final _Zeiger _allocator;

  final _sitzungen = <String, _Sitzung>{};
  final _werte = <String, _Wert>{};
  var _zaehler = 0;

  Pointer<NativeFunction<T>> _f<T extends Function>(int stelle) =>
      _api[stelle].cast<NativeFunction<T>>();

  late final Pointer<Utf8> Function(_Status) _getErrorMessage;
  late final void Function(_Status) _releaseStatus;
  late final _Status Function(int, Pointer<Utf8>, Pointer<_Zeiger>) _createEnv;
  late final void Function(_Zeiger) _releaseEnv;
  late final _Status Function(Pointer<_Zeiger>) _createSessionOptions;
  late final void Function(_Zeiger) _releaseSessionOptions;
  late final _Status Function(_Zeiger, int) _setIntra;
  late final _Status Function(_Zeiger, int) _setInter;
  late final _Status Function(_Zeiger, Pointer<Utf8>, Pointer<Utf8>)
  _addConfigEntry;
  late final _Status Function(_Zeiger) _disableArena;
  late final _Status Function(_Zeiger, Pointer<Utf8>, _Zeiger, Pointer<_Zeiger>)
  _createSession;
  late final void Function(_Zeiger) _releaseSession;
  late final _Status Function(_Zeiger, Pointer<Size>) _inputCount;
  late final _Status Function(_Zeiger, Pointer<Size>) _outputCount;
  late final _Status Function(_Zeiger, int, _Zeiger, Pointer<Pointer<Utf8>>)
  _inputName;
  late final _Status Function(_Zeiger, int, _Zeiger, Pointer<Pointer<Utf8>>)
  _outputName;
  late final _Status Function(Pointer<_Zeiger>) _getAllocatorWithDefaultOptions;
  late final _Status Function(_Zeiger, _Zeiger) _allocatorFree;
  late final _Status Function(
    _Zeiger,
    Pointer<Int64>,
    int,
    int,
    Pointer<_Zeiger>,
  )
  _createTensor;
  late final _Status Function(_Zeiger, Pointer<_Zeiger>) _mutableData;
  late final void Function(_Zeiger) _releaseValue;
  late final _Status Function(_Zeiger, Pointer<_Zeiger>) _typeAndShape;
  late final _Status Function(_Zeiger, Pointer<Int32>) _elementType;
  late final _Status Function(_Zeiger, Pointer<Size>) _dimensionsCount;
  late final _Status Function(_Zeiger, Pointer<Int64>, int) _dimensions;
  late final _Status Function(_Zeiger, Pointer<Size>) _elementCount;
  late final void Function(_Zeiger) _releaseTypeAndShape;
  late final _Status Function(
    _Zeiger,
    _Zeiger,
    Pointer<Pointer<Utf8>>,
    Pointer<_Zeiger>,
    int,
    Pointer<Pointer<Utf8>>,
    int,
    Pointer<_Zeiger>,
  )
  _run;
  late final _Status Function(Pointer<Pointer<Pointer<Utf8>>>, Pointer<Int32>)
  _availableProviders;
  late final _Status Function(Pointer<Pointer<Utf8>>, int)
  _releaseAvailableProviders;
  late final _Status Function(
    _Zeiger,
    Pointer<Utf8>,
    Pointer<Pointer<Utf8>>,
    Pointer<Pointer<Utf8>>,
    int,
  )
  _appendProvider;
  late final _Status Function(
    _Zeiger,
    Pointer<Pointer<Utf8>>,
    Pointer<Pointer<Utf8>>,
    int,
  )
  _appendOpenVino;
  late final _Status Function(Pointer<_Zeiger>) _createCudaOptions;
  late final _Status Function(
    _Zeiger,
    Pointer<Pointer<Utf8>>,
    Pointer<Pointer<Utf8>>,
    int,
  )
  _updateCudaOptions;
  late final void Function(_Zeiger) _releaseCudaOptions;
  late final _Status Function(_Zeiger, _Zeiger) _appendCuda;

  void _bind() {
    _getErrorMessage = _f<Pointer<Utf8> Function(_Status)>(
      _Stelle.getErrorMessage,
    ).asFunction();
    _releaseStatus = _f<Void Function(_Status)>(
      _Stelle.releaseStatus,
    ).asFunction();
    _createEnv = _f<_Status Function(Int32, Pointer<Utf8>, Pointer<_Zeiger>)>(
      _Stelle.createEnv,
    ).asFunction();
    _releaseEnv = _f<Void Function(_Zeiger)>(_Stelle.releaseEnv).asFunction();
    _createSessionOptions = _f<_Status Function(Pointer<_Zeiger>)>(
      _Stelle.createSessionOptions,
    ).asFunction();
    _releaseSessionOptions = _f<Void Function(_Zeiger)>(
      _Stelle.releaseSessionOptions,
    ).asFunction();
    _setIntra = _f<_Status Function(_Zeiger, Int32)>(
      _Stelle.setIntraOpNumThreads,
    ).asFunction();
    _setInter = _f<_Status Function(_Zeiger, Int32)>(
      _Stelle.setInterOpNumThreads,
    ).asFunction();
    _addConfigEntry =
        _f<_Status Function(_Zeiger, Pointer<Utf8>, Pointer<Utf8>)>(
          _Stelle.addSessionConfigEntry,
        ).asFunction();
    _disableArena = _f<_Status Function(_Zeiger)>(
      _Stelle.disableCpuMemArena,
    ).asFunction();
    _createSession =
        _f<_Status Function(_Zeiger, Pointer<Utf8>, _Zeiger, Pointer<_Zeiger>)>(
          _Stelle.createSession,
        ).asFunction();
    _releaseSession = _f<Void Function(_Zeiger)>(
      _Stelle.releaseSession,
    ).asFunction();
    _inputCount = _f<_Status Function(_Zeiger, Pointer<Size>)>(
      _Stelle.sessionGetInputCount,
    ).asFunction();
    _outputCount = _f<_Status Function(_Zeiger, Pointer<Size>)>(
      _Stelle.sessionGetOutputCount,
    ).asFunction();
    _inputName =
        _f<_Status Function(_Zeiger, Size, _Zeiger, Pointer<Pointer<Utf8>>)>(
          _Stelle.sessionGetInputName,
        ).asFunction();
    _outputName =
        _f<_Status Function(_Zeiger, Size, _Zeiger, Pointer<Pointer<Utf8>>)>(
          _Stelle.sessionGetOutputName,
        ).asFunction();
    _getAllocatorWithDefaultOptions = _f<_Status Function(Pointer<_Zeiger>)>(
      _Stelle.getAllocatorWithDefaultOptions,
    ).asFunction();
    _allocatorFree = _f<_Status Function(_Zeiger, _Zeiger)>(
      _Stelle.allocatorFree,
    ).asFunction();
    _createTensor =
        _f<
              _Status Function(
                _Zeiger,
                Pointer<Int64>,
                Size,
                Int32,
                Pointer<_Zeiger>,
              )
            >(_Stelle.createTensorAsOrtValue)
            .asFunction();
    _mutableData = _f<_Status Function(_Zeiger, Pointer<_Zeiger>)>(
      _Stelle.getTensorMutableData,
    ).asFunction();
    _releaseValue = _f<Void Function(_Zeiger)>(
      _Stelle.releaseValue,
    ).asFunction();
    _typeAndShape = _f<_Status Function(_Zeiger, Pointer<_Zeiger>)>(
      _Stelle.getTensorTypeAndShape,
    ).asFunction();
    _elementType = _f<_Status Function(_Zeiger, Pointer<Int32>)>(
      _Stelle.getTensorElementType,
    ).asFunction();
    _dimensionsCount = _f<_Status Function(_Zeiger, Pointer<Size>)>(
      _Stelle.getDimensionsCount,
    ).asFunction();
    _dimensions = _f<_Status Function(_Zeiger, Pointer<Int64>, Size)>(
      _Stelle.getDimensions,
    ).asFunction();
    _elementCount = _f<_Status Function(_Zeiger, Pointer<Size>)>(
      _Stelle.getTensorShapeElementCount,
    ).asFunction();
    _releaseTypeAndShape = _f<Void Function(_Zeiger)>(
      _Stelle.releaseTensorTypeAndShapeInfo,
    ).asFunction();
    _run =
        _f<
              _Status Function(
                _Zeiger,
                _Zeiger,
                Pointer<Pointer<Utf8>>,
                Pointer<_Zeiger>,
                Size,
                Pointer<Pointer<Utf8>>,
                Size,
                Pointer<_Zeiger>,
              )
            >(_Stelle.run)
            .asFunction();
    _availableProviders =
        _f<_Status Function(Pointer<Pointer<Pointer<Utf8>>>, Pointer<Int32>)>(
          _Stelle.getAvailableProviders,
        ).asFunction();
    _releaseAvailableProviders =
        _f<_Status Function(Pointer<Pointer<Utf8>>, Int32)>(
          _Stelle.releaseAvailableProviders,
        ).asFunction();
    _appendProvider =
        _f<
              _Status Function(
                _Zeiger,
                Pointer<Utf8>,
                Pointer<Pointer<Utf8>>,
                Pointer<Pointer<Utf8>>,
                Size,
              )
            >(_Stelle.appendExecutionProvider)
            .asFunction();
    _appendOpenVino =
        _f<
              _Status Function(
                _Zeiger,
                Pointer<Pointer<Utf8>>,
                Pointer<Pointer<Utf8>>,
                Size,
              )
            >(_Stelle.appendOpenVinoV2)
            .asFunction();
    _createCudaOptions = _f<_Status Function(Pointer<_Zeiger>)>(
      _Stelle.createCudaOptions,
    ).asFunction();
    _updateCudaOptions =
        _f<
              _Status Function(
                _Zeiger,
                Pointer<Pointer<Utf8>>,
                Pointer<Pointer<Utf8>>,
                Size,
              )
            >(_Stelle.updateCudaOptions)
            .asFunction();
    _releaseCudaOptions = _f<Void Function(_Zeiger)>(
      _Stelle.releaseCudaOptions,
    ).asFunction();
    _appendCuda = _f<_Status Function(_Zeiger, _Zeiger)>(
      _Stelle.appendCudaV2,
    ).asFunction();
  }

  /// Ein Status ungleich null ist ein Fehler: Text holen, freigeben, werfen.
  void _pruefe(_Status status) {
    if (status == nullptr) return;
    final text = _getErrorMessage(status).toDartString();
    _releaseStatus(status);
    throw StateError(text);
  }

  Object? fuehreAus(String methode, List<Object?> a) => switch (methode) {
    'anbieter' => _anbieter(),
    'sitzung' => _sitzung(a[0]! as String, (
      intra: a[1] as int?,
      inter: a[2] as int?,
      arena: a[3] as bool?,
      eintraege: (a[4]! as Map).cast<String, String>(),
    ), beschleunigen: a[5]! as bool),
    'zustand' => _zustand(),
    'schliesse' => _schliesse(a[0]! as String),
    'wert' => _wert(
      a[0]! as String,
      (a[1]! as TransferableTypedData).materialize(),
      (a[2]! as List).cast<int>(),
    ),
    'rechne' => _rechne(a[0]! as String, (a[1]! as Map).cast<String, String>()),
    'lies' => _lies(a[0]! as String),
    'frei' => _frei(a[0]! as String),
    _ => throw UnsupportedError(methode),
  };

  List<String> _anbieter() => using((a) {
    final liste = a<Pointer<Pointer<Utf8>>>();
    final anzahl = a<Int32>();
    _pruefe(_availableProviders(liste, anzahl));
    final namen = [
      for (var i = 0; i < anzahl.value; i++) liste.value[i].toDartString(),
    ];
    _pruefe(_releaseAvailableProviders(liste.value, anzahl.value));
    // ONNX Runtime nennt den Anbieter „CPUExecutionProvider“, die
    // Plattform-Schnittstelle „CPU“.
    return [
      for (final n in namen)
        n.replaceAll('ExecutionProvider', '').toUpperCase(),
    ];
  });

  /// Legt eine Sitzung an. Mit [beschleunigen] (und einem Beschleuniger,
  /// der geht) rechnet sie dort – bis zur bestandenen Gegenprobe zusammen
  /// mit einem Zwilling auf der CPU.
  List<Object?> _sitzung(
    String pfad,
    _Sitzungsoptionen o, {
    required bool beschleunigen,
  }) {
    if (beschleunigen &&
        art != 'cpu' &&
        _anbieterFehler == null &&
        !_verworfen.containsKey(pfad)) {
      try {
        final zeiger = _erzeuge(pfad, o, mitAnbieter: true);
        _Zeiger? zwilling;
        if (!_bestanden.contains(pfad)) {
          try {
            zwilling = _erzeuge(pfad, o, mitAnbieter: false);
          } on Object {
            _releaseSession(zeiger);
            rethrow;
          }
        }
        return _merke(pfad, zeiger, o, name, zwilling: zwilling);
      } on _AnbieterFehlt catch (f) {
        _anbieterFehler = f.grund;
      } on StateError catch (f) {
        // Der Anbieter ist da, aber dieses Modell lädt mit ihm nicht.
        _verworfen[pfad] = 'lädt nicht: ${f.message}';
      }
    }
    return _merke(pfad, _erzeuge(pfad, o, mitAnbieter: false), o, 'CPU');
  }

  List<Object?> _merke(
    String pfad,
    _Zeiger zeiger,
    _Sitzungsoptionen o,
    String anbieter, {
    _Zeiger? zwilling,
  }) => using((a) {
    final eingaenge = _namen(zeiger, _inputCount, _inputName, a);
    final ausgaenge = _namen(zeiger, _outputCount, _outputName, a);
    final id = 's${_zaehler++}';
    _sitzungen[id] = _Sitzung(
      pfad,
      zeiger,
      eingaenge,
      ausgaenge,
      anbieter,
      o,
      zwilling: zwilling,
    );
    // Während der Gegenprobe zählt, was die CPU rechnet.
    return [id, eingaenge, ausgaenge, zwilling == null ? anbieter : 'CPU'];
  });

  _Zeiger _erzeuge(
    String pfad,
    _Sitzungsoptionen o, {
    required bool mitAnbieter,
  }) => using((a) {
    final aus = a<_Zeiger>();
    _pruefe(_createSessionOptions(aus));
    final optionen = aus.value;
    try {
      if (o.intra != null) _pruefe(_setIntra(optionen, o.intra!));
      if (o.inter != null) _pruefe(_setInter(optionen, o.inter!));
      for (final e in o.eintraege.entries) {
        _pruefe(
          _addConfigEntry(
            optionen,
            e.key.toNativeUtf8(allocator: a),
            e.value.toNativeUtf8(allocator: a),
          ),
        );
      }
      if (o.arena == false) _pruefe(_disableArena(optionen));
      if (mitAnbieter) _haengeAn(optionen, a);
      final s = a<_Zeiger>();
      _pruefe(
        _createSession(_env, pfad.toNativeUtf8(allocator: a), optionen, s),
      );
      return s.value;
    } finally {
      _releaseSessionOptions(optionen);
    }
  });

  /// Hängt den Beschleuniger an [optionen]; wirft [_AnbieterFehlt], wenn die
  /// Bibliothek oder der Rechner ihn nicht hat.
  void _haengeAn(_Zeiger optionen, Arena a) {
    final schluessel = a<Pointer<Utf8>>(anbieterOptionen.length.clamp(1, 64));
    final werte = a<Pointer<Utf8>>(anbieterOptionen.length.clamp(1, 64));
    var i = 0;
    for (final e in anbieterOptionen.entries) {
      schluessel[i] = e.key.toNativeUtf8(allocator: a);
      werte[i] = e.value.toNativeUtf8(allocator: a);
      i++;
    }
    try {
      switch (art) {
        case 'openvino':
          _pruefe(_appendOpenVino(optionen, schluessel, werte, i));
        case 'cuda':
          final aus = a<_Zeiger>();
          _pruefe(_createCudaOptions(aus));
          try {
            _pruefe(_updateCudaOptions(aus.value, schluessel, werte, i));
            _pruefe(_appendCuda(optionen, aus.value));
          } finally {
            _releaseCudaOptions(aus.value);
          }
        case 'coreml':
          _pruefe(
            _appendProvider(
              optionen,
              'CoreML'.toNativeUtf8(allocator: a),
              schluessel,
              werte,
              i,
            ),
          );
        default:
          throw _AnbieterFehlt('unbekannter Beschleuniger $art');
      }
    } on StateError catch (f) {
      throw _AnbieterFehlt(f.message);
    }
  }

  /// Wie es um den Beschleuniger steht.
  Map<String, Object?> _zustand() => {
    'onnxRuntime': fassung,
    'beschleuniger': name,
    'fehler': ?_anbieterFehler,
    'geprueft': [..._bestanden.map(_kurz)]..sort(),
    'inPruefung': {
      for (final s in _sitzungen.values)
        if (s.zwilling != null) _kurz(s.pfad),
    }.toList()..sort(),
    'verworfen': {for (final e in _verworfen.entries) _kurz(e.key): e.value},
  };

  static String _kurz(String pfad) => pfad.split(RegExp(r'[/\\]')).last;

  List<String> _namen(
    _Zeiger sitzung,
    _Status Function(_Zeiger, Pointer<Size>) zahl,
    _Status Function(_Zeiger, int, _Zeiger, Pointer<Pointer<Utf8>>) name,
    Arena a,
  ) {
    final n = a<Size>();
    _pruefe(zahl(sitzung, n));
    final namen = <String>[];
    for (var i = 0; i < n.value; i++) {
      final p = a<Pointer<Utf8>>();
      _pruefe(name(sitzung, i, _allocator, p));
      namen.add(p.value.toDartString());
      _pruefe(_allocatorFree(_allocator, p.value.cast()));
    }
    return namen;
  }

  Object? _schliesse(String id) {
    final s = _sitzungen.remove(id);
    if (s != null) {
      _releaseSession(s.zeiger);
      if (s.zwilling case final z?) _releaseSession(z);
    }
    return null;
  }

  String _wert(String typ, ByteBuffer daten, List<int> form) {
    final (code, breite) =
        _typen[typ] ?? (throw UnsupportedError('Typ $typ über FFI'));
    final zeiger = using((a) {
      final f = a<Int64>(form.length);
      for (var i = 0; i < form.length; i++) {
        f[i] = form[i];
      }
      final aus = a<_Zeiger>();
      _pruefe(_createTensor(_allocator, f, form.length, code, aus));
      return aus.value;
    });
    final bytes = daten.asUint8List();
    final erwartet = form.fold(1, (x, y) => x * y) * breite;
    if (bytes.length != erwartet) {
      _releaseValue(zeiger);
      throw ArgumentError(
        '${bytes.length} Bytes für Form $form vom Typ $typ ($erwartet erwartet)',
      );
    }
    using((a) {
      final p = a<_Zeiger>();
      _pruefe(_mutableData(zeiger, p));
      p.value.cast<Uint8>().asTypedList(bytes.length).setAll(0, bytes);
    });
    final id = 'v${_zaehler++}';
    _werte[id] = _Wert(zeiger, typ, form);
    return id;
  }

  /// Rechnet; die Antwort ist `[Ausgaben, Anbieter]`. Während der
  /// Gegenprobe rechnen Beschleuniger und CPU, und zurück geht das Ergebnis
  /// der CPU – erst ein bestandenes Modell liefert, was der Beschleuniger
  /// gerechnet hat.
  List<Object?> _rechne(String sitzungId, Map<String, String> eingaben) {
    final s =
        _sitzungen[sitzungId] ??
        (throw StateError('Sitzung $sitzungId gibt es nicht'));
    final zwilling = s.zwilling;
    if (zwilling != null) {
      final cpu = _lauf(zwilling, s, eingaben);
      String? abweichung;
      try {
        final beschleunigt = _lauf(s.zeiger, s, eingaben);
        try {
          abweichung = _vergleiche(cpu, beschleunigt, s.ausgaenge);
        } finally {
          beschleunigt.forEach(_releaseValue);
        }
      } on StateError catch (f) {
        abweichung = 'rechnet nicht: ${f.message}';
      }
      if (abweichung != null) {
        _verworfen[s.pfad] = abweichung;
        _releaseSession(s.zeiger);
        s
          ..zeiger = zwilling
          ..zwilling = null
          ..anbieter = 'CPU';
      } else if (--s.offen <= 0) {
        _bestanden.add(s.pfad);
        _releaseSession(zwilling);
        s.zwilling = null;
      }
      return [_registriere(cpu, s), 'CPU'];
    }
    try {
      return [_registriere(_lauf(s.zeiger, s, eingaben), s), s.anbieter];
    } on StateError catch (f) {
      if (s.anbieter == 'CPU') rethrow;
      // Bestanden und trotzdem gescheitert (etwa eine Form, die in der
      // Probe nicht vorkam): ab jetzt auf der CPU.
      _verworfen[s.pfad] = 'rechnet nicht: ${f.message}';
      _releaseSession(s.zeiger);
      s
        ..zeiger = _erzeuge(s.pfad, s.optionen, mitAnbieter: false)
        ..anbieter = 'CPU';
      return [_registriere(_lauf(s.zeiger, s, eingaben), s), 'CPU'];
    }
  }

  List<_Zeiger> _lauf(
    _Zeiger sitzung,
    _Sitzung s,
    Map<String, String> eingaben,
  ) =>
      using((a) {
        final namen = a<Pointer<Utf8>>(eingaben.length);
        final werte = a<_Zeiger>(eingaben.length);
        var i = 0;
        for (final e in eingaben.entries) {
          final w =
              _werte[e.value] ??
              (throw StateError('Wert ${e.value} gibt es nicht'));
          namen[i] = e.key.toNativeUtf8(allocator: a);
          werte[i] = w.zeiger;
          i++;
        }
        final ausNamen = a<Pointer<Utf8>>(s.ausgaenge.length);
        for (var j = 0; j < s.ausgaenge.length; j++) {
          ausNamen[j] = s.ausgaenge[j].toNativeUtf8(allocator: a);
        }
        final aus = a<_Zeiger>(s.ausgaenge.length);
        for (var j = 0; j < s.ausgaenge.length; j++) {
          aus[j] = nullptr;
        }
        _pruefe(
          _run(
            sitzung,
            nullptr,
            namen,
            werte,
            eingaben.length,
            ausNamen,
            s.ausgaenge.length,
            aus,
          ),
        );
        return [for (var j = 0; j < s.ausgaenge.length; j++) aus[j]];
      });

  Map<String, Object?> _registriere(List<_Zeiger> aus, _Sitzung s) =>
      using((a) {
        final ergebnis = <String, Object?>{};
        for (var j = 0; j < s.ausgaenge.length; j++) {
          final (typ, form) = _typUndForm(aus[j], a);
          final id = 'v${_zaehler++}';
          _werte[id] = _Wert(aus[j], typ, form);
          ergebnis[s.ausgaenge[j]] = [id, typ, form];
        }
        return ergebnis;
      });

  /// `null`, wenn [b] dasselbe ist wie [a] (siehe [_mindestKosinus]);
  /// sonst, was abweicht.
  String? _vergleiche(List<_Zeiger> a, List<_Zeiger> b, List<String> namen) =>
      using((arena) {
        for (var j = 0; j < a.length; j++) {
          final (typA, formA) = _typUndForm(a[j], arena);
          final (typB, formB) = _typUndForm(b[j], arena);
          if (typA != typB || formA.join(',') != formB.join(',')) {
            return '${namen[j]}: Form $typA$formA gegen $typB$formB';
          }
          final n = formA.fold(1, (x, y) => x * y);
          if (n == 0) continue;
          final breite = _typen[typA]!.$2;
          final pa = arena<_Zeiger>();
          final pb = arena<_Zeiger>();
          _pruefe(_mutableData(a[j], pa));
          _pruefe(_mutableData(b[j], pb));
          if (typA != 'float32') {
            final x = pa.value.cast<Uint8>().asTypedList(n * breite);
            final y = pb.value.cast<Uint8>().asTypedList(n * breite);
            for (var i = 0; i < x.length; i++) {
              if (x[i] != y[i]) return '${namen[j]}: andere Werte ($typA)';
            }
            continue;
          }
          final grund = abweichung(
            pa.value.cast<Float>().asTypedList(n),
            pb.value.cast<Float>().asTypedList(n),
          );
          if (grund != null) return '${namen[j]}: $grund';
        }
        return null;
      });

  (String, List<int>) _typUndForm(_Zeiger wert, Arena a) {
    final info = a<_Zeiger>();
    _pruefe(_typeAndShape(wert, info));
    try {
      final code = a<Int32>();
      _pruefe(_elementType(info.value, code));
      final n = a<Size>();
      _pruefe(_dimensionsCount(info.value, n));
      final dims = a<Int64>(n.value == 0 ? 1 : n.value);
      _pruefe(_dimensions(info.value, dims, n.value));
      final typ = _typen.entries
          .firstWhere(
            (e) => e.value.$1 == code.value,
            orElse: () => throw UnsupportedError(
              'Ausgabe vom Elementtyp ${code.value} über FFI',
            ),
          )
          .key;
      return (typ, [for (var i = 0; i < n.value; i++) dims[i]]);
    } finally {
      _releaseTypeAndShape(info.value);
    }
  }

  List<Object?> _lies(String id) {
    final w = _werte[id] ?? (throw StateError('Wert $id gibt es nicht'));
    final breite = _typen[w.typ]!.$2;
    return using((a) {
      final info = a<_Zeiger>();
      _pruefe(_typeAndShape(w.zeiger, info));
      final n = a<Size>();
      try {
        _pruefe(_elementCount(info.value, n));
      } finally {
        _releaseTypeAndShape(info.value);
      }
      final p = a<_Zeiger>();
      _pruefe(_mutableData(w.zeiger, p));
      final kopie = Uint8List.fromList(
        p.value.cast<Uint8>().asTypedList(n.value * breite),
      );
      return [
        w.typ,
        TransferableTypedData.fromList([kopie]),
        w.form,
      ];
    });
  }

  Object? _frei(String id) {
    final w = _werte.remove(id);
    if (w != null) _releaseValue(w.zeiger);
    return null;
  }

  void raeumeAuf() {
    for (final w in _werte.values) {
      _releaseValue(w.zeiger);
    }
    _werte.clear();
    for (final s in _sitzungen.values) {
      _releaseSession(s.zeiger);
      if (s.zwilling case final z?) _releaseSession(z);
    }
    _sitzungen.clear();
    _releaseEnv(_env);
  }
}
