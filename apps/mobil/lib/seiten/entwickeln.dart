import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/cube_lut.dart';
import 'package:kern/services/develop_color.dart';
import 'package:kern/services/entwicklungswerte.dart';
import 'package:path/path.dart' as p;
import 'package:zierbild/entwickeln_rechnung.dart';

import '../l10n/app_localizations.dart';
import '../sitzung.dart';

/// Ein Regler wie im Browser (web/entwickeln.js, ENTW_REGLER): die Spalte
/// in den Einstellungen, Bereich und Schritt.
typedef _Regler = ({
  String spalte,
  String Function(AppTexte) name,
  double min,
  double max,
  double schritt,
  double vorgabe,
  bool weissabgleich,
});

final List<_Regler> _regler = [
  (
    spalte: 'exposure',
    name: (t) => t.entwBelichtung,
    min: -3,
    max: 3,
    schritt: 0.01,
    vorgabe: 0,
    weissabgleich: false,
  ),
  (
    spalte: 'contrast',
    name: (t) => t.entwKontrast,
    min: -1,
    max: 1,
    schritt: 0.01,
    vorgabe: 0,
    weissabgleich: false,
  ),
  (
    spalte: 'highlights',
    name: (t) => t.entwLichter,
    min: -1,
    max: 1,
    schritt: 0.01,
    vorgabe: 0,
    weissabgleich: false,
  ),
  (
    spalte: 'shadows',
    name: (t) => t.entwSchatten,
    min: -1,
    max: 1,
    schritt: 0.01,
    vorgabe: 0,
    weissabgleich: false,
  ),
  (
    spalte: 'temperature',
    name: (t) => t.entwTemperatur,
    min: 2000,
    max: 12000,
    schritt: 50,
    vorgabe: 6500,
    weissabgleich: true,
  ),
  (
    spalte: 'tint',
    name: (t) => t.entwToenung,
    min: -100,
    max: 100,
    schritt: 1,
    vorgabe: 0,
    weissabgleich: true,
  ),
  (
    spalte: 'clarity',
    name: (t) => t.entwKlarheit,
    min: -1,
    max: 1,
    schritt: 0.01,
    vorgabe: 0,
    weissabgleich: false,
  ),
  (
    spalte: 'sharpness',
    name: (t) => t.entwSchaerfe,
    min: 0,
    max: 1,
    schritt: 0.01,
    vorgabe: 0,
    weissabgleich: false,
  ),
  (
    spalte: 'noise_reduction',
    name: (t) => t.entwRauschen,
    min: 0,
    max: 1,
    schritt: 0.01,
    vorgabe: 0,
    weissabgleich: false,
  ),
  (
    spalte: 'vignette',
    name: (t) => t.entwVignette,
    min: -1,
    max: 1,
    schritt: 0.01,
    vorgabe: 0,
    weissabgleich: false,
  ),
];

/// Formate, die das Telefon selbst dekodiert – wie im Browser
/// (api.dart, entwickeln): RAW und HEIC rechnen aus der Vorschau.
const _selbstLesbar = {'jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp'};

/// Die längste Kante der Vorschau auf dem Bildschirm.
const _vorschauKante = 1600;

/// Entwickeln wie im Browser: dieselben zehn Regler, automatischer
/// Weissabgleich, „Vorher“ zum Vergleichen, Zurücksetzen, die Entwicklung
/// entfernen und Speichern in voller Grösse. Gerechnet wird mit denselben
/// Shadern wie am Rechner unter Linux und Windows (Paket zierbild); Kurve,
/// Farbmischer und Look vom Rechner wirken mit und bleiben erhalten. Das
/// gerenderte Bild geht zuerst zum Server, danach der Befehl – wie beim
/// verbundenen Rechner.
class Entwickeln extends StatefulWidget {
  const Entwickeln({super.key, required this.sitzung, required this.id});

  final Sitzung sitzung;
  final String id;

  @override
  State<Entwickeln> createState() => _EntwickelnState();
}

class _EntwickelnState extends State<Entwickeln> {
  AssetData? _a;
  DevelopSettingsData? _e;
  Uint8List? _quelle;
  var _breite = 0, _hoehe = 0;
  var _ausVorschau = false;
  ui.Image? _basis;
  ui.Image? _bild;
  Entwicklungsvorschau? _vorschau;
  CubeLut? _lut;
  var _kurve = ToneCurve.neutral;
  var _mischer = ColorMixer.neutral;
  final _werte = <String, double?>{};
  var _vergleich = false;
  var _geaendert = false;
  var _rechnet = false;
  var _nochmal = false;
  var _speichert = false;
  String? _meldung;
  String? _fehler;

  AppDatabase get _db => widget.sitzung.db;

  @override
  void initState() {
    super.initState();
    _lade();
  }

  @override
  void dispose() {
    _basis?.dispose();
    _bild?.dispose();
    _vorschau?.dispose();
    super.dispose();
  }

  Future<void> _lade() async {
    try {
      final a = await _db.assetById(widget.id);
      if (a == null) return;
      final e = await _db.developSettingsForAsset(widget.id);
      final format =
          (a.dateiformat ??
                  p.extension(a.originalFileName).replaceFirst('.', ''))
              .toLowerCase();
      final ausVorschau = !_selbstLesbar.contains(format);
      final rel = ausVorschau
          ? (a.previewRelativePath ?? a.thumbnailRelativePath)
          : a.relativePath;
      if (rel == null) throw StateError('ohne Datei');
      final bytes = await (await widget.sitzung.paths.bereit(
        rel,
      )).readAsBytes();
      var breite = 0, hoehe = 0;
      final puffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final codec = await ui.instantiateImageCodecWithSize(
        puffer,
        getTargetSize: (b, h) {
          breite = b;
          hoehe = h;
          return Entwicklungsrechnung.zielGroesse(
            breite: b,
            hoehe: h,
            maxKante: _vorschauKante,
          );
        },
      );
      final ui.Image basis;
      try {
        basis = (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
      CubeLut? lut;
      final lutPfad = e?.lutPath;
      if (lutPfad != null && (e?.lutStrength ?? 0) > 0) {
        try {
          lut = parseCubeLut(
            await (await widget.sitzung.paths.bereit(lutPfad)).readAsString(),
          );
        } catch (_) {
          // Eine fehlende oder kaputte Tabelle wirkt eben nicht – wie im
          // Browser.
        }
      }
      final vorschau = await Entwicklungsvorschau.lade();
      if (!mounted) {
        basis.dispose();
        vorschau?.dispose();
        return;
      }
      setState(() {
        _a = a;
        _e = e;
        _quelle = bytes;
        _breite = breite;
        _hoehe = hoehe;
        _ausVorschau = ausVorschau;
        _basis = basis;
        _vorschau = vorschau;
        _lut = lut;
        _kurve = toneCurveAus(e?.toneCurveJson);
        _mischer = colorMixerAus(e?.colorMixerJson);
        _werte
          ..clear()
          ..addAll({
            'exposure': e?.exposure ?? 0,
            'contrast': e?.contrast ?? 0,
            'highlights': e?.highlights ?? 0,
            'shadows': e?.shadows ?? 0,
            'temperature': e?.temperature,
            'tint': e?.tint,
            'clarity': e?.clarity ?? 0,
            'sharpness': e?.sharpness ?? 0,
            'noise_reduction': e?.noiseReduction ?? 0,
            'vignette': e?.vignette ?? 0,
          });
      });
      await _rechne();
    } catch (_) {
      if (mounted) {
        setState(() => _fehler = AppTexte.of(context).entwNichtGeladen);
      }
    }
  }

  DevelopAdjustments _einstellungen() {
    double w(String s) => _werte[s] ?? 0;
    return DevelopAdjustments(
      exposure: w('exposure'),
      temperature: _werte['temperature'],
      tint: _werte['tint'],
      contrast: w('contrast'),
      shadows: w('shadows'),
      highlights: w('highlights'),
      sharpness: w('sharpness'),
      noiseReduction: w('noise_reduction'),
      clarity: w('clarity'),
      vignette: w('vignette'),
      lensCorrectionEnabled: _e?.lensCorrectionEnabled ?? true,
      toneCurve: _kurve,
      colorMixer: _mischer,
      lut: _lut,
      lutStrength: _e?.lutStrength ?? 1,
    );
  }

  /// Rechnet die Vorschau neu – höchstens einmal zugleich; kommt während
  /// des Rechnens ein neuer Stand, folgt genau ein weiterer Durchgang.
  Future<void> _rechne() async {
    final basis = _basis, vorschau = _vorschau;
    if (basis == null || vorschau == null) return;
    if (_rechnet) {
      _nochmal = true;
      return;
    }
    _rechnet = true;
    try {
      do {
        _nochmal = false;
        final neu = await vorschau.rechne(basis, _einstellungen());
        if (!mounted) {
          neu.dispose();
          return;
        }
        final alt = _bild;
        setState(() => _bild = neu);
        alt?.dispose();
      } while (_nochmal);
    } finally {
      _rechnet = false;
    }
  }

  void _setze(String spalte, double? wert) {
    setState(() {
      _werte[spalte] = wert;
      _geaendert = true;
    });
    _rechne();
  }

  void _zuruecksetzen() {
    setState(() {
      for (final r in _regler) {
        _werte[r.spalte] = r.weissabgleich ? null : 0;
      }
      _geaendert = true;
    });
    _rechne();
  }

  Future<bool> _frage(String text) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(AppTexte.of(context).abbrechen),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('OK'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _entfernen() async {
    final t = AppTexte.of(context);
    if (!await _frage(t.entwEntfernenFrage)) return;
    await _db.fuehreAus(EntwicklungZuruecksetzen(widget.id));
    _geaendert = false;
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _speichern() async {
    final t = AppTexte.of(context);
    final quelle = _quelle;
    if (quelle == null || _speichert) return;
    setState(() {
      _speichert = true;
      _meldung = t.entwRechne(_breite, _hoehe);
    });
    try {
      final jpeg = await Entwicklungsrechnung.rendere(
        quelle,
        adjustments: _einstellungen(),
        maxDimension: _breite > _hoehe ? _breite : _hoehe,
        quality: 92,
      );
      if (jpeg == null) throw StateError(t.entwNichtGeladen);
      if (!mounted) return;
      setState(() => _meldung = t.entwLaedtHoch);
      // Ein neuer Name je Speichern: Geräte halten Dateien unter ihrem
      // Namen vor – wie im Browser.
      final rel =
          'developed/${widget.id}-${DateTime.now().millisecondsSinceEpoch}.jpg';
      final datei = widget.sitzung.paths.absolute(rel);
      await datei.parent.create(recursive: true);
      await datei.writeAsBytes(jpeg, flush: true);
      await widget.sitzung.paths.abgelegt(rel);
      double w(String s) => _werte[s] ?? 0;
      final e = _e;
      await _db.fuehreAus(
        EntwicklungSpeichern(
          widget.id,
          DevelopSettingsCompanion.insert(
            assetId: widget.id,
            exposure: Value(w('exposure')),
            temperature: Value(_werte['temperature']),
            tint: Value(_werte['tint']),
            contrast: Value(w('contrast')),
            shadows: Value(w('shadows')),
            highlights: Value(w('highlights')),
            sharpness: Value(w('sharpness')),
            noiseReduction: Value(w('noise_reduction')),
            clarity: Value(w('clarity')),
            vignette: Value(w('vignette')),
            lensCorrectionEnabled: Value(e?.lensCorrectionEnabled ?? true),
            lutPath: Value(e?.lutPath),
            lutStrength: Value(e?.lutStrength ?? 1),
            toneCurveJson: Value(e?.toneCurveJson),
            colorMixerJson: Value(e?.colorMixerJson),
            updatedAt: DateTime.now(),
          ),
          rel,
        ),
      );
      _geaendert = false;
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(t.entwGespeichert)));
      Navigator.of(context).pop();
    } catch (x) {
      if (mounted) setState(() => _meldung = '$x');
    } finally {
      if (mounted) setState(() => _speichert = false);
    }
  }

  Future<void> _abbrechen() async {
    final t = AppTexte.of(context);
    if (_geaendert && !await _frage(t.entwVerwerfen)) return;
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final farben = Theme.of(context).colorScheme;
    final a = _a;
    if (_fehler != null) {
      return Scaffold(
        appBar: AppBar(title: Text(t.entwTitel)),
        body: Center(child: Text(_fehler!)),
      );
    }
    if (a == null || _basis == null) {
      return Scaffold(
        appBar: AppBar(title: Text(t.entwTitel)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final e = _e;
    final hinweise = [
      if (_ausVorschau) t.entwVorschauQuelle,
      if (e != null &&
          (e.toneCurveJson != null ||
              e.colorMixerJson != null ||
              e.lutPath != null))
        t.entwVomRechner,
    ];
    final automatisch = _werte['temperature'] == null;
    final zeigen = _vergleich ? _basis : (_bild ?? _basis);
    return PopScope(
      canPop: !_geaendert,
      onPopInvokedWithResult: (geschlossen, _) {
        if (!geschlossen) _abbrechen();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(t.entwTitel),
          actions: [
            TextButton(
              onPressed: _speichert ? null : _speichern,
              child: Text(t.entwSpeichern),
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              flex: 5,
              child: ColoredBox(
                color: Colors.black,
                child: Center(
                  child: RawImage(image: zeigen, fit: BoxFit.contain),
                ),
              ),
            ),
            if (hinweise.isNotEmpty || _meldung != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                child: Text(
                  [...hinweise, ?_meldung].join(' '),
                  style: TextStyle(
                    color: farben.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ),
            Expanded(
              flex: 6,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      GestureDetector(
                        onTapDown: (_) {
                          setState(() => _vergleich = true);
                        },
                        onTapUp: (_) => setState(() => _vergleich = false),
                        onTapCancel: () => setState(() => _vergleich = false),
                        child: Chip(
                          avatar: const Icon(Icons.compare, size: 18),
                          label: Text(t.entwVorher),
                        ),
                      ),
                      ActionChip(
                        label: Text(t.entwZuruecksetzen),
                        onPressed: _speichert ? null : _zuruecksetzen,
                      ),
                      if (a.developedRelativePath != null || e != null)
                        ActionChip(
                          label: Text(t.entwEntfernen),
                          onPressed: _speichert ? null : _entfernen,
                        ),
                    ],
                  ),
                  for (final r in _regler) ...[
                    if (r.spalte == 'temperature')
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(t.entwAutoWeiss),
                        value: automatisch,
                        onChanged: (an) {
                          setState(() {
                            _werte['temperature'] = an ? null : 6500;
                            _werte['tint'] = an ? null : 0;
                            _geaendert = true;
                          });
                          _rechne();
                        },
                      ),
                    _Reglerzeile(
                      name: r.name(t),
                      regler: r,
                      wert: _werte[r.spalte] ?? r.vorgabe,
                      aus: r.weissabgleich && automatisch,
                      setze: (w) => _setze(r.spalte, w),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Reglerzeile extends StatelessWidget {
  const _Reglerzeile({
    required this.name,
    required this.regler,
    required this.wert,
    required this.aus,
    required this.setze,
  });

  final String name;
  final _Regler regler;
  final double wert;
  final bool aus;
  final ValueChanged<double> setze;

  @override
  Widget build(BuildContext context) {
    final farben = Theme.of(context).colorScheme;
    final r = regler;
    final zahl = r.min.abs() >= 100
        ? wert.round().toString()
        : wert.toStringAsFixed(2);
    return Opacity(
      opacity: aus ? 0.45 : 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Doppeltipp auf den Namen setzt den Regler zurück – wie der
          // Doppelklick im Browser.
          GestureDetector(
            onDoubleTap: aus ? null : () => setze(r.vorgabe),
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Expanded(child: Text(name)),
                  Text(
                    zahl,
                    style: TextStyle(
                      color: farben.onSurfaceVariant,
                      fontFeatures: const [ui.FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Slider(
            value: wert.clamp(r.min, r.max),
            min: r.min,
            max: r.max,
            divisions: ((r.max - r.min) / r.schritt).round(),
            onChanged: aus ? null : setze,
          ),
        ],
      ),
    );
  }
}
