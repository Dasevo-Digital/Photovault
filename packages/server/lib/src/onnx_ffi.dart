import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:onnxruntime_api/onnxruntime_api.dart';

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
class FfiOnnxPlattform extends OnnxRuntimePlatform {
  FfiOnnxPlattform._(this._an, this._von, this.fassung, this.eintraege);

  /// Konfigurationseinträge, die jede Sitzung zusätzlich bekommt.
  final Map<String, String> eintraege;

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
  }) async {
    final von = ReceivePort();
    await Isolate.spawn(_arbeite, [von.sendPort, pfad]);
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
      // Beschleuniger kommen mit Stufe 5 (Issue #104). Bis dahin lieber
      // ablehnen als stillschweigend auf der CPU rechnen.
      throw UnsupportedError('Anbieter $fremd gibt es über FFI noch nicht');
    }
    final r = await _frag<List<Object?>>('sitzung', [
      modelPath,
      o['intraOpNumThreads'],
      o['interOpNumThreads'],
      o['useArena'],
      {...eintraege, ...?(o['sessionConfigs'] as Map?)?.cast<String, String>()},
    ]);
    return {
      'sessionId': r[0],
      'inputNames': (r[1]! as List).cast<String>(),
      'outputNames': (r[2]! as List).cast<String>(),
    };
  }

  @override
  Future<void> closeSession(String sessionId) =>
      _frag<void>('schliesse', [sessionId]);

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
    final r = await _frag<Map<Object?, Object?>>('rechne', [
      sessionId,
      {for (final e in inputs.entries) e.key: e.value.id},
    ]);
    return r.cast<String, dynamic>();
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
    ort = _Ort(start[1]! as String);
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
}

const _apiFassung = 28;

typedef _Zeiger = Pointer<Void>;
typedef _Status = Pointer<Void>;

final class _Sitzung {
  _Sitzung(this.zeiger, this.eingaenge, this.ausgaenge);
  final _Zeiger zeiger;
  final List<String> eingaenge;
  final List<String> ausgaenge;
}

final class _Wert {
  _Wert(this.zeiger, this.typ, this.form);
  final _Zeiger zeiger;
  final String typ;
  final List<int> form;
}

class _Ort {
  _Ort(String pfad) : _lib = DynamicLibrary.open(pfad) {
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
        'die Bibliothek kennt die API-Fassung $_apiFassung nicht',
      );
    }
    fassung = basis[1]
        .cast<NativeFunction<Pointer<Utf8> Function()>>()
        .asFunction<Pointer<Utf8> Function()>()()
        .toDartString();
    _bind();
    _env = using((a) {
      final aus = a<Pointer<Void>>();
      _pruefe(
        _createEnv(2, 'PhotoVaultServer'.toNativeUtf8(allocator: a), aus),
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
    'sitzung' => _sitzung(
      a[0]! as String,
      a[1] as int?,
      a[2] as int?,
      a[3] as bool?,
      (a[4]! as Map).cast<String, String>(),
    ),
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

  List<Object?> _sitzung(
    String pfad,
    int? intra,
    int? inter,
    bool? arena,
    Map<String, String> eintraege,
  ) => using((a) {
    final aus = a<_Zeiger>();
    _pruefe(_createSessionOptions(aus));
    final optionen = aus.value;
    try {
      if (intra != null) _pruefe(_setIntra(optionen, intra));
      if (inter != null) _pruefe(_setInter(optionen, inter));
      for (final e in eintraege.entries) {
        _pruefe(
          _addConfigEntry(
            optionen,
            e.key.toNativeUtf8(allocator: a),
            e.value.toNativeUtf8(allocator: a),
          ),
        );
      }
      if (arena == false) _pruefe(_disableArena(optionen));
      final s = a<_Zeiger>();
      _pruefe(
        _createSession(_env, pfad.toNativeUtf8(allocator: a), optionen, s),
      );
      final eingaenge = _namen(s.value, _inputCount, _inputName, a);
      final ausgaenge = _namen(s.value, _outputCount, _outputName, a);
      final id = 's${_zaehler++}';
      _sitzungen[id] = _Sitzung(s.value, eingaenge, ausgaenge);
      return [id, eingaenge, ausgaenge];
    } finally {
      _releaseSessionOptions(optionen);
    }
  });

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
    if (s != null) _releaseSession(s.zeiger);
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

  Map<String, Object?> _rechne(String sitzungId, Map<String, String> eingaben) {
    final s =
        _sitzungen[sitzungId] ??
        (throw StateError('Sitzung $sitzungId gibt es nicht'));
    return using((a) {
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
          s.zeiger,
          nullptr,
          namen,
          werte,
          eingaben.length,
          ausNamen,
          s.ausgaenge.length,
          aus,
        ),
      );
      final ergebnis = <String, Object?>{};
      for (var j = 0; j < s.ausgaenge.length; j++) {
        final (typ, form) = _typUndForm(aus[j], a);
        final id = 'v${_zaehler++}';
        _werte[id] = _Wert(aus[j], typ, form);
        ergebnis[s.ausgaenge[j]] = [id, typ, form];
      }
      return ergebnis;
    });
  }

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
    }
    _sitzungen.clear();
    _releaseEnv(_env);
  }
}
