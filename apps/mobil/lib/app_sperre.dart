import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'l10n/app_localizations.dart';

/// Die App-Sperre (#376): Face ID, Touch ID oder der Gerätecode, bevor die
/// App etwas zeigt.
///
/// **Warum.** Die App bleibt über ihre Sitzung angemeldet. Wer das
/// entsperrte Telefon in der Hand hatte, sah die ganze Bibliothek, auch
/// Offline-Alben und die Fotos von Partnern. Ein Telefon gibt man eher aus
/// der Hand als einen Rechner, und man verliert es eher.
///
/// Sie gilt nur für dieses Gerät und nur für die Oberfläche: Die Sicherung
/// im Hintergrund und das Teilen aus anderen Apps zeigen nichts und laufen
/// weiter. Im App-Umschalter deckt das System die App ab (siehe
/// `AppDelegate.swift` und `MainActivity.kt`), solange sie an ist.
class AppSperre extends ChangeNotifier {
  AppSperre({
    this.an = false,
    this.frist = Duration.zero,
    this.datei,
    Future<bool> Function(String grund)? pruefe,
    Future<bool> Function()? verfuegbar,
    DateTime Function()? jetzt,
    Future<void> Function(bool an)? abdecken,
  }) : _pruefe = pruefe ?? _systemPruefung,
       _verfuegbar = verfuegbar ?? LocalAuthentication().isDeviceSupported,
       _jetzt = jetzt ?? DateTime.now,
       _abdecken = abdecken ?? _systemAbdeckung,
       gesperrt = an;

  /// Wie lange die App im Hintergrund sein darf, ehe sie wieder fragt.
  static const fristen = [
    Duration.zero,
    Duration(minutes: 1),
    Duration(minutes: 5),
    Duration(minutes: 15),
  ];

  bool an;
  Duration frist;

  /// Ob die Oberfläche gerade gesperrt ist.
  bool gesperrt;

  /// Ob die App gerade nicht vorne ist: Dann liegt eine Abdeckung über
  /// allem, damit der App-Umschalter nichts zeigt.
  bool verdeckt = false;

  /// Wo die Einstellung liegt; ohne sie bleibt sie im Speicher.
  final File? datei;
  final Future<bool> Function(String grund) _pruefe;
  final Future<bool> Function() _verfuegbar;
  final DateTime Function() _jetzt;
  final Future<void> Function(bool an) _abdecken;
  DateTime? _weg;
  bool _fragtGerade = false;

  /// Liest die Einstellung dieses Geräts. Ohne Datei oder bei einem Fehler
  /// ist die Sperre aus.
  static Future<AppSperre> lade() async {
    final datei = File(
      p.join((await getApplicationSupportDirectory()).path, 'app_sperre.json'),
    );
    var an = false;
    var frist = Duration.zero;
    try {
      if (await datei.exists()) {
        final w = jsonDecode(await datei.readAsString());
        if (w is Map) {
          an = w['an'] == true;
          frist = Duration(seconds: (w['frist'] as num?)?.toInt() ?? 0);
        }
      }
    } on Object catch (e) {
      debugPrint('App-Sperre nicht gelesen: $e');
    }
    final sperre = AppSperre(an: an, frist: frist, datei: datei);
    unawaited(sperre._abdecken(an).catchError((Object _) {}));
    return sperre;
  }

  /// Ob das Gerät überhaupt Face ID, Touch ID oder einen Gerätecode hat.
  Future<bool> verfuegbar() async {
    try {
      return await _verfuegbar();
    } on Object {
      return false;
    }
  }

  /// Fragt nach Face ID, Touch ID oder dem Gerätecode; `true`, wenn es
  /// geklappt hat. Ein Fehler des Systems zählt als nein.
  Future<bool> pruefe(String grund) async {
    if (_fragtGerade) return false;
    _fragtGerade = true;
    try {
      return await _pruefe(grund);
    } on Object catch (e) {
      debugPrint('App-Sperre: $e');
      return false;
    } finally {
      _fragtGerade = false;
    }
  }

  Future<bool> entsperre(String grund) async {
    if (!gesperrt) return true;
    final ok = await pruefe(grund);
    if (ok) {
      gesperrt = false;
      notifyListeners();
    }
    return ok;
  }

  /// Schaltet die Sperre um oder ändert die Frist und merkt es sich.
  Future<void> setze({bool? an, Duration? frist}) async {
    this.an = an ?? this.an;
    this.frist = frist ?? this.frist;
    if (!this.an) gesperrt = false;
    notifyListeners();
    await _abdecken(this.an).catchError((Object _) {});
    final ziel = datei;
    if (ziel == null) return;
    try {
      await ziel.parent.create(recursive: true);
      await ziel.writeAsString(
        jsonEncode({'an': this.an, 'frist': this.frist.inSeconds}),
      );
    } on Object catch (e) {
      debugPrint('App-Sperre nicht gespeichert: $e');
    }
  }

  /// Die App verlässt den Vordergrund. Der Dialog von Face ID selbst macht
  /// sie nur inaktiv, nicht unsichtbar – das zählt nicht als weg.
  void lebenslauf(AppLifecycleState zustand) {
    if (!an) {
      if (verdeckt) {
        verdeckt = false;
        notifyListeners();
      }
      return;
    }
    switch (zustand) {
      case AppLifecycleState.inactive:
        if (!_fragtGerade && !verdeckt) {
          verdeckt = true;
          notifyListeners();
        }
      case AppLifecycleState.hidden || AppLifecycleState.paused:
        _weg ??= _jetzt();
        if (!verdeckt) {
          verdeckt = true;
          notifyListeners();
        }
      case AppLifecycleState.resumed:
        final weg = _weg;
        _weg = null;
        if (weg != null && _jetzt().difference(weg) >= frist) gesperrt = true;
        verdeckt = false;
        notifyListeners();
      case AppLifecycleState.detached:
        break;
    }
  }

  static Future<bool> _systemPruefung(String grund) => LocalAuthentication()
      .authenticate(localizedReason: grund, persistAcrossBackgrounding: true);

  static const _kanal = MethodChannel('de.dasevo.photovault/gemeinsam');

  static Future<void> _systemAbdeckung(bool an) async {
    if (!Platform.isIOS && !Platform.isAndroid) return;
    await _kanal.invokeMethod<void>('abdeckung', an);
  }
}

/// Legt die Sperre über die ganze App: davor die Abfrage, solange
/// [AppSperre.gesperrt], und eine leere Fläche, solange die App nicht vorne
/// ist. Was darunter liegt, bekommt keine Berührung und keine Ansage für
/// VoiceOver.
class AppSperrschicht extends StatefulWidget {
  const AppSperrschicht({super.key, required this.sperre, required this.child});

  final AppSperre sperre;
  final Widget child;

  @override
  State<AppSperrschicht> createState() => _AppSperrschichtState();
}

class _AppSperrschichtState extends State<AppSperrschicht>
    with WidgetsBindingObserver {
  var _gefragt = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.sperre.addListener(_neu);
  }

  @override
  void dispose() {
    widget.sperre.removeListener(_neu);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _neu() {
    if (!widget.sperre.gesperrt) _gefragt = false;
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Wer die Abfrage abgebrochen hat und wiederkommt, wird wieder gefragt.
    if (state == AppLifecycleState.resumed) _gefragt = false;
    widget.sperre.lebenslauf(state);
  }

  Future<void> _entsperre() async {
    final t = AppTexte.of(context);
    await widget.sperre.entsperre(t.appSperreGrund);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.sperre;
    final zeige = s.an && (s.gesperrt || s.verdeckt);
    // Einmal von selbst fragen, sobald die Sperre vorne steht – danach nur
    // noch auf Tipp, sonst stünde der Dialog nach „Abbrechen“ gleich wieder.
    if (s.an && s.gesperrt && !s.verdeckt && !_gefragt) {
      _gefragt = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _entsperre();
      });
    }
    return Stack(
      children: [
        ExcludeSemantics(excluding: zeige, child: widget.child),
        if (zeige)
          Positioned.fill(
            child: _Sperrbild(
              frage: s.gesperrt && !s.verdeckt,
              beiTipp: _entsperre,
            ),
          ),
      ],
    );
  }
}

class _Sperrbild extends StatelessWidget {
  const _Sperrbild({required this.frage, required this.beiTipp});

  final bool frage;
  final VoidCallback beiTipp;

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final farben = Theme.of(context).colorScheme;
    return Material(
      color: farben.surface,
      child: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, size: 56, color: farben.primary),
              if (frage) ...[
                const SizedBox(height: 16),
                Text(
                  t.appSperreGesperrt,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: beiTipp,
                  icon: const Icon(Icons.face_outlined),
                  label: Text(t.appSperreEntsperren),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
